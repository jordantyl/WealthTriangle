import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/admin_api.dart';

/// Helper for the manual "add this UID to ADMIN_UIDS on Render" step —
/// there's no API that can flip ADMIN_UIDS itself (it's a Render env var,
/// not something this backend can rewrite about itself), so the best this
/// can do is remove the copy-paste error risk: fetch the current list,
/// compose the exact new value, and let you copy it in one click.
Future<void> showPromoteToAdminDialog(BuildContext context, {required String uid, required String email}) {
  return showDialog(
    context: context,
    builder: (_) => _PromoteToAdminDialog(uid: uid, email: email),
  );
}

class _PromoteToAdminDialog extends StatefulWidget {
  final String uid;
  final String email;

  const _PromoteToAdminDialog({required this.uid, required this.email});

  @override
  State<_PromoteToAdminDialog> createState() => _PromoteToAdminDialogState();
}

class _PromoteToAdminDialogState extends State<_PromoteToAdminDialog> {
  List<String>? _currentAdminUids;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final health = await AdminApi.fetchHealth();
      final uids = List<String>.from(health['adminUids'] as List? ?? []);
      if (mounted) setState(() => _currentAdminUids = uids);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final newValue = _currentAdminUids == null
        ? null
        : ({..._currentAdminUids!, widget.uid}.toList()..sort()).join(',');

    return AlertDialog(
      title: const Text('Promote to Admin'),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text('Failed to load: $_error', style: const TextStyle(color: Colors.redAccent))
                : _buildContent(newValue!),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _buildContent(String newValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${widget.email} is not on the admin allowlist yet.',
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        const Text('1. Copy this value:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(newValue, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: newValue));
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '2. Go to the Render Dashboard → your backend service → Environment tab\n'
          '3. Paste it as the value of ADMIN_UIDS (replacing the current value)\n'
          '4. Save — Render will redeploy automatically\n'
          '5. Have them sign out and back in on this page once it\'s live',
          style: TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}
