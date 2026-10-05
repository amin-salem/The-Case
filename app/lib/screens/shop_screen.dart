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
      toast(context, 'برای خرید، اپ مایکت باید روی گوشی نصب و به‌روز باشه.');
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
          toast(context, 'برای خرید، اپ مایکت باید روی گوشی نصب و به‌روز باشه.');
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
          // SafeArea: the last button must not end up under the phone's navigation bar
          child: SafeArea(
            top: false,
            child: ListView(padding: const EdgeInsets.all(16), children: [
            const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
            Text('با سکه سرنخ بگیر و پرونده‌های قدیمی رو باز کن.', style: tBody(14, color: K.textSoft)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _pack('coins_small', 'کیسه‌ی کوچیک', 1)),
              const SizedBox(width: 10),
              Expanded(child: _pack('coins_medium', 'کیف کارآگاه', 2, tag: 'محبوب‌ترین')),
              const SizedBox(width: 10),
              Expanded(child: _pack('coins_large', 'گاوصندوق', 3, tag: 'بهترین ارزش')),
            ]),
            const SizedBox(height: 14),
            _row('starter_pack', 'بسته‌ی شروع', '${fa(api.productCoins('starter_pack'))} سکه با تخفیف · فقط یک بار',
                Icons.card_giftcard_rounded, K.stamp),
            _row('vip_monthly', 'کارآگاه ویژه · ۳۰ روز', 'همه‌ی پرونده‌های بایگانی رایگان و اولین سرنخ هر پرونده رایگان',
                Icons.workspace_premium_rounded, K.brass),
            ListenableBuilder(listenable: Api.i, builder: (_, __) => _insuranceRow()),
            const SizedBox(height: 10),
            if (api.adsEnabled)
              StampButton(label: 'دیدن تبلیغ و گرفتن سکه رایگان', icon: Icons.play_circle_fill_rounded, color: K.ok,
                  onTap: () => watchAd(context)),
            const SizedBox(height: 14),
            Text('پرداخت از طریق مایکت انجام می‌شه. اگه پرداخت کردی و خریدت نرسید، دفعه‌ی بعد که بازی وصل بشه خودش اضافه می‌شه.',
                style: tBody(12.5, color: K.textSoft)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _pack(String id, String title, int size, {String? tag}) {
    final api = Api.i;
    return GestureDetector(
      onTap: () => _buy(id, title),
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
          decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            Wrap(alignment: WrapAlignment.center, children: [for (int i = 0; i < size; i++) const CoinIcon(size: 24)]),
            const SizedBox(height: 6),
            Text(fa(api.productCoins(id)), maxLines: 1, style: tDisplay(20, color: K.ink)),
            Text(title, textAlign: TextAlign.center, style: tBody(12, color: K.inkSoft)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(color: K.ok, borderRadius: BorderRadius.circular(8)),
              child: Text(Billing.i.price(id) ?? api.price(id), textAlign: TextAlign.center, style: tBody(12, color: Colors.white, w: FontWeight.w900)),
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
                decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(99)),
                child: Text(tag, style: tBody(10, color: Colors.white, w: FontWeight.w900)),
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
    return GestureDetector(
      onTap: () => buyStreakInsurance(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.ok.withValues(alpha: 0.5))),
        child: Row(children: [
          const Icon(Icons.shield_rounded, color: K.ok, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('بیمه‌ی زنجیره', style: tBody(16, w: FontWeight.w900)),
              Text('یه شب جا بمونی، زنجیره‌ات نمی‌شکنه · داری: ${fa(held)} از ${fa(api.maxFreezes)}',
                  style: tBody(12.5, color: K.textSoft)),
            ]),
          ),
          const SizedBox(width: 6),
          const CoinIcon(size: 18),
          const SizedBox(width: 4),
          Text(fa(api.freezeCost), style: tBody(13, color: K.brass, w: FontWeight.w900)),
        ]),
      ),
    );
  }

  Widget _row(String id, String title, String sub, IconData icon, Color color) {
    return GestureDetector(
      onTap: () => _buy(id, title),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.5))),
        child: Row(children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: tBody(16, w: FontWeight.w900)),
              Text(sub, style: tBody(12.5, color: K.textSoft)),
            ]),
          ),
          const SizedBox(width: 6),
          Text(Billing.i.price(id) ?? Api.i.price(id), style: tBody(13, color: K.brass, w: FontWeight.w900)),
        ]),
      ),
    );
  }
}
