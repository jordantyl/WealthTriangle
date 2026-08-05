import 'package:flutter/material.dart';

import '../data/admin_api.dart';
import '../domain/content_schema.dart';
import 'content_doc_editor.dart';

/// Full document list for one academy_* collection: add/edit/delete,
/// backed by the per-doc CRUD endpoints (Firestore is the source of truth
/// for this content now — see admin_content_tab.dart's "Sync" buttons for
/// the separate "reset this collection to the app's built-in defaults"
/// path, which is a bulk overwrite rather than per-doc editing).
class ContentCollectionScreen extends StatefulWidget {
  final String collection;

  const ContentCollectionScreen({super.key, required this.collection});

  @override
  State<ContentCollectionScreen> createState() => _ContentCollectionScreenState();
}

class _ContentCollectionScreenState extends State<ContentCollectionScreen> {
  List<Map<String, dynamic>>? _docs;
  String? _error;
  bool _loading = true;

  ContentSchema get _schema => contentSchemas[widget.collection]!;

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
      final docs = await AdminApi.fetchContentDocs(widget.collection);
      setState(() => _docs = docs);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openEditor({String? docId, Map<String, dynamic>? existing}) async {
    final saved = await showContentDocEditor(
      context,
      collection: widget.collection,
      schema: _schema,
      docId: docId,
      existing: existing,
    );
    if (saved == true) _load();
  }

  Future<void> _delete(String docId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this?'),
        content: Text('"$title" will be permanently removed from Firestore.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AdminApi.deleteContentDoc(widget.collection, docId);
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_schema.label)),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
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
    final docs = _docs ?? [];
    if (docs.isEmpty) {
      return const Center(
        child: Text('No documents yet. Tap + to add one.', style: TextStyle(color: Colors.white70)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: docs.length,
        itemBuilder: (context, i) {
          final doc = docs[i];
          final docId = doc['docId'] as String;
          final title = _schema.titleOf(doc);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              title: Text(title),
              subtitle: Text(docId, style: const TextStyle(fontSize: 11, color: Colors.white38)),
              onTap: () => _openEditor(docId: docId, existing: doc),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _delete(docId, title),
              ),
            ),
          );
        },
      ),
    );
  }
}
