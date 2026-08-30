import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../application/wealth_state.dart';
import '../../../investment/presentation/screens/ticker_search_field.dart';
import '../../../shared/backend_headers.dart';

/// Dedicated watchlist management screen (Report request: "make watchlist
/// visible, transparent" + let the user manage it themselves). Previously
/// the watchlist had NO editing UI at all — it could only be changed
/// through the AI assistant's add/remove tools. Default starter tickers
/// (WealthState.defaultWatchlist) are shown locked here; the protection
/// itself lives in WealthState.updateWatchlist/removeFromWatchlist so it
/// can't be bypassed from this screen or the AI assistant.
class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  static final RegExp _tickerFormat = RegExp(r'^[A-Z0-9.\-]{1,10}$');

  /// Checks the typed ticker against the same live /api/search endpoint the
  /// autocomplete dropdown uses, so a manually-typed symbol that never
  /// resolved to a dropdown suggestion still gets checked instead of being
  /// written straight to Firestore unverified (previously: typing e.g.
  /// "ZZZZINVALID999" and tapping Add Ticker added it with zero validation
  /// — no format check, no existence check — and it would sit in the
  /// watchlist forever silently failing downstream in Market Intel/Events).
  /// Returns null if the backend couldn't be reached (caller falls back to
  /// asking the user directly rather than hard-blocking on a network hiccup).
  Future<bool?> _tickerExistsInSearch(String ticker) async {
    try {
      final response = await http
          .get(
            Uri.parse('$defaultBackendBaseUrl/api/search?q=${Uri.encodeComponent(ticker)}'),
            headers: await authedBackendHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final List data = json.decode(response.body);
      return data.any((item) =>
          (item['symbol']?.toString().toUpperCase() ?? '') == ticker);
    } catch (_) {
      return null;
    }
  }

  Future<void> _addTickerValidated(
    BuildContext screenContext,
    BuildContext sheetContext,
    WealthState wealthState,
    String rawTicker,
    void Function(bool) setChecking,
  ) async {
    final ticker = rawTicker.trim().toUpperCase();
    if (ticker.isEmpty) return;

    if (!_tickerFormat.hasMatch(ticker)) {
      ScaffoldMessenger.of(screenContext).showSnackBar(SnackBar(content: Text(
          "'$ticker' doesn't look like a real ticker symbol — use letters/numbers only, up to 10 characters.")));
      return;
    }

    setChecking(true);
    final found = await _tickerExistsInSearch(ticker);
    // The bottom sheet can be dismissed (tap outside / swipe down) while
    // this network call is in flight — calling setChecking (setState on the
    // StatefulBuilder) after that would throw "setState() called after
    // dispose()", so bail out before touching sheet-local state once it's
    // no longer mounted.
    if (!sheetContext.mounted) return;
    setChecking(false);

    if (found == true) {
      await wealthState.addToWatchlist(ticker);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
      return;
    }

    // found == false (search ran, no match) or null (search unreachable) —
    // either way, don't silently accept it: ask instead of hard-blocking,
    // since a network hiccup or an obscure/newly-listed symbol shouldn't
    // permanently lock a legitimate ticker out.
    if (!sheetContext.mounted) return;
    final message = found == false
        ? "We couldn't find '$ticker' in stock search. Add it anyway?"
        : "Couldn't verify '$ticker' right now (search unreachable). Add it anyway?";
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unrecognized Ticker'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add Anyway'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await wealthState.addToWatchlist(ticker);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
    }
  }

  Future<void> _showAddDialog(BuildContext context, WealthState wealthState) async {
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (sheetContext) {
        bool checking = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
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
                    icon: checking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add),
                    label: Text(checking ? 'Checking...' : 'Add Ticker'),
                    onPressed: checking
                        ? null
                        : () => _addTickerValidated(
                              context,
                              sheetContext,
                              wealthState,
                              controller.text,
                              (v) => setSheetState(() => checking = v),
                            ),
                  ),
                ],
              ),
            );
          },
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
                    ? IconButton(
                        icon: const Icon(Icons.lock_outline, color: Colors.grey),
                        tooltip: 'Default tickers can\'t be removed',
                        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Default tickers can\'t be removed — you can still add your own.'),
                          ),
                        ),
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
