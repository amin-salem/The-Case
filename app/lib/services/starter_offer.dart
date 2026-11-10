import 'dart:async';

import '../models/models.dart';
import 'api.dart';

/// Where the starter-pack sheet may appear. Never inside tonight's case flow as a blocker: the sheet always closes
/// in one tap and the case itself never costs coins.
enum StarterMoment { lackCoins, firstSolve }

/// The starter pack is offered at most [kMax] times per account lifetime (Amin, 9 Nov 2026).
const int kStarterMaxShows = 2;

/// Product id in the store config.
const String kStarterId = 'starter_pack';

/// Pure rule: may the sheet be shown now?
bool starterMayShow({
  required int shown,
  required bool bought,
  required bool productExists,
  required bool online,
}) =>
    productExists && !bought && online && shown < kStarterMaxShows;

/// The suggested archive case for the result screen: unsolved, never lost, not tonight's, not a dearer weekend case.
/// A case that fits the player's level comes first (difficulty up to `rank`-based cap), then the one closest to the
/// level, then the cheapest, then the better rated, then the newer.
CaseRow? pickSuggestedCase(List<CaseRow> archive, {required int rank, String? excludeId}) {
  final target = (2 + rank ~/ 3).clamp(2, 5); // rank 0-2 -> 2, 3-5 -> 3, 6-8 -> 4, 9+ -> 5
  final pool = [
    for (final r in archive)
      if (!r.solved && !r.failed && !r.today && !r.weekend && r.id != excludeId) r
  ];
  if (pool.isEmpty) return null;
  int price(CaseRow r) => r.locked ? r.unlockCost : 0;
  pool.sort((a, b) {
    final fa = a.difficulty <= target ? 0 : 1, fb = b.difficulty <= target ? 0 : 1;
    if (fa != fb) return fa.compareTo(fb);
    final da = (a.difficulty - target).abs(), db = (b.difficulty - target).abs();
    if (da != db) return da.compareTo(db);
    final pa = price(a), pb = price(b);
    if (pa != pb) return pa.compareTo(pb);
    if (a.ratingAvg != b.ratingAvg) return b.ratingAvg.compareTo(a.ratingAvg);
    return b.number.compareTo(a.number);
  });
  return pool.first;
}

/// Price the player pays to open [r] now (0 when it is already open).
int suggestedPrice(CaseRow r) => r.locked ? r.unlockCost : 0;

/// How many archive cases [coins] open at the real prices of the cheapest unsolved locked cases (greedy, cheapest first).
int archiveCasesFor(int coins, List<CaseRow> archive) {
  final prices = [
    for (final r in archive)
      if (!r.solved && !r.today && r.locked && r.unlockCost > 0) r.unlockCost
  ]..sort();
  var left = coins, n = 0;
  for (final p in prices) {
    if (left < p) break;
    left -= p;
    n++;
  }
  return n;
}

/// The local counter of how many times the sheet was shown to this account. Local is acceptable (Amin).
class StarterOffer {
  StarterOffer._();
  static const _key = 'starter_offer_shown';

  static String _k() => '${_key}_${Api.i.profile?.playerId ?? ''}';

  static int shown() => Api.i.intPref(_k());

  /// True when the product exists in the store config, is not owned, and the counter allows another showing.
  static bool eligible() {
    final api = Api.i;
    return starterMayShow(
      shown: shown(),
      bought: api.profile?.noAds ?? false,
      productExists: api.productCoins(kStarterId) > 0 && api.price(kStarterId).isNotEmpty,
      online: api.online,
    );
  }

  static Future<void> noteShown(String moment) async {
    await Api.i.setIntPref(_k(), shown() + 1);
    unawaited(Api.i.track('starter_offer_shown', {'moment': moment, 'n': shown()}));
  }
}
