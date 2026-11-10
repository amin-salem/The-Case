/// Value lines of the shop, computed from the REAL prices and coins (never typed in).
/// Pure functions so the behaviour is tested without a widget.
class ShopValue {
  /// A middle-difficulty archive case costs this many coins.
  static const int typicalArchive = 150;

  /// Archive cases a coin amount opens; 0 when it is less than one case.
  static int cases(int coins) => coins <= 0 ? 0 : coins ~/ typicalArchive;

  /// The id with the most coins per toman, or null when prices are unknown or two packs tie at the top
  /// (a badge that is not clearly true is not shown). [packs] maps id -> (coins, toman).
  static String? bestValueId(Map<String, ({int coins, int? toman})> packs) {
    String? best;
    double top = 0;
    bool tie = false;
    for (final e in packs.entries) {
      final t = e.value.toman;
      if (e.value.coins <= 0 || t == null || t <= 0) return null; // one unknown price: do not claim anything
      final v = e.value.coins / t;
      if (v > top + 1e-9) {
        top = v;
        best = e.key;
        tie = false;
      } else if ((v - top).abs() <= 1e-9) {
        tie = true;
      }
    }
    return tie ? null : best;
  }

  /// How many archive cases a month the VIP card (price [vipToman]) beats buying them with coins at the
  /// best real coins-per-toman rate [bestCoinsPerToman]. Null when it cannot be computed or is not sensible.
  static int? vipBreakEven(int? vipToman, double? bestCoinsPerToman) {
    if (vipToman == null || vipToman <= 0 || bestCoinsPerToman == null || bestCoinsPerToman <= 0) return null;
    final tomanPerCase = typicalArchive / bestCoinsPerToman;
    final n = (vipToman / tomanPerCase).floor() + 1; // the first whole number of cases that costs MORE than VIP
    return n >= 2 && n <= 99 ? n : null;
  }
}
