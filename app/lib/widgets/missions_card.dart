import 'dart:async';

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

// ---------------------------------------------------------------- the big card on Home

/// What the «ادامه» button of a mission should do.
enum MissionTarget { tonight, weekend, archive, sheet }

/// Which screen a mission lives on (an unknown mission opens the missions sheet).
MissionTarget missionTarget(String id) => switch (id) {
      'daily_case' || 'case_3stars' || 'case_no_hint' || 'case_first_try' || 'interrogate_all' || 'talk3' || 'hint_use' =>
        MissionTarget.tonight,
      'weekend_talk' => MissionTarget.weekend,
      'case_solve2' || 'archive_open' => MissionTarget.archive,
      _ => MissionTarget.sheet,
    };

/// The prominent «مأموریت‌های امروز» card under tonight's case: three missions, the chest, one button, and the
/// time left until the missions change at 21:00, with the new case.
class HomeMissionsCard extends StatefulWidget {
  const HomeMissionsCard({super.key, required this.day, required this.onChanged, required this.onGo, required this.onOpenSheet, this.now});
  final MissionsDay day;
  final ValueChanged<MissionsDay> onChanged;

  /// Take the player to where [MissionRow] can be done.
  final void Function(MissionRow) onGo;
  final VoidCallback onOpenSheet;

  /// The clock (tests pass a fixed one).
  final DateTime Function()? now;

  @override
  State<HomeMissionsCard> createState() => _HomeMissionsCardState();
}

class _HomeMissionsCardState extends State<HomeMissionsCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  Timer? _tick;
  bool _busy = false;

  bool get _ready => widget.day.allDone && !widget.day.claimed;

  @override
  void initState() {
    super.initState();
    _syncPulse();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(HomeMissionsCard old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  void _syncPulse() {
    if (_ready) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _claim() async {
    if (_busy || !needOnline(context)) return;
    setState(() => _busy = true);
    try {
      final (m, coins) = await Api.i.claimChest();
      widget.onChanged(m);
      if (mounted) await showChest(context, coins, m.chestStreak);
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  MissionRow? get _firstOpen {
    for (final m in widget.day.missions) {
      if (!m.done) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.day;
    final total = d.missions.length;
    final left = d.nextAt.difference((widget.now ?? DateTime.now)());
    final next = _firstOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: const ValueKey('home-missions'),
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: K.kraft.withValues(alpha: 0.55), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(children: [
            // a soft brass glow in the corner
            Positioned(
              left: -50,
              top: -50,
              child: IgnorePointer(
                child: Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [K.brass.withValues(alpha: 0.22), K.brass.withValues(alpha: 0)]),
                  ),
                ),
              ),
            ),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onOpenSheet, child: _top(d, total)),
                  const SizedBox(height: 12),
                  for (final m in d.missions) _mission(m),
                  const SizedBox(height: 4),
                  _action(d, next),
                  const SizedBox(height: 10),
                  _footer(d, left),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _top(MissionsDay d, int total) {
    return Row(children: [
      AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: K.night3,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: K.kraftDark, width: 1.5),
            boxShadow: _ready ? [BoxShadow(color: K.brass.withValues(alpha: 0.2 + 0.45 * _pulse.value), blurRadius: 6 + 16 * _pulse.value)] : null,
          ),
          child: child,
        ),
        child: Icon(d.claimed ? Icons.inventory_2_outlined : Icons.inventory_2_rounded, color: K.brass, size: 32),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('مأموریت‌های امروز', style: tDisplay(18)),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'هر سه رو انجام بده؛ صندوقچه‌ی '),
              TextSpan(text: '${fa(d.chestCoins)} سکه‌ای', style: tBody(12, color: K.brass, w: FontWeight.w900)),
              const TextSpan(text: ' باز می‌شه'),
            ]),
            style: tBody(12, color: K.textSoft).copyWith(height: 1.5),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 48,
        height: 48,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              key: const ValueKey('missions-ring'),
              value: total == 0 ? 0 : d.done / total,
              strokeWidth: 5,
              backgroundColor: K.night3,
              color: K.brass,
            ),
          ),
          Text('${fa(d.done)}/${fa(total)}', style: tBody(12, w: FontWeight.w900, color: K.brass).copyWith(height: 1.2)),
        ]),
      ),
    ]);
  }

  Widget _mission(MissionRow m) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(children: [
          Icon(m.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              key: ValueKey('mission-${m.done ? 'done' : 'open'}-${m.id}'), size: 22, color: m.done ? K.ok : K.textSoft),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.title,
                  style: tBody(13.5, w: FontWeight.w700, color: m.done ? K.textSoft : K.text)
                      .copyWith(decoration: m.done ? TextDecoration.lineThrough : null, height: 1.45)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: m.done ? 1 : (m.target <= 0 ? 0 : (m.progress / m.target).clamp(0.0, 1.0).toDouble()),
                  minHeight: 6,
                  backgroundColor: K.night3,
                  color: m.done ? K.ok : K.brass,
                ),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Text('${fa(m.done ? m.target : m.progress)}/${fa(m.target)}', style: tBody(12, color: K.textSoft)),
        ]),
      );

  Widget _action(MissionsDay d, MissionRow? next) {
    if (d.claimed) {
      return Row(children: [
        const Icon(Icons.inventory_2_rounded, color: K.ok, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text('صندوقچه‌ی امروز باز شد', style: tBody(13.5, color: K.ok, w: FontWeight.w900))),
      ]);
    }
    final ready = d.allDone;
    return SizedBox(
      height: 44,
      child: Material(
        color: ready ? K.ok : K.brass,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: ValueKey(ready ? 'missions-claim' : 'missions-go'),
          borderRadius: BorderRadius.circular(12),
          onTap: ready ? _claim : (next == null ? widget.onOpenSheet : () => widget.onGo(next)),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                ready ? 'باز کردن صندوقچه · ${fa(d.chestCoins)} سکه' : 'ادامه: ${next?.title ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tBody(14, w: FontWeight.w900, color: K.ink).copyWith(height: 1.3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer(MissionsDay d, Duration left) {
    return Row(children: [
      if (d.chestStreak > 1)
        Expanded(
          child: Text('${fa(d.chestStreak)} روز پیاپی صندوقچه رو باز کردی',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.stamp, w: FontWeight.w700)),
        )
      else
        const Spacer(),
      const Icon(Icons.schedule_rounded, size: 14, color: K.textSoft),
      const SizedBox(width: 4),
      Text('تا مأموریت‌های تازه: ${faClock(left)}', maxLines: 1, style: tBody(11.5, color: K.textSoft)),
    ]);
  }
}
