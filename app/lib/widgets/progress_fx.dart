import 'dart:async';

import 'package:flutter/material.dart';

import '../models/progress.dart';
import '../services/sound.dart';
import '../theme.dart';

/// Shows what an action earned (a finished mission, a new rank, an achievement) as banners
/// that slide in from the top, one after another. Nothing happens when there is nothing to show.
void celebrate(BuildContext context, Gains g) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay != null) celebrateOn(overlay, g);
}

void celebrateOn(OverlayState overlay, Gains g) {
  final items = <(IconData, String, String)>[
    for (final m in g.missionsDone) (Icons.task_alt_rounded, 'مأموریت انجام شد', m),
    for (final a in g.achievements)
      (Icons.military_tech_rounded, 'دستاورد تازه: «${a.title}»', a.coins > 0 ? '${fa(a.coins)} سکه جایزه' : ''),
    if (g.rankUp != null) (Icons.workspace_premium_rounded, 'درجه‌ی تازه!', 'حالا «${g.rankUp}» هستی'),
  ];
  if (items.isEmpty) return;
  unawaited(_show(overlay, items));
}

Future<void> _show(OverlayState overlay, List<(IconData, String, String)> items) async {
  for (final (icon, title, sub) in items) {
    if (!overlay.mounted) return;
    final entry = OverlayEntry(builder: (_) => _Banner(icon: icon, title: title, sub: sub));
    overlay.insert(entry);
    Sfx.i.play('clue', volume: 0.6);
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    entry.remove();
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.sub});
  final IconData icon;
  final String title, sub;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.translate(offset: Offset(0, -90 * (1 - v)), child: child),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2B2414),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: K.brass, width: 2),
                    boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 16, offset: Offset(0, 6))],
                  ),
                  child: Row(children: [
                    Icon(icon, color: K.brass, size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(title, style: tDisplay(16, color: K.brass)),
                        if (sub.isNotEmpty) Text(sub, style: tBody(13)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
