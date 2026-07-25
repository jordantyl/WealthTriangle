import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/badge.dart';

/// 🏅 BadgeService — award and read badges. Fully self-contained.
///
/// Storage: users/{uid}/badges/{badgeId} -> { earnedAt }
///
/// USAGE (one line wherever something badge-worthy happens):
///   BadgeService.award(context, 'first_steps');
///
/// It is idempotent: awarding the same badge twice does nothing, and the
/// unlock popup only shows the FIRST time.
class BadgeService {
  static CollectionReference? get _badgesRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('badges');
  }

  /// Awards a badge if not already earned. Shows an unlock dialog on
  /// first award. Safe to call from anywhere with a BuildContext.
  static Future<void> award(BuildContext context, String badgeId) async {
    final ref = _badgesRef;
    final badge = badgeById(badgeId);
    if (ref == null || badge == null) return;

    try {
      final doc = await ref.doc(badgeId).get();
      if (doc.exists) return; // already earned — do nothing

      await ref.doc(badgeId).set({
        'earnedAt': FieldValue.serverTimestamp(),
        'title': badge.title,
      });

      if (context.mounted) _showUnlockDialog(context, badge);
    } catch (e) {
      debugPrint('Badge award failed: $e');
    }
  }

  /// Stream of earned badge IDs — used by the badges screen.
  static Stream<Set<String>> earnedBadgeIds() {
    final ref = _badgesRef;
    if (ref == null) return Stream.value(<String>{});
    return ref.snapshots().map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  static void _showUnlockDialog(BuildContext context, AppBadge badge) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: badge.color, width: 2),
        ),
        title: const Center(
          child: Text('🏅 BADGE UNLOCKED!',
              style: TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.bold,
                  fontSize: 18)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(badge.emoji, style: const TextStyle(fontSize: 60)),
            const SizedBox(height: 10),
            Text(badge.title,
                style: TextStyle(
                    color: badge.color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(badge.description,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: badge.color),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('NICE!',
                  style: TextStyle(
                      color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}