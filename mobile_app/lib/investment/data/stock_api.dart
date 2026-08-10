import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../domain/simulation_result.dart';
import '../../shared/backend_headers.dart';

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

  const DividendHistory({
    this.frequencyPerYear = 0,
    this.trailing12mTotal = 0.0,
    this.projectedAnnualPerShare = 0.0,
  });

  static const DividendHistory none = DividendHistory();
}

class StockApi {
  // ✅ READ FROM .env
  static String get _baseUrl => dotenv.env['PYTHON_BACKEND_URL'] ?? 'http://10.0.2.2:5000/api/stock';
  static String get _apiBaseUrl =>
      dotenv.env['BACKEND_BASE_URL'] ?? 'http://10.0.2.2:5000';

  Future<DividendHistory> fetchDividendHistory(String ticker) async {
    try {
      final response = await http
          .get(Uri.parse('$_apiBaseUrl/api/dividend_history?ticker=$ticker'),
              headers: await authedBackendHeaders())
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return DividendHistory.none;
      final data = json.decode(response.body);
      return DividendHistory(
        frequencyPerYear: (data['frequency_per_year'] ?? 0) as int,
        trailing12mTotal: (data['trailing_12m_total'] ?? 0.0).toDouble(),
        projectedAnnualPerShare: (data['projected_annual_per_share'] ?? 0.0).toDouble(),
      );
    } catch (_) {
      // Non-fatal — callers fall back to the yield-based estimate.
      return DividendHistory.none;
    }
  }

  Future<SimulationResult> fetchSimulation(String ticker, {String period = '1y'}) async {
    try {
      print("Fetching $ticker from $_baseUrl...");
      final response = await http.get(Uri.parse("$_baseUrl?ticker=$ticker&period=$period"), headers: await authedBackendHeaders());

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
          cagr: 0.0,
          momentumScore: (data['momentum_score'] ?? 0).toDouble(),
          marketRegime: data['market_regime'] ?? 'Neutral',
        );
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      print("API Error: $e");
      throw Exception("Failed to connect. Is Python running?");
    }
  }
}