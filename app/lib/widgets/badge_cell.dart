import 'dart:math';

import 'package:flutter/material.dart';

import '../models/progress.dart';
import '../theme.dart';

/// One badge on the badge wall: a 64 px circle. Earned = gold gradient ring, dark icon, brass subtitle.
/// Not earned = grey: dark fill, dashed border, grey icon and text, and the progress under the name.
class BadgeCell extends StatelessWidget {
  const BadgeCell({super.key, required this.badge, required this.icon, this.onTap});
  final AchievementRow badge;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final a = badge;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        a.earned
            ? Container(
                key: ValueKey('badge-earned-${a.id}'),
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [kBadgeGold, K.kraft, K.kraftDark]),
                  boxShadow: [BoxShadow(color: Color(0x33E0A526), blurRadius: 10)],
                ),
                child: Icon(icon, color: K.ink, size: 30),
              )
            : CustomPaint(
                key: ValueKey('badge-locked-${a.id}'),
                foregroundPainter: const _DashedCircle(color: kBadgeLockedBorder, width: 2),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: K.night3),
                  child: Icon(icon, color: kBadgeLockedIcon, size: 28),
                ),
              ),
        const SizedBox(height: 6),
        Text(a.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tBody(12, w: FontWeight.w700, color: a.earned ? K.text : kBadgeLockedText).copyWith(height: 1.35)),
        if (a.earned && a.coins > 0)
          Text('${fa(a.coins)} سکه', style: tBody(11, w: FontWeight.w700, color: K.brass).copyWith(height: 1.3))
        else if (!a.earned)
          Text('${fa(a.progress)} از ${fa(a.target)}', style: tBody(11, color: kBadgeLockedText).copyWith(height: 1.3)),
      ]),
    );
  }
}

class _DashedCircle extends CustomPainter {
  const _DashedCircle({required this.color, required this.width});
  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()..addOval(Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width));
    const dash = 6.0, gap = 4.0;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color || old.width != width;
}
