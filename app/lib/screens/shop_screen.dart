import 'account_sheets.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../services/billing.dart';
import '../services/shop_value.dart';
import '../theme.dart';
import '../widgets/offline.dart';
import '../widgets/state_view.dart';
import 'dialogs.dart';

/// Coin packs and perks, paid through Cafe Bazaar. Every purchase is checked by our server with Bazaar
/// before coins are added; the price shown is Bazaar's own when it can tell us.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool _busy = false;

  Future<void> _buy(String productId, String title) async {
    if (!needOnline(context)) return;
    if (!await offerSecure(context, afterSolve: false)) return;
    if (!mounted) return;
    _lastId = productId;
    _lastTitle = title;
    setState(() => _busy = true);
    try {
      final (result, added) = await Billing.i.buy(productId);
      if (!mounted) return;
      switch (result) {
        case BuyResult.granted:
          toast(context, added > 0 ? '${fa(added)} سکه اضافه شد!' : 'خرید انجام شد!');
        case BuyResult.pending:
          toast(context, 'پرداخت انجام شد؛ به‌محض وصل شدن اینترنت، خریدت اضافه می‌شه.');
        case BuyResult.cancelled:
          break;
        case BuyResult.unavailable:
          await _explainProblem();
        case BuyResult.failed:
          toast(context, 'خرید انجام نشد. اگه پولی کم شده، نگران نباش؛ برمی‌گرده یا خریدت اضافه می‌شه.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Tells WHY the purchase could not start (not just "install Bazaar"): missing, too old, no answer, other.
  Future<void> _explainProblem() async {
    final problem = Billing.i.problem;
    final text = billingProblemText(problem) ?? billingProblemText(BillingProblem.other)!;
    final openStore = problem == BillingProblem.notInstalled || problem == BillingProblem.tooOld;
    final retry = problem == BillingProblem.timeout || problem == BillingProblem.other;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: K.night,
          title: Text('خرید شروع نشد', style: tDisplay(18)),
          content: Text(text),
          actions: [
            if (openStore) TextButton(onPressed: () => Navigator.pop(ctx, 'store'), child: Text('باز کردن $kStoreName')),
            if (retry) TextButton(onPressed: () => Navigator.pop(ctx, 'retry'), child: const Text('دوباره امتحان کن')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('بستن')),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'store') {
      for (final u in ['bazaar://details?id=com.farsitel.bazaar', 'https://cafebazaar.ir/app/com.farsitel.bazaar']) {
        try {
          if (await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication)) break;
        } catch (_) {}
      }
    } else if (choice == 'retry') {
      await _buyAgain();
    }
  }

  String? _lastId, _lastTitle;
  Future<void> _buyAgain() async {
    if (_lastId != null) await _buy(_lastId!, _lastTitle ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final api = Api.i;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: K.night,
        title: Text('فروشگاه', style: tDisplay(20)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(child: ListenableBuilder(listenable: api, builder: (_, __) => CoinChip(coins: api.coins))),
          ),
        ],
      ),
      body: GrainBackground(
        child: AbsorbPointer(
          absorbing: _busy,
          // SafeArea: the last row must not end up under the phone's navigation bar
          child: SafeArea(
            top: false,
            // nothing is known about the store yet and there is no connection: one calm page instead of empty cards
            child: !api.online && api.config.isEmpty
                ? StateView.offline(
                    key: const ValueKey('shop-state'),
                    body: 'برای دیدن فروشگاه باید به اینترنت وصل باشی. سکه و پیشرفتت سر جاشه؛ وقتی خط برگشت، خودش تازه می‌شه.',
                    onRetry: () async {
                      await api.reconnect();
                      if (mounted) setState(() {});
                    })
                : ListView(padding: const EdgeInsets.all(16), children: [
              const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
              ListenableBuilder(
                listenable: Billing.i,
                builder: (_, __) => Billing.i.connecting
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('در حال اتصال به $kStoreName…', style: const TextStyle(color: K.textSoft)),
                        ]),
                      )
                    : const SizedBox.shrink(),
              ),
              // the «کارآگاه ویژه» card leads; the one-time starter pack is its own row below the bags
              ListenableBuilder(listenable: api, builder: (_, __) => _vipHero()),
              const SizedBox(height: 22),
              _heading('سکه', null),
              const SizedBox(height: 16),
              ListenableBuilder(
                listenable: api,
                builder: (_, __) {
                  final best = _bestPackId;
                  return IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: _pack('coins_small', 'کیسه‌ی کوچیک', 1, tag: best == 'coins_small' ? 'بیشترین ارزش' : null)),
                      const SizedBox(width: 10),
                      Expanded(child: _pack('coins_medium', 'کیف کارآگاه', 2, tag: best == 'coins_medium' ? 'بیشترین ارزش' : null)),
                      const SizedBox(width: 10),
                      Expanded(child: _pack('coins_large', 'گاوصندوق', 3, tag: best == 'coins_large' ? 'بیشترین ارزش' : null)),
                    ]),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text('هر پرونده یعنی یه پرونده‌ی بایگانی با سختی متوسط (${fa(ShopValue.typicalArchive)} سکه).',
                  style: tBody(11.5, color: K.textSoft)),
              ListenableBuilder(listenable: api, builder: (_, __) => _starterHero()),
              const SizedBox(height: 22),
              if (api.adsEnabled) ...[
                const SizedBox(height: 4),
                GhostButton(label: 'دیدن تبلیغ و گرفتن سکه رایگان', icon: Icons.play_circle_fill_rounded, color: K.brass,
                    onTap: () => watchAd(context)),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: K.night, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.night3)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.lock_outline_rounded, size: 20, color: K.textSoft)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        'پرداخت از طریق $kStoreName انجام می‌شه. اگه پول کم شد ولی سکه‌ها نرسید، دفعه‌ی بعد که بازی به اینترنت وصل بشه خودبه‌خود اضافه می‌شن. پرونده‌ی روزانه همیشه رایگانه و برای بازی کردنش سکه لازم نداری.',
                        style: tBody(12, color: K.textSoft).copyWith(height: 1.8)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- value labels (computed from the real prices, never typed in)

  /// Toman in a price label like «۳۹٬۰۰۰ تومان»; null when it cannot be read.
  static int? _toman(String label) {
    final ascii = label.replaceAllMapped(RegExp('[۰-۹]'), (m) => '${m[0]!.codeUnitAt(0) - 0x06F0}');
    final m = RegExp(r'\d[\d٬,]*').firstMatch(ascii);
    if (m == null) return null;
    final v = int.tryParse(m[0]!.replaceAll(RegExp('[٬,]'), ''));
    return v == null || v <= 0 ? null : v;
  }

  String _priceOf(String id) => Billing.i.price(id) ?? Api.i.price(id);

  /// Coins per toman of a product, or null when the price or the coins are unknown.
  double? _perToman(String id) {
    final coins = Api.i.productCoins(id);
    final t = _toman(_priceOf(id));
    return coins > 0 && t != null ? coins / t : null;
  }

  /// The bag with the most coins per toman (real prices); null when unknown or tied.
  String? get _bestPackId => ShopValue.bestValueId({
        for (final id in ['coins_small', 'coins_medium', 'coins_large']) id: (coins: Api.i.productCoins(id), toman: _toman(_priceOf(id))),
      });

  /// Best coins per toman over the three bags (for the VIP comparison).
  double? get _bestPerToman {
    double? best;
    for (final id in ['coins_small', 'coins_medium', 'coins_large']) {
      final v = _perToman(id);
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  /// Archive cases a coin amount opens at the middle difficulty price (150).
  int _cases(int coins) => ShopValue.cases(coins);

  /// True when the starter pack gives more coins per toman than every bag.
  bool get _starterIsCheapest {
    final s = _perToman('starter_pack');
    if (s == null) return false;
    for (final id in ['coins_small', 'coins_medium', 'coins_large']) {
      final o = _perToman(id);
      if (o != null && o >= s) return false;
    }
    return true;
  }

  Widget _starterHero() {
    final api = Api.i;
    if (api.profile?.noAds ?? false) return const SizedBox.shrink(); // bought (or VIP): nothing to sell here
    const id = 'starter_pack';
    final coins = api.productCoins(id);
    if (coins <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GestureDetector(
        onTap: () => _buy(id, 'بسته‌ی شروع'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF3A2C12), K.night2]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: K.brass, width: 1.5),
            boxShadow: [BoxShadow(color: K.brass.withValues(alpha: 0.18), blurRadius: 26)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
                child: Text('فقط یک بار برای هر حساب', style: tBody(11.5, color: K.ink, w: FontWeight.w900)),
              ),
              if (_starterIsCheapest) Text('ارزان‌ترین سکه‌ی فروشگاه', style: tBody(11.5, color: K.brass, w: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              const CoinIcon(size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('بسته‌ی شروع', style: tBody(13, color: K.textSoft, w: FontWeight.w800)),
                  Text('${fa(coins)} سکه', style: tDisplay(26, color: K.brass)),
                  Text('+ همیشه بدون تبلیغ', style: tBody(13, w: FontWeight.w800)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            if (_cases(coins) > 0) ...[
              Text('${fa(coins)} سکه ≈ ${fa(_cases(coins))} پرونده‌ی بایگانی', style: tBody(12, color: K.text.withValues(alpha: 0.8)).copyWith(height: 1.7)),
              const SizedBox(height: 10),
            ],
            StampButton(label: 'بخرش · ${_priceOf(id)}', icon: Icons.shopping_bag_rounded, height: 48, onTap: () => _buy(id, 'بسته‌ی شروع')),
          ]),
        ),
      ),
    );
  }

  Widget _heading(String title, String? sub) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(title, style: tDisplay(18)),
        if (sub != null) ...[
          const SizedBox(width: 8),
          Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.textSoft))),
        ],
      ]);

  int _vipDaysLeft() {
    final until = Api.i.profile?.vipUntil;
    if (until == null) return 0;
    final left = until * 1000 - DateTime.now().millisecondsSinceEpoch;
    return left <= 0 ? 0 : (left / Duration.millisecondsPerDay).ceil();
  }

  /// The 30-day VIP card.
  Widget _vipHero() {
    const id = 'vip_monthly';
    final vip = Api.i.profile?.vip ?? false;
    final breakEven = ShopValue.vipBreakEven(_toman(_priceOf(id)), _bestPerToman);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF2E2416), K.night2],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: K.brass, width: 1.5),
        boxShadow: [BoxShadow(color: K.brass.withValues(alpha: 0.16), blurRadius: 20)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
            child: Text('پیشنهاد ویژه', style: tBody(11.5, color: K.ink, w: FontWeight.w900)),
          ),
          const Spacer(),
          const Icon(Icons.workspace_premium_rounded, color: K.brass, size: 30),
        ]),
        const SizedBox(height: 8),
        Text('کارآگاه ویژه · ۳۰ روز', style: tDisplay(22)),
        const SizedBox(height: 4),
        Text('✓ کل بایگانی باز، بدون سکه', style: tBody(13.5, color: K.text.withValues(alpha: 0.85))),
        Text('✓ سرنخ اول هر پرونده رایگان', style: tBody(13.5, color: K.text.withValues(alpha: 0.85))),
        if (breakEven != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('اگه ماهی ${fa(breakEven)} پرونده‌ی قدیمی یا بیشتر باز کنی، از سکه خریدن ارزون‌تره.',
                style: tBody(12, color: K.textSoft).copyWith(height: 1.6)),
          ),
        if (vip)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('الان کارآگاه ویژه‌ای${_vipDaysLeft() > 0 ? ' · ${fa(_vipDaysLeft())} روز مانده' : ''}؛ با خرید دوباره ۳۰ روز اضافه می‌شه.',
                style: tBody(12.5, color: K.brass, w: FontWeight.w700)),
          ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Text(Billing.i.price(id) ?? Api.i.price(id),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: tDisplay(18, color: K.brass)),
          ),
          const SizedBox(width: 10),
          StampButton(label: 'بخر', icon: Icons.shopping_bag_rounded, height: 46, onTap: () => _buy(id, 'کارآگاه ویژه')),
        ]),
      ]),
    );
  }

  Widget _price(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: K.brass.withValues(alpha: 0.6))),
        child: Text(text, maxLines: 1, textAlign: TextAlign.center, style: tBody(12, color: K.brass, w: FontWeight.w900)),
      );

  Widget _pack(String id, String title, int size, {String? tag}) {
    final api = Api.i;
    return GestureDetector(
      onTap: () => _buy(id, title),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 16, 6, 10),
          decoration: BoxDecoration(
            color: K.night2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tag != null ? K.brass.withValues(alpha: 0.7) : K.night3),
          ),
          child: Column(children: [
            SizedBox(
              height: 26,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (int i = 0; i < size; i++)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 1), child: CoinIcon(size: 22)),
              ]),
            ),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(fa(api.productCoins(id)), maxLines: 1, style: tDisplay(20))),
            Text(title, textAlign: TextAlign.center, maxLines: 2, style: tBody(11.5, color: K.textSoft, w: FontWeight.w800)),
            const SizedBox(height: 2),
            const SizedBox(height: 4),
            if (_cases(api.productCoins(id)) > 0)
              Text('≈ ${fa(_cases(api.productCoins(id)))} پرونده', textAlign: TextAlign.center, maxLines: 1, style: tBody(12, w: FontWeight.w800)),
            const Spacer(),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FittedBox(fit: BoxFit.scaleDown, child: _price(Billing.i.price(id) ?? api.price(id))),
            ),
          ]),
        ),
        if (tag != null)
          Positioned(
            top: -10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(99)),
                child: Text(tag, maxLines: 1, style: tBody(10, color: K.ink, w: FontWeight.w900)),
              ),
            ),
          ),
      ]),
    );
  }
}
