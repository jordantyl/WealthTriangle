import 'package:flutter/material.dart';

import '../data/admin_api.dart';

class AdminOverviewTab extends StatefulWidget {
  const AdminOverviewTab({super.key});

  @override
  State<AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<AdminOverviewTab> {
  Map<String, dynamic>? _health;
  Map<String, dynamic>? _stats;
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
      final results = await Future.wait([AdminApi.fetchHealth(), AdminApi.fetchStats()]);
      setState(() {
        _health = results[0];
        _stats = results[1];
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildStatsRow(),
          const SizedBox(height: 24),
          _buildHealthCard(),
        ],
      ),
    );
  }

  Widget _buildError() {
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

  Widget _buildStatsRow() {
    final stats = _stats ?? {};
    final tiles = [
      _StatTile(label: 'Total Users', value: '${stats['totalUsers'] ?? '—'}'),
      _StatTile(label: 'Holdings Tracked', value: '${stats['totalHoldings'] ?? '—'}'),
      _StatTile(label: 'Tycoon Battles', value: '${stats['tycoonBattlesPlayed'] ?? '—'}'),
      _StatTile(label: 'Academy Progress', value: '${stats['academyProgressRecords'] ?? '—'}'),
    ];
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: tiles,
    );
  }

  Widget _buildHealthCard() {
    final health = _health ?? {};
    final rows = [
      ('Firebase Admin', health['firebaseAdminConfigured'] == true),
      ('Gemini API key', health['geminiConfigured'] == true),
      ('OpenAI API key', health['openaiConfigured'] == true),
      ('Sentry crash reporting', health['sentryConfigured'] == true),
      ('Backend API key', health['backendApiKeyConfigured'] == true),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('System Health', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              '${health['adminUidCount'] ?? '—'} admin UID(s) allowlisted',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (final (label, ok) in rows) _buildHealthRow(label, ok),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthRow(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              color: ok ? Colors.greenAccent : Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D44),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}
