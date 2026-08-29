import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/simulation_result.dart';
import '../../shared/backend_headers.dart';

/// One estimated future payment for a ticker, from backend's
/// _estimate_upcoming_payments() — expectedDate/amountPerShare are a
/// pattern-based estimate (clustered by day-of-year against the last few
/// years of real payment history), not an announced date, since Yahoo's
/// forward-looking ex-dividend calendar is unreliable/empty for KLSE
/// tickers until very close to the actual event.
class UpcomingDividendPayment {
  final DateTime expectedDate;
  final double amountPerShare;

  const UpcomingDividendPayment({
    required this.expectedDate,
    required this.amountPerShare,
  });
}

/// A response the backend actually sent, just not a 200 — distinct from a
/// connection failure so fetchSimulation can show the real reason (rate
/// limited, bad ticker, etc.) instead of a misleading "backend is down".
class _ServerError implements Exception {
  final String message;
  _ServerError(this.message);
}

/// Real dividend payment schedule for one ticker — from backend's
/// /api/dividend_history (GET backend/app.py:dividend_history), which
/// infers payments/year from actual payment date gaps rather than
/// assuming quarterly. projectedAnnualPerShare = most recent per-payment
/// amount x frequencyPerYear, so a recent raise/cut shows up immediately
/// instead of being averaged away by a trailing-12-month sum.
class DividendHistory {
  final int frequencyPerYear;
  final double trailing12mTotal;
  final double projectedAnnualPerShare;
  // Sum of upcomingPayments' amounts — "what's still coming this calendar
  // year", date-aware (see upcomingPayments), not just a blended annual
  // estimate minus what's already landed.
  final double remainingThisYearPerShare;
  final List<UpcomingDividendPayment> upcomingPayments;

  const DividendHistory({
    this.frequencyPerYear = 0,
    this.trailing12mTotal = 0.0,
    this.projectedAnnualPerShare = 0.0,
    this.remainingThisYearPerShare = 0.0,
    this.upcomingPayments = const [],
  });

  static const DividendHistory none = DividendHistory();
}

class StockApi {
  // --dart-define first (what a release build should be given — see
  // dartdefines.example.json). Previously fell back straight to a
  // hardcoded 'http://10.0.2.2:5000/api/stock' when PYTHON_BACKEND_URL
  // wasn't set at build time or in a bundled lib/.env — which, since
  // lib/.env stopped being bundled (it leaked BACKEND_API_KEY), is exactly
  // what every release build did: fetchSimulation() below silently hit the
  // emulator's own loopback instead of the deployed Render backend. Now
  // falls back through defaultBackendBaseUrl (dart-define -> local .env ->
  // localhost default), the same chain every other backend call in this
  // app already uses, so a release build actually reaches Render instead
  // of failing closed against a local server that was never running.
  static const String _dartDefinePythonBackendUrl =
      String.fromEnvironment('PYTHON_BACKEND_URL');
  static String get _baseUrl => _dartDefinePythonBackendUrl.isNotEmpty
      ? _dartDefinePythonBackendUrl
      : '$defaultBackendBaseUrl/api/stock';
  static String get _apiBaseUrl => defaultBackendBaseUrl;

  Future<DividendHistory> fetchDividendHistory(String ticker) async {
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/api/dividend_history?ticker=$ticker'),
              headers: await authedBackendHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return DividendHistory.none;
      final data = json.decode(response.body);
      final upcomingRaw = (data['upcoming_payments'] as List?) ?? const [];
      return DividendHistory(
        frequencyPerYear: (data['frequency_per_year'] ?? 0) as int,
        trailing12mTotal: (data['trailing_12m_total'] ?? 0.0).toDouble(),
        projectedAnnualPerShare: (data['projected_annual_per_share'] ?? 0.0).toDouble(),
        remainingThisYearPerShare: (data['remaining_this_year_per_share'] ?? 0.0).toDouble(),
        upcomingPayments: upcomingRaw
            .map((p) => UpcomingDividendPayment(
                  expectedDate: DateTime.parse(p['expected_date'] as String),
                  amountPerShare: (p['amount'] ?? 0.0).toDouble(),
                ))
            .toList(),
      );
    } catch (_) {
      // Non-fatal — callers fall back to the yield-based estimate.
      return DividendHistory.none;
    }
  }

  Future<SimulationResult> fetchSimulation(String ticker, {String period = '1y'}) async {
    try {
      print("Fetching $ticker from $_baseUrl...");
      // 40s, not the usual 10s (fetchDividendHistory above) — the Render
      // free plan idles and takes ~30s to cold-start (§6.2 "Note on the
      // free plan"), and without an explicit timeout here this request
      // used to hang forever with no feedback if the backend/yfinance
      // call stalled for any reason. StockDashboard._runSimulation
      // distinguishes a TimeoutException from other failures for the
      // user-facing message.
      final response = await http
          .get(Uri.parse("$_baseUrl?ticker=$ticker&period=$period"), headers: await authedBackendHeaders())
          .timeout(const Duration(seconds: 40));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String trendStr = data['trend'] ?? 'neutral';
        Trend trend = trendStr == 'up' ? Trend.up : (trendStr == 'down' ? Trend.down : Trend.neutral);

        Map<String, dynamic> macdData = data['macd'] ?? {};
        Map<String, double> macd = {
          'macd': (macdData['macd'] ?? 0).toDouble(),
          'signal': (macdData['signal'] ?? 0).toDouble(),
          'histogram': (macdData['histogram'] ?? 0).toDouble(),
        };

        double riskScore = (data['risk_score_volatility'] ?? 50).toDouble();
        String volatilityLabel = riskScore > 70 ? "High" : (riskScore > 40 ? "Medium" : "Low");
        double maxDrawdown = (data['max_drawdown'] ?? -25).toDouble();

        // Real dividend yield from the backend (yfinance), already a percentage.
        double dividendYield = (data['dividend_yield'] ?? 0.0).toDouble();

        // Settlement term based on market
        String settlementTerm = ticker.endsWith('.KL') ? "T+2" : "T+1";
        
        // Liquidity label based on market cap (simplified)
        String liquidityLabel = ticker.endsWith('.KL') ? "Medium" : "High";


        return SimulationResult(
          ticker: data['symbol'] ?? ticker.toUpperCase(),
          price: (data['current_price'] ?? 0).toDouble(),
          changePercent: (data['change_percent'] ?? 0).toDouble(),
          riskScore: (data['risk_score_volatility'] ?? 50).toDouble(),
          trend: trend,
          aiSentiment: data['ai_sentiment'] ?? "Neutral",
          aiReason: data['ai_reason'] ?? "No data available.",
          expected: (data['expected_price_1y'] ?? 0).toDouble(),
          worst: (data['worst_case_1y'] ?? 0).toDouble(),
          best: (data['best_case_1y'] ?? 0).toDouble(),
          currencyCode: data['currency_code'] ?? 'USD',
          rsi: (data['rsi'] ?? 50).toDouble(),
          ma50: (data['ma50'] ?? 0).toDouble(),
          macd: macd,
          maxDrawdown: maxDrawdown,
          dividendYield: dividendYield,
          settlementTerm: settlementTerm,
          volatilityLabel: volatilityLabel,
          liquidityLabel: liquidityLabel,
          cagr: (data['cagr'] ?? 0).toDouble(),
          momentumScore: (data['momentum_score'] ?? 0).toDouble(),
          marketRegime: data['market_regime'] ?? 'Neutral',
        );
      } else {
        // The backend returns {"error": "..."} for every failure case
        // (rate limits, bad tickers, upstream yfinance errors) — surface
        // that real message instead of a made-up one below.
        String serverMessage = "Server returned HTTP ${response.statusCode}";
        try {
          final body = json.decode(response.body);
          if (body is Map && body['error'] != null) {
            serverMessage = body['error'].toString();
          }
        } catch (_) {
          // Response body wasn't JSON — keep the generic HTTP-status message.
        }
        throw _ServerError(serverMessage);
      }
    } on TimeoutException {
      print("API Error: fetchSimulation($ticker) timed out");
      throw TimeoutException("Timed out waiting for $ticker data");
    } on _ServerError catch (e) {
      // A real response came back, just not a successful one — show the
      // backend's actual reason rather than claiming the backend is down.
      print("API Error: ${e.message}");
      throw Exception(e.message);
    } catch (e) {
      // No response at all (DNS/socket/TLS failure) — this is the only
      // case that's actually "is the backend running?".
      print("API Error: $e");
      throw Exception("Failed to connect. Is the backend running?");
    }
  }
}