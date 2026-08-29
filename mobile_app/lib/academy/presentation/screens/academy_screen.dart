import 'package:flutter/material.dart';
import 'flash_trader_screen.dart';
import 'quiz_screen.dart';
import 'tycoon_lobby_screen.dart';

import '../../application/academy_state.dart';
import 'learning_path_screen.dart';

import 'package:provider/provider.dart';
import 'badges_screen.dart';
import '../../../shared/app_theme_colors.dart';

class AcademyScreen extends StatelessWidget {
  const AcademyScreen({super.key});

  Future<void> _confirmResetToDefaults(BuildContext context) async {
    final colors = context.appColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Reset all academy content?', style: TextStyle(color: colors.textPrimary)),
        content: Text(
          'This overwrites scenarios, quizzes, flashcards, and trade items/events back to '
          'the app\'s built-in defaults — any edits made in the Admin panel will be lost. '
          'This can\'t be undone.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL', style: TextStyle(color: colors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('RESET', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text("Resetting to defaults...")));
    try {
      await Provider.of<AcademyState>(context, listen: false).seedDatabase();
      messenger.showSnackBar(const SnackBar(
          content: Text("✅ Reset to defaults successfully.")));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text("❌ Reset failed: $e"),
          backgroundColor: Colors.redAccent));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen so the Rank header updates when XP/level changes
    final state = Provider.of<AcademyState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Investor Academy"),
        // Academy content (quizzes/scenarios/flashcards/trade items) is
        // fetched once per app session (AcademyState's constructor) and
        // cached — an admin deleting/editing content in the Admin panel
        // doesn't push to already-open sessions, so without this, a session
        // that was open before the edit keeps showing stale content until
        // the app is fully restarted. This re-fetches on demand instead.
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh content",
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await state.fetchGameContent();
              messenger.showSnackBar(
                  const SnackBar(content: Text("Academy content refreshed.")));
            },
          ),
        ],
      ),

      // Only shown once /api/admin/status confirms this user is in the
      // backend's ADMIN_UIDS allowlist — previously showed to every user and
      // only failed (403) after tapping it.
      //
      // This calls the same AcademyState.seedDatabase() as the Admin panel's
      // "Reset to Defaults" button (admin_content_tab.dart) — it overwrites
      // ALL academy content back to the app's built-in defaults, wiping any
      // custom edits. Labeled/confirmed to match, since this one sits on the
      // regular app screen where an accidental tap is far more likely than
      // in the gated Admin panel.
      floatingActionButton: state.isAdmin
          ? FloatingActionButton.extended(
              label: const Text("Reset to Defaults"),
              icon: const Icon(Icons.restart_alt),
              backgroundColor: Colors.redAccent,
              onPressed: () => _confirmResetToDefaults(context),
            )
          : null,

      // ✅ THIS WAS THE MISSING PIECE: body + ListView wrap everything below
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. RANK HEADER — tap to open Badge collection
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BadgesScreen())),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.purple.shade900, Colors.blue.shade900]),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Your Rank",
                          style: TextStyle(color: Colors.white70)),
                      // ✅ Live level + XP instead of hardcoded "Level 1: Novice"
                      Text("Level ${state.level} • ${state.xp} XP",
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      const Text("Tap to view your badges 🏅",
                          style: TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                  const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.amber,
                    child: Icon(Icons.emoji_events, color: Colors.black),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 30),

          // 2. GAME MODES
          const Text("Training Simulations",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),

          _buildGameCard(context,
              title: "Learning Path",
              subtitle: "Structured lessons tailored to your risk profile",
              icon: Icons.school,
              color: Colors.greenAccent, onTap: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LearningPathScreen()));
          }),

          _buildGameCard(context,
              title: "Financial IQ Quiz",
              subtitle: "Earn capital for your simulations.",
              icon: Icons.quiz,
              color: Colors.orangeAccent, onTap: () {
            Navigator.push(
                context, MaterialPageRoute(builder: (_) => const QuizScreen()));
          }),

          _buildGameCard(context,
              title: "Flash Trader",
              subtitle: "Speed & Reflexes.",
              icon: Icons.flash_on,
              color: Colors.yellowAccent,
              onTap: () => _showModeSelection(context,
                      title: "Flash Trader",
                      icon: Icons.flash_on,
                      color: Colors.yellowAccent,
                      modes: [
                        {
                          "label": "⚡ Blitz Mode",
                          "desc": "Standard speed run.",
                          "icon": Icons.timer,
                          "onTap": () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const FlashTraderScreen(mode: 'blitz')))
                        },
                        {
                          "label": "💀 Sudden Death",
                          "desc": "One mistake = Game Over.",
                          "icon": Icons.dangerous,
                          "onTap": () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const FlashTraderScreen(
                                      mode: 'sudden_death')))
                        }
                      ])),

          _buildGameCard(context,
              title: "Market Tycoon",
              subtitle: "Solo & Multiplayer Battles.",
              icon: Icons.show_chart,
              color: Colors.greenAccent, onTap: () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TycoonLobbyScreen()));
          }),
        ],
      ),
    );
  }

  Widget _buildGameCard(BuildContext context,
      {required String title,
      required String subtitle,
      required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: const Offset(0, 4))
            ]),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.play_arrow_rounded, color: colors.textPrimary, size: 30),
          ],
        ),
      ),
    );
  }

  void _showModeSelection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, dynamic>> modes,
  }) {
    final colors = context.appColors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 30),
                  const SizedBox(width: 10),
                  Text(title,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              Divider(color: colors.border, height: 30),
              ...modes.map((mode) => ListTile(
                    contentPadding: const EdgeInsets.all(10),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Icon(mode['icon'] ?? Icons.play_arrow,
                          color: color),
                    ),
                    title: Text(mode['label'],
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                    subtitle: Text(mode['desc'],
                        style: TextStyle(color: colors.textSecondary)),
                    trailing: Icon(Icons.arrow_forward_ios,
                        color: colors.textTertiary, size: 16),
                    onTap: () {
                      Navigator.pop(context);
                      mode['onTap']();
                    },
                  )),
            ],
          ),
        );
      },
    );
  }
}