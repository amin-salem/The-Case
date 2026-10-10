import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/billing.dart';
import '../theme.dart';
import '../widgets/engagement.dart';
import '../widgets/offline.dart';
import 'dialogs.dart';

/// Coin packs and perks, paid through Myket. Every purchase is checked by our server with Myket
/// before coins are added; the price shown is Myket's own when it can tell us.
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  bool _busy = false;

  Future<void> _buy(String productId, String title) async {
    if (!needOnline(context)) return;
    if (!Billing.i.available) {
      toast(context, 'برای خرید، اپ $kStoreName باید روی گوشی نصب و به‌روز باشه.');
      return;
    }
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
          toast(context, 'برای خرید، اپ $kStoreName باید روی گوشی نصب و به‌روز باشه.');
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
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
              ListenableBuilder(listenable: api, builder: (_, __) => _vipHero()),
              const SizedBox(height: 22),
              _heading('سکه', 'برای سرنخ و پرونده‌های قدیمی'),
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: _pack('coins_small', 'کیسه‌ی کوچیک', 1)),
                  const SizedBox(width: 10),
                  Expanded(child: _pack('coins_medium', 'کیف کارآگاه', 2, tag: 'محبوب')),
                  const SizedBox(width: 10),
                  Expanded(child: _pack('coins_large', 'گاوصندوق', 3, tag: 'بهترین ارزش')),
                ]),
              ),
              const SizedBox(height: 10),
              _row(
                icon: Icons.card_giftcard_rounded,
                title: 'بسته‌ی شروع',
                sub: '${fa(api.productCoins('starter_pack'))} سکه با تخفیف · فقط یک بار',
                trailing: _price(Billing.i.price('starter_pack') ?? api.price('starter_pack')),
                onTap: () => _buy('starter_pack', 'بسته‌ی شروع'),
              ),
              const SizedBox(height: 14),
              _heading('با سکه', null),
              const SizedBox(height: 8),
              ListenableBuilder(listenable: api, builder: (_, __) => _insuranceRow()),
              if (api.adsEnabled) ...[
                const SizedBox(height: 4),
                GhostButton(label: 'دیدن تبلیغ و گرفتن سکه رایگان', icon: Icons.play_circle_fill_rounded, color: K.brass,
                    onTap: () => watchAd(context)),
              ],
              const SizedBox(height: 16),
              Text('پرداخت از طریق $kStoreName انجام می‌شه. اگه پول کم شد ولی سکه‌ها نرسید، دفعه‌ی بعد که بازی به اینترنت وصل بشه خودبه‌خود اضافه می‌شن.',
                  style: tBody(12.5, color: K.textSoft)),
            ]),
          ),
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

  /// The 30-day VIP: the one big card at the top.
  Widget _vipHero() {
    const id = 'vip_monthly';
    final vip = Api.i.profile?.vip ?? false;
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
        Text('همه‌ی پرونده‌های بایگانی رایگان · اولین سرنخ هر پرونده رایگان',
            style: tBody(13.5, color: K.text.withValues(alpha: 0.85))),
        if (vip)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('الان کارآگاه ویژه‌ای؛ با خرید دوباره ۳۰ روز اضافه می‌شه.',
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
            Text(title, textAlign: TextAlign.center, maxLines: 2, style: tBody(11.5, color: K.textSoft)),
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

  /// Streak insurance is bought with coins, not money.
  Widget _insuranceRow() {
    final api = Api.i;
    final held = api.profile?.streakFreezes ?? 0;
    return _row(
      icon: Icons.shield_rounded,
      title: 'بیمه‌ی زنجیره',
      sub: 'یه شب جا بمونی، زنجیره‌ات نمی‌شکنه · داری: ${fa(held)} از ${fa(api.maxFreezes)}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        const CoinIcon(size: 18),
        const SizedBox(width: 4),
        Text(fa(api.freezeCost), style: tBody(13, color: K.brass, w: FontWeight.w900)),
      ]),
      onTap: () => buyStreakInsurance(context),
    );
  }

  Widget _row({required IconData icon, required String title, required String sub, required Widget trailing, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.night3)),
        child: Row(children: [
          Icon(icon, color: K.brass, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: tBody(15, w: FontWeight.w900)),
              Text(sub, style: tBody(12, color: K.textSoft)),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      ),
    );
  }
}
