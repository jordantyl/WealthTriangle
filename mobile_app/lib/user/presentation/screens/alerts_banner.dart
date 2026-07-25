import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

/// 🔔 Fulfills report requirement 7.2:
/// "The system shall alert the user to upcoming critical financial events."
///
/// Shows a banner on the Home screen whenever the user has bell-toggled
/// events happening within the next 7 days. Tapping opens the calendar.
///
/// HOW TO ADD: in home_screen.dart, place this right below the
/// welcome header (before "Your Financial Snapshot"):
///
///   const AlertsBanner(),
///   const SizedBox(height: 15),
class AlertsBanner extends StatelessWidget {
  const AlertsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('event_alerts')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final now = DateTime.now();
        final in7Days = now.add(const Duration(days: 7));

        // Parse and keep only alerts happening in the next 7 days
        final upcoming = snapshot.data!.docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final date = DateTime.tryParse(data['eventDate'] ?? '');
              return (title: data['title'] as String? ?? 'Event', date: date);
            })
            .where((e) =>
                e.date != null &&
                e.date!.isAfter(now) &&
                e.date!.isBefore(in7Days))
            .toList()
          ..sort((a, b) => a.date!.compareTo(b.date!));

        if (upcoming.isEmpty) return const SizedBox.shrink();

        final next = upcoming.first;
        final daysUntil = next.date!.difference(now).inDays;
        final whenText = daysUntil == 0
            ? 'today'
            : daysUntil == 1
                ? 'tomorrow'
                : 'in $daysUntil days';

        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/calendar'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.amber.withOpacity(0.25),
                Colors.orange.withOpacity(0.10),
              ]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withOpacity(0.6)),
            ),
            child: Row(
              children: [
                const Text('🔔', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        upcoming.length == 1
                            ? '1 alert this week'
                            : '${upcoming.length} alerts this week',
                        style: const TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${next.title} — $whenText (${DateFormat('MMM d').format(next.date!)})',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.amber),
              ],
            ),
          ),
        );
      },
    );
  }
}