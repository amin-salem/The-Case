import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../models/story.dart';
import '../theme.dart';

/// A rounded rectangle with a dashed border (locked options, clues not found, people not met).
class DashedBox extends StatelessWidget {
  const DashedBox({super.key, required this.child, this.color = const Color(0xFF45464A), this.radius = 16, this.fill = K.night2, this.padding = EdgeInsets.zero});
  final Widget child;
  final Color color, fill;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashPainter(color, radius, fill),
        child: Padding(padding: padding, child: child),
      );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.radius, this.fill);
  final Color color, fill;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    canvas.drawRRect(rrect, Paint()..color = fill);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(rrect.deflate(0.6));
    for (final PathMetric m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 8) {
        canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), line);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color || old.radius != radius || old.fill != fill;
}

/// One option of a scene: a paper card with a numbered tile, or (locked) a dashed dark card with the reason.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({super.key, required this.option, required this.index, required this.onTap});
  final ChoiceOption option;
  final int index; // 1-based
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (option.locked) {
      return Semantics(
        label: '${option.title}. ${option.reason}',
        child: DashedBox(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.lock_rounded, size: 18, color: K.textSoft),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(option.title, style: tBody(14.5, color: K.textSoft, w: FontWeight.w900)),
                Text(option.reason, style: tBody(12.5, color: K.textSoft)),
              ]),
            ),
          ]),
        ),
      );
    }
    return Material(
      color: K.paper,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: K.ink, borderRadius: BorderRadius.circular(10)),
              child: Text(fa(index), style: tDisplay(16, color: K.brass)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(option.title, style: tBody(14.5, color: K.ink, w: FontWeight.w900)),
                if (option.sub.isNotEmpty) Text(option.sub, style: tBody(12.5, color: K.inkSoft)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

String _initial(String name) {
  final t = name.trim();
  return t.isEmpty ? '؟' : String.fromCharCode(t.runes.first);
}

/// A person on the board: avatar ring, name and how they feel about the player.
class PersonTile extends StatelessWidget {
  const PersonTile({super.key, required this.person});
  final BoardPerson person;

  @override
  Widget build(BuildContext context) {
    final met = person.state != 'unmet';
    final color = switch (person.state) {
      'friendly' => K.ok,
      'suspicious' => K.stamp,
      _ => K.textSoft,
    };
    final circle = Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: K.night3,
        border: Border.all(color: met ? K.brass : const Color(0xFF45464A), width: 2),
      ),
      child: Text(met ? _initial(person.name) : '؟', style: tDisplay(18, color: met ? K.brass : K.textSoft)),
    );
    final label = person.text.isNotEmpty ? person.text : (met ? '' : 'هنوز ندیده‌ای');
    final body = Column(mainAxisSize: MainAxisSize.min, children: [
      circle,
      const SizedBox(height: 6),
      Text(met ? person.name : 'ناشناس', textAlign: TextAlign.center, style: tBody(12.5, color: met ? K.text : K.textSoft, w: FontWeight.w900)),
      Text(label, textAlign: TextAlign.center, style: tBody(11, color: color)),
    ]);
    if (!met) {
      return DashedBox(radius: 14, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10), child: Center(child: body));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14)),
      child: Center(child: body),
    );
  }
}

/// A clue row: held (paper, «انتخاب تو»), skipped (gray, dashed, lock) or not found yet (gray, dashed).
class ClueTile extends StatelessWidget {
  const ClueTile({super.key, required this.clue});
  final BoardClue clue;

  @override
  Widget build(BuildContext context) {
    if (clue.held) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(clue.title ?? '', style: tBody(14, color: K.ink, w: FontWeight.w900)),
              if ((clue.text ?? '').isNotEmpty) Text(clue.text!, style: tBody(12.5, color: K.inkSoft)),
            ]),
          ),
          if (clue.byChoice) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: K.ink, borderRadius: BorderRadius.circular(10)),
              child: Text('انتخاب تو', style: tBody(11, color: K.brass, w: FontWeight.w900)),
            ),
          ],
        ]),
      );
    }
    final missed = clue.missed;
    return DashedBox(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(missed ? (clue.title ?? '') : 'سرنخی که هنوز پیدا نکرده‌ای', style: tBody(14, color: K.textSoft, w: FontWeight.w900)),
            Text(missed ? 'راهی که نرفتی' : 'جلوتر شاید پیدا بشه', style: tBody(12.5, color: const Color(0xFF6C6D71))),
          ]),
        ),
        Icon(missed ? Icons.lock_rounded : Icons.help_outline_rounded, size: 18, color: const Color(0xFF6C6D71)),
      ]),
    );
  }
}
