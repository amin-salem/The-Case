import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/services/home_rules.dart';

void main() {
  group('streak row', () {
    bool due({int streak = 4, bool open = true, int? next = 3, bool repair = false}) =>
        HomeRules.streakDue(streak: streak, tonightOpen: open, nightsToNext: next, repairOffer: repair);

    test('at risk: tonight is not solved and the streak is 3 nights or more', () {
      expect(due(streak: 3), isTrue);
      expect(due(streak: 13, next: 17), isTrue);
    });

    test('not at risk: tonight solved, or a short streak', () {
      expect(due(streak: 4, open: false), isFalse);
      expect(due(streak: 2, next: 5), isFalse);
      expect(due(streak: 0, next: 3), isFalse);
    });

    test('the next step is one night away: shown even after tonight is solved', () {
      expect(due(streak: 6, open: false, next: 1), isTrue);
      expect(due(streak: 2, open: false, next: 1), isTrue);
      expect(due(streak: 5, open: false, next: 2), isFalse);
    });

    test('a broken streak that can be repaired always asks something of the player', () {
      expect(due(streak: 0, open: false, next: null, repair: true), isTrue);
    });

    test('the top of the ladder (no next step) and no risk: hidden', () {
      expect(due(streak: 400, open: false, next: null), isFalse);
    });
  });

  group('secure row', () {
    final now = DateTime(2026, 11, 11, 20);
    bool due({bool secured = false, int solved = 3, bool bought = false, DateTime? closed}) =>
        HomeRules.secureDue(secured: secured, casesSolved: solved, bought: bought, closedAt: closed, now: now);

    test('only after the 3rd solve, or after a purchase', () {
      expect(due(solved: 2), isFalse);
      expect(due(solved: 3), isTrue);
      expect(due(solved: 0, bought: true), isTrue);
    });

    test('a secured account never sees it', () {
      expect(due(secured: true, solved: 9, bought: true), isFalse);
    });

    test('closed with the ✕: gone for 7 days, then back', () {
      expect(due(closed: now.subtract(const Duration(days: 6, hours: 23))), isFalse);
      expect(due(closed: now.subtract(const Duration(days: 7))), isTrue);
      expect(due(closed: now.subtract(const Duration(days: 30))), isTrue);
    });
  });
}
