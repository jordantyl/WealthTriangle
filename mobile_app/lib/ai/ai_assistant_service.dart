import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../investment/application/portfolio_state.dart';
import '../user/application/wealth_state.dart';
import '../academy/application/academy_state.dart';
import '../investment/data/stock_api.dart';
import '../shared/backend_headers.dart';

class AIAssistantService {
  // ✅ FIXED: was http://localhost:11434 — dead on any real device or
  // emulator. Now goes through your Flask backend, which forwards to
  // Ollama running on the laptop.
  static String get _baseUrl =>
      dotenv.env['BACKEND_BASE_URL'] ?? 'http://10.0.2.2:5000';

  final WealthState wealthState;
  final PortfolioState portfolioState;
  final AcademyState academyState;

  AIAssistantService({
    required this.wealthState,
    required this.portfolioState,
    required this.academyState,
  });

  String get _systemPrompt {
    return """
You are the internal assistant of the Wealth Triangle App. You can only do the following:
1. Query real-time/historical data for Malaysian and US stocks (MA, RSI, PE, price, etc.).
2. Start or query backtesting simulations.
3. Query the user's simulated holdings, profit/loss, and Triangle Health Score.
4. Interpret the above data, providing educational analysis from the 'Return-Safety-Liquidity' Triangle perspective.
5. For any question beyond this scope, always reply: 'I can only assist you with investment learning and simulation-related matters.'
Before executing any action that would modify the user's account, you must output a clear description of the operation and request user confirmation.
""";
  }

  static const String toolDefinition = '''
Available tools:
- get_stock_data(ticker, period): Returns current price, RSI, MA50, and Triangle attributes.
- run_backtest(ticker, start_date, end_date): Runs a historical simulation.
- get_user_triangle_health(): Returns the user's current Return-Safety-Liquidity scores.
- add_to_watchlist(ticker): Adds a stock to the user's watchlist (requires confirmation).
- get_portfolio_summary(): Returns the user's current holdings and P&L.
''';

  Future<Map<String, dynamic>> processQuery(String userQuery) async {
    final prompt = """
$_systemPrompt

$toolDefinition

User Profile:
- Risk Tolerance: ${wealthState.riskTolerance}
- Safety Score: ${wealthState.safetyScore}
- Passive Income: \$${wealthState.totalPassiveIncome}

User Query: "$userQuery"

Return your response in JSON format with keys: "action" (the tool name or "chat"), "parameters" (the tool parameters), "confirmation_needed" (true/false), and "message" (your natural language response).
""";

    try {
      final headers = await authedBackendHeaders({'Content-Type': 'application/json'});
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/assistant'),
            headers: headers,
            body: json.encode({'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final responseText = data['response'] as String;
        try {
          return json.decode(_stripJsonFence(responseText));
        } catch (_) {
          return {
            'action': 'chat',
            'message': responseText,
            'confirmation_needed': false,
          };
        }
      }
    } catch (e) {
      print("Assistant Error: $e");
    }

    return {
      'action': 'chat',
      'message':
          'I am having trouble connecting to my brain. Please make sure the backend server and Ollama are running.',
      'confirmation_needed': false,
    };
  }

  // Gemini (and sometimes other models) often wrap JSON replies in a
  // ```json ... ``` markdown fence even when told to return raw JSON.
  // json.decode() chokes on that, so strip it before parsing — otherwise
  // the whole raw response (fence, braces, literal \n and all) leaks into
  // the chat bubble as the fallback "message" instead of being parsed.
  String _stripJsonFence(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      t = t.substring(3);
      if (t.startsWith('json')) t = t.substring(4);
      final end = t.lastIndexOf('```');
      if (end != -1) t = t.substring(0, end);
    }
    return t.trim();
  }

  Future<String> executeTool(String action, Map<String, dynamic> params) async {
    switch (action) {
      case 'get_stock_data':
        return await _getStockData(params['ticker'] ?? 'AAPL');
      case 'get_user_triangle_health':
        return _getUserTriangleHealth();
      case 'get_portfolio_summary':
        return _getPortfolioSummary();
      case 'run_backtest':
        return await _runBacktest(params['ticker'] ?? 'AAPL');
      case 'add_to_watchlist':
        return await _addToWatchlist(params['ticker'] ?? 'AAPL');
      default:
        return 'Unknown action: $action';
    }
  }

  Future<String> _runBacktest(String ticker) async {
    try {
      final api = StockApi();
      final result = await api.fetchSimulation(ticker);
      return "Backtest for $ticker complete. Expected 1Y Price: \$${result.expected}. Max Drawdown historically was ${result.maxDrawdown}%. This heavily impacts the Safety aspect of the Iron Triangle.";
    } catch (e) {
      return "Failed to run backtest on $ticker.";
    }
  }

  Future<String> _addToWatchlist(String ticker) async {
    // ✅ IMPROVED: actually persists via WealthState (was a fake success
    // message before).
    final current = List<String>.from(wealthState.watchlist);
    if (!current.contains(ticker.toUpperCase())) {
      current.add(ticker.toUpperCase());
      await wealthState.updateWatchlist(current);
    }
    return "Successfully added $ticker to your watchlist. Keep an eye on its Liquidity and Volatility!";
  }

  Future<String> _getStockData(String ticker) async {
    try {
      final api = StockApi();
      final result = await api.fetchSimulation(ticker);
      return """
  Stock Data for $ticker:
  - Current Price: \$${result.price}
  - 1Y Expected Price: \$${result.expected}
  - Triangle Attributes:
    - Return Trend: ${result.trend.name}
    - Safety (Volatility): ${result.volatilityLabel}
    - Liquidity: ${result.liquidityLabel}
  - AI Sentiment: ${result.aiSentiment} (${result.aiReason})
  """;
    } catch (e) {
      return "Error fetching data for $ticker. Please check the symbol and try again.";
    }
  }

  String _getUserTriangleHealth() {
    return """
  Your Triangle Health Overview:
  - UNIFIED TRIANGLE SCORE: ${wealthState.triangleHealthScore.toStringAsFixed(1)}/100
  - Return Potential (Simulated Dividends): \$${portfolioState.totalSimulatedAnnualDividend.toStringAsFixed(0)}/year
  - Safety Score (Emergency Fund + Risk): ${wealthState.safetyScore.toStringAsFixed(0)}/100
  - Liquidity (Cash vs Total Assets): ${wealthState.liquidityScore.toStringAsFixed(0)}/100
  - User Preference: ${wealthState.trianglePreference.name.toUpperCase()}

  Advice for AI: Use the Unified Triangle Score and User Preference to guide your recommendations.
  """;
  }

  String _getPortfolioSummary() {
    if (portfolioState.holdings.isEmpty) {
      return "You have no holdings. Start by analyzing a stock!";
    }
    String summary = "Your Portfolio:\n";
    for (var item in portfolioState.holdings) {
      summary +=
          "- ${item.ticker}: ${item.quantity} units, Value: \$${item.totalValue.toStringAsFixed(0)}\n";
    }
    return summary;
  }
}