import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:candlesticks/candlesticks.dart' as pkg;

import '../../../firestore/constants/firestore_constants.dart';
import 'simulation_history_screen.dart';
import 'ticker_search_field.dart';
import '../../../academy/application/badge_service.dart';
import '../../../shared/backend_headers.dart';

/// ⏳ TIME MACHINE — the core feature from the report (2.4, 3.1.3, 3.1.7).
/// User picks a ticker, a custom START/END date, and virtual capital.
/// The backend simulates the holding period with a liquidity slippage
/// penalty, then the result is saved to the user's simulation history.
class TimeMachineScreen extends StatefulWidget {
  const TimeMachineScreen({super.key});

  @override
  State<TimeMachineScreen> createState() => _TimeMachineScreenState();
}

class _TimeMachineScreenState extends State<TimeMachineScreen> {
  final TextEditingController _tickerCtrl = TextEditingController(text: 'AAPL');
  final TextEditingController _capitalCtrl = TextEditingController(text: '10000');

  DateTime _startDate = DateTime(DateTime.now().year - 3, 1, 1);
  DateTime _endDate = DateTime.now().subtract(const Duration(days: 1));

  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _result;

  // Base URL without the /api/stock path.
  // Add BACKEND_BASE_URL=http://10.0.2.2:5000 to your .env
  String get _baseUrl =>
      dotenv.env['BACKEND_BASE_URL'] ?? 'http://10.0.2.2:5000';

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate.add(const Duration(days: 30));
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _runSimulation() async {
    final ticker = _tickerCtrl.text.trim().toUpperCase();
    final capital = double.tryParse(_capitalCtrl.text.trim()) ?? 0;

    if (ticker.isEmpty) {
      setState(() => _error = 'Please enter a stock ticker.');
      return;
    }
    if (capital <= 0) {
      setState(() => _error = 'Virtual capital must be greater than 0.');
      return;
    }
    if (!_endDate.isAfter(_startDate)) {
      setState(() => _error = 'End date must be after start date.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    final fmt = DateFormat('yyyy-MM-dd');
    final url =
        '$_baseUrl/api/backtest?ticker=$ticker&start=${fmt.format(_startDate)}&end=${fmt.format(_endDate)}&capital=$capital';

    try {
      final response = await http
          .get(Uri.parse(url), headers: await authedBackendHeaders())
          .timeout(const Duration(seconds: 20));
      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        setState(() => _result = data);
        await _saveToHistory(data);

        // 🏅 Badge awards (req 3.4)
        if (mounted) {
          await BadgeService.award(context, 'time_traveler');
          final dd = (data['max_drawdown'] as num?)?.toDouble() ?? 0;
          if (dd < -30 && mounted) {
            await BadgeService.award(context, 'crash_survivor');
          }
        }
      } else {
        setState(() => _error = data['error'] ?? 'Simulation failed.');
      }
    } catch (e) {
      setState(() =>
          _error = 'Could not reach the backend. Is the Python server running?');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Saves the run so SimulationHistoryScreen and the CSV export
  /// (Report 7.3) both read the SAME collection and field names.
  Future<void> _saveToHistory(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection(FirestoreConstants.usersCollection)
          .doc(user.uid)
          .collection(FirestoreConstants.simulationHistorySubCollection)
          .add({
        'stockTicker': data['symbol'],
        'startDate': data['start_date'],
        'endDate': data['end_date'],
        'initialCapital': data['initial_capital'],
        'finalCapital': data['final_capital'],
        'cagr': data['cagr'],
        'maxDrawdown': data['max_drawdown'],
        'riskScore': data['risk_score_volatility'],
        'liquidityLabel': data['liquidity_label'],
        'slippagePct': data['slippage_pct'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to save simulation history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyCode = _result?['currency_code'] ?? 'USD';
    final currency = NumberFormat.simpleCurrency(name: currencyCode);
    final fmt = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('⏳ Time Machine'),
        actions: [
          IconButton(
            tooltip: 'Simulation History',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SimulationHistoryScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Travel back in time. See exactly how your money would have grown — or shrunk.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // ✅ Autocomplete: type "maybank" and pick 1155.KL from the list
            TickerSearchField(controller: _tickerCtrl),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(
                  child: _dateBox('START', fmt.format(_startDate),
                      () => _pickDate(true)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, color: Colors.grey),
                ),
                Expanded(
                  child: _dateBox('END', fmt.format(_endDate),
                      () => _pickDate(false)),
                ),
              ],
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _capitalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Virtual Capital (\$)',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _runSimulation,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.rocket_launch),
                label: Text(_isLoading ? 'Simulating...' : 'RUN TIME MACHINE'),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ],

            if (_result != null) ...[
              const SizedBox(height: 25),
              _buildResultCard(currency),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateBox(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  List<pkg.Candle> _packageCandles() {
    final raw = _result?['price_series'] as List? ?? const [];
    final fmt = DateFormat('yyyy-MM-dd');
    final candles = raw.map((c) {
      final m = c as Map<String, dynamic>;
      return pkg.Candle(
        date: fmt.parse(m['date'] as String),
        open: (m['open'] as num).toDouble(),
        high: (m['high'] as num).toDouble(),
        low: (m['low'] as num).toDouble(),
        close: (m['close'] as num).toDouble(),
        volume: (m['volume'] as num).toDouble(),
      );
    }).toList();
    // Package wants newest-first; backend returns oldest-first.
    return candles.reversed.toList();
  }

  /// Merges dividend + split events (both from the raw trading-day frame,
  /// see backend/algorithms.py:extract_price_series) into one chronological
  /// (newest-first) timeline so the "what actually happened" detail view
  /// isn't just a price chart — it shows what moved the price too.
  List<_TimelineEvent> _mergedEvents() {
    final r = _result;
    if (r == null) return const [];
    final events = <_TimelineEvent>[];
    for (final e in (r['dividend_events'] as List? ?? const [])) {
      final m = e as Map<String, dynamic>;
      events.add(_TimelineEvent(
        date: DateTime.parse(m['date'] as String),
        icon: Icons.savings,
        color: Colors.greenAccent,
        label: 'Dividend paid',
        detail: '\$${(m['amount'] as num).toDouble().toStringAsFixed(4)} / share',
      ));
    }
    for (final e in (r['split_events'] as List? ?? const [])) {
      final m = e as Map<String, dynamic>;
      final ratio = (m['ratio'] as num).toDouble();
      events.add(_TimelineEvent(
        date: DateTime.parse(m['date'] as String),
        icon: Icons.call_split,
        color: Colors.cyanAccent,
        label: 'Stock split',
        detail: '${ratio.toStringAsFixed(ratio.truncateToDouble() == ratio ? 0 : 2)}:1',
      ));
    }
    events.sort((a, b) => b.date.compareTo(a.date));
    return events;
  }

  Widget _buildChartSection() {
    final candles = _packageCandles();
    if (candles.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('📈 PRICE HISTORY',
            style: TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 10),
        SizedBox(
          height: 260,
          child: pkg.Candlesticks(candles: candles),
        ),
      ],
    );
  }

  Widget _buildEventTimeline() {
    final events = _mergedEvents();
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'No dividend payments or stock splits occurred during this window.',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
      );
    }
    final fmt = DateFormat('dd MMM yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: events.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(e.icon, color: e.color, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.label,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(fmt.format(e.date),
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
              Text(e.detail,
                  style: TextStyle(color: e.color, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildResultCard(NumberFormat currency) {
    final r = _result!;
    final double profit = (r['profit'] as num?)?.toDouble() ?? 0.0;
    final double initialCapital = (r['initial_capital'] as num?)?.toDouble() ?? 0.0;
    final double finalCapital = (r['final_capital'] as num?)?.toDouble() ?? 0.0;
    final double liquidityPenaltyCost = (r['liquidity_penalty_cost'] as num?)?.toDouble() ?? 0.0;
    final double dividendsReceived = (r['dividends_received'] as num?)?.toDouble() ?? 0.0;
    final double totalReturnProfit = (r['total_return_profit'] as num?)?.toDouble() ?? profit;
    final bool isWin = totalReturnProfit >= 0;
    final Color mainColor = isWin ? Colors.greenAccent : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D44),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mainColor.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Text(isWin ? '📈 YOU WOULD HAVE MADE' : '📉 YOU WOULD HAVE LOST',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 5),
                Text(
                  '${isWin ? '+' : ''}${currency.format(totalReturnProfit)}',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: mainColor),
                ),
                Text(
                  '${currency.format(initialCapital)} → ${currency.format(finalCapital + dividendsReceived)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (dividendsReceived > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${currency.format(profit)} from price change  +  ${currency.format(dividendsReceived)} from dividends',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 30, color: Colors.white24),

          _buildChartSection(),
          if (_packageCandles().length >= 2)
            const Divider(height: 30, color: Colors.white24),

          const Text('🗓️ EVENTS DURING THIS PERIOD',
              style: TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 10),
          _buildEventTimeline(),
          const Divider(height: 30, color: Colors.white24),

          // 🔺 IRON TRIANGLE BREAKDOWN
          const Text('🔺 IRON TRIANGLE BREAKDOWN',
              style: TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
          const SizedBox(height: 12),
          _metricRow('RETURN', 'CAGR', '${r['cagr']}%/year',
              Colors.blueAccent),
          _metricRow('SAFETY', 'Max Drawdown', '${r['max_drawdown']}%',
              Colors.orangeAccent),
          _metricRow('SAFETY', 'Volatility Risk',
              '${r['risk_score_volatility']}/100', Colors.orangeAccent),
          _metricRow('LIQUIDITY', 'Market Liquidity',
              '${r['liquidity_label']}', Colors.cyanAccent),
          _metricRow('LIQUIDITY', 'Slippage Penalty',
              '${r['slippage_pct']}% (cost ${currency.format(liquidityPenaltyCost)})',
              Colors.cyanAccent),

          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _lesson(r),
              style: const TextStyle(
                  color: Colors.amber, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(String pillar, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(pillar,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: color, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
          Text(value,
              style:
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _lesson(Map<String, dynamic> r) {
    final dd = (r['max_drawdown'] as num?)?.toDouble() ?? 0.0;
    final cagr = (r['cagr'] as num?)?.toDouble() ?? 0.0;
    if (dd < -40) {
      return 'Lesson: This asset dropped ${dd.abs().toStringAsFixed(0)}% at its worst. Could you have held on without panic-selling? High Return often costs Safety.';
    } else if (r['liquidity_label'] == 'Illiquid') {
      return 'Lesson: This asset has low trading volume. Your slippage penalty shows how hard it is to exit an illiquid position quickly.';
    } else if (cagr > 15) {
      return 'Lesson: Strong returns! But check the drawdown — sustainable growth balances all three sides of the Triangle.';
    }
    return 'Lesson: Compare this run against a different date range (e.g. include 2020) to see how market crashes affect the same strategy.';
  }
}

class _TimelineEvent {
  final DateTime date;
  final IconData icon;
  final Color color;
  final String label;
  final String detail;

  const _TimelineEvent({
    required this.date,
    required this.icon,
    required this.color,
    required this.label,
    required this.detail,
  });
}