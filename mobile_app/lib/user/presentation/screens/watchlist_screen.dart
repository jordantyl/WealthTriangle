import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../application/wealth_state.dart';
import '../../../investment/presentation/screens/ticker_search_field.dart';

/// Dedicated watchlist management screen (Report request: "make watchlist
/// visible, transparent" + let the user manage it themselves). Previously
/// the watchlist had NO editing UI at all — it could only be changed
/// through the AI assistant's add/remove tools. Default starter tickers
/// (WealthState.defaultWatchlist) are shown locked here; the protection
/// itself lives in WealthState.updateWatchlist/removeFromWatchlist so it
/// can't be bypassed from this screen or the AI assistant.
class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  Future<void> _showAddDialog(BuildContext context, WealthState wealthState) async {
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add to Watchlist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              TickerSearchField(
                controller: controller,
                onSelected: (symbol) async {
                  await wealthState.addToWatchlist(symbol);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              const SizedBox(height: 15),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Ticker'),
                onPressed: () async {
                  final ticker = controller.text.trim();
                  if (ticker.isEmpty) return;
                  await wealthState.addToWatchlist(ticker);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WealthState wealthState, String ticker) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from Watchlist?'),
        content: Text('Remove $ticker from your watchlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await wealthState.removeFromWatchlist(ticker);
    } on WatchlistProtectedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wealthState = Provider.of<WealthState>(context);
    final tickers = wealthState.watchlist;

    return Scaffold(
      appBar: AppBar(
        title: const Text('⭐ Watchlist'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDialog(context, wealthState),
        icon: const Icon(Icons.add),
        label: const Text('Add Ticker'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Tickers you track for Market Intel and Events. Default starter '
            'tickers are locked and always stay on your watchlist — you (and '
            'the AI assistant) can only remove tickers you added yourself.',
            style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ...tickers.map((ticker) {
            final isDefault = wealthState.isDefaultTicker(ticker);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isDefault
                      ? Colors.grey.withOpacity(0.3)
                      : Colors.blueAccent.withOpacity(0.2),
                  child: Icon(
                    isDefault ? Icons.lock : Icons.show_chart,
                    size: 18,
                    color: isDefault ? Colors.grey : Colors.blueAccent,
                  ),
                ),
                title: Text(ticker, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(isDefault ? 'Default — always tracked' : 'Added by you'),
                trailing: isDefault
                    ? const Tooltip(
                        message: 'Default tickers can\'t be removed',
                        child: Icon(Icons.lock_outline, color: Colors.grey),
                      )
                    : IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _confirmRemove(context, wealthState, ticker),
                      ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
