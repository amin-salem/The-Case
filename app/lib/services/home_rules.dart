/// Which extra rows the lean home page shows: only what asks something of the player now.
/// Pure functions, so the rules are tested without a screen.
class HomeRules {
  const HomeRules._();

  /// How long a closed «امن‌کردن حساب» row stays away.
  static const secureSnooze = Duration(days: 7);

  /// The streak row: the streak is at risk (tonight is still open and the streak is 3 nights or more), or the next
  /// step of the ladder is exactly one night away, or the server offers to repair a broken streak.
  static bool streakDue({required int streak, required bool tonightOpen, required int? nightsToNext, required bool repairOffer}) {
    if (repairOffer) return true;
    if (streak >= 3 && tonightOpen) return true;
    return streak > 0 && nightsToNext == 1;
  }

  /// The «امن‌کردن حساب» row: not secured yet, and the player has solved 3 cases or has paid for something,
  /// and did not close the row in the last 7 days.
  static bool secureDue({
    required bool secured,
    required int casesSolved,
    required bool bought,
    required DateTime? closedAt,
    required DateTime now,
  }) {
    if (secured) return false;
    if (casesSolved < 3 && !bought) return false;
    if (closedAt != null && now.difference(closedAt) < secureSnooze) return false;
    return true;
  }
}
