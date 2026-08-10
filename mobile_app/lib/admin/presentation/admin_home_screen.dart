import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../academy/application/academy_state.dart';
import 'admin_activity_tab.dart';
import 'admin_content_tab.dart';
import 'admin_overview_tab.dart';
import 'admin_users_tab.dart';

/// The web admin dashboard: four tabs (Overview/Users/Content/Activity)
/// built on top of AcademyState's isAdmin gating. Kept as one screen with
/// a TabBar rather than separate routes since this is a small internal
/// tool, not something that needs deep-linkable URLs.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  bool _checkedAdmin = false;

  @override
  void initState() {
    super.initState();
    // AcademyState is constructed at app start, before this user's sign-in
    // resolves, so its own constructor-time admin check ran with no ID
    // token. Re-check now that we're definitely signed in.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AcademyState>().refreshAdminStatus();
      if (mounted) setState(() => _checkedAdmin = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AcademyState>();
    final user = FirebaseAuth.instance.currentUser;

    if (!_checkedAdmin) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!state.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('WealthTriangle Admin')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(padding: const EdgeInsets.all(24), child: _buildAccessDenied(user)),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Image.asset('assets/icon/logo_icon.png', height: 28),
              ),
              const Text('WealthTriangle Admin'),
            ],
          ),
          bottom: const TabBar(tabs: [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
            Tab(text: 'Users', icon: Icon(Icons.people_outline)),
            Tab(text: 'Content', icon: Icon(Icons.cloud_upload_outlined)),
            Tab(text: 'Activity', icon: Icon(Icons.history)),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: () => FirebaseAuth.instance.signOut(),
            ),
          ],
        ),
        body: const TabBarView(children: [
          AdminOverviewTab(),
          AdminUsersTab(),
          AdminContentTab(),
          AdminActivityTab(),
        ]),
      ),
    );
  }

  Widget _buildAccessDenied(User? user) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.block, size: 48, color: Colors.redAccent),
        const SizedBox(height: 12),
        Text(
          '${user?.email ?? 'This account'} is signed in but not on the admin allowlist.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ask whoever deploys the backend to add this account\'s Firebase UID '
          'to ADMIN_UIDS.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => FirebaseAuth.instance.signOut(),
          child: const Text('Sign Out'),
        ),
      ],
    );
  }
}
