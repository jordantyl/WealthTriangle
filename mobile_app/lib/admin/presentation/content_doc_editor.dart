import 'package:flutter/material.dart';

import '../data/admin_api.dart';
import '../domain/content_schema.dart';

/// Modal form for creating/editing one document in an academy_* collection.
/// Field widgets are generated from [ContentSchema] rather than hand-built
/// per collection — see content_schema.dart for why each field's type and
/// requiredness is what it is (mirrors what the mobile app's readers
/// actually cast/access, to avoid producing a doc that crashes the app).
Future<bool?> showContentDocEditor(
  BuildContext context, {
  required String collection,
  required ContentSchema schema,
  String? docId,
  Map<String, dynamic>? existing,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ContentDocEditorDialog(
      collection: collection,
      schema: schema,
      docId: docId,
      existing: existing,
    ),
  );
}

class _ContentDocEditorDialog extends StatefulWidget {
  final String collection;
  final ContentSchema schema;
  final String? docId;
  final Map<String, dynamic>? existing;

  const _ContentDocEditorDialog({
    required this.collection,
    required this.schema,
    this.docId,
    this.existing,
  });

  @override
  State<_ContentDocEditorDialog> createState() => _ContentDocEditorDialogState();
}

class _ContentDocEditorDialogState extends State<_ContentDocEditorDialog> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, bool> _boolValues = {};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final data = widget.existing ?? {};
    for (final field in widget.schema.fields) {
      if (field.type == FieldType.boolean) {
        _boolValues[field.key] = data[field.key] == true;
      } else {
        _controllers[field.key] = TextEditingController(text: _displayValue(field, data[field.key]));
      }
    }
  }

  String _displayValue(FieldSpec field, dynamic value) {
    switch (field.type) {
      case FieldType.text:
      case FieldType.multilineText:
        return (value as String?) ?? '';
      case FieldType.number:
        return value == null ? '' : '$value';
      case FieldType.stringList:
        return (value is List) ? value.join('\n') : '';
      case FieldType.numberMap:
        if (value is Map) {
          return value.entries.map((e) => '${e.key}: ${e.value}').join('\n');
        }
        return '';
      case FieldType.boolean:
        return '';
    }
  }

  Map<String, dynamic> _collectValues() {
    final result = <String, dynamic>{};
    for (final field in widget.schema.fields) {
      switch (field.type) {
        case FieldType.text:
        case FieldType.multilineText:
          result[field.key] = _controllers[field.key]!.text.trim();
          break;
        case FieldType.number:
          result[field.key] = num.tryParse(_controllers[field.key]!.text.trim()) ?? 0;
          break;
        case FieldType.boolean:
          result[field.key] = _boolValues[field.key] ?? false;
          break;
        case FieldType.stringList:
          result[field.key] = _controllers[field.key]!
              .text
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          break;
        case FieldType.numberMap:
          final map = <String, num>{};
          for (final line in _controllers[field.key]!.text.split('\n')) {
            final parts = line.split(':');
            if (parts.length != 2) continue;
            final key = parts[0].trim();
            final value = num.tryParse(parts[1].trim());
            if (key.isEmpty || value == null) continue;
            map[key] = value;
          }
          result[field.key] = map;
          break;
      }
    }
    return result;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = _collectValues();
      if (widget.docId == null) {
        await AdminApi.createContentDoc(widget.collection, data);
      } else {
        await AdminApi.updateContentDoc(widget.collection, widget.docId!, data);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.docId == null
                    ? 'New ${widget.schema.label.substring(0, widget.schema.label.length - 1)}'
                    : 'Edit ${widget.schema.label.substring(0, widget.schema.label.length - 1)}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final field in widget.schema.fields) _buildField(field),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(FieldSpec field) {
    if (field.type == FieldType.boolean) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          value: _boolValues[field.key] ?? false,
          onChanged: (v) => setState(() => _boolValues[field.key] = v),
        ),
      );
    }
    final isMultiline = field.type == FieldType.multilineText ||
        field.type == FieldType.stringList ||
        field.type == FieldType.numberMap;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _controllers[field.key],
        maxLines: isMultiline ? 4 : 1,
        // Was TextInputType.text for these "one per line" fields too — on
        // Flutter Web the keyboardType decides whether the field binds to a
        // single-line <input> or a <textarea>, so without this, pressing
        // Enter here just defocused the field instead of adding a line
        // break, and multi-line paste/programmatic input got silently
        // collapsed to one line. Confirmed live: this corrupted saved data
        // with no error shown (e.g. a quiz's 4 answer options collapsing
        // into one garbled string) since stringList/numberMap fields are
        // parsed by splitting on '\n' (see _collectValues() above).
        keyboardType: field.type == FieldType.number
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : isMultiline
                ? TextInputType.multiline
                : TextInputType.text,
        textInputAction: isMultiline ? TextInputAction.newline : TextInputAction.done,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: field.hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
