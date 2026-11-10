import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/account_sheets.dart';
import '../screens/dialogs.dart';
import '../services/api.dart';
import '../services/billing.dart';
import '../services/starter_offer.dart';
import '../theme.dart';
import 'offline.dart';

/// What the starter pack buys in game terms, from real numbers only (a tile is dropped when its number is unknown or 0).
/// [archive] is the archive list from the server; the hint price is the cheapest hint in the economy config.
List<(String, String)> starterTiles({required int coins, required List<CaseRow> archive, required int cheapestHint}) => [
      if (archiveCasesFor(coins, archive) > 0) ('≈ ${fa(archiveCasesFor(coins, archive))}', 'پرونده‌ی بایگانی'),
      if (cheapestHint > 0 && coins ~/ cheapestHint > 0) ('≈ ${fa(coins ~/ cheapestHint)}', 'سرنخ'),
      ('۰', 'تبلیغ، برای همیشه'),
    ];

int _cheapestHint() {
  final e = Api.i.config['economy'];
  final h = e is Map ? e['hint_costs'] : null;
  if (h is List) {
    final xs = [for (final x in h) if (x is num && x > 0) x.toInt()]..sort();
    if (xs.isNotEmpty) return xs.first;
  }
  return 0;
}

/// Shows the starter-pack sheet when the rule allows (not bought, product in the store config, fewer than two showings).
/// Counts the showing and logs it. Returns true when the sheet was shown. Closes in one tap; never blocks anything.
Future<bool> maybeShowStarterSheet(
  BuildContext context,
  StarterMoment moment, {
  int need = 0,
  String? what,
}) async {
  if (!context.mounted || !StarterOffer.eligible()) return false;
  List<CaseRow> archive = const [];
  try {
    archive = (await Api.i.cases()).archive;
  } catch (_) {}
  if (!context.mounted || !StarterOffer.eligible()) return false;
  final name = moment == StarterMoment.lackCoins ? 'lack_coins' : 'first_solve';
  await StarterOffer.noteShown(name);
  if (!context.mounted) return true;
  final r = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StarterSheet(moment: moment, need: need, what: what, archive: archive, name: name),
  );
  if (r == 'ad' && context.mounted) await watchAd(context);
  return true;
}

class StarterSheet extends StatefulWidget {
  const StarterSheet({super.key, required this.moment, required this.archive, this.need = 0, this.what, this.name = ''});
  final StarterMoment moment;
  final int need;
  final String? what; // e.g. «سرنخ», «ابزار», «پرونده‌ی بایگانی»
  final List<CaseRow> archive;
  final String name;

  @override
  State<StarterSheet> createState() => _StarterSheetState();
}

class _StarterSheetState extends State<StarterSheet> {
  bool _busy = false;

  void _close() {
    unawaited(Api.i.track('starter_offer_closed', {'moment': widget.name}));
    Navigator.of(context).pop();
  }

  Future<void> _buy() async {
    if (_busy || !needOnline(context)) return;
    unawaited(Api.i.track('starter_offer_tapped', {'moment': widget.name}));
    if (!await offerSecure(context, afterSolve: false)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final (result, added) = await Billing.i.buy(kStarterId);
      if (!mounted) return;
      switch (result) {
        case BuyResult.granted:
          unawaited(Api.i.track('starter_offer_bought', {'moment': widget.name}));
          toast(context, added > 0 ? '${fa(added)} سکه اضافه شد!' : 'خرید انجام شد!');
          Navigator.of(context).pop();
        case BuyResult.pending:
          toast(context, 'پرداخت انجام شد؛ به‌محض وصل شدن اینترنت، خریدت اضافه می‌شه.');
        case BuyResult.cancelled:
          break;
        case BuyResult.unavailable:
        case BuyResult.failed:
          toast(context, 'خرید انجام نشد. اگه پولی کم شده، نگران نباش؛ برمی‌گرده یا خریدت اضافه می‌شه.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = Api.i;
    final coins = api.productCoins(kStarterId);
    final lack = widget.moment == StarterMoment.lackCoins;
    final head = lack
        ? (widget.need > 0 ? 'برای ${widget.what ?? 'این کار'} ${fa(widget.need)} سکه لازم داری' : 'سکه‌ات کم شد')
        : 'اولین پرونده‌ات رو حل کردی';
    final sub = lack
        ? 'الان ${fa(api.coins)} سکه داری. پرونده‌ی امشب همیشه رایگانه.'
        : 'بایگانی ده‌ها پرونده‌ی دیگه داره. اگه خواستی، با بسته‌ی شروع چندتاش رو باز کن.';
    final tiles = starterTiles(coins: coins, archive: widget.archive, cheapestHint: _cheapestHint());
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Container(
          key: const ValueKey('starter-sheet'),
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(22)),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(head, style: tDisplay(18, color: K.ink)),
                  const SizedBox(height: 4),
                  Text(sub, style: tBody(12.5, color: K.inkSoft)),
                ]),
              ),
              IconButton(
                key: const ValueKey('starter-x'),
                tooltip: 'بستن',
                onPressed: _close,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.close_rounded, color: K.ink),
              ),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
              decoration: BoxDecoration(border: Border.all(color: K.ink, width: 2), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(999)),
                    child: Text('فقط یک بار برای هر حساب', style: tBody(11.5, color: Colors.white, w: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 8),
                Text('بسته‌ی شروع', style: tBody(13, color: K.inkSoft, w: FontWeight.w800)),
                Text('${fa(coins)} سکه', style: tDisplay(26, color: K.kraftDark)),
                Text('+ همیشه بدون تبلیغ', style: tBody(13, color: K.ink, w: FontWeight.w800)),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          decoration: BoxDecoration(color: K.paperDark, borderRadius: BorderRadius.circular(10)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(tiles[i].$1, style: tBody(15, color: K.ink, w: FontWeight.w900)),
                            Text(tiles[i].$2, textAlign: TextAlign.center, style: tBody(10.5, color: K.inkSoft, w: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),
                StampButton(
                  label: _busy ? 'کمی صبر کن...' : 'خرید · ${api.price(kStarterId)}',
                  icon: Icons.shopping_bag_rounded,
                  height: 50,
                  onTap: _busy ? null : _buy,
                ),
              ]),
            ),
            TextButton(
              key: const ValueKey('starter-later'),
              onPressed: _close,
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: Text('فعلاً نه', style: tBody(13.5, color: K.inkSoft, w: FontWeight.w800)),
            ),
            if (lack && api.adsEnabled)
              TextButton(
                key: const ValueKey('starter-ad'),
                onPressed: () {
                  unawaited(Api.i.track('starter_offer_closed', {'moment': widget.name, 'via': 'ad'}));
                  Navigator.of(context).pop('ad');
                },
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                child: Text('یا با دیدن تبلیغ سکه‌ی رایگان بگیر', style: tBody(12.5, color: K.stamp, w: FontWeight.w800)),
              ),
            Text('این پیشنهاد در کل فقط دو بار نشونت داده می‌شه', textAlign: TextAlign.center, style: tBody(11, color: K.inkSoft)),
          ]),
        ),
      ),
    );
  }
}
