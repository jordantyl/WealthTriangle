import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../domain/simulation_result.dart';
import '../../shared/backend_headers.dart';

class StockApi {
  // ✅ READ FROM .env
  static String get _baseUrl => dotenv.env['PYTHON_BACKEND_URL'] ?? 'http://10.0.2.2:5000/api/stock';

  Future<SimulationResult> fetchSimulation(String ticker, {String period = '1y'}) async {
    try {
      print("Fetching $ticker from $_baseUrl...");
      final response = await http.get(Uri.parse("$_baseUrl?ticker=$ticker&period=$period"), headers: backendHeaders());

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