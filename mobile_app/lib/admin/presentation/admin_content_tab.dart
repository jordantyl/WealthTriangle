import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../academy/application/academy_state.dart';
import '../data/admin_api.dart';
import '../domain/content_schema.dart';
import 'content_collection_screen.dart';

class AdminContentTab extends StatefulWidget {
  const AdminContentTab({super.key});

  @override
  State<AdminContentTab> createState() => _AdminContentTabState();
}

class _AdminContentTabState extends State<AdminContentTab> {
  Map<String, int>? _counts;
  String? _error;
  bool _loading = true;
  String? _seeding;

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
      final counts = await AdminApi.fetchContentCounts();
      setState(() => _counts = counts);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetToDefaults(String? collectionName) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _seeding = collectionName ?? 'all');
    try {
      await context.read<AcademyState>().seedDatabase(
          only: collectionName == null ? null : {collectionName});
      messenger.showSnackBar(SnackBar(
          content: Text(
              '✅ ${collectionName == null ? 'All content' : contentSchemas[collectionName]!.label} reset to defaults.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('❌ Reset failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _seeding = null);
    }
  }

  Future<void> _openCollection(String key) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContentCollectionScreen(collection: key)),
    );
    _load();
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

    final counts = _counts ?? {};
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Academy Content', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Firestore is the live source of truth for these collections. "Manage" opens '
          'a full editor to add/edit/delete individual entries. "Reset to Defaults" '
          'overwrites a collection back to the app\'s built-in starter content — use it '
          'to wipe out edits and start over, not for day-to-day authoring.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 16),
        for (final entry in contentSchemas.entries) _buildContentRow(entry.key, counts),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: _seeding == 'all'
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.restart_alt),
          label: const Text('Reset All to Defaults'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
          onPressed: _seeding != null ? null : () => _resetToDefaults(null),
        ),
      ],
    );
  }

  Widget _buildContentRow(String key, Map<String, int> counts) {
    final count = counts[key];
    final isSeeding = _seeding == key;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(contentSchemas[key]!.label),
        subtitle: Text(count == null ? 'Unknown count' : '$count docs live'),
        onTap: () => _openCollection(key),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () => _openCollection(key), child: const Text('Manage')),
            const SizedBox(width: 4),
            OutlinedButton(
              onPressed: _seeding != null ? null : () => _resetToDefaults(key),
              child: isSeeding
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
