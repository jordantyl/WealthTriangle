import 'package:flutter/material.dart';
import '../../domain/badge.dart';
import '../../application/badge_service.dart';
import '../../../shared/app_theme_colors.dart';

/// 🏅 Badge collection screen — shows every badge in the catalog,
/// earned ones in full color, locked ones greyed out.
class BadgesScreen extends StatelessWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('🏅 My Badges')),
      body: StreamBuilder<Set<String>>(
        stream: BadgeService.earnedBadgeIds(),
        builder: (context, snapshot) {
          final earned = snapshot.data ?? <String>{};

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.purple.shade900,
                    Colors.blue.shade900
                  ]),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '${earned.length} / ${badgeCatalog.length} badges earned',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: badgeCatalog.length,
                  itemBuilder: (context, i) {
                    final badge = badgeCatalog[i];
                    final isEarned = earned.contains(badge.id);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isEarned
                              ? badge.color
                              : colors.border,
                          width: isEarned ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Opacity(
                            opacity: isEarned ? 1.0 : 0.25,
                            child: Text(badge.emoji,
                                style: const TextStyle(fontSize: 40)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            badge.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isEarned ? badge.color : colors.textTertiary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            badge.description,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isEarned
                                  ? colors.textSecondary
                                  : colors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                          if (!isEarned) ...[
                            const SizedBox(height: 4),
                            Icon(Icons.lock,
                                color: colors.textTertiary, size: 14),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}