import 'dart:async';          // ✅ ADDED for Timer
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../application/investment_logic.dart';
import '../../application/portfolio_state.dart';
import '../../domain/simulation_result.dart';

import '../widgets/triangle_radar_chart.dart';
import '../../../user/application/wealth_state.dart';
import '../../../shared/backend_headers.dart';
import '../../../firestore/constants/firestore_constants.dart';
import '../../../academy/presentation/screens/learning_path_screen.dart';
import 'add_transaction_screen.dart';
import 'simulation_history_screen.dart';

class StockDashboard extends StatefulWidget {
  const StockDashboard({super.key});

  @override
  State<StockDashboard> createState() => _StockDashboardState();
}

class _StockDashboardState extends State<StockDashboard> {
  final InvestmentLogic _logic = InvestmentLogic();
  
  SimulationResult? _data;
  bool _isLoading = false;
  bool _slowLoading = false;      // true once a load has been running a while — reassures the user it isn't frozen
  String? _loadError;             // set on failure/timeout so the spinner never just hangs forever with no feedback
  String _selectedFilter = "All";
  String _selectedPeriod = '1y';
  Timer? _debounceTimer;          // ✅ ADDED
  // Set by the Autocomplete's fieldViewBuilder so the manual-entry "Analyze"
  // button below can read whatever the user typed, even if the dropdown
  // never returned a matching suggestion (previously: onSelected was the
  // ONLY path into _runSimulation, so a ticker the search API didn't
  // resolve — e.g. auth hiccup, an obscure symbol — had literally no way
  // to be analyzed, not even a validation error, just nothing happened).
  TextEditingController? _tickerFieldController;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Color _getColorFromString(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'orange': return Colors.orange;
      case 'red': return Colors.redAccent;
      case 'teal': return Colors.teal;
      case 'indigo': return Colors.indigo;
      case 'green': return Colors.green;
      case 'purple': return Colors.purple;
      case 'blue': return Colors.blueAccent;
      case 'brown': return Colors.brown;
      case 'lime': return Colors.lime;
      case 'grey': return Colors.grey;
      default: return Colors.blueGrey;
    }
  }

  Future<List<Map<String, String>>> _searchStocks(String query) async {
    if (query.isEmpty) return [];

    final baseUrl = defaultBackendBaseUrl;
    final url = Uri.parse("$baseUrl/api/search?q=$query");

    try {
      final response = await http.get(url, headers: await authedBackendHeaders());
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        
        var results = data.map<Map<String, String>>((item) => {
          "symbol": item['symbol'].toString(),
          "name": item['name'].toString(),
          "type": item['type'].toString(),
          "exch": item['exch'].toString(),
          "tag_label": item['tag_label']?.toString() ?? "US", 
          "tag_color": item['tag_color']?.toString() ?? "blue",
        }).toList();

        if (_selectedFilter == "Malaysia (KLCI)") {
          results = results.where((i) => i['symbol']!.toUpperCase().endsWith(".KL")).toList();
        }
        else if (_selectedFilter == "US (S&P500/NDX)") {
          results = results.where((i) => i['tag_label'] == "US" || !i['symbol']!.contains(".")).toList();
        }
        return results;
      }
    } catch (e) {
      print("Search Connection Error: $e");
    }
    return [];
  }

  // ✅ REMOVED unused _runAnalysis – we use _runSimulation instead

  String getRecommendation(double riskTolerance, double stockRisk) {
    if (stockRisk > riskTolerance + 20) return "AVOID (Too Risky)";
    if (stockRisk < riskTolerance - 20) return "BUY (Safe)";
    return "HOLD (Matches Profile)";
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = Provider.of<PortfolioState>(context);
    final wealthState = Provider.of<WealthState>(context);
    
    final currencyCode = _data?.currencyCode ?? 'USD';
    final currencyFormatter = NumberFormat.simpleCurrency(name: currencyCode);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Investment Lab"),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SimulationHistoryScreen()));
            },
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () => _showNotificationDialog(context, portfolio),
              ),
              if (portfolio.pendingTrades.isNotEmpty) 
                Positioned(
                  right: 11, top: 11,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text('${portfolio.pendingTrades.length}', 
                       style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
                  ),
                )
            ],
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. INVESTOR PROFILE HEADER
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 25),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blueAccent.shade700, Colors.purpleAccent.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Your Investor Profile", style: TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1.0)),
                  const SizedBox(height: 5),
                  Text(
                    portfolio.investorType, 
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Based on your actual holdings analysis", 
                    style: TextStyle(color: Colors.white60, fontSize: 10, fontStyle: FontStyle.italic)
                  ),
                ],
              ),
            ),

            // 2. MY PORTFOLIO SECTION
            if (portfolio.holdings.isNotEmpty) ...[
              const Text("My Portfolio", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: portfolio.holdings.length,
                itemBuilder: (ctx, i) {
                  final item = portfolio.holdings[i];
                  final itemFormatter = NumberFormat.simpleCurrency(name: item.currency);
                  
                  double dailyGainVal = item.dailyGainLoss; 
                  double dailyChangePct = item.dailyChange; 
                  
                  Color profitColor = dailyChangePct >= 0 ? Colors.greenAccent : Colors.redAccent;
                  String sign = dailyChangePct >= 0 ? "+" : "";

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 2,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.blueAccent.withOpacity(0.1),
                        child: Text(item.ticker.substring(0,1), style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                      ),
                      
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(item.ticker, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: profitColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4)
                            ),
                            child: Text(
                              "$sign${dailyChangePct.toStringAsFixed(2)}%",
                              style: TextStyle(fontSize: 10, color: profitColor, fontWeight: FontWeight.bold),
                            ),
                          )
                        ],
                      ),
                      
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${item.quantity} units"),
                          const SizedBox(height: 2),
                          Text(
                            "Avg: ${itemFormatter.format(item.avgPrice)}",
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12, 
                              fontStyle: FontStyle.italic
                            ),
                          ),
                        ],
                      ),
                      
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            itemFormatter.format(item.totalValue), 
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                          ),
                          Text(
                            "$sign${itemFormatter.format(dailyGainVal)} Today", 
                            style: TextStyle(fontSize: 11, color: profitColor)
                          )
                        ],
                      ),
                      onTap: () {
                          double priceToUse = item.currentMarketPrice > 0 ? item.currentMarketPrice : item.avgPrice;

                          Navigator.push(context, MaterialPageRoute(builder: (_) => AddTransactionScreen(
                            ticker: item.ticker,
                            currentPrice: priceToUse,
                            currency: item.currency,
                            existingHolding: item, 
                          )));
                        },
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],

            const Text("Market Analysis", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip("All Allowed"),
                  const SizedBox(width: 8),
                  _buildFilterChip("Malaysia (KLCI)"),
                  const SizedBox(width: 8),
                  _buildFilterChip("US (S&P500/NDX)"),
                ],
              ),
            ),
            const SizedBox(height: 15),

            // Debounce with a real cancelable Timer + Completer — the
            // previous version canceled a `_debounceTimer` that was never
            // actually assigned anywhere, so every keystroke independently
            // scheduled its own Future.delayed(300ms, _searchStocks(...)):
            // typing "AAPL" fired 4 real HTTP calls instead of 1 (harmless
            // to correctness, since Autocomplete discards stale out-of-order
            // results, but wasteful load on every keystroke). Now a new
            // keystroke actually cancels the pending Timer before it fires,
            // so only the last keystroke in a burst ever calls _searchStocks.
            Autocomplete<Map<String, String>>(
              key: ValueKey(_selectedFilter),
              optionsBuilder: (TextEditingValue textEditingValue) {
                _debounceTimer?.cancel();
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<Map<String, String>>.empty();
                }
                final completer = Completer<Iterable<Map<String, String>>>();
                _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
                  final result = await _searchStocks(textEditingValue.text);
                  if (!completer.isCompleted) completer.complete(result);
                });
                return completer.future;
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    child: Container(
                      width: 300,
                      color: const Color(0xFF1E1E2C), 
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            leading: _buildTypeTag(option),
                            title: Text(option['symbol']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text(option['name']!, style: const TextStyle(color: Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              onSelected: (Map<String, String> selection) { _runSimulation(selection['symbol']!); },
              displayStringForOption: (Map<String, String> option) => option['symbol']!,
              fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                _tickerFieldController = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onEditingComplete: onEditingComplete,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (value) => _analyzeTypedTicker(),
                  decoration: InputDecoration(
                    labelText: "Search ${_selectedFilter == 'All' ? 'Global' : _selectedFilter} Stocks...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.search),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _analyzeTypedTicker,
                icon: const Icon(Icons.analytics_outlined),
                label: const Text("Analyze Ticker"),
              ),
            ),

            const SizedBox(height: 15),
            const Text("Forecast Settings", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTimeButton("1 Year", '1y'),
                _buildTimeButton("3 Years", '3y'),
                _buildTimeButton("5 Years", '5y'),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      if (_slowLoading) ...[
                        const SizedBox(height: 12),
                        const Text(
                          "Still working, please wait — first request after inactivity can take up to 30s.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_loadError != null)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_loadError!, style: const TextStyle(color: Colors.redAccent))),
                  ],
                ),
              ),

            if (_data != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_data!.ticker, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text(currencyFormatter.format(_data!.price), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      ],
                    ),
                    const Divider(),
                    Row(
                      children: [
                        _buildTag("Trend: ${_data!.trend.name.toUpperCase()}", _data!.trend == Trend.up ? Colors.green : Colors.red),
                        const SizedBox(width: 10),
                        _buildTag("AI: ${_data!.aiSentiment}", _data!.aiSentiment == "Positive" ? Colors.green : Colors.orange),
                        const SizedBox(width: 10),
                        // FR 2.3: Bull/Bear market-regime visual, derived from the
                        // same momentum score (RSI + MACD + price-vs-MA50) that
                        // drives the momentum-adjusted Monte Carlo simulation.
                        _buildTag("Regime: ${_data!.marketRegime.toUpperCase()}",
                            _data!.marketRegime == 'Bull'
                                ? Colors.green
                                : (_data!.marketRegime == 'Bear' ? Colors.red : Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text("AI Insight: ${_data!.aiReason}", style: const TextStyle(fontStyle: FontStyle.italic)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIndicatorChip("RSI", _data!.rsi.toStringAsFixed(1), 
                              _data!.rsi > 70 ? Colors.red : (_data!.rsi < 30 ? Colors.green : Colors.orange)),
                          _buildIndicatorChip("MACD Hist", _data!.macd['histogram']!.toStringAsFixed(2),
                              _data!.macd['histogram']! > 0 ? Colors.green : Colors.red),
                          _buildIndicatorChip("MA50", _data!.ma50.toStringAsFixed(2),
                              _data!.price > _data!.ma50 ? Colors.green : Colors.red),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildRiskWarningBanner(portfolio, _data!),
                    _buildTriangleAttributes(_data!),
                    const SizedBox(height: 20),
                    const Text("TIME MACHINE FORECAST", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildForecastCard("Worst Case", _data!.worst, Colors.redAccent, currencyFormatter),
                        _buildForecastCard("Expected", _data!.expected, Colors.blueAccent, currencyFormatter),
                        _buildForecastCard("Best Case", _data!.best, Colors.green, currencyFormatter),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    const Text("INVESTOR MATCH", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple)),
                    const SizedBox(height: 5),
                    Text(getRecommendation(wealthState.riskTolerance, _data!.riskScore), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.purple)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.history, color: Colors.white),
                      label: const Text("Save Simulation", style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: _saveSimulationToHistory,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shopping_cart),
                      label: const Text("Buy Live"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: () {
                        String currency = _data?.currencyCode ?? "USD";
                        Navigator.push(context, MaterialPageRoute(builder: (_) => AddTransactionScreen(
                          ticker: _data!.ticker,
                          currentPrice: _data!.price,
                          currency: currency, 
                        )));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const SizedBox(height: 20),
              const Center(child: Text("🔺 TRIANGLE RADAR", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2))),
              const SizedBox(height: 5),
              const Center(child: Text("Return vs Safety vs Liquidity", style: TextStyle(color: Colors.grey, fontSize: 12))),
              const SizedBox(height: 15),
              Center(
                child: TriangleRadarChart(
                  returnScore: _data!.expected > 0 ? 70 + (_data!.expected / 10) : 40,
                  safetyScore: 100 - _data!.riskScore,
                  liquidityScore: _data!.liquidityLabel == "High" ? 80 : (_data!.liquidityLabel == "Medium" ? 50 : 30),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _getRadarExplanation(_data!),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Center(
                child: Text(
                  _data!.riskScore > 50 ? "HIGH RISK INVESTMENT" : "SAFE INVESTMENT",
                  style: TextStyle(color: _data!.riskScore > 50 ? Colors.redAccent : Colors.green, fontWeight: FontWeight.bold),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    bool isSelected = _selectedFilter == label;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool value) { setState(() { _selectedFilter = label; }); },
      backgroundColor: Colors.grey.withOpacity(0.1),
      selectedColor: Colors.blueAccent.withOpacity(0.3),
      showCheckmark: false,
    );
  }

  Widget _buildTypeTag(Map<String, String> option) {
    String text = option['tag_label'] ?? "??";
    String colorName = option['tag_color'] ?? "grey";
    Color color = _getColorFromString(colorName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  /// Report 3.1.5 closed loop: a Conservative user looking at a simulation
  /// with a large drawdown should get a warning + a way to act on it, not
  /// just a static profile-based suggestion. Compares the live simulation's
  /// maxDrawdown against the user's classified risk profile and, when they
  /// mismatch, surfaces a warning banner linking straight into a matching
  /// Academy lesson.
  Widget _buildRiskWarningBanner(PortfolioState portfolio, SimulationResult data) {
    final profile = portfolio.investorType; // e.g. "Conservative 🛡️"
    const conservativeDrawdownThreshold = -20.0;
    const balancedDrawdownThreshold = -35.0;

    final isConservative = profile.startsWith('Conservative');
    final isBalanced = profile.startsWith('Balanced');
    final threshold = isConservative
        ? conservativeDrawdownThreshold
        : (isBalanced ? balancedDrawdownThreshold : null);

    if (threshold == null || data.maxDrawdown > threshold) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Risk mismatch: your profile is $profile, but ${data.ticker} shows a "
                    "Max Drawdown of ${data.maxDrawdown.toStringAsFixed(1)}%.",
                    style: const TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LearningPathScreen()),
                ),
                icon: const Icon(Icons.school, size: 16, color: Colors.redAccent),
                label: const Text("Review a matching lesson",
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  void _showNotificationDialog(BuildContext context, PortfolioState portfolio) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Smart Trade Detector"),
        content: SizedBox(
          width: double.maxFinite,
          child: portfolio.pendingTrades.isEmpty 
              ? const Text("No pending trades.\n\nSimulate a trade below!", textAlign: TextAlign.center) 
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: portfolio.pendingTrades.length,
                  itemBuilder: (ctx, i) {
                    final trade = portfolio.pendingTrades[i];
                    return Card(
                      color: Colors.blueAccent.withOpacity(0.1),
                      child: ListTile(
                        title: Text("Buy ${trade.ticker}", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${trade.qty} units @ \$${trade.price}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () { portfolio.rejectTrade(i); Navigator.pop(ctx); },
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: () async {
                                final ticker = trade.ticker;
                                Navigator.pop(ctx);
                                final success = await portfolio.confirmTrade(i);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(success
                                      ? "Added $ticker!"
                                      : "Couldn't add $ticker — please try again."),
                                ));
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              portfolio.parseNotification("Alert", "Buy 50 TSLA at 240.00");
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Simulated SMS Received! Check Bell.")));
            }, 
            child: const Text("Simulate SMS")
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close"))
        ],
      ),
    );
  }

  Widget _buildTimeButton(String label, String value) {
    bool isSelected = _selectedPeriod == value;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blueAccent : const Color(0xFF2D2D44),
        foregroundColor: isSelected ? Colors.white : Colors.grey,
      ),
      onPressed: () {
        setState(() {
          _selectedPeriod = value;
        });
        if (_data != null) {
          _runSimulation(_data!.ticker); 
        }
      },
      child: Text(label),
    );
  }

  Widget _buildForecastCard(String title, double value, Color color, NumberFormat formatter) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          children: [
            Text(title, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 5),
            Text(
              formatter.format(value), 
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Runs an analysis for whatever the user has typed in the search field,
  /// even if the autocomplete dropdown never returned/showed a matching
  /// suggestion for them to tap (the only path into _runSimulation before
  /// this button existed). _runSimulation's own error handling (timeout
  /// message, red error banner) already covers a ticker that doesn't
  /// actually exist, so no separate format validation is needed here.
  void _analyzeTypedTicker() {
    final typed = _tickerFieldController?.text.trim() ?? '';
    if (typed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Type a ticker symbol to analyze first.')));
      return;
    }
    FocusScope.of(context).unfocus();
    _runSimulation(typed.toUpperCase());
  }

  Future<void> _runSimulation(String ticker) async {
    setState(() {
      _isLoading = true;
      _slowLoading = false;
      _loadError = null;
    });

    // Purely cosmetic reassurance — the real timeout lives in
    // StockApi.fetchSimulation (40s, matching the documented Render
    // cold-start delay). This just tells the user it's still working
    // rather than leaving a bare spinner up with no explanation.
    final slowTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _slowLoading = true);
    });

    try {
      final result = await _logic.getPrediction(ticker, period: _selectedPeriod);
      if (!mounted) return;
      setState(() => _data = result);
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _loadError =
          "This is taking too long. The server may be waking up from idle (can take up to 30s) — please try again in a moment.");
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = "Couldn't load $ticker: $e");
    } finally {
      slowTimer.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _slowLoading = false;
        });
      }
    }
  }

  Future<void> _saveSimulationToHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _data == null) return;

    try {
      // Aligned with FirestoreConstants.simulationHistorySubCollection and
      // the field names TimeMachineScreen writes, so this save path is
      // actually visible in SimulationHistoryScreen and CSV/PDF export
      // (report FR 7.3) instead of landing in an orphaned collection.
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.usersCollection)
          .doc(user.uid)
          .collection(FirestoreConstants.simulationHistorySubCollection)
          .add({
        'stockTicker': _data!.ticker,
        'startDate': _selectedPeriod,
        'endDate': '1Y prediction',
        'initialCapital': _data!.price,
        'finalCapital': _data!.expected,
        'cagr': _data!.cagr,
        'maxDrawdown': _data!.maxDrawdown,
        'riskScore': _data!.riskScore,
        'liquidityLabel': _data!.liquidityLabel,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Simulation Result Saved to History!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildIndicatorChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildTriangleAttributes(SimulationResult data) {
    Color getVolatilityColor(String label) {
      if (label == "High") return Colors.redAccent;
      if (label == "Medium") return Colors.orange;
      return Colors.green;
    }
    
    Color getLiquidityColor(String label) {
      if (label == "High") return Colors.green;
      if (label == "Medium") return Colors.orange;
      return Colors.redAccent;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "🔺 TRIANGLE ATTRIBUTES",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          // Wrapped in a horizontal scroll now that this is 5 chips, not 4 —
          // Liquidity was previously missing entirely from this row even
          // though it's one of the three Iron Triangle pillars (Risk,
          // Return, Liquidity) and getLiquidityColor() already existed for
          // exactly this chip, just never wired in.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              // spaceAround needs a bounded width to distribute; inside a
              // horizontally-scrolling (unbounded) Row it's a no-op, so
              // spacing is explicit here instead.
              children: [
                _buildAttributeChip("Volatility", data.volatilityLabel, getVolatilityColor(data.volatilityLabel)),
                const SizedBox(width: 14),
                _buildAttributeChip("Max Drawdown", "${data.maxDrawdown.toStringAsFixed(1)}%", data.maxDrawdown < -30 ? Colors.redAccent : Colors.orange),
                const SizedBox(width: 14),
                _buildAttributeChip("Liquidity", data.liquidityLabel, getLiquidityColor(data.liquidityLabel)),
                const SizedBox(width: 14),
                _buildAttributeChip("Settlement", data.settlementTerm, Colors.blueAccent),
                const SizedBox(width: 14),
                _buildAttributeChip("Dividend Yield", "${data.dividendYield.toStringAsFixed(1)}%", Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _getTriangleExplanation(data),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttributeChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  String _getTriangleExplanation(SimulationResult data) {
    String volatilityNote = data.volatilityLabel == "High" 
        ? "High volatility means larger price swings (higher risk, higher potential return)." 
        : data.volatilityLabel == "Medium" 
        ? "Moderate volatility - balanced risk and return potential." 
        : "Low volatility - stable price movements (lower risk, lower return).";
        
    String liquidityNote = data.liquidityLabel == "High" 
        ? "High liquidity - easy to buy/sell without affecting price." 
        : "Medium liquidity - may face slight slippage during large trades.";
        
    String drawdownNote = data.maxDrawdown < -30 
        ? "⚠️ Large historical drawdown - this stock has experienced significant drops." 
        : "Historical drawdown is manageable for most investors.";
        
    return "$volatilityNote $liquidityNote $drawdownNote";
  }

  String _getRadarExplanation(SimulationResult data) {
    String dominant = "";
    if (data.riskScore > 60) {
      dominant = "📈 Return-focused (Higher risk)";
    } else if (data.riskScore < 30) {
      dominant = "🛡️ Safety-focused (Lower risk)";
    } else {
      dominant = "⚖️ Balanced approach";
    }
    return "$dominant | Liquidity: ${data.liquidityLabel.toLowerCase()}";
  }

}