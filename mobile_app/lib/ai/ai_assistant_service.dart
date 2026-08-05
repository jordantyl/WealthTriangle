import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../investment/application/portfolio_state.dart';
import '../user/application/wealth_state.dart';
import '../academy/application/academy_state.dart';
import '../investment/data/stock_api.dart';
import '../shared/backend_headers.dart';

/// Mutating tools (anything that writes to the user's portfolio or profile).
/// Kept as a static set — rather than trusting the LLM's own
/// "confirmation_needed" flag — so a bad/hallucinated model response can
/// never silently skip the confirmation dialog for a real write.
const Set<String> mutatingAiActions = {
  'record_holding',
  'sell_holding',
  'remove_holding',
  'add_to_watchlist',
  'remove_from_watchlist',
  'set_salary',
  'set_expenses',
  'set_savings',
  'set_financial_goal',
  'set_risk_tolerance',
  'add_income_source',
  'remove_income_source',
  'set_triangle_preference',
};

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
5. Operate the app on the user's behalf: record/sell/remove stock holdings, manage the watchlist,
   and update their financial profile (salary, expenses, savings, financial goal, risk tolerance,
   income sources, Triangle preference).
6. For any question beyond this scope, always reply: 'I can only assist you with investment learning and simulation-related matters.'

`ticker` parameters may be a company name or partial ticker (e.g. "RHB", "Maybank", "Apple") — the
app will resolve it to an exact symbol itself, so pass through whatever the user said rather than
guessing a symbol yourself.
Every action that would modify the user's account always requires user confirmation — the app
enforces this itself, so just set confirmation_needed accordingly and describe the operation
clearly in "message".
""";
  }

  static const String toolDefinition = '''
Available tools:

Read-only:
- get_stock_data(ticker, period): Returns current price, RSI, MA50, and Triangle attributes.
- run_backtest(ticker, start_date, end_date): Runs a historical simulation.
- get_user_triangle_health(): Returns the user's current Return-Safety-Liquidity scores.
- get_portfolio_summary(): Returns the user's current holdings and P&L.

Mutating (require confirmation):
- record_holding(ticker, quantity, price): Records a stock purchase (adds to or creates a holding).
- sell_holding(ticker, quantity, price): Sells shares from an existing holding.
- remove_holding(ticker): Removes a holding entirely from the portfolio.
- add_to_watchlist(ticker): Adds a stock to the user's watchlist.
- remove_from_watchlist(ticker): Removes a stock from the user's watchlist.
- set_salary(amount): Sets the user's monthly salary.
- set_expenses(amount): Sets the user's monthly expenses.
- set_savings(amount): Sets the user's current cash savings.
- set_financial_goal(amount, target_date): Sets a financial goal amount and optional target date (YYYY-MM-DD).
- set_risk_tolerance(value): Sets risk tolerance, 0-100.
- add_income_source(name, amount, is_monthly): Adds a passive income source.
- remove_income_source(name): Removes a passive income source by name.
- set_triangle_preference(preference): Sets Triangle preference to one of "balanced", "safety", "liquidity", "return".
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

  /// Resolves free-text like "RHB" or "Apple" against the backend's stock
  /// search (the same one the manual Add Transaction ticker picker uses)
  /// and returns the top match, or null if nothing came back.
  Future<Map<String, String>?> _resolveTicker(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/search?q=${Uri.encodeQueryComponent(trimmed)}'),
        headers: backendHeaders(),
      );
      if (response.statusCode != 200) return null;
      final List data = json.decode(response.body);
      if (data.isEmpty) return null;

      final upper = trimmed.toUpperCase();
      final exact = data.firstWhere(
        (item) => (item['symbol']?.toString().toUpperCase() ?? '') == upper,
        orElse: () => null,
      );
      final best = exact ?? data.first;
      return {
        'symbol': best['symbol'].toString(),
        'name': best['name']?.toString() ?? best['symbol'].toString(),
      };
    } catch (e) {
      print("Ticker resolve error: $e");
      return null;
    }
  }

  String _inferCurrency(String ticker) => ticker.toUpperCase().endsWith('.KL') ? 'MYR' : 'USD';

  /// Enriches/validates the raw parameters the model returned before they're
  /// shown in a confirmation dialog or executed — mainly resolving
  /// free-text tickers to real symbols and finding the right income source
  /// to remove. Returns params with an "error" key set if something
  /// couldn't be resolved, so the caller can show that instead of a
  /// confirmation dialog.
  Future<Map<String, dynamic>> prepareAction(String action, Map<String, dynamic> params) async {
    final prepared = Map<String, dynamic>.from(params);

    switch (action) {
      case 'record_holding':
      case 'sell_holding':
      case 'remove_holding':
      case 'add_to_watchlist':
      case 'remove_from_watchlist':
        final rawTicker = (prepared['ticker'] ?? '').toString();
        if (rawTicker.isEmpty) {
          return {...prepared, 'error': 'No ticker was given.'};
        }

        // For sell/remove, prefer matching an existing holding/watchlist
        // entry the user actually has, rather than re-resolving against
        // the full market search (which could return an unrelated symbol
        // that happens to share the name).
        if (action == 'sell_holding' || action == 'remove_holding') {
          final existing = portfolioState.holdings.where(
            (h) => h.ticker.toUpperCase().contains(rawTicker.toUpperCase()) ||
                rawTicker.toUpperCase().contains(h.ticker.toUpperCase()),
          );
          if (existing.isNotEmpty) {
            prepared['ticker'] = existing.first.ticker;
            break;
          }
        }
        if (action == 'remove_from_watchlist') {
          final existing = wealthState.watchlist.where(
            (t) => t.toUpperCase().contains(rawTicker.toUpperCase()) ||
                rawTicker.toUpperCase().contains(t.toUpperCase()),
          );
          if (existing.isNotEmpty) {
            final match = existing.first;
            // Default starter tickers are off-limits to the AI assistant
            // too — reject here, before a confirmation dialog is even
            // offered, rather than letting WealthState's write silently
            // no-op after the user already confirmed.
            if (wealthState.isDefaultTicker(match)) {
              return {
                ...prepared,
                'error': '$match is one of your default watchlist tickers and can\'t be removed — '
                    'only tickers you added yourself can be removed.',
              };
            }
            prepared['ticker'] = match;
            break;
          }
        }

        final resolved = await _resolveTicker(rawTicker);
        if (resolved == null) {
          return {...prepared, 'error': 'Could not find a stock matching "$rawTicker".'};
        }
        prepared['ticker'] = resolved['symbol'];
        prepared['resolvedName'] = resolved['name'];
        if (action == 'record_holding' || action == 'sell_holding') {
          prepared['currency'] = _inferCurrency(resolved['symbol']!);
        }
        break;

      case 'remove_income_source':
        final name = (prepared['name'] ?? '').toString();
        final index = wealthState.incomeSources.indexWhere(
          (s) => s.name.toLowerCase() == name.toLowerCase(),
        );
        if (index == -1) {
          return {...prepared, 'error': 'No income source named "$name" was found.'};
        }
        prepared['index'] = index;
        break;
    }

    return prepared;
  }

  /// Builds the human-readable confirmation text for a mutating action,
  /// using the already-resolved params from [prepareAction] — never the
  /// model's own free-text "message", so the user is confirming the exact
  /// values that will actually be written.
  String describeAction(String action, Map<String, dynamic> params) {
    switch (action) {
      case 'record_holding':
        return 'Record a BUY of ${params['quantity']} shares of ${params['ticker']} '
            '(${params['resolvedName'] ?? ''}) at ${params['currency']} ${params['price']} each?';
      case 'sell_holding':
        return 'Sell ${params['quantity']} shares of ${params['ticker']} at ${params['currency'] ?? ''} ${params['price']} each?';
      case 'remove_holding':
        return 'Remove your entire ${params['ticker']} holding from your portfolio?';
      case 'add_to_watchlist':
        return 'Add ${params['ticker']} (${params['resolvedName'] ?? ''}) to your watchlist?';
      case 'remove_from_watchlist':
        return 'Remove ${params['ticker']} from your watchlist?';
      case 'set_salary':
        return 'Set your monthly salary to \$${params['amount']}?';
      case 'set_expenses':
        return 'Set your monthly expenses to \$${params['amount']}?';
      case 'set_savings':
        return 'Set your current savings to \$${params['amount']}?';
      case 'set_financial_goal':
        final date = params['target_date'];
        return 'Set a financial goal of \$${params['amount']}${date != null ? ' by $date' : ''}?';
      case 'set_risk_tolerance':
        return 'Set your risk tolerance to ${params['value']}/100?';
      case 'add_income_source':
        final freq = (params['is_monthly'] == false) ? 'yearly' : 'monthly';
        return 'Add income source "${params['name']}" of \$${params['amount']} ($freq)?';
      case 'remove_income_source':
        return 'Remove income source "${params['name']}"?';
      case 'set_triangle_preference':
        return 'Set your Triangle preference to "${params['preference']}"?';
      default:
        return 'Are you sure?';
    }
  }

  double _asDouble(dynamic v, [double fallback = 0]) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? fallback;
  }

  int _asInt(dynamic v, [int fallback = 0]) {
    if (v is num) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
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
      case 'remove_from_watchlist':
        return await _removeFromWatchlist(params['ticker'] ?? '');
      case 'record_holding':
        return await _recordHolding(params);
      case 'sell_holding':
        return await _sellHolding(params);
      case 'remove_holding':
        return await _removeHolding(params['ticker'] ?? '');
      case 'set_salary':
        wealthState.updateSalary(_asDouble(params['amount']));
        return "Monthly salary updated to \$${_asDouble(params['amount']).toStringAsFixed(0)}.";
      case 'set_expenses':
        wealthState.updateExpenses(_asDouble(params['amount']));
        return "Monthly expenses updated to \$${_asDouble(params['amount']).toStringAsFixed(0)}.";
      case 'set_savings':
        wealthState.updateSavings(_asDouble(params['amount']));
        return "Current savings updated to \$${_asDouble(params['amount']).toStringAsFixed(0)}.";
      case 'set_financial_goal':
        final date = DateTime.tryParse(params['target_date']?.toString() ?? '') ??
            DateTime.now().add(const Duration(days: 365));
        wealthState.setFinancialGoal(_asDouble(params['amount']), date);
        return "Financial goal set to \$${_asDouble(params['amount']).toStringAsFixed(0)} by ${date.toIso8601String().split('T').first}.";
      case 'set_risk_tolerance':
        wealthState.updateRiskTolerance(_asDouble(params['value']).clamp(0, 100));
        return "Risk tolerance set to ${_asDouble(params['value']).clamp(0, 100).toStringAsFixed(0)}/100.";
      case 'add_income_source':
        wealthState.addIncomeSource(
          (params['name'] ?? 'Income').toString(),
          _asDouble(params['amount']),
          params['is_monthly'] != false,
        );
        return "Added income source \"${params['name']}\".";
      case 'remove_income_source':
        if (params['index'] is int) {
          wealthState.removeIncomeSource(params['index']);
          return "Removed income source \"${params['name']}\".";
        }
        return "Couldn't find that income source.";
      case 'set_triangle_preference':
        final pref = _parseTrianglePreference(params['preference']?.toString() ?? '');
        if (pref == null) return "Unrecognized Triangle preference.";
        await wealthState.updateTrianglePreference(pref);
        return "Triangle preference set to ${pref.name}.";
      default:
        return 'Unknown action: $action';
    }
  }

  TrianglePreference? _parseTrianglePreference(String value) {
    switch (value.toLowerCase().trim()) {
      case 'balanced':
        return TrianglePreference.balanced;
      case 'safety':
        return TrianglePreference.safety;
      case 'liquidity':
        return TrianglePreference.liquidity;
      case 'return':
      case 'return_':
        return TrianglePreference.return_;
      default:
        return null;
    }
  }

  Future<String> _recordHolding(Map<String, dynamic> params) async {
    final ticker = (params['ticker'] ?? '').toString();
    final qty = _asInt(params['quantity']);
    final price = _asDouble(params['price']);
    final currency = (params['currency'] ?? _inferCurrency(ticker)).toString();
    if (ticker.isEmpty || qty <= 0 || price <= 0) {
      return "Couldn't record that holding — missing ticker, quantity, or price.";
    }
    await portfolioState.buyStock(ticker, qty, price, currency);
    return "Recorded $qty shares of $ticker at $currency ${price.toStringAsFixed(2)}.";
  }

  Future<String> _sellHolding(Map<String, dynamic> params) async {
    final ticker = (params['ticker'] ?? '').toString();
    final qty = _asInt(params['quantity']);
    final price = _asDouble(params['price']);
    if (ticker.isEmpty || qty <= 0 || price <= 0) {
      return "Couldn't sell that holding — missing ticker, quantity, or price.";
    }
    final error = await portfolioState.sellStock(ticker, qty, price);
    if (error != null) return error;
    return "Sold $qty shares of $ticker at ${price.toStringAsFixed(2)}.";
  }

  Future<String> _removeHolding(String ticker) async {
    if (ticker.isEmpty) return "No ticker given.";
    await portfolioState.deleteHolding(ticker);
    return "Removed $ticker from your portfolio.";
  }

  Future<String> _removeFromWatchlist(String ticker) async {
    if (ticker.isEmpty) return "No ticker given.";
    try {
      await wealthState.removeFromWatchlist(ticker);
      return "Removed $ticker from your watchlist.";
    } on WatchlistProtectedException catch (e) {
      // prepareAction already filters this out before confirmation, but
      // this stays as a hard backstop against the write itself.
      return e.toString();
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
    await wealthState.addToWatchlist(ticker);
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
  - Return Potential (Dividend Income): \$${portfolioState.totalAnnualDividendIncome.toStringAsFixed(0)}/year
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
