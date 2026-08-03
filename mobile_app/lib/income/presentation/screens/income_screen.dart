import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../user/application/wealth_state.dart';
import '../../../investment/application/portfolio_state.dart';
import '../../../event_integrate/application/event_intelligence_state.dart';
import '../../../event_integrate/domain/economic_event.dart';
import 'cash_flow_screen.dart';

class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  // Real upcoming dividend ex-dates for held stocks, sourced from the same
  // Event Integration service the Economic Calendar uses — rather than only
  // showing PortfolioState's flat simulated-yield estimate, this gives an
  // actual per-holding payout tracker (ticker, ex-date, $/share).
  List<EconomicEvent> _dividendEvents = [];
  bool _loadingDividends = true;
  List<String> _lastFetchedTickers = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadDividends());
  }

  bool _sameTickers(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _maybeLoadDividends() async {
    if (!mounted) return;
    final tickers = Provider.of<PortfolioState>(context, listen: false)
        .holdings
        .map((h) => h.ticker)
        .toList();

    if (tickers.isEmpty) {
      if (_dividendEvents.isEmpty && !_loadingDividends) return;
      setState(() {
        _dividendEvents = [];
        _loadingDividends = false;
        _lastFetchedTickers = [];
      });
      return;
    }

    if (_sameTickers(tickers, _lastFetchedTickers)) return;

    setState(() => _loadingDividends = true);
    final service = Provider.of<EventIntegrationState>(context, listen: false).api;
    try {
      final events = await service.fetchEventsForWatchlist(tickers);
      if (!mounted) return;
      final upcomingDividends = events
          .where((e) => e.type == EventType.dividendExDate && e.isUpcoming)
          .toList()
        ..sort((a, b) => a.eventDate.compareTo(b.eventDate));
      setState(() {
        _dividendEvents = upcomingDividends;
        _lastFetchedTickers = tickers;
        _loadingDividends = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDividends = false);
    }
  }

  void _showAddDialog(BuildContext context) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    // ✅ FIXED: was hardcoded to monthly — now the user can choose.
    bool isMonthly = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D44),
          title: const Text("Add Side Hustle",
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: "Name (e.g. YouTube)")),
              TextField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: "Amount (RM)"),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 15),
              // ✅ NEW: frequency selector
              Row(
                children: [
                  const Text("Frequency:",
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text("Monthly")),
                        ButtonSegment(value: false, label: Text("Yearly")),
                      ],
                      selected: {isMonthly},
                      onSelectionChanged: (sel) =>
                          setDialogState(() => isMonthly = sel.first),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                child: const Text("CANCEL"),
                onPressed: () => Navigator.pop(ctx)),
            ElevatedButton(
              child: const Text("ADD"),
              onPressed: () {
                final amount = double.tryParse(amountController.text) ?? 0;
                if (nameController.text.isNotEmpty && amount > 0) {
                  Provider.of<WealthState>(context, listen: false)
                      .addIncomeSource(
                          nameController.text, amount, isMonthly);
                }
                Navigator.pop(ctx);
              },
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wealthState = Provider.of<WealthState>(context);
    final portfolio = Provider.of<PortfolioState>(context);

    // Holdings can change (buy/sell) independently of this widget's own
    // rebuilds — re-check (cheaply, guarded by the ticker-list comparison)
    // whenever the portfolio notifies.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadDividends());

    double totalAnnualDividend = portfolio.totalAnnualDividendIncome;
    double totalMonthlyDividend = totalAnnualDividend / 12;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Passive Income"),
        actions: [
          IconButton(
              icon: const Icon(Icons.pie_chart_outline),
              tooltip: "Cash Flow Analysis",
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CashFlowScreen()))),
          IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: ListView(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E2C),
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Column(
              children: [
                const Text("TOTAL PASSIVE INCOME",
                    style: TextStyle(
                        color: Colors.grey, letterSpacing: 1.5, fontSize: 12)),
                const SizedBox(height: 10),
                Text(
                  "RM ${(wealthState.totalPassiveIncome + totalMonthlyDividend).toStringAsFixed(2)} / mo",
                  style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.greenAccent),
                ),
                Text(
                    "Safety Score: ${wealthState.safetyScore.toStringAsFixed(0)}/100",
                    style: const TextStyle(
                        fontStyle: FontStyle.italic, color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.blueAccent.shade700,
                  Colors.purpleAccent.shade700
                ]),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                      color: Colors.blueAccent.withOpacity(0.3), blurRadius: 8)
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.show_chart, color: Colors.white, size: 30),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text("Stock Dividend Income",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
                        Text("From your actual holdings' real dividend yields",
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text("+RM ${totalMonthlyDividend.toStringAsFixed(0)}/mo",
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const CashFlowScreen())),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D44),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.pie_chart_outline, color: Colors.amberAccent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Cash Flow Analysis",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          Text(
                              "Capital gains vs. passive income, side by side",
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Upcoming Dividends (Your Holdings)",
                    style: TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.bold))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildDividendTracker(portfolio),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text("Manual Income Sources",
                    style: TextStyle(
                        color: Colors.grey, fontWeight: FontWeight.bold))),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: wealthState.incomeSources.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return Dismissible(
                  key: Key('${item.name}_$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    Provider.of<WealthState>(context, listen: false)
                        .removeIncomeSource(index);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Income source deleted")),
                    );
                  },
                  child: Card(
                    color: const Color(0xFF2D2D44),
                    margin: const EdgeInsets.only(bottom: 15),
                    child: ListTile(
                      leading: const Icon(Icons.monetization_on,
                          color: Colors.greenAccent),
                      title: Text(item.name,
                          style: const TextStyle(color: Colors.white)),
                      // ✅ NEW: show the frequency so users can tell them apart
                      subtitle: Text(item.isMonthly ? "Monthly" : "Yearly",
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                      trailing: Text(
                          "RM ${item.amount.toStringAsFixed(0)}",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDividendTracker(PortfolioState portfolio) {
    if (_loadingDividends) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (portfolio.holdings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          "Buy a stock in Investment Lab to start tracking real dividend payout dates here.",
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }

    if (_dividendEvents.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          "No upcoming dividend ex-dates found for your current holdings.",
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      );
    }

    return Column(
      children: _dividendEvents.map((event) {
        PortfolioItem? holding;
        for (final h in portfolio.holdings) {
          if (h.ticker == event.ticker) {
            holding = h;
            break;
          }
        }
        final qty = holding?.quantity ?? 0;
        final perShare = event.dividendAmount ?? 0;
        final total = perShare * qty;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D44),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('💰', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.ticker ?? '',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      'Ex-date ${DateFormat('MMM d').format(event.eventDate)} · ${qty}x shares held',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('RM ${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text('RM ${perShare.toStringAsFixed(2)}/share',
                      style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
