import 'dart:math';

import 'package:flutter/material.dart';

import '../services/sound.dart';
import '../theme.dart';

/// Screens arrive like a case file sliding across a desk: a short fade, a rise and a tiny settle.
class NoirTransitions extends PageTransitionsBuilder {
  const NoirTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final under = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: Tween(begin: 0.0, end: 1.0).animate(curved),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.045), end: Offset.zero).animate(curved),
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(curved),
          // the screen underneath dims a little while another sits on top
          child: Stack(fit: StackFit.passthrough, children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(opacity: Tween(begin: 0.0, end: 0.35).animate(under), child: const ColoredBox(color: Colors.black)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A number that counts up to its value (coins, rewards).
class AnimatedCount extends StatelessWidget {
  const AnimatedCount({super.key, required this.value, required this.style, this.prefix = '', this.suffix = ''});
  final int value;
  final TextStyle style;
  final String prefix, suffix;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Text('$prefix${fa(v.round())}$suffix', style: style),
      );
}

/// Speaker icon that mutes / unmutes all game sound.
class SoundButton extends StatelessWidget {
  const SoundButton({super.key, this.color = K.text});
  final Color color;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Sfx.i,
        builder: (_, __) => IconButton(
          tooltip: Sfx.i.muted ? 'روشن کردن صدا' : 'بی‌صدا',
          onPressed: Sfx.i.toggle,
          splashRadius: 22,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(Sfx.i.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, key: ValueKey(Sfx.i.muted), color: color),
          ),
        ),
      );
}

/// A red map pin that drops onto a piece of evidence when it is marked.
class PinBadge extends StatelessWidget {
  const PinBadge({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: on ? 1 : 0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.elasticOut,
        child: Transform.rotate(angle: 0.5, child: const Icon(Icons.push_pin_rounded, color: K.stamp, size: 26)),
      );
}

/// Gold confetti and coins falling over the result screen.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.count = 70});
  final int count;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..forward();
  late final List<_Bit> _bits;

  @override
  void initState() {
    super.initState();
    final r = Random(3);
    _bits = List.generate(
        widget.count,
        (_) => _Bit(r.nextDouble(), r.nextDouble() * 0.5, 0.5 + r.nextDouble(), r.nextDouble() * 6.28, r.nextInt(4), 4 + r.nextDouble() * 5));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: _ConfettiPainter(_bits, _c.value), size: Size.infinite)),
      );
}

class _Bit {
  _Bit(this.x, this.delay, this.speed, this.spin, this.kind, this.size);
  final double x, delay, speed, spin, size;
  final int kind;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.bits, this.t);
  final List<_Bit> bits;
  final double t;
  static const colors = [K.brass, K.stamp, Color(0xFFFFE9A3), K.ok];

  @override
  void paint(Canvas c, Size s) {
    for (final b in bits) {
      final p = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final y = -20 + p * (s.height + 40) * b.speed;
      final x = b.x * s.width + sin(p * 8 + b.spin) * 22;
      final paint = Paint()..color = colors[b.kind].withValues(alpha: (1 - p * p).clamp(0.0, 1.0));
      c.save();
      c.translate(x, y);
      c.rotate(b.spin + p * 9);
      if (b.kind == 0) {
        c.drawCircle(Offset.zero, b.size * 0.8, paint); // coin
        c.drawCircle(Offset.zero, b.size * 0.45, Paint()..color = const Color(0xFF9C7420).withValues(alpha: paint.color.a)..style = PaintingStyle.stroke);
      } else {
        c.drawRect(Rect.fromCenter(center: Offset.zero, width: b.size, height: b.size * 0.5), paint);
      }
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}

/// A slow spotlight sweep behind a title, like a torch searching a dark room.
class Torchlight extends StatefulWidget {
  const Torchlight({super.key, required this.child});
  final Widget child;

  @override
  State<Torchlight> createState() => _TorchlightState();
}

class _TorchlightState extends State<Torchlight> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.9 + 1.8 * Curves.easeInOut.transform(_c.value), -0.3),
              radius: 0.9,
              colors: [Colors.white.withValues(alpha: 0.10), Colors.transparent],
            ),
          ),
          child: child,
        ),
        child: widget.child,
      );
}
