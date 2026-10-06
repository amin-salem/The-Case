import 'dart:math';

import 'package:flutter/material.dart';

import 'scene_extra.dart';

/// An animated night illustration for each kind of crime scene
/// (rain, flickering lamps, passing train lights, fire embers...).
/// Twenty scenes; every case file names one of them in its "scene" field.
class AnimatedScene extends StatefulWidget {
  const AnimatedScene({super.key, required this.scene, this.height = 200, this.dim = 0, this.animated = true});
  final String scene;
  final double height;
  final double dim; // 0..1 darken (for text on top)
  final bool animated; // false: a still frame (cheap, for thumbnails in long lists)

  @override
  State<AnimatedScene> createState() => _AnimatedSceneState();
}

class _AnimatedSceneState extends State<AnimatedScene> with SingleTickerProviderStateMixin {
  // runs for an hour before wrapping, so no animation ever jumps back mid-scene
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(hours: 1));

  @override
  void initState() {
    super.initState();
    if (widget.animated) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kSceneArt.contains(widget.scene)) return _painted();
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => RepaintBoundary(
            child: CustomPaint(painter: ScenePainter(widget.scene, widget.animated ? _c.value * 3600 : 3.0, widget.dim))),
      ),
    );
  }

  /// A painted background (assets/scenes) with a slow camera drift and a light weather layer on top.
  Widget _painted() {
    final image = Image.asset('assets/scenes/${widget.scene}.webp',
        fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _c,
          child: image,
          builder: (_, child) {
            final t = widget.animated ? _c.value * 3600 : 0.0;
            final drift = sin(t / 9);
            return Stack(fit: StackFit.expand, children: [
              Transform.scale(
                scale: 1.08 + 0.03 * sin(t / 13),
                child: Transform.translate(offset: Offset(drift * 6, cos(t / 11) * 3), child: child),
              ),
              if (widget.animated) RepaintBoundary(child: CustomPaint(painter: _WeatherPainter(widget.scene, t))),
              if (widget.dim > 0) ColoredBox(color: Colors.black.withValues(alpha: widget.dim.clamp(0.0, 1.0) * 0.85)),
            ]);
          },
        ),
      ),
    );
  }
}

/// Scenes that have a painted background in assets/scenes.
const Set<String> kSceneArt = {
  'airport', 'bazaar_night', 'desert', 'harbor', 'hospital', 'hotel', 'kitchen', 'lab', 'library', 'museum',
  'office', 'school', 'snow_lodge', 'subway', 'theater', 'tower', 'train', 'villa_rain', 'warehouse', 'wedding',
};

/// Rain, snow or floating dust over a painted scene.
class _WeatherPainter extends CustomPainter {
  _WeatherPainter(this.scene, this.t);
  final String scene;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    if (scene == 'villa_rain' || scene == 'harbor') {
      final p = Paint()
        ..color = const Color(0x44CFD8E6)
        ..strokeWidth = 1.1;
      for (int i = 0; i < 70; i++) {
        final x0 = rnd.nextDouble() * size.width, sp = 380 + rnd.nextDouble() * 220, ph = rnd.nextDouble();
        final y = ((t * sp / size.height + ph) % 1) * (size.height + 30) - 15;
        final x = (x0 - y * 0.18) % size.width;
        canvas.drawLine(Offset(x, y), Offset(x - 3, y + 12), p);
      }
    } else if (scene == 'snow_lodge') {
      final p = Paint()..color = const Color(0xAAFFFFFF);
      for (int i = 0; i < 55; i++) {
        final x0 = rnd.nextDouble() * size.width, sp = 18 + rnd.nextDouble() * 26, ph = rnd.nextDouble();
        final r = 0.8 + rnd.nextDouble() * 1.6;
        final y = ((t * sp / size.height + ph) % 1) * (size.height + 10) - 5;
        canvas.drawCircle(Offset(x0 + sin(t * 0.8 + i) * 8, y), r, p);
      }
    } else {
      // dust in the light
      for (int i = 0; i < 26; i++) {
        final x0 = rnd.nextDouble() * size.width, y0 = rnd.nextDouble() * size.height, ph = rnd.nextDouble() * 6;
        final a = (0.25 + 0.25 * sin(t * 0.7 + ph)).clamp(0.0, 1.0);
        canvas.drawCircle(Offset(x0 + sin(t * 0.15 + ph) * 14, y0 + cos(t * 0.12 + ph) * 10), 1.1,
            Paint()..color = const Color(0xFFFFE2A8).withValues(alpha: a * 0.6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter old) => old.t != t;
}

class ScenePainter extends CustomPainter {
  ScenePainter(this.scene, this.t, this.dim);
  final String scene;
  final double t; // seconds
  final double dim;

  static final _rng = Random(3);
  static final List<Offset> _stars = List.generate(40, (_) => Offset(_rng.nextDouble(), _rng.nextDouble() * 0.5));
  static final List<double> _rain = List.generate(90, (_) => _rng.nextDouble());

  @override
  void paint(Canvas c, Size s) {
    switch (scene) {
      case 'bazaar_night':
        _bazaar(c, s);
      case 'office':
        _office(c, s);
      case 'train':
        _train(c, s);
      case 'museum':
        _museum(c, s);
      case 'villa_rain':
        _villa(c, s);
      case 'warehouse':
        _warehouse(c, s);
      case 'harbor':
        ExtraScenes.harbor(c, s, t);
      case 'hospital':
        ExtraScenes.hospital(c, s, t);
      case 'library':
        ExtraScenes.library(c, s, t);
      case 'theater':
        ExtraScenes.theater(c, s, t);
      case 'hotel':
        ExtraScenes.hotel(c, s, t);
      case 'kitchen':
        ExtraScenes.kitchen(c, s, t);
      case 'snow_lodge':
        ExtraScenes.snowLodge(c, s, t);
      case 'desert':
        ExtraScenes.desert(c, s, t);
      case 'subway':
        ExtraScenes.subway(c, s, t);
      case 'lab':
        ExtraScenes.lab(c, s, t);
      case 'wedding':
        ExtraScenes.wedding(c, s, t);
      case 'school':
        ExtraScenes.school(c, s, t);
      case 'airport':
        ExtraScenes.airport(c, s, t);
      case 'tower':
        ExtraScenes.tower(c, s, t);
      default:
        _city(c, s);
    }
    _atmosphere(c, s);
    // vignette + optional dim
    final r = Offset.zero & s;
    c.drawRect(
        r,
        Paint()
          ..shader = RadialGradient(radius: 0.9, colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.55 + dim * 0.3),
          ]).createShader(r));
    if (dim > 0) c.drawRect(r, Paint()..color = Colors.black.withValues(alpha: dim * 0.4));
  }

  /// Drifting fog, floating dust and a faint film flicker on top of every scene.
  void _atmosphere(Canvas c, Size s) {
    for (int i = 0; i < 3; i++) {
      final cx = ((t * 5 * (1 + i * 0.6) + i * s.width * 0.45) % (s.width * 1.7)) - s.width * 0.35;
      final rect = Rect.fromCenter(center: Offset(cx, s.height * (0.58 + i * 0.13)), width: s.width * 0.95, height: s.height * 0.3);
      c.drawOval(rect, Paint()..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.055), Colors.transparent]).createShader(rect));
    }
    for (int i = 0; i < 16; i++) {
      final p = _stars[i % _stars.length];
      final x = (p.dx * s.width + sin(t * 0.6 + i) * 14 + t * 2) % s.width;
      final y = s.height - ((p.dy * 2 + t * (0.01 + (i % 4) * 0.004)) % 1.0) * s.height;
      c.drawCircle(Offset(x, y), 1.1, Paint()..color = Colors.white.withValues(alpha: 0.12 + 0.12 * sin(t * 1.7 + i)));
    }
    final fl = 0.015 + 0.02 * max(0.0, sin(t * 31) * sin(t * 7.3));
    c.drawRect(Offset.zero & s, Paint()..color = Colors.black.withValues(alpha: fl));
  }

  void _sky(Canvas c, Size s, List<Color> colors) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r));
  }

  void _starsLayer(Canvas c, Size s) {
    for (int i = 0; i < _stars.length; i++) {
      final tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 2 + i));
      c.drawCircle(Offset(_stars[i].dx * s.width, _stars[i].dy * s.height), 1.1,
          Paint()..color = Colors.white.withValues(alpha: 0.5 * tw));
    }
  }

  // ---------------------------------------------------------------- bazaar
  void _bazaar(Canvas c, Size s) {
    _sky(c, s, const [Color(0xFF1A1420), Color(0xFF2A1C1A)]);
    final w = s.width, h = s.height;
    // brick vault arches
    final arch = Paint()..color = const Color(0xFF3A2A22);
    for (int i = -1; i < 5; i++) {
      final x = i * w / 4;
      final p = Path()
        ..moveTo(x, h)
        ..lineTo(x, h * 0.45)
        ..quadraticBezierTo(x + w / 8, h * 0.05, x + w / 4, h * 0.45)
        ..lineTo(x + w / 4, h)
        ..lineTo(x + w / 4 - 10, h)
        ..lineTo(x + w / 4 - 10, h * 0.47)
        ..quadraticBezierTo(x + w / 8, h * 0.13, x + 10, h * 0.47)
        ..lineTo(x + 10, h)
        ..close();
      c.drawPath(p, arch);
    }
    // closed shutters
    for (int i = 0; i < 4; i++) {
      final r = Rect.fromLTWH(i * w / 4 + 16, h * 0.55, w / 4 - 32, h * 0.45);
      c.drawRect(r, Paint()..color = const Color(0xFF4A4D52));
      for (double y = r.top + 6; y < r.bottom; y += 7) {
        c.drawLine(Offset(r.left, y), Offset(r.right, y), Paint()..color = const Color(0xFF34373B)..strokeWidth = 2);
      }
    }
    // the open shutter of the robbed shop (gold glow)
    final robbed = Rect.fromLTWH(w / 4 + 16, h * 0.55, w / 4 - 32, h * 0.45);
    c.drawRect(robbed, Paint()..color = const Color(0xFF2A1E10));
    c.drawRect(robbed, Paint()..shader = const RadialGradient(colors: [Color(0x55FFC870), Colors.transparent]).createShader(robbed));
    // hanging lamps, one flickering
    for (int i = 0; i < 4; i++) {
      final x = i * w / 4 + w / 8;
      final flick = i == 2 ? (sin(t * 23) > 0.6 ? 0.2 : 1.0) : 1.0;
      c.drawLine(Offset(x, h * 0.18), Offset(x, h * 0.3), Paint()..color = const Color(0xFF111111)..strokeWidth = 1.5);
      c.drawCircle(Offset(x, h * 0.32), 30, Paint()..color = const Color(0xFFFFB347).withValues(alpha: 0.18 * flick));
      c.drawCircle(Offset(x, h * 0.32), 5, Paint()..color = Color.lerp(const Color(0xFF553311), const Color(0xFFFFD27A), flick)!);
    }
  }

  // ---------------------------------------------------------------- office
  void _office(Canvas c, Size s) {
    _sky(c, s, const [Color(0xFF0D1626), Color(0xFF1C2638)]);
    final w = s.width, h = s.height;
    _starsLayer(c, s);
    // skyline with blinking windows
    final rng = Random(11);
    for (double x = 0; x < w; x += 34) {
      final bh = h * (0.35 + rng.nextDouble() * 0.45);
      final r = Rect.fromLTWH(x, h - bh, 30, bh);
      c.drawRect(r, Paint()..color = const Color(0xFF151D2B));
      for (double wy = r.top + 8; wy < r.bottom - 6; wy += 12) {
        for (double wx = r.left + 5; wx < r.right - 5; wx += 9) {
          final on = (sin(wx * 3.1 + wy * 1.7 + (t * 0.6).floor()) > 0.55);
          if (on) c.drawRect(Rect.fromLTWH(wx, wy, 4, 5), Paint()..color = const Color(0xAAFFE08A));
        }
      }
    }
    // window frame of the office
    final frame = Paint()
      ..color = const Color(0xFF0A0E15)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;
    c.drawRect(Rect.fromLTWH(5, 5, w - 10, h - 10), frame);
    c.drawLine(Offset(w / 2, 0), Offset(w / 2, h), frame);
    // safe silhouette with an open door
    final safe = Rect.fromLTWH(w * 0.68, h * 0.55, w * 0.2, h * 0.42);
    c.drawRRect(RRect.fromRectAndRadius(safe, const Radius.circular(6)), Paint()..color = const Color(0xFF2B3240));
    c.drawRect(Rect.fromLTWH(safe.left + 8, safe.top + 8, safe.width - 16, safe.height - 16), Paint()..color = const Color(0xFF0B0E13));
  }

  // ---------------------------------------------------------------- train
  void _train(Canvas c, Size s) {
    _sky(c, s, const [Color(0xFF0B1020), Color(0xFF141B2E)]);
    final w = s.width, h = s.height;
    // passing lights outside the window
    for (int i = 0; i < 6; i++) {
      final x = w - ((t * 140 + i * w / 5) % (w + 120));
      c.drawLine(Offset(x, h * 0.42), Offset(x + 60, h * 0.42),
          Paint()..color = const Color(0x88FFD27A)..strokeWidth = 3..strokeCap = StrokeCap.round);
    }
    // hills
    final hill = Path()..moveTo(0, h * 0.62);
    for (double x = 0; x <= w; x += 20) {
      hill.lineTo(x, h * 0.6 + sin((x + t * 60) / 70) * 10);
    }
    hill
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    c.drawPath(hill, Paint()..color = const Color(0xFF0E1422));
    // compartment window frame
    final wall = Paint()..color = const Color(0xFF3B2A20);
    c.drawRect(Rect.fromLTWH(0, 0, w, h * 0.16), wall);
    c.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), wall);
    c.drawRect(Rect.fromLTWH(0, 0, w * 0.08, h), wall);
    c.drawRect(Rect.fromLTWH(w * 0.92, 0, w * 0.08, h), wall);
    // tea glass on the table, with steam that has stopped
    final g = Offset(w * 0.5, h * 0.78);
    final glass = Path()
      ..moveTo(g.dx - 9, g.dy - 26)
      ..quadraticBezierTo(g.dx - 4, g.dy - 12, g.dx - 7, g.dy)
      ..lineTo(g.dx + 7, g.dy)
      ..quadraticBezierTo(g.dx + 4, g.dy - 12, g.dx + 9, g.dy - 26)
      ..close();
    c.drawPath(glass, Paint()..color = const Color(0xCCB0451C));
    c.drawRect(Rect.fromLTWH(w * 0.08, h * 0.76, w * 0.84, 6), Paint()..color = const Color(0xFF6D4C35));
  }

  // ---------------------------------------------------------------- museum
  void _museum(Canvas c, Size s) {
    _sky(c, s, const [Color(0xFF1C1A22), Color(0xFF2B2630)]);
    final w = s.width, h = s.height;
    c.drawRect(Rect.fromLTWH(0, h * 0.82, w, h * 0.18), Paint()..color = const Color(0xFF3A2E26));
    // frames
    final frames = [Rect.fromLTWH(w * 0.08, h * 0.22, w * 0.22, h * 0.36), Rect.fromLTWH(w * 0.39, h * 0.16, w * 0.24, h * 0.46),
        Rect.fromLTWH(w * 0.72, h * 0.24, w * 0.2, h * 0.32)];
    for (int i = 0; i < frames.length; i++) {
      final f = frames[i];
      c.drawRect(f.inflate(6), Paint()..color = const Color(0xFFB08A3E));
      c.drawRect(f, Paint()..color = i == 1 ? const Color(0xFF5B6B5E) : const Color(0xFF4A3B33));
      if (i == 1) {
        // the "painting": an alley in Kashan, quickly sketched
        c.drawRect(Rect.fromLTWH(f.left, f.top + f.height * 0.55, f.width, f.height * 0.45), Paint()..color = const Color(0xFF8C7354));
        c.drawRect(Rect.fromLTWH(f.left + f.width * 0.42, f.top + f.height * 0.3, f.width * 0.16, f.height * 0.25),
            Paint()..color = const Color(0xFF2E2620));
      }
    }
    // a sweeping UV-light beam
    final bx = w * (0.5 + 0.45 * sin(t * 0.7));
    final beam = Path()
      ..moveTo(bx - 8, 0)
      ..lineTo(bx + 8, 0)
      ..lineTo(bx + 60, h)
      ..lineTo(bx - 60, h)
      ..close();
    c.drawPath(beam, Paint()..color = const Color(0x267B5CFF));
  }

  // ---------------------------------------------------------------- villa
  void _villa(Canvas c, Size s) {
    final flash = (t % 7.0) < 0.12 || ((t % 7.0) > 0.25 && (t % 7.0) < 0.32);
    _sky(c, s, flash ? const [Color(0xFF8C9AB8), Color(0xFF3A4660)] : const [Color(0xFF0E1420), Color(0xFF1A2230)]);
    final w = s.width, h = s.height;
    // trees
    for (int i = 0; i < 5; i++) {
      final x = i * w / 4.5;
      final sway = sin(t * 1.5 + i) * 4;
      c.drawPath(
          Path()
            ..moveTo(x - 24, h * 0.8)
            ..lineTo(x + sway, h * 0.25)
            ..lineTo(x + 24, h * 0.8)
            ..close(),
          Paint()..color = const Color(0xFF0B1410));
    }
    // villa with one lit window (the study)
    final house = Path()
      ..moveTo(w * 0.28, h * 0.48)
      ..lineTo(w * 0.5, h * 0.26)
      ..lineTo(w * 0.72, h * 0.48)
      ..lineTo(w * 0.72, h * 0.86)
      ..lineTo(w * 0.28, h * 0.86)
      ..close();
    c.drawPath(house, Paint()..color = const Color(0xFF151B24));
    final lit = (sin(t * 3) > -0.9) ? const Color(0xFFFFD27A) : const Color(0xFF5A4A2A);
    c.drawRect(Rect.fromLTWH(w * 0.36, h * 0.56, w * 0.08, h * 0.12), Paint()..color = lit);
    c.drawRect(Rect.fromLTWH(w * 0.56, h * 0.56, w * 0.08, h * 0.12), Paint()..color = const Color(0xFF232B38));
    c.drawRect(Rect.fromLTWH(0, h * 0.86, w, h * 0.14), Paint()..color = const Color(0xFF3A1E18)); // red clay garden
    // rain
    final rain = Paint()
      ..color = const Color(0x66A8C4E0)
      ..strokeWidth = 1.2;
    for (int i = 0; i < _rain.length; i++) {
      final x = (_rain[i] * w + t * 40) % w;
      final y = ((_rain[(i * 7) % _rain.length] * h) + t * 420) % h;
      c.drawLine(Offset(x, y), Offset(x - 4, y + 14), rain);
    }
  }

  // ---------------------------------------------------------------- warehouse
  void _warehouse(Canvas c, Size s) {
    _sky(c, s, const [Color(0xFF140E14), Color(0xFF3A1A10)]);
    final w = s.width, h = s.height;
    // glow
    final glow = Rect.fromLTWH(0, h * 0.3, w, h * 0.7);
    c.drawRect(glow, Paint()..shader = RadialGradient(center: const Alignment(0, 0.6), radius: 0.8,
        colors: [Color.lerp(const Color(0xAAFF6A1A), const Color(0xAAFF9A2A), 0.5 + 0.5 * sin(t * 6))!, Colors.transparent]).createShader(glow));
    // warehouse silhouette
    final wh = Path()
      ..moveTo(w * 0.12, h)
      ..lineTo(w * 0.12, h * 0.5)
      ..lineTo(w * 0.5, h * 0.36)
      ..lineTo(w * 0.88, h * 0.5)
      ..lineTo(w * 0.88, h)
      ..close();
    c.drawPath(wh, Paint()..color = const Color(0xFF120C0C));
    // flames
    for (int i = 0; i < 7; i++) {
      final x = w * (0.2 + i * 0.1);
      final fh = h * (0.12 + 0.06 * sin(t * 8 + i * 1.7));
      final f = Path()
        ..moveTo(x - 14, h * 0.52)
        ..quadraticBezierTo(x, h * 0.52 - fh * 2, x + 14, h * 0.52)
        ..close();
      c.drawPath(f, Paint()..color = const Color(0xDDFF7A1A));
    }
    // embers
    for (int i = 0; i < 25; i++) {
      final p = ((t * 0.3 + i / 25) % 1.0);
      final x = w * (0.2 + 0.6 * _rain[i]) + sin(t * 2 + i) * 10;
      final y = h * 0.5 - p * h * 0.5;
      c.drawCircle(Offset(x, y), 1.6, Paint()..color = const Color(0xFFFFB347).withValues(alpha: 1 - p));
    }
  }

  // ---------------------------------------------------------------- default
  void _city(Canvas c, Size s) {
    _sky(c, s, const [Color(0xFF0D1220), Color(0xFF1B2232)]);
    _starsLayer(c, s);
    final w = s.width, h = s.height;
    final rng = Random(5);
    for (double x = 0; x < w; x += 40) {
      final bh = h * (0.3 + rng.nextDouble() * 0.4);
      c.drawRect(Rect.fromLTWH(x, h - bh, 36, bh), Paint()..color = const Color(0xFF121826));
    }
    c.drawCircle(Offset(w * 0.8, h * 0.2), 18, Paint()..color = const Color(0xFFEDE6D8));
  }

  @override
  bool shouldRepaint(covariant ScenePainter o) => o.t != t || o.scene != scene || o.dim != dim;
}
