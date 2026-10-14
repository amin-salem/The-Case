import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Frames that move (embers drift, neon pulses). Everything else is drawn still.
const Set<String> kAnimatedFrames = {'frame_ember', 'frame_neon'};

/// A player's portrait: `assets/avatars/ID.webp` in a circle. If the file cannot be loaded, a drawn silhouette.
class AvatarFace extends StatelessWidget {
  const AvatarFace(this.id, {super.key, required this.size});
  final String id;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
        child: Image.asset('assets/avatars/$id.webp',
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => Container(
                  width: size,
                  height: size,
                  color: K.night3,
                  child: Icon(Icons.person_rounded, size: size * 0.7, color: K.textSoft),
                )),
      );
}

/// The one widget for a player's avatar anywhere in the app: the portrait inside its frame, [size] wide in total.
/// A null [frame] shows the portrait alone. Frames are drawn in code (sharp at every size); only the ember and
/// neon frames move, and only when [animate] is true and the system does not ask to reduce motion.
class AvatarWithFrame extends StatefulWidget {
  const AvatarWithFrame({super.key, required this.avatar, required this.frame, required this.size, this.animate = false});
  final String avatar;
  final String? frame;
  final double size;
  final bool animate;

  @override
  State<AvatarWithFrame> createState() => _AvatarWithFrameState();
}

class _AvatarWithFrameState extends State<AvatarWithFrame> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  bool get _wantsMotion =>
      widget.animate &&
      kAnimatedFrames.contains(widget.frame) &&
      !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);

  void _sync() {
    if (_wantsMotion) {
      _c ??= AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    } else {
      _c?.dispose();
      _c = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AvatarWithFrame old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Widget _build(double t) {
    final size = widget.size;
    final frame = widget.frame;
    if (frame == null) return AvatarFace(widget.avatar, size: size);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: FramePainter(frame, t, behind: true),
        foregroundPainter: FramePainter(frame, t),
        child: Center(child: AvatarFace(widget.avatar, size: size * 76 / 120)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return _build(0.3);
    return AnimatedBuilder(animation: c, builder: (_, __) => _build(c.value));
  }
}

/// Draws a frame on a square canvas (the design is a 120 x 120 board with the portrait's circle at radius 38).
class FramePainter extends CustomPainter {
  FramePainter(this.frame, this.t, {this.behind = false});
  final String frame;
  final double t; // 0..1 loop for the moving frames
  final bool behind; // only what must lie under the portrait (the light stripes)

  static const _gold = [Color(0xFFFFE9A0), Color(0xFFB8821A)];
  static const _silver = [Color(0xFFF2F4F8), Color(0xFF8A8F99)];
  static const _bronze = [Color(0xFFE0A07A), Color(0xFF7A4A1E)];

  Paint _ring(double w, {Color? color, List<Color>? grad}) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..isAntiAlias = true;
    if (grad != null) {
      p.shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad)
          .createShader(const Rect.fromLTWH(0, 0, 120, 120));
    } else {
      p.color = color ?? K.brass;
    }
    return p;
  }

  static const _c = Offset(60, 60);

  void _circle(Canvas canvas, double r, Paint p) => canvas.drawCircle(_c, r, p);

  /// A circle drawn as dashes: [pattern] is dash, gap, dash, gap ... in board units along the circle.
  void _dashed(Canvas canvas, double r, Paint p, List<double> pattern, {double rotateDeg = 0}) {
    final total = 2 * math.pi * r;
    var pos = rotateDeg / 360 * total;
    final end = pos + total;
    var i = 0;
    while (pos < end) {
      final len = pattern[i % pattern.length];
      if (i.isEven) {
        final stop = math.min(len, end - pos);
        canvas.drawArc(Rect.fromCircle(center: _c, radius: r), pos / r, stop / r, false, p);
      }
      pos += len;
      i++;
    }
  }

  void _diamond(Canvas canvas, Offset c, double hw, double hh) {
    final path = Path()
      ..moveTo(c.dx, c.dy - hh)
      ..lineTo(c.dx + hw, c.dy)
      ..lineTo(c.dx, c.dy + hh)
      ..lineTo(c.dx - hw, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFF3C4));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFB8821A));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 120);
    if (behind) {
      if (frame == 'frame_blinds') _blindsBehind(canvas);
    } else {
      _front(canvas);
    }
    canvas.restore();
  }

  void _blindsBehind(Canvas canvas) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: _c, radius: 60)));
    final p = Paint()..color = const Color(0xFFF2C230).withValues(alpha: 0.38);
    for (int k = 0; k < 9; k++) {
      canvas.drawRect(Rect.fromLTWH(0, 4.0 + 13 * k, 120, 6), p);
    }
    canvas.restore();
  }

  void _front(Canvas canvas) {
    switch (frame) {
      case 'frame_bronze':
        _circle(canvas, 43, _ring(6, grad: _bronze));
        final dot = Paint()..color = const Color(0xFFFFD7B0);
        for (int k = 0; k < 8; k++) {
          final a = k * math.pi / 4;
          canvas.drawCircle(Offset(60 + 43 * math.cos(a), 60 + 43 * math.sin(a)), 1.8, dot);
        }
      case 'frame_silver':
        _circle(canvas, 43, _ring(6, grad: _silver));
        _circle(canvas, 38.5, _ring(1, color: Colors.white.withValues(alpha: 0.5)));
      case 'frame_gold':
        _circle(canvas, 43, _ring(7, grad: _gold));
        _diamond(canvas, const Offset(60, 14), 4, 5);
        _diamond(canvas, const Offset(60, 106), 4, 5);
        _diamond(canvas, const Offset(106, 60), 5, 4);
        _diamond(canvas, const Offset(14, 60), 5, 4);
      case 'frame_ember':
        _circle(canvas, 42, _ring(5, color: const Color(0xFF7A2A1E)));
        _dashed(canvas, 42, _ring(2.5, color: const Color(0xFFD0543F)), const [14, 5]);
        _embers(canvas);
      case 'frame_tape':
        _circle(canvas, 43, _ring(9, color: const Color(0xFFF2C230)));
        _dashed(canvas, 43, _ring(9, color: K.night), const [9, 9], rotateDeg: 10);
      case 'frame_loupe':
        _circle(canvas, 43, _ring(6, grad: _gold));
        canvas.drawArc(
            Rect.fromCircle(center: _c, radius: 38.5),
            -2.61,
            0.73,
            false,
            _ring(3, color: Colors.white.withValues(alpha: 0.7))..strokeCap = StrokeCap.round);
        canvas.drawLine(const Offset(92, 92), const Offset(112, 112),
            _ring(9, color: const Color(0xFF5A3B1E))..strokeCap = StrokeCap.round);
        canvas.drawLine(const Offset(88, 88), const Offset(96, 96), _ring(10, color: K.brass)..strokeCap = StrokeCap.round);
      case 'frame_fingerprint':
        final c = _ring(1.6, color: const Color(0xFFB9B5AA));
        _dashed(canvas, 41, c, const [60, 12, 30, 8]);
        _dashed(canvas, 44, c, const [40, 10, 70, 6], rotateDeg: 50);
        _dashed(canvas, 47, c, const [80, 8, 20, 14], rotateDeg: 120);
        _dashed(canvas, 50, c, const [30, 9, 55, 10], rotateDeg: 200);
      case 'frame_blinds':
        _circle(canvas, 43, _ring(7, color: K.night3));
        _circle(canvas, 43, _ring(1.8, color: const Color(0xFFF2C230)));
      case 'frame_cuffs':
        _cuffs(canvas);
      case 'frame_stamp':
        _stamp(canvas);
      case 'frame_neon':
        _neon(canvas);
      case 'frame_royal':
        _circle(canvas, 43, _ring(7, grad: _gold));
        final crown = Path()
          ..moveTo(40, 20)
          ..relativeLineTo(-3, -14)
          ..relativeLineTo(10, 8)
          ..relativeLineTo(13, -12)
          ..relativeLineTo(13, 12)
          ..relativeLineTo(10, -8)
          ..relativeLineTo(-3, 14)
          ..close();
        canvas.drawPath(crown, Paint()..color = K.brass);
        canvas.drawPath(
            crown,
            _ring(1.5, color: const Color(0xFFFFF3C4))
              ..strokeJoin = StrokeJoin.round);
        final violet = Paint()..color = const Color(0xFF9B6BFF);
        final red = Paint()..color = K.stamp;
        canvas.drawCircle(const Offset(60, 17), 3, violet);
        canvas.drawCircle(const Offset(60, 103), 3, violet);
        canvas.drawCircle(const Offset(17, 60), 3, red);
        canvas.drawCircle(const Offset(103, 60), 3, red);
      default: // frame_brass and anything unknown
        _circle(canvas, 42, _ring(4, color: K.brass));
    }
  }

  /// Sparks that rise from the ring and fade, each on its own loop.
  void _embers(Canvas canvas) {
    final rnd = math.Random(7);
    for (int k = 0; k < 14; k++) {
      final base = rnd.nextDouble() * 2 * math.pi;
      final off = rnd.nextDouble();
      final phase = (t + off) % 1.0;
      final x = 60 + 42 * math.cos(base) + math.sin(phase * 6 + k) * 3;
      final y = 60 + 42 * math.sin(base) - phase * 22;
      final r = (1.2 + rnd.nextDouble() * 1.4) * (1 - phase * 0.5);
      final color = [const Color(0xFFFFB347), const Color(0xFFFFD27A), const Color(0xFFFF7A3C)][k % 3];
      canvas.drawCircle(Offset(x, y), r, Paint()..color = color.withValues(alpha: (1 - phase).clamp(0.0, 1.0)));
    }
  }

  void _cuffs(Canvas canvas) {
    const n = 14;
    final link = _ring(2.4, color: const Color(0xFFC0C4CC));
    for (int k = 0; k < n; k++) {
      final a = k * 2 * math.pi / n;
      canvas.save();
      canvas.translate(60 + 44 * math.cos(a), 60 + 44 * math.sin(a));
      canvas.rotate(a + math.pi / 2);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 12, height: 6), link);
      canvas.restore();
    }
    canvas.drawCircle(const Offset(60, 14), 10, _ring(5, color: const Color(0xFF8A8F99)));
    canvas.drawCircle(const Offset(60, 14), 10, _ring(1.5, color: const Color(0xFFE6E9EE)));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(55, 22, 10, 6), const Radius.circular(2)),
        Paint()..color = const Color(0xFF8A8F99));
  }

  void _stamp(Canvas canvas) {
    _circle(canvas, 43, _ring(4, color: K.stamp));
    _dashed(canvas, 48, _ring(1.5, color: K.stamp), const [3, 3]);
    canvas.save();
    canvas.translate(60, 106);
    canvas.rotate(-12 * math.pi / 180);
    final tag = RRect.fromRectAndRadius(const Rect.fromLTWH(-26, -10, 52, 20), const Radius.circular(4));
    canvas.drawRRect(tag, Paint()..color = K.night);
    canvas.drawRRect(tag, _ring(2.5, color: K.stamp));
    final tp = TextPainter(
      text: TextSpan(text: 'حل شد', style: TextStyle(fontFamily: kFont, fontSize: 13, fontWeight: FontWeight.w900, color: K.stamp)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _neon(Canvas canvas) {
    final pulse = 0.75 + 0.25 * math.sin(t * 2 * math.pi);
    const glow = MaskFilter.blur(BlurStyle.normal, 3);
    _circle(canvas, 42, _ring(6, color: const Color(0xFF2EE6D6).withValues(alpha: pulse))..maskFilter = glow);
    _circle(canvas, 42, _ring(2.5, color: const Color(0xFF7FFFF2)));
    _dashed(canvas, 47, _ring(2, color: const Color(0xFFFF3DCB).withValues(alpha: pulse))..maskFilter = glow, const [40, 14]);
    _dashed(canvas, 47, _ring(1.2, color: const Color(0xFFFF8BE6)), const [40, 14]);
  }

  @override
  bool shouldRepaint(covariant FramePainter old) => old.frame != frame || old.t != t || old.behind != behind;
}
