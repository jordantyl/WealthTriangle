import 'package:flutter_test/flutter_test.dart';
import 'package:wealth_triangle/academy/domain/badge.dart';

void main() {
  group('badgeCatalog', () {
    test('every badge has a unique id', () {
      final ids = badgeCatalog.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every badge has non-empty title, description, and emoji', () {
      for (final b in badgeCatalog) {
        expect(b.title, isNotEmpty, reason: 'badge ${b.id} missing a title');
        expect(b.description, isNotEmpty, reason: 'badge ${b.id} missing a description');
        expect(b.emoji, isNotEmpty, reason: 'badge ${b.id} missing an emoji');
      }
    });
  });

  group('badgeById', () {
    test('finds a known badge by id', () {
      final badge = badgeById('first_steps');
      expect(badge, isNotNull);
      expect(badge!.title, 'First Steps');
    });

    test('returns null for an unknown id', () {
      expect(badgeById('does_not_exist'), isNull);
    });
  });
}
