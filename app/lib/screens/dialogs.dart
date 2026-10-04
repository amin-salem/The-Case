import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import 'shop_screen.dart';

/// "Not enough coins": go to the shop or watch an ad.
Future<void> showNeedCoins(BuildContext context, int need) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
      decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(20)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('سکه کم داری!', style: tDisplay(24, color: K.ink)),
        const SizedBox(height: 4),
        Text('برای این کار ${fa(need)} سکه لازمه. تو ${fa(Api.i.coins)} سکه داری.', style: tBody(14, color: K.inkSoft)),
        const SizedBox(height: 16),
        StampButton(
          label: 'خرید سکه',
          icon: Icons.storefront_rounded,
          onTap: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen()));
          },
        ),
        const SizedBox(height: 10),
        StampButton(
          label: 'دیدن تبلیغ و گرفتن سکه',
          icon: Icons.play_circle_fill_rounded,
          color: K.ok,
          onTap: () async {
            Navigator.pop(ctx);
            await watchAd(context);
          },
        ),
      ]),
    ),
  );
}

/// Shows a (placeholder) rewarded ad, then asks the server for the reward.
/// Replace the waiting part with Tapsell / Adivery later.
Future<void> watchAd(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _FakeAd(),
  );
  if (ok != true || !context.mounted) return;
  try {
    final added = await Api.i.adReward();
    if (context.mounted) toast(context, '${fa(added)} سکه گرفتی!');
  } on ApiException catch (e) {
    if (context.mounted) toast(context, Api.errorText(e.code));
  } catch (e) {
    if (context.mounted) toast(context, 'اتصال به سرور برقرار نیست');
  }
}

class _FakeAd extends StatefulWidget {
  const _FakeAd();

  @override
  State<_FakeAd> createState() => _FakeAdState();
}

class _FakeAdState extends State<_FakeAd> {
  int _left = 5;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        Navigator.pop(context, true);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: K.night3,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.ondemand_video_rounded, size: 48, color: K.brass),
          const SizedBox(height: 10),
          Text('تبلیغ آزمایشی', style: tDisplay(18)),
          Text('${fa(_left)} ثانیه...', style: tBody(14, color: K.textSoft)),
        ]),
      );
}

/// Asks "are you sure?" with a stamp-styled confirm button.
Future<bool> confirm(BuildContext context, String title, String body, String yes) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: K.paper,
      title: Text(title, style: tDisplay(20, color: K.ink)),
      content: Text(body, style: tBody(15, color: K.ink)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('نه', style: tBody(15, color: K.inkSoft))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: K.stamp),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes, style: tBody(15, color: Colors.white, w: FontWeight.w700)),
        ),
      ],
    ),
  );
  return r == true;
}
