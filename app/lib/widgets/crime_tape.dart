import 'dart:math';

import 'package:flutter/material.dart';

import '../services/sound.dart';
import '../theme.dart';

const _tapeYellow = Color(0xFFF2C230);
const _tapeInk = Color(0xFF1C1A14);

/// A strip of yellow police tape: «صحنه‌ی جرم · وارد نشوید ·» repeated along it.
class CrimeTape extends StatelessWidget {
  const CrimeTape({super.key, this.height = 26, this.text = 'صحنه‌ی جرم  •  وارد نشوید  •  '});
  final double height;
  final String text;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _TapePainter(height, text)));
}

class _TapePainter extends CustomPainter {
  _TapePainter(this.h, this.text);
  final double h;
  final String text;

  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = _tapeYellow);
    final edge = Paint()..color = _tapeInk;
    final e = max(1.0, h * 0.07);
    c.drawRect(Rect.fromLTWH(0, 0, s.width, e), edge);
    c.drawRect(Rect.fromLTWH(0, s.height - e, s.width, e), edge);
    final tp = TextPainter(
      text: TextSpan(text: text, style: tBody(h * 0.5, color: _tapeInk, w: FontWeight.w900)),
      textDirection: TextDirection.rtl,
    )..layout();
    if (tp.width <= 0) return;
    for (double x = -tp.width * 0.3; x < s.width; x += tp.width) {
      tp.paint(c, Offset(x, (s.height - tp.height) / 2));
    }
    // a little wear: lighter creases across the tape
    final crease = Paint()..color = Colors.white.withValues(alpha: 0.12);
    for (double x = 37; x < s.width; x += 113) {
      c.drawRect(Rect.fromLTWH(x, 0, 3, s.height), crease);
    }
  }

  @override
  bool shouldRepaint(_TapePainter o) => o.h != h || o.text != text;
}

/// Opening a case: two tapes snap across the screen, hold, then are pulled away.
class CrimeTapeIntro extends StatefulWidget {
  const CrimeTapeIntro({super.key});

  @override
  State<CrimeTapeIntro> createState() => _CrimeTapeIntroState();
}

class _CrimeTapeIntroState extends State<CrimeTapeIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))
    ..forward();

  @override
  void initState() {
    super.initState();
    Sfx.i.play('paper', volume: 0.5);
    Future.delayed(const Duration(milliseconds: 950), () {
      if (mounted) Sfx.i.play('paper', volume: 0.6);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) {
          final t = _a.value;
          if (t >= 1) return const SizedBox.shrink();
          final size = MediaQuery.sizeOf(context);
          final w = size.width + size.height; // longer than the diagonal
          final inn = Curves.easeOutBack.transform((t / 0.3).clamp(0.0, 1.0));
          final out = Curves.easeInCubic.transform(((t - 0.55) / 0.45).clamp(0.0, 1.0));
          Widget tape(double angle, double y, double dir, double delay) {
            final i = Curves.easeOutBack.transform(((t - delay) / 0.3).clamp(0.0, 1.0));
            final dx = (1 - i) * dir * w + out * -dir * w * 0.9;
            return Positioned(
              left: (size.width - w) / 2 + dx,
              top: size.height * y + out * size.height * 0.25,
              width: w,
              child: Transform.rotate(angle: angle + out * dir * 0.15, child: const CrimeTape(height: 34)),
            );
          }

          return Stack(children: [
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.35 * inn * (1 - out)))),
            tape(-0.32, 0.36, 1, 0),
            tape(0.26, 0.52, -1, 0.08),
          ]);
        },
      ),
    );
  }
}

/// A yellow numbered evidence marker (the little tents placed at a crime scene).
class EvidenceMarker extends StatelessWidget {
  const EvidenceMarker(this.number, {super.key});
  final int number;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TentPainter(),
      child: SizedBox(
        width: 30,
        height: 26,
        child: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(fa(number), textAlign: TextAlign.center, style: tBody(12, color: _tapeInk, w: FontWeight.w900)),
        ),
      ),
    );
  }
}

class _TentPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Path()
      ..moveTo(s.width * 0.22, 0)
      ..lineTo(s.width * 0.78, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(p.shift(const Offset(0, 2)), Paint()..color = Colors.black.withValues(alpha: 0.3));
    c.drawPath(p, Paint()..color = _tapeYellow);
    c.drawPath(p, Paint()..color = _tapeInk..style = PaintingStyle.stroke..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_TentPainter o) => false;
}
