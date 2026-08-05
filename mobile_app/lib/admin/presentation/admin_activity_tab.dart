import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/admin_api.dart';
import '../domain/content_schema.dart';

const _actionIcons = {
  'create': (Icons.add_circle_outline, Colors.greenAccent),
  'update': (Icons.edit_outlined, Colors.blueAccent),
  'delete': (Icons.delete_outline, Colors.redAccent),
};

class AdminActivityTab extends StatefulWidget {
  const AdminActivityTab({super.key});

  @override
  State<AdminActivityTab> createState() => _AdminActivityTabState();
}

class _AdminActivityTabState extends State<AdminActivityTab> {
  List<Map<String, dynamic>>? _entries;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await AdminApi.fetchAuditLog();
      setState(() => _entries = entries);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _formatTimestamp(dynamic millis) {
    if (millis == null) return 'just now';
    final date = DateTime.fromMillisecondsSinceEpoch((millis as num).toInt());
    return '${date.year}-${_two(date.month)}-${_two(date.day)} ${_two(date.hour)}:${_two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed to load: $_error', style: const TextStyle(color: Colors.redAccent)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final entries = _entries ?? [];
    if (entries.isEmpty) {
      return const Center(
        child: Text('No content edits yet.', style: TextStyle(color: Colors.white70)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        itemBuilder: (context, i) => _buildEntry(entries[i]),
      ),
    );
  }

  Widget _buildEntry(Map<String, dynamic> entry) {
    final action = entry['action'] as String? ?? 'update';
    final (icon, color) = _actionIcons[action] ?? _actionIcons['update']!;
    final collection = entry['collection'] as String?;
    final schema = collection == null ? null : contentSchemas[collection];
    final after = entry['after'] as Map<String, dynamic>?;
    final before = entry['before'] as Map<String, dynamic>?;
    final title = schema?.titleOf(after ?? before ?? {}) ?? (entry['docId'] as String? ?? '');
    final actorEmail = entry['actorEmail'] as String? ?? 'unknown';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text('${_actionVerb(action)} "$title"'),
        subtitle: Text(
          '${schema?.label ?? collection} · $actorEmail · ${_formatTimestamp(entry['timestamp'])}',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (before != null) _buildJsonBlock('Before', before),
                if (before != null && after != null) const SizedBox(height: 8),
                if (after != null) _buildJsonBlock('After', after),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _actionVerb(String action) {
    switch (action) {
      case 'create':
        return 'Created';
      case 'delete':
        return 'Deleted';
      default:
        return 'Edited';
    }
  }

  Widget _buildJsonBlock(String label, Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            encoder.convert(data),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ],
    );
  }
}
