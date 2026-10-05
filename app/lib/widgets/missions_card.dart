import 'package:flutter/material.dart';

import '../models/progress.dart';
import '../services/api.dart';
import '../services/sound.dart';
import '../theme.dart';
import 'fx.dart';
import 'offline.dart';
import 'typewriter.dart';

/// Today's three missions with progress bars, and the chest when all are done.
class MissionsCard extends StatelessWidget {
  const MissionsCard({super.key, required this.day, required this.onChanged});
  final MissionsDay day;
  final ValueChanged<MissionsDay> onChanged;

  Future<void> _claim(BuildContext context) async {
    if (!needOnline(context)) return;
    try {
      final (m, coins) = await Api.i.claimChest();
      onChanged(m);
      if (context.mounted) await showChest(context, coins, m.chestStreak);
    } catch (e) {
      if (context.mounted) toast(context, Api.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = day;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: K.kraft.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.assignment_turned_in_rounded, color: K.brass, size: 26),
          const SizedBox(width: 8),
          Expanded(child: Text('مأموریت‌های امروز', style: tDisplay(18))),
          if (d.chestStreak > 1)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('${fa(d.chestStreak)} روز پیاپی', style: tBody(12, color: K.stamp, w: FontWeight.w700)),
            ),
          Text('${fa(d.done)}/${fa(d.missions.length)}', style: tBody(14, color: K.brass, w: FontWeight.w900)),
        ]),
        const SizedBox(height: 8),
        for (final m in d.missions) _row(m),
        const SizedBox(height: 4),
        if (d.claimed)
          Row(children: [
            const Icon(Icons.inventory_2_rounded, color: K.ok, size: 20),
            const SizedBox(width: 6),
            Expanded(child: Text('صندوقچه‌ی امروز باز شد. فردا مأموریت‌های تازه!', style: tBody(12.5, color: K.ok))),
          ])
        else if (d.allDone)
          StampButton(
            label: 'باز کردن صندوقچه · ${fa(d.chestCoins)} سکه',
            icon: Icons.inventory_2_rounded,
            color: K.ok,
            height: 46,
            onTap: () => _claim(context),
          )
        else
          Row(children: [
            Icon(Icons.inventory_2_outlined, color: K.textSoft.withValues(alpha: 0.8), size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text('هر سه رو انجام بده تا صندوقچه‌ی ${fa(d.chestCoins)} سکه‌ای باز بشه',
                  style: tBody(12.5, color: K.textSoft)),
            ),
          ]),
      ]),
    );
  }

  Widget _row(MissionRow m) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(m.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 20, color: m.done ? K.ok : K.textSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title,
                  style: tBody(13.5, w: FontWeight.w700, color: m.done ? K.textSoft : K.text)
                      .copyWith(decoration: m.done ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: m.target == 0 ? 0 : m.progress / m.target),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) =>
                      LinearProgressIndicator(value: v, minHeight: 5, backgroundColor: K.night3, color: m.done ? K.ok : K.brass),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text('${fa(m.progress)}/${fa(m.target)}', style: tBody(12, color: K.textSoft)),
        ]),
      );
}

/// The chest opening: coins, and the streak of days.
Future<void> showChest(BuildContext context, int coins, int streak) {
  Sfx.i.play('win', volume: 0.8);
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Stack(alignment: Alignment.center, children: [
        const Positioned.fill(child: IgnorePointer(child: Confetti())),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const StampIn(child: Icon(Icons.inventory_2_rounded, color: K.kraftDark, size: 72)),
            const SizedBox(height: 8),
            Text('صندوقچه باز شد!', style: tDisplay(24, color: K.ink)),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('+${fa(coins)}', style: tDisplay(28, color: K.kraftDark)),
              const SizedBox(width: 6),
              const CoinIcon(size: 26),
            ]),
            if (streak > 1) ...[
              const SizedBox(height: 6),
              Text('${fa(streak)} روز پشت سر هم همه‌ی مأموریت‌ها رو انجام دادی!',
                  textAlign: TextAlign.center, style: tBody(13.5, color: K.inkSoft)),
            ],
            const SizedBox(height: 14),
            StampButton(label: 'عالی', onTap: () => Navigator.pop(ctx)),
          ]),
        ),
      ]),
    ),
  );
}
