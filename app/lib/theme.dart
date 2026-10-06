import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/sound.dart';
import 'widgets/fx.dart';

/// Colors: a detective's desk at night. Dark ink background, paper case
/// sheets, kraft folders, a red rubber stamp and brass details.
class K {
  static const night = Color(0xFF17181A);
  static const night2 = Color(0xFF202124);
  static const night3 = Color(0xFF2B2D31);
  static const paper = Color(0xFFE9E4D8);
  static const paperDark = Color(0xFFD9D2C2);
  static const ink = Color(0xFF222326); // text on paper
  static const inkSoft = Color(0xFF615F5A);
  static const text = Color(0xFFE6E2DA); // text on night
  static const textSoft = Color(0xFF9A9890);
  static const kraft = Color(0xFFC9A15E);
  static const kraftDark = Color(0xFF8A6A2E);
  static const stamp = Color(0xFFD0543F);
  static const brass = Color(0xFFE0A526);
  static const ok = Color(0xFF5DAE7E);
  static const clue = Color(0xFFFFE08A);
}

const String kFont = 'Vazirmatn';

TextStyle tDisplay(double size, {Color color = K.text}) =>
    TextStyle(fontFamily: kFont, fontWeight: FontWeight.w900, fontSize: size, color: color, height: 1.25);
TextStyle tBody(double size, {Color color = K.text, FontWeight w = FontWeight.w400}) =>
    TextStyle(fontFamily: kFont, fontWeight: w, fontSize: size, color: color, height: 1.7);

/// Persian digits with a thousands separator.
String fa(num n) {
  final neg = n < 0;
  final s = n.abs().round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('٬');
    buf.write('۰۱۲۳۴۵۶۷۸۹'[s.codeUnitAt(i) - 48]);
  }
  return (neg ? '-' : '') + buf.toString();
}

/// "۰۲:۱۵:۳۰" style countdown.
String faClock(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int v) => fa(v).padLeft(2, '۰');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

ThemeData buildTheme() => ThemeData(
      fontFamily: kFont,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: K.night,
      colorScheme: ColorScheme.fromSeed(seedColor: K.stamp, brightness: Brightness.dark),
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: NoirTransitions(),
        TargetPlatform.iOS: NoirTransitions(),
        TargetPlatform.linux: NoirTransitions(),
        TargetPlatform.macOS: NoirTransitions(),
        TargetPlatform.windows: NoirTransitions(),
      }),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: K.paper,
        contentTextStyle: TextStyle(fontFamily: kFont, color: K.ink, fontWeight: FontWeight.w700),
        behavior: SnackBarBehavior.floating,
      ),
    );

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
}

// ---------------------------------------------------------------- widgets

/// A paper sheet (case file page).
class Paper extends StatelessWidget {
  const Paper({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = K.paper});
  final Widget child;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 8))],
      ),
      child: DefaultTextStyle(style: tBody(15, color: K.ink), child: child),
    );
  }
}

/// Main button: a red rubber stamp.
class StampButton extends StatefulWidget {
  const StampButton({super.key, required this.label, required this.onTap, this.icon, this.color = K.stamp, this.height = 54});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  final double height;

  @override
  State<StampButton> createState() => _StampButtonState();
}

class _StampButtonState extends State<StampButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              HapticFeedback.lightImpact();
              Sfx.i.play('tap', volume: 0.5);
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.icon != null) ...[Icon(widget.icon, color: Colors.white, size: 22), const SizedBox(width: 8)],
              Flexible(
                child: Text(widget.label,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tDisplay(17, color: Colors.white)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Quiet outlined button.
class GhostButton extends StatelessWidget {
  const GhostButton({super.key, required this.label, required this.onTap, this.icon, this.color = K.text});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon ?? Icons.chevron_left_rounded, color: color, size: 20),
      label: Text(label, style: tBody(14, color: color, w: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}

/// Coin balance chip.
class CoinChip extends StatelessWidget {
  const CoinChip({super.key, required this.coins, this.onTap});
  final int coins;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(999),
            border: Border.all(color: K.brass.withValues(alpha: 0.5))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const CoinIcon(size: 18),
          const SizedBox(width: 6),
          AnimatedCount(value: coins, style: tBody(15, w: FontWeight.w900)),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.add_circle_rounded, size: 18, color: K.brass),
          ],
        ]),
      ),
    );
  }
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _CoinPainter());
}

class _CoinPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = s.width / 2;
    final o = Offset(r, r);
    c.drawCircle(o, r, Paint()..color = const Color(0xFF9C7420));
    c.drawCircle(o.translate(0, -r * 0.08), r * 0.92, Paint()..color = K.brass);
    c.drawCircle(o.translate(0, -r * 0.08), r * 0.55,
        Paint()
          ..color = const Color(0xFF9C7420)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.14);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class Stars extends StatelessWidget {
  const Stars({super.key, required this.count, this.size = 22, this.max = 3});
  final int count;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < max; i++)
          Icon(i < count ? Icons.star_rounded : Icons.star_outline_rounded, color: K.brass, size: size),
      ]);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.sub, this.color = K.ink});
  final String text;
  final String? sub;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(text, style: tDisplay(19, color: color)),
          if (sub != null) ...[
            const SizedBox(width: 8),
            Expanded(child: Text(sub!, style: tBody(12, color: color.withValues(alpha: 0.6)))),
          ],
        ]),
      );
}

/// A rotated rubber-stamp mark ("حل شد", "باخت").
class StampMark extends StatelessWidget {
  const StampMark(this.text, {super.key, this.color = K.stamp, this.size = 30});
  final String text;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -0.2,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: size * 0.45, vertical: size * 0.05),
          decoration: BoxDecoration(border: Border.all(color: color, width: 3), borderRadius: BorderRadius.circular(8)),
          child: Text(text, style: tDisplay(size, color: color)),
        ),
      );
}

/// Difficulty shown as magnifying glasses.
class Difficulty extends StatelessWidget {
  const Difficulty(this.level, {super.key, this.color = K.inkSoft});
  final int level;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < 5; i++)
          Icon(Icons.search_rounded, size: 16, color: i < level ? color : color.withValues(alpha: 0.25)),
      ]);
}

/// Subtle film grain for the night background.
class GrainBackground extends StatelessWidget {
  const GrainBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.8), radius: 1.3, colors: [K.night2, K.night]),
        ),
        child: CustomPaint(painter: _GrainPainter(), child: child),
      );
}

class _GrainPainter extends CustomPainter {
  static final _rng = Random(7);
  static final List<Offset> _dots = List.generate(500, (_) => Offset(_rng.nextDouble(), _rng.nextDouble()));

  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0x0DFFFFFF);
    for (final d in _dots) {
      c.drawCircle(Offset(d.dx * s.width, d.dy * s.height), 0.8, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
