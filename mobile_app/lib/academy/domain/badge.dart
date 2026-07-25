import 'package:flutter/material.dart';

/// 🏅 Badge catalog — fulfills report requirement 3.4:
/// "The system shall award the user gamification badges and experience
///  points for completing educational tasks."
///
/// Self-contained: does not depend on AcademyState, so it can't conflict
/// with your existing academy code.
class AppBadge {
  final String id;
  final String title;
  final String description;
  final String emoji;
  final Color color;

  const AppBadge({
    required this.id,
    required this.title,
    required this.description,
    required this.emoji,
    required this.color,
  });
}

/// The full set of badges the app can award.
/// Add more entries here anytime — the badges screen renders this list.
const List<AppBadge> badgeCatalog = [
  AppBadge(
    id: 'first_steps',
    title: 'First Steps',
    description: 'Complete your first Financial IQ Quiz',
    emoji: '🐣',
    color: Colors.greenAccent,
  ),
  AppBadge(
    id: 'quiz_master',
    title: 'Quiz Master',
    description: 'Score 500+ XP in a single quiz run',
    emoji: '🧠',
    color: Colors.purpleAccent,
  ),
  AppBadge(
    id: 'time_traveler',
    title: 'Time Traveler',
    description: 'Run your first Time Machine simulation',
    emoji: '⏳',
    color: Colors.amberAccent,
  ),
  AppBadge(
    id: 'crash_survivor',
    title: 'Crash Survivor',
    description:
        'Simulate a period with a max drawdown worse than -30% — and learn from it',
    emoji: '🎢',
    color: Colors.redAccent,
  ),
  AppBadge(
    id: 'flash_streak_5',
    title: 'Fast Hands',
    description: 'Reach a 5-streak in Flash Trader',
    emoji: '⚡',
    color: Colors.yellowAccent,
  ),
  AppBadge(
    id: 'master_merchant',
    title: 'Master Merchant',
    description: 'Win the Merchant Master campaign (\$20k goal)',
    emoji: '💰',
    color: Colors.cyanAccent,
  ),
  AppBadge(
    id: 'diversified',
    title: 'Diversified',
    description: 'Hold 3 or more different stocks in your simulated portfolio',
    emoji: '🧺',
    color: Colors.blueAccent,
  ),
  AppBadge(
    id: 'goal_setter',
    title: 'Goal Setter',
    description: 'Set your first financial freedom milestone',
    emoji: '🎯',
    color: Colors.orangeAccent,
  ),
];

AppBadge? badgeById(String id) {
  for (final b in badgeCatalog) {
    if (b.id == id) return b;
  }
  return null;
}