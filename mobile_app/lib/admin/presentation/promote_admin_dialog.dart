import 'package:flutter/material.dart';

import '../data/admin_api.dart';

/// Confirm-and-promote: sets role: "admin" on the target's Firestore doc via
/// the backend (see admin_promote_user in app.py). Takes effect immediately
/// — no more manual "paste this into Render's ADMIN_UIDS and wait for a
/// redeploy" step.
Future<bool?> showPromoteToAdminDialog(BuildContext context, {required String uid, required String email}) {
  return showDialog<bool>(
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

/// Confirm-and-demote counterpart. Not offered for env-var (ADMIN_UIDS)
/// admins — the caller should only show this for Firestore-promoted ones
/// (see AdminUsersTab, which checks isEnvAdmin before wiring this in).
Future<bool?> showDemoteAdminDialog(BuildContext context, {required String uid, required String email}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _DemoteAdminDialog(uid: uid, email: email),
  );
}

class _DemoteAdminDialog extends StatefulWidget {
  final String uid;
  final String email;

  const _DemoteAdminDialog({required this.uid, required this.email});

  @override
  State<_DemoteAdminDialog> createState() => _DemoteAdminDialogState();
}

class _DemoteAdminDialogState extends State<_DemoteAdminDialog> {
  bool _working = false;
  String? _error;

  Future<void> _demote() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await AdminApi.demoteAdmin(widget.uid);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Remove Admin Access'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove admin access from ${widget.email}?'),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working ? null : _demote,
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          child: _working
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Remove'),
        ),
      ],
    );
  }
}

class _PromoteToAdminDialogState extends State<_PromoteToAdminDialog> {
  bool _working = false;
  String? _error;

  Future<void> _promote() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await AdminApi.promoteToAdmin(widget.uid);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Promote to Admin'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Give ${widget.email} admin access? They\'ll be able to edit shared '
                'content, view all users, and promote/demote other admins.'),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _working ? null : _promote,
          child: _working
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Promote'),
        ),
      ],
    );
  }
}
