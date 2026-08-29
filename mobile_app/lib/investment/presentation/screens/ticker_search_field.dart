import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../shared/backend_headers.dart';

/// 🔍 Reusable ticker search field with autocomplete.
/// Backed by your existing Flask /api/search endpoint, so users pick
/// "MAYBANK (1155.KL)" from a list instead of typing codes blindly.
///
/// Usage:
///   TickerSearchField(
///     controller: _tickerCtrl,
///     onSelected: (symbol) { ... optional ... },
///   )
class TickerSearchField extends StatefulWidget {
  final TextEditingController controller;
  final void Function(String symbol)? onSelected;
  final String label;

  const TickerSearchField({
    super.key,
    required this.controller,
    this.onSelected,
    this.label = 'Stock Ticker (type to search)',
  });

  @override
  State<TickerSearchField> createState() => _TickerSearchFieldState();
}

class _TickerSearchFieldState extends State<TickerSearchField> {
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  String get _baseUrl => defaultBackendBaseUrl;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    // Debounce so we don't call the API on every keystroke
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() => _isSearching = true);
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/search?q=${Uri.encodeComponent(query)}'), headers: await authedBackendHeaders())
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 && mounted) {
        final List data = json.decode(response.body);
        setState(() =>
            _results = data.cast<Map<String, dynamic>>().take(6).toList());
      }
    } catch (_) {
      // Silent fail — user can still type a ticker manually
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _select(Map<String, dynamic> item) {
    widget.controller.text = item['symbol'] ?? '';
    setState(() => _results = []);
    FocusScope.of(context).unfocus();
    widget.onSelected?.call(item['symbol'] ?? '');
  }

  Color _tagColor(String? name) {
    switch (name) {
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purpleAccent;
      case 'grey':
        return Colors.grey;
      default:
        return Colors.blueAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: widget.controller,
          textCapitalization: TextCapitalization.characters,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D44),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Colors.white12),
              itemBuilder: (context, i) {
                final item = _results[i];
                return ListTile(
                  dense: true,
                  onTap: () => _select(item),
                  title: Text(item['symbol'] ?? '',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(item['name'] ?? '',
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _tagColor(item['tag_color']).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(item['tag_label'] ?? '',
                        style: TextStyle(
                            color: _tagColor(item['tag_color']),
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}