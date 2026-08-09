import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/admin_api.dart';
import 'promote_admin_dialog.dart';
import 'user_detail_dialog.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key});

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  List<Map<String, dynamic>>? _users;
  String? _error;
  bool _loading = true;
  String _search = '';

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
      final users = await AdminApi.fetchUsers();
      setState(() => _users = users);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final users = _users ?? [];
    if (_search.isEmpty) return users;
    final q = _search.toLowerCase();
    return users.where((u) {
      final email = (u['email'] as String? ?? '').toLowerCase();
      final uid = (u['uid'] as String? ?? '').toLowerCase();
      return email.contains(q) || uid.contains(q);
    }).toList();
  }

  String _formatDate(dynamic millis) {
    if (millis == null) return '—';
    final date = DateTime.fromMillisecondsSinceEpoch((millis as num).toInt());
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

    final users = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Search by email or UID',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('${users.length} of ${_users?.length ?? 0} users',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: users.length,
            itemBuilder: (context, i) => _buildUserRow(users[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildUserRow(Map<String, dynamic> user) {
    final isAdmin = user['isAdmin'] == true;
    final isEnvAdmin = user['isEnvAdmin'] == true;
    final uid = user['uid'] as String? ?? '';
    final email = user['email'] as String? ?? '(no email)';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(email),
        subtitle: Text(
          'UID: $uid\nCreated ${_formatDate(user['createdAt'])} · '
          'Last sign-in ${_formatDate(user['lastSignInAt'])}',
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        onTap: () => showUserDetailDialog(context, uid: uid, email: email),
        leading: isAdmin
            ? const Icon(Icons.verified_user, color: Colors.blueAccent)
            : const Icon(Icons.person_outline, color: Colors.white38),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 20),
                tooltip: 'Promote to Admin',
                onPressed: () async {
                  final result = await showPromoteToAdminDialog(context, uid: uid, email: email);
                  if (result == true) _load();
                },
              )
            else if (!isEnvAdmin)
              IconButton(
                icon: const Icon(Icons.remove_moderator_outlined, size: 20),
                tooltip: 'Remove Admin Access',
                onPressed: () async {
                  final result = await showDemoteAdminDialog(context, uid: uid, email: email);
                  if (result == true) _load();
                },
              ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy UID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: uid));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('UID copied to clipboard')));
              },
            ),
          ],
        ),
      ),
    );
  }
}
