import 'package:flutter/material.dart';

import '../data/admin_api.dart';

/// Drill-down for one user: academy progress, holdings/badges counts, and
/// tycoon battles played — pulled from /api/admin/users/<uid>/detail so you
/// don't have to open Firebase Console and manually walk each subcollection.
Future<void> showUserDetailDialog(BuildContext context, {required String uid, required String email}) {
  return showDialog(
    context: context,
    builder: (_) => _UserDetailDialog(uid: uid, email: email),
  );
}

class _UserDetailDialog extends StatefulWidget {
  final String uid;
  final String email;

  const _UserDetailDialog({required this.uid, required this.email});

  @override
  State<_UserDetailDialog> createState() => _UserDetailDialogState();
}

class _UserDetailDialogState extends State<_UserDetailDialog> {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await AdminApi.fetchUserDetail(widget.uid);
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.email),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(
                height: 100, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text('Failed to load: $_error', style: const TextStyle(color: Colors.redAccent))
                : _buildDetail(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }

  Widget _buildDetail() {
    final detail = _detail ?? {};
    final academy = detail['academy'] as Map<String, dynamic>?;
    final profile = detail['profile'] as Map<String, dynamic>?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (profile != null && profile['RiskProfile'] != null)
          _row('Risk Profile', '${profile['RiskProfile']}'),
        _row('Academy Level', academy == null ? 'Not started' : '${academy['level'] ?? 1}'),
        if (academy != null) _row('Academy XP', '${academy['xp'] ?? 0}'),
        _row('Holdings Tracked', '${detail['holdingsCount'] ?? 0}'),
        _row('Badges Earned', '${detail['badgesCount'] ?? 0}'),
        _row('Tycoon Battles Played', '${detail['tycoonBattlesPlayed'] ?? 0}'),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
