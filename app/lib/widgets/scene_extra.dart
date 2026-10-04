import 'dart:math';

import 'package:flutter/material.dart';

/// More crime-scene illustrations. Each draws one animated night scene;
/// `t` is seconds (loops every 12 s, so every animation here repeats with a period that divides 12).
class ExtraScenes {
  static final _r = Random(21);
  static final List<Offset> _pts = List.generate(120, (_) => Offset(_r.nextDouble(), _r.nextDouble()));
  static const _tau = pi * 2;

  static void sky(Canvas c, Size s, List<Color> colors, [double to = 1.0]) {
    final r = Rect.fromLTWH(0, 0, s.width, s.height * to);
    c.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r));
  }

  static void glow(Canvas c, Offset o, double r, Color color, [double a = 1]) {
    final rect = Rect.fromCircle(center: o, radius: r);
    c.drawCircle(o, r, Paint()..shader = RadialGradient(colors: [color.withValues(alpha: color.a * a), Colors.transparent]).createShader(rect));
  }

  static double flick(double t, double rate, [double seed = 0]) => (sin(t * rate + seed) * sin(t * rate * 2.3 + seed * 3)) > 0.82 ? 0.25 : 1.0;

  // -------------------------------------------------------------- harbor
  static void harbor(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF07131C), Color(0xFF12303A)], 0.62);
    final moon = Offset(w * 0.78, h * 0.18);
    glow(c, moon, 60, const Color(0x66BFE4F0));
    c.drawCircle(moon, 16, Paint()..color = const Color(0xFFE6F2F4));
    // sea
    final sea = Rect.fromLTWH(0, h * 0.6, w, h * 0.4);
    c.drawRect(sea, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F2A33), Color(0xFF050D12)]).createShader(sea));
    for (int i = 0; i < 9; i++) {
      final y = h * 0.62 + i * h * 0.04;
      final p = Path()..moveTo(0, y);
      for (double x = 0; x <= w; x += 12) {
        p.lineTo(x, y + sin(x / 28 + t * _tau / 6 * (1 + i % 2) + i) * (1.5 + i * 0.4));
      }
      c.drawPath(p, Paint()..color = Colors.white.withValues(alpha: 0.05 + 0.01 * i)..style = PaintingStyle.stroke..strokeWidth = 1.2);
    }
    // moon path on the water
    for (int i = 0; i < 12; i++) {
      final y = h * 0.62 + i * h * 0.03;
      final wd = 14.0 + i * 5 + sin(t * _tau / 4 + i) * 6;
      c.drawRect(Rect.fromCenter(center: Offset(moon.dx + sin(t * _tau / 3 + i) * 4, y), width: wd, height: 1.6),
          Paint()..color = const Color(0xFFBFE4F0).withValues(alpha: 0.22));
    }
    // lighthouse beam
    final tower = Offset(w * 0.12, h * 0.56);
    c.drawRect(Rect.fromCenter(center: Offset(tower.dx, tower.dy - h * 0.12), width: 12, height: h * 0.24), Paint()..color = const Color(0xFF0B1118));
    final ang = t * _tau / 6;
    final beam = Path()
      ..moveTo(tower.dx, tower.dy - h * 0.24)
      ..lineTo(tower.dx + cos(ang) * w * 1.3 - sin(ang) * 40, tower.dy - h * 0.24 + sin(ang) * 20 - 40)
      ..lineTo(tower.dx + cos(ang) * w * 1.3 + sin(ang) * 40, tower.dy - h * 0.24 + sin(ang) * 20 + 40)
      ..close();
    c.drawPath(beam, Paint()..color = const Color(0x1AFFF2B0));
    // containers
    final cols = [const Color(0xFF7A2E2A), const Color(0xFF2E5A7A), const Color(0xFF6A5A2A)];
    for (int i = 0; i < 5; i++) {
      final r = Rect.fromLTWH(w * 0.5 + (i % 3) * 38, h * 0.5 - (i ~/ 3) * 22, 36, 20);
      c.drawRect(r, Paint()..color = cols[i % 3]);
      c.drawRect(r, Paint()..color = Colors.black26..style = PaintingStyle.stroke);
    }
    glow(c, Offset(w * 0.5 + 56, h * 0.47), 22, const Color(0x66FFC060), 0.6 + 0.4 * sin(t * 3));
    // pier + boat
    c.drawRect(Rect.fromLTWH(0, h * 0.58, w * 0.7, 6), Paint()..color = const Color(0xFF1A130C));
    for (double x = 10; x < w * 0.7; x += 34) {
      c.drawRect(Rect.fromLTWH(x, h * 0.58, 4, h * 0.1), Paint()..color = const Color(0xFF120C08));
    }
    final bob = sin(t * _tau / 4) * 3;
    final boat = Path()
      ..moveTo(w * 0.62, h * 0.7 + bob)
      ..lineTo(w * 0.9, h * 0.7 + bob)
      ..lineTo(w * 0.85, h * 0.76 + bob)
      ..lineTo(w * 0.66, h * 0.76 + bob)
      ..close();
    c.drawPath(boat, Paint()..color = const Color(0xFF0A0F14));
    c.drawLine(Offset(w * 0.76, h * 0.7 + bob), Offset(w * 0.76, h * 0.55 + bob), Paint()..color = const Color(0xFF0A0F14)..strokeWidth = 3);
    // buoy light
    final on = (t * 1.0) % 2 < 0.4;
    glow(c, Offset(w * 0.34, h * 0.7 + sin(t * 1.3) * 2), on ? 16 : 6, const Color(0xCCFF3B30));
  }

  // -------------------------------------------------------------- hospital
  static void hospital(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF0C1A1E), Color(0xFF16282C)]);
    final vp = Offset(w * 0.5, h * 0.46);
    // floor / ceiling / walls in perspective
    final floor = Path()..moveTo(0, h)..lineTo(w, h)..lineTo(vp.dx + 26, vp.dy + 14)..lineTo(vp.dx - 26, vp.dy + 14)..close();
    c.drawPath(floor, Paint()..color = const Color(0xFF22403F));
    final ceil = Path()..moveTo(0, 0)..lineTo(w, 0)..lineTo(vp.dx + 26, vp.dy - 14)..lineTo(vp.dx - 26, vp.dy - 14)..close();
    c.drawPath(ceil, Paint()..color = const Color(0xFF0E1D20));
    for (int i = 0; i < 7; i++) {
      final k = pow(0.62, i).toDouble();
      final y = vp.dy - 14 - (vp.dy - 14) * k;
      final wd = 26 + (w / 2 - 26) * k;
      final lit = i == 3 ? flick(t, 9, 2) : 1.0;
      c.drawRect(Rect.fromCenter(center: Offset(vp.dx, y + 4), width: wd * 0.7, height: 3 + 6 * k),
          Paint()..color = const Color(0xFFDFF7F2).withValues(alpha: 0.85 * lit));
      glow(c, Offset(vp.dx, y + 8), wd * 0.8, const Color(0x3319D6B8), lit);
      c.drawLine(Offset(vp.dx - wd, vp.dy + 14 + (h - vp.dy - 14) * k * 0.0 + (h - vp.dy - 14) * (1 - k)),
          Offset(vp.dx + wd, vp.dy + 14 + (h - vp.dy - 14) * (1 - k)), Paint()..color = Colors.black12);
    }
    // door at the end, exit sign pulse
    c.drawRect(Rect.fromCenter(center: Offset(vp.dx, vp.dy + 2), width: 34, height: 28), Paint()..color = const Color(0xFF0A1416));
    final pulse = 0.55 + 0.45 * sin(t * _tau / 3);
    c.drawRect(Rect.fromCenter(center: Offset(vp.dx, vp.dy - 20), width: 26, height: 7), Paint()..color = const Color(0xFF29D67A).withValues(alpha: pulse));
    glow(c, Offset(vp.dx, vp.dy - 20), 24, const Color(0x6629D67A), pulse);
    // ECG monitor on the left wall
    final m = Rect.fromLTWH(w * 0.06, h * 0.3, w * 0.26, h * 0.2);
    c.drawRRect(RRect.fromRectAndRadius(m, const Radius.circular(6)), Paint()..color = const Color(0xFF06100F));
    final ecg = Path();
    for (double x = 0; x < m.width - 8; x += 2) {
      final ph = ((x / 60) - t * 0.5) % 1.0;
      double y = 0;
      if (ph > 0.40 && ph < 0.44) y = -18 * (1 - (ph - 0.42).abs() / 0.02);
      if (ph >= 0.44 && ph < 0.48) y = 8 * (1 - (ph - 0.46).abs() / 0.02);
      final px = m.left + 4 + x, py = m.center.dy + y;
      x == 0 ? ecg.moveTo(px, py) : ecg.lineTo(px, py);
    }
    c.drawPath(ecg, Paint()..color = const Color(0xFF39FF88)..style = PaintingStyle.stroke..strokeWidth = 2);
    // gurney silhouette
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.62, h * 0.7, w * 0.3, 12), const Radius.circular(4)), Paint()..color = const Color(0xFF0A1416));
    for (final x in [0.65, 0.88]) {
      c.drawCircle(Offset(w * x, h * 0.78), 7, Paint()..color = const Color(0xFF0A1416));
    }
  }

  // -------------------------------------------------------------- library
  static void library(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF1A130C), Color(0xFF2B1D12)]);
    final rng = Random(5);
    final spines = const [Color(0xFF6B2A22), Color(0xFF28463A), Color(0xFF3A2D52), Color(0xFF8A6A2C), Color(0xFF2B3E5C), Color(0xFF5A3A24)];
    for (final side in [0, 1]) {
      final x0 = side == 0 ? 0.0 : w * 0.7;
      c.drawRect(Rect.fromLTWH(x0, 0, w * 0.3, h), Paint()..color = const Color(0xFF120C07));
      for (int row = 0; row < 5; row++) {
        double x = x0 + 4;
        final y = 10 + row * h * 0.19;
        while (x < x0 + w * 0.3 - 6) {
          final bw = 4.0 + rng.nextInt(6);
          final bh = h * 0.14 + rng.nextInt(10);
          c.drawRect(Rect.fromLTWH(x, y + (h * 0.17 - bh), bw, bh), Paint()..color = spines[rng.nextInt(spines.length)]);
          x += bw + 1;
        }
        c.drawRect(Rect.fromLTWH(x0, y + h * 0.17, w * 0.3, 3), Paint()..color = const Color(0xFF3A2814));
      }
    }
    // reading lamp
    final lamp = Offset(w * 0.5, h * 0.44);
    final cone = Path()..moveTo(lamp.dx - 6, lamp.dy)..lineTo(lamp.dx - 70, h)..lineTo(lamp.dx + 70, h)..lineTo(lamp.dx + 6, lamp.dy)..close();
    c.drawPath(cone, Paint()..shader = RadialGradient(center: Alignment.topCenter, radius: 1.2, colors: [const Color(0x55FFD27A), Colors.transparent]).createShader(Rect.fromLTWH(lamp.dx - 70, lamp.dy, 140, h - lamp.dy)));
    c.drawRect(Rect.fromLTWH(lamp.dx - 3, lamp.dy - 30, 6, 30), Paint()..color = const Color(0xFF0B0805));
    c.drawArc(Rect.fromCenter(center: Offset(lamp.dx, lamp.dy), width: 40, height: 22), pi, pi, true, Paint()..color = const Color(0xFF2E7D5B));
    glow(c, lamp, 46, const Color(0x88FFD27A), 0.85 + 0.15 * sin(t * 5));
    // desk + open book
    c.drawRect(Rect.fromLTWH(w * 0.3, h * 0.82, w * 0.4, h * 0.18), Paint()..color = const Color(0xFF3A2410));
    final book = Path()..moveTo(w * 0.44, h * 0.82)..lineTo(w * 0.5, h * 0.8)..lineTo(w * 0.56, h * 0.82)..lineTo(w * 0.5, h * 0.84)..close();
    c.drawPath(book, Paint()..color = const Color(0xFFEBDDB8));
    // dust motes in the cone
    for (int i = 0; i < 26; i++) {
      final p = _pts[i];
      final y = lamp.dy + ((p.dy + t / 12 * (0.4 + 0.5 * p.dx)) % 1.0) * (h - lamp.dy);
      final spread = (y - lamp.dy) / (h - lamp.dy) * 60;
      final x = lamp.dx + (p.dx - 0.5) * 2 * spread + sin(t * 1.5 + i) * 4;
      c.drawCircle(Offset(x, y), 1.2, Paint()..color = const Color(0xFFFFE9B0).withValues(alpha: 0.45 + 0.4 * sin(t * 2 + i)));
    }
  }

  // -------------------------------------------------------------- theater
  static void theater(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF16060A), Color(0xFF2A0C12)]);
    // stage floor
    final floor = Rect.fromLTWH(0, h * 0.68, w, h * 0.32);
    c.drawRect(floor, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF4A2A18), Color(0xFF1C0F08)]).createShader(floor));
    for (double x = -h; x < w + h; x += 26) {
      c.drawLine(Offset(x, h * 0.68), Offset(w / 2 + (x - w / 2) * 2.4, h), Paint()..color = Colors.black26);
    }
    // spotlight
    final sw = sin(t * _tau / 6);
    final spot = Offset(w * 0.5 + sw * w * 0.28, h * 0.8);
    final cone = Path()..moveTo(w * 0.5, 0)..lineTo(spot.dx - 40, spot.dy)..lineTo(spot.dx + 40, spot.dy)..close();
    c.drawPath(cone, Paint()..color = const Color(0x22FFF2C0));
    c.drawOval(Rect.fromCenter(center: spot, width: 90, height: 20), Paint()..color = const Color(0x44FFE9A8));
    // curtains with swaying folds
    for (final side in [0, 1]) {
      final x0 = side == 0 ? 0.0 : w * 0.76;
      final cw = w * 0.24;
      c.drawRect(Rect.fromLTWH(x0, 0, cw, h * 0.7), Paint()..color = const Color(0xFF7A1420));
      for (int i = 0; i < 9; i++) {
        final x = x0 + i * cw / 9 + sin(t * _tau / 4 + i * 0.7) * 2;
        c.drawRect(Rect.fromLTWH(x, 0, cw / 18, h * 0.7), Paint()..color = Colors.black.withValues(alpha: 0.28));
        c.drawRect(Rect.fromLTWH(x + cw / 18, 0, cw / 30, h * 0.7), Paint()..color = const Color(0xFFB02A3C).withValues(alpha: 0.35));
      }
    }
    c.drawRect(Rect.fromLTWH(0, 0, w, h * 0.08), Paint()..color = const Color(0xFF5A0E18));
    // chair at the center and a fallen lamp silhouette
    c.drawRect(Rect.fromLTWH(w * 0.46, h * 0.62, 5, h * 0.12), Paint()..color = const Color(0xFF0A0405));
    c.drawRect(Rect.fromLTWH(w * 0.46, h * 0.62, w * 0.06, 4), Paint()..color = const Color(0xFF0A0405));
    // audience heads
    for (int i = 0; i < 16; i++) {
      final x = i * w / 15;
      c.drawCircle(Offset(x, h * 0.97 + (i % 2) * 4), 14, Paint()..color = const Color(0xFF080204));
    }
  }

  // -------------------------------------------------------------- hotel
  static void hotel(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF1E1410), Color(0xFF2E1F18)]);
    c.drawRect(Rect.fromLTWH(0, h * 0.78, w, h * 0.22), Paint()..color = const Color(0xFF3A1218));
    for (double x = 0; x < w; x += 22) {
      c.drawRect(Rect.fromLTWH(x + 4, h * 0.82, 8, 8), Paint()..color = const Color(0xFF5A2028));
    }
    // doors
    for (int i = 0; i < 4; i++) {
      final x = w * 0.06 + i * w * 0.22;
      final ajar = i == 2;
      c.drawRect(Rect.fromLTWH(x, h * 0.28, w * 0.14, h * 0.5), Paint()..color = const Color(0xFF4A2A16));
      c.drawRect(Rect.fromLTWH(x + 6, h * 0.34, w * 0.14 - 12, h * 0.16), Paint()..color = Colors.black12);
      c.drawCircle(Offset(x + w * 0.11, h * 0.54), 3, Paint()..color = const Color(0xFFD4A84B));
      c.drawRect(Rect.fromLTWH(x + w * 0.04, h * 0.22, w * 0.06, 12), Paint()..color = const Color(0xFFD4A84B));
      if (ajar) {
        c.drawRect(Rect.fromLTWH(x + w * 0.14 - 4, h * 0.28, 4, h * 0.5), Paint()..color = const Color(0xFFFFD27A).withValues(alpha: 0.6 + 0.4 * flick(t, 6, 1)));
        glow(c, Offset(x + w * 0.14, h * 0.78), 50, const Color(0x44FFD27A), 0.7);
      }
    }
    // wall lamps
    for (int i = 0; i < 4; i++) {
      final p = Offset(w * 0.13 + i * w * 0.22, h * 0.18);
      glow(c, p, 36, const Color(0x44FFC060), flick(t, 5.0 + i, i.toDouble()));
      c.drawRect(Rect.fromCenter(center: p, width: 8, height: 14), Paint()..color = const Color(0xFFFFD27A));
    }
    // lift indicator counting floors
    final floors = (t / 2).floor() % 6 + 1;
    c.drawRect(Rect.fromLTWH(w * 0.9, h * 0.06, 28, 16), Paint()..color = Colors.black);
    final tp = TextPainter(text: TextSpan(text: '$floors', style: const TextStyle(color: Color(0xFFFF4A3A), fontSize: 11, fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, Offset(w * 0.9 + 14 - tp.width / 2, h * 0.06 + 2));
  }

  // -------------------------------------------------------------- kitchen
  static void kitchen(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF1A1512), Color(0xFF2A211B)]);
    for (double x = 0; x < w; x += 24) {
      c.drawLine(Offset(x, 0), Offset(x, h * 0.62), Paint()..color = Colors.white10);
    }
    for (double y = 0; y < h * 0.62; y += 24) {
      c.drawLine(Offset(0, y), Offset(w, y), Paint()..color = Colors.white10);
    }
    // hanging pots
    for (int i = 0; i < 5; i++) {
      final x = w * 0.12 + i * w * 0.18;
      final sw = sin(t * _tau / 6 + i) * 2;
      c.drawLine(Offset(x, 0), Offset(x + sw, h * 0.14), Paint()..color = const Color(0xFF111111));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + sw, h * 0.18), width: 28 + (i % 2) * 8, height: 20), const Radius.circular(5)), Paint()..color = const Color(0xFF8A8F98));
    }
    // counter
    final ct = Rect.fromLTWH(0, h * 0.62, w, h * 0.38);
    c.drawRect(ct, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9AA3AB), Color(0xFF3A4046)]).createShader(ct));
    // stove with gas flames
    final sx = w * 0.5;
    c.drawRect(Rect.fromCenter(center: Offset(sx, h * 0.62), width: 90, height: 10), Paint()..color = const Color(0xFF15191C));
    for (int i = -3; i <= 3; i++) {
      final fh = 9 + 4 * sin(t * 12 + i * 1.7).abs();
      final p = Path()..moveTo(sx + i * 11 - 4, h * 0.615)..quadraticBezierTo(sx + i * 11, h * 0.615 - fh, sx + i * 11 + 4, h * 0.615)..close();
      c.drawPath(p, Paint()..color = const Color(0xFF4DA8FF));
    }
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx, h * 0.57), width: 70, height: 26), const Radius.circular(6)), Paint()..color = const Color(0xFF1B1F23));
    // steam
    for (int i = 0; i < 14; i++) {
      final p = ((t / 4 + i / 14) % 1.0);
      final x = sx + sin(i * 2.1 + t * 1.3) * 16 + (i % 3 - 1) * 8;
      final y = h * 0.52 - p * h * 0.4;
      c.drawCircle(Offset(x, y), 5 + p * 12, Paint()..color = Colors.white.withValues(alpha: 0.16 * (1 - p)));
    }
    // knife block
    c.drawRect(Rect.fromLTWH(w * 0.82, h * 0.52, 26, 28), Paint()..color = const Color(0xFF3A2410));
    for (int i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(w * 0.82 + 4 + i * 7, h * 0.46, 3, 10), Paint()..color = const Color(0xFF111111));
    }
  }

  // -------------------------------------------------------------- snow lodge
  static void snowLodge(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF06101E), Color(0xFF1E3550)]);
    // aurora
    for (int i = 0; i < 3; i++) {
      final p = Path()..moveTo(0, h * 0.2 + i * 12);
      for (double x = 0; x <= w; x += 14) {
        p.lineTo(x, h * 0.2 + i * 12 + sin(x / 60 + t * _tau / 12 * (i + 1)) * 12);
      }
      c.drawPath(p, Paint()..color = const Color(0xFF3DFFB0).withValues(alpha: 0.07)..style = PaintingStyle.stroke..strokeWidth = 18 - i * 4);
    }
    for (int i = 0; i < 30; i++) {
      c.drawCircle(Offset(_pts[i].dx * w, _pts[i].dy * h * 0.4), 1, Paint()..color = Colors.white.withValues(alpha: 0.5));
    }
    // mountains
    final m = Path()..moveTo(0, h * 0.7)..lineTo(w * 0.2, h * 0.4)..lineTo(w * 0.38, h * 0.62)..lineTo(w * 0.62, h * 0.32)..lineTo(w * 0.85, h * 0.6)..lineTo(w, h * 0.45)..lineTo(w, h)..lineTo(0, h)..close();
    c.drawPath(m, Paint()..color = const Color(0xFF16263A));
    c.drawRect(Rect.fromLTWH(0, h * 0.74, w, h * 0.26), Paint()..color = const Color(0xFFD7E6F2));
    // cabin
    final cab = Rect.fromLTWH(w * 0.34, h * 0.56, w * 0.32, h * 0.2);
    c.drawRect(cab, Paint()..color = const Color(0xFF3A2414));
    final roof = Path()..moveTo(cab.left - 10, cab.top)..lineTo(cab.center.dx, cab.top - h * 0.12)..lineTo(cab.right + 10, cab.top)..close();
    c.drawPath(roof, Paint()..color = const Color(0xFFEAF2F8));
    final lit = 0.8 + 0.2 * sin(t * 7);
    c.drawRect(Rect.fromLTWH(cab.left + 14, cab.top + 12, 24, 20), Paint()..color = const Color(0xFFFFC060).withValues(alpha: lit));
    glow(c, Offset(cab.left + 26, cab.top + 22), 40, const Color(0x55FFC060), lit);
    // chimney smoke
    for (int i = 0; i < 10; i++) {
      final p = ((t / 6 + i / 10) % 1.0);
      c.drawCircle(Offset(cab.right - 18 + sin(i + t) * 6 + p * 18, cab.top - h * 0.1 - p * h * 0.3), 4 + p * 10,
          Paint()..color = Colors.white.withValues(alpha: 0.2 * (1 - p)));
    }
    // pines
    for (final x in [0.12, 0.22, 0.8, 0.9]) {
      for (int k = 0; k < 3; k++) {
        final p = Path()..moveTo(w * x - 18 + k * 3, h * 0.76 - k * 18)..lineTo(w * x, h * 0.62 - k * 18)..lineTo(w * x + 18 - k * 3, h * 0.76 - k * 18)..close();
        c.drawPath(p, Paint()..color = const Color(0xFF0A1A14));
      }
    }
    // falling snow (period 12 s)
    for (int i = 0; i < 90; i++) {
      final p = _pts[i % 120];
      final sp = 0.5 + p.dx;
      final y = ((p.dy + t / 12 * sp * 2) % 1.0) * h;
      final x = (p.dx * w + sin(t * _tau / 6 + i) * 10 + t * 3) % w;
      c.drawCircle(Offset(x, y), 1 + (i % 3) * 0.6, Paint()..color = Colors.white.withValues(alpha: 0.8));
    }
  }

  // -------------------------------------------------------------- desert
  static void desert(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF0B0F24), Color(0xFF402A3A), Color(0xFFB0653A)]);
    for (int i = 0; i < 40; i++) {
      c.drawCircle(Offset(_pts[i].dx * w, _pts[i].dy * h * 0.45), 1, Paint()..color = Colors.white.withValues(alpha: 0.4 + 0.3 * sin(t * 2 + i)));
    }
    glow(c, Offset(w * 0.2, h * 0.58), 70, const Color(0x66FFB060));
    c.drawCircle(Offset(w * 0.2, h * 0.58), 18, Paint()..color = const Color(0xFFFFC07A));
    // dune layers with parallax drift
    final colors = [const Color(0xFF6A3A2A), const Color(0xFF4A2A22), const Color(0xFF2A1A18)];
    for (int l = 0; l < 3; l++) {
      final p = Path()..moveTo(0, h);
      for (double x = 0; x <= w; x += 10) {
        p.lineTo(x, h * (0.62 + l * 0.1) + sin(x / (60 - l * 12) + l * 2 + t * _tau / 12 * (0.3 + l * 0.2)) * (10 + l * 5));
      }
      p.lineTo(w, h);
      c.drawPath(p, Paint()..color = colors[l]);
    }
    // caravanserai arch
    final cx = w * 0.7;
    final arch = Path()..moveTo(cx - 36, h * 0.66)..lineTo(cx - 36, h * 0.5)..quadraticBezierTo(cx, h * 0.34, cx + 36, h * 0.5)..lineTo(cx + 36, h * 0.66)..close();
    c.drawPath(arch, Paint()..color = const Color(0xFF1A100E));
    c.drawRect(Rect.fromLTWH(cx - 14, h * 0.5, 28, h * 0.16), Paint()..color = const Color(0xFFFFB347).withValues(alpha: 0.5 + 0.2 * sin(t * 4)));
    // camel caravan
    final camel = Offset((w + 60) - ((t / 12) * (w + 120)), h * 0.72);
    for (int i = 0; i < 3; i++) {
      final o = camel.translate(i * 46.0, sin(t * 3 + i) * 1.5);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: o, width: 26, height: 10), const Radius.circular(5)), Paint()..color = const Color(0xFF120A08));
      c.drawCircle(o.translate(-6, -8), 5, Paint()..color = const Color(0xFF120A08));
      c.drawCircle(o.translate(4, -7), 4, Paint()..color = const Color(0xFF120A08));
      c.drawLine(o.translate(-12, -4), o.translate(-16, -14), Paint()..color = const Color(0xFF120A08)..strokeWidth = 3);
      for (final dx in [-8.0, -3.0, 4.0, 9.0]) {
        c.drawLine(o.translate(dx, 4), o.translate(dx, 14), Paint()..color = const Color(0xFF120A08)..strokeWidth = 2);
      }
    }
    // blowing sand
    for (int i = 0; i < 40; i++) {
      final p = _pts[i];
      final x = (p.dx * w + t / 12 * w * 2 * (0.5 + p.dy)) % w;
      final y = h * 0.6 + p.dy * h * 0.4;
      c.drawLine(Offset(x, y), Offset(x - 10, y + 1), Paint()..color = const Color(0x55E6B070)..strokeWidth = 1);
    }
  }

  // -------------------------------------------------------------- subway
  static void subway(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF0E1214), Color(0xFF1B2226)]);
    final vp = Offset(w * 0.5, h * 0.45);
    // tiled walls
    c.drawRect(Rect.fromLTWH(0, 0, w * 0.3, h), Paint()..color = const Color(0xFF263238));
    c.drawRect(Rect.fromLTWH(w * 0.7, 0, w * 0.3, h), Paint()..color = const Color(0xFF263238));
    for (double y = 0; y < h; y += 18) {
      c.drawLine(Offset(0, y), Offset(w * 0.3, y), Paint()..color = Colors.black26);
      c.drawLine(Offset(w * 0.7, y), Offset(w, y), Paint()..color = Colors.black26);
    }
    // tunnel arch
    c.drawOval(Rect.fromCenter(center: vp, width: w * 0.42, height: h * 0.5), Paint()..color = const Color(0xFF050708));
    // rails
    for (final dx in [-0.18, 0.18]) {
      c.drawLine(Offset(vp.dx + dx * w * 0.25, vp.dy + 14), Offset(vp.dx + dx * w * 2.4, h), Paint()..color = const Color(0xFF7A8288)..strokeWidth = 3);
    }
    for (int i = 0; i < 8; i++) {
      final k = pow(0.7, i).toDouble();
      final y = vp.dy + 14 + (h - vp.dy - 14) * k * 0 + (h - vp.dy - 14) * (1 - k);
      c.drawLine(Offset(vp.dx - w * 0.5 * (1 - k) - 10, y), Offset(vp.dx + w * 0.5 * (1 - k) + 10, y), Paint()..color = const Color(0xFF3A2A1C)..strokeWidth = 2 + 4 * (1 - k));
    }
    // platform edge, yellow line
    c.drawRect(Rect.fromLTWH(0, h * 0.9, w, h * 0.1), Paint()..color = const Color(0xFF3A4348));
    c.drawRect(Rect.fromLTWH(0, h * 0.9, w, 4), Paint()..color = const Color(0xFFFFC21A));
    // oncoming train lights (every 12 s)
    final p = (t / 12);
    final k = Curves.easeIn.transform((p * 1.6).clamp(0.0, 1.0));
    if (p < 0.65) {
      final r = 3 + 26 * k;
      glow(c, vp.translate(-r * 1.2, 8), r * 3, const Color(0x88FFF2C0), k);
      glow(c, vp.translate(r * 1.2, 8), r * 3, const Color(0x88FFF2C0), k);
      c.drawCircle(vp.translate(-r * 1.2, 8), r * 0.5, Paint()..color = Colors.white);
      c.drawCircle(vp.translate(r * 1.2, 8), r * 0.5, Paint()..color = Colors.white);
    }
    // flickering ceiling tubes
    for (int i = 0; i < 3; i++) {
      c.drawRect(Rect.fromLTWH(w * (0.1 + i * 0.3), 6, w * 0.16, 5), Paint()..color = const Color(0xFFDFF7F2).withValues(alpha: 0.8 * flick(t, 8.0 + i * 3, i.toDouble())));
    }
  }

  // -------------------------------------------------------------- lab
  static void lab(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF081418), Color(0xFF11262A)]);
    for (double x = 0; x < w; x += 30) {
      c.drawLine(Offset(x, 0), Offset(x, h * 0.66), Paint()..color = Colors.white.withValues(alpha: 0.04));
    }
    // hazard stripes
    for (double x = -20; x < w; x += 26) {
      final p = Path()..moveTo(x, h * 0.04)..lineTo(x + 13, h * 0.04)..lineTo(x + 5, h * 0.09)..lineTo(x - 8, h * 0.09)..close();
      c.drawPath(p, Paint()..color = const Color(0xFFFFC21A).withValues(alpha: 0.7));
    }
    // monitor with a moving graph
    final m = Rect.fromLTWH(w * 0.06, h * 0.2, w * 0.3, h * 0.26);
    c.drawRRect(RRect.fromRectAndRadius(m, const Radius.circular(6)), Paint()..color = const Color(0xFF04100E));
    final g = Path();
    for (double x = 0; x < m.width - 8; x += 3) {
      final y = sin((x + t * 40) / 18) * 10 + sin((x + t * 20) / 7) * 4;
      x == 0 ? g.moveTo(m.left + 4, m.center.dy + y) : g.lineTo(m.left + 4 + x, m.center.dy + y);
    }
    c.drawPath(g, Paint()..color = const Color(0xFF5CF0C0)..style = PaintingStyle.stroke..strokeWidth = 1.6);
    // bench
    c.drawRect(Rect.fromLTWH(0, h * 0.66, w, h * 0.34), Paint()..color = const Color(0xFF1B2B30));
    c.drawRect(Rect.fromLTWH(0, h * 0.66, w, 4), Paint()..color = const Color(0xFF4A6168));
    // flasks with bubbling liquid
    final colors = [const Color(0xFF39FF88), const Color(0xFF3AA8FF), const Color(0xFFFF4DAA)];
    for (int i = 0; i < 3; i++) {
      final x = w * (0.48 + i * 0.16);
      final fl = Path()..moveTo(x - 6, h * 0.46)..lineTo(x - 6, h * 0.54)..lineTo(x - 22, h * 0.66)..lineTo(x + 22, h * 0.66)..lineTo(x + 6, h * 0.54)..lineTo(x + 6, h * 0.46)..close();
      c.drawPath(fl, Paint()..color = Colors.white.withValues(alpha: 0.08));
      final liquid = Path()..moveTo(x - 17, h * 0.6)..lineTo(x - 22, h * 0.66)..lineTo(x + 22, h * 0.66)..lineTo(x + 17, h * 0.6)..close();
      c.drawPath(liquid, Paint()..color = colors[i].withValues(alpha: 0.75));
      glow(c, Offset(x, h * 0.62), 34, colors[i].withValues(alpha: 0.25));
      for (int b = 0; b < 5; b++) {
        final p = ((t / 3 + b / 5 + i * 0.2) % 1.0);
        c.drawCircle(Offset(x + sin(b * 2 + i) * 8, h * 0.62 - p * h * 0.14), 1.5 + (b % 2), Paint()..color = Colors.white.withValues(alpha: 0.7 * (1 - p)));
      }
      c.drawPath(fl, Paint()..color = Colors.white24..style = PaintingStyle.stroke);
    }
    // centrifuge
    final ce = Offset(w * 0.2, h * 0.58);
    c.drawCircle(ce, 22, Paint()..color = const Color(0xFF2A3A40));
    for (int i = 0; i < 4; i++) {
      final a = t * _tau * 2 + i * pi / 2;
      c.drawCircle(ce + Offset(cos(a), sin(a)) * 12, 3, Paint()..color = const Color(0xFF9AB0B8));
    }
  }

  // -------------------------------------------------------------- wedding
  static void wedding(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF1A0A24), Color(0xFF3A1838)]);
    // dance floor tiles that change colors
    final floor = h * 0.72;
    for (int i = 0; i < 10; i++) {
      for (int j = 0; j < 3; j++) {
        final hue = ((t / 12 * 360) + i * 28 + j * 60) % 360;
        c.drawRect(Rect.fromLTWH(i * w / 10, floor + j * (h - floor) / 3, w / 10 - 2, (h - floor) / 3 - 2),
            Paint()..color = HSVColor.fromAHSV(0.45, hue, 0.7, 0.9).toColor());
      }
    }
    // chandeliers
    for (final x in [0.25, 0.75]) {
      final o = Offset(w * x, h * 0.2);
      c.drawLine(Offset(o.dx, 0), o, Paint()..color = const Color(0xFFD4A84B));
      for (int i = -3; i <= 3; i++) {
        final p = o.translate(i * 9.0, 10 + (i.abs()) * 4.0);
        c.drawCircle(p, 3, Paint()..color = const Color(0xFFFFF0C0).withValues(alpha: 0.7 + 0.3 * sin(t * 4 + i)));
      }
      glow(c, o.translate(0, 12), 56, const Color(0x44FFD27A), 0.8 + 0.2 * sin(t * 3 + x));
    }
    // string-light bokeh
    for (int i = 0; i < 24; i++) {
      final p = _pts[i];
      final hue = (i * 37 + t * 20) % 360;
      glow(c, Offset(p.dx * w, h * 0.1 + p.dy * h * 0.5), 16 + 6 * sin(t * 2 + i), HSVColor.fromAHSV(0.35, hue, 0.6, 1).toColor());
    }
    // balloons
    for (int i = 0; i < 5; i++) {
      final x = w * (0.08 + i * 0.2);
      final y = h * 0.58 + sin(t * _tau / 6 + i * 1.3) * 8;
      c.drawLine(Offset(x, y + 18), Offset(x, floor), Paint()..color = Colors.white24);
      c.drawOval(Rect.fromCenter(center: Offset(x, y), width: 24, height: 30), Paint()..color = HSVColor.fromAHSV(1, (i * 60.0 + 340) % 360, 0.55, 0.85).toColor());
    }
    // confetti
    for (int i = 0; i < 40; i++) {
      final p = _pts[(i + 40) % 120];
      final y = ((p.dy + t / 12 * (1 + p.dx)) % 1.0) * h;
      final x = p.dx * w + sin(t * 2 + i) * 8;
      c.drawRect(Rect.fromCenter(center: Offset(x, y), width: 3, height: 5), Paint()..color = HSVColor.fromAHSV(0.9, (i * 47) % 360, 0.7, 1).toColor());
    }
  }

  // -------------------------------------------------------------- school
  static void school(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF111A18), Color(0xFF1E2B26)]);
    // moonlit windows
    for (int i = 0; i < 3; i++) {
      final r = Rect.fromLTWH(w * 0.06 + i * w * 0.14, h * 0.1, w * 0.1, h * 0.34);
      c.drawRect(r, Paint()..color = const Color(0xFF2B4A6A).withValues(alpha: 0.8));
      c.drawLine(r.centerLeft, r.centerRight, Paint()..color = Colors.black54..strokeWidth = 2);
      c.drawLine(r.topCenter, r.bottomCenter, Paint()..color = Colors.black54..strokeWidth = 2);
    }
    final beam = Path()..moveTo(w * 0.06, h * 0.44)..lineTo(w * 0.42, h * 0.44)..lineTo(w * 0.6, h * 0.95)..lineTo(w * 0.2, h * 0.95)..close();
    c.drawPath(beam, Paint()..color = const Color(0x142B4A6A));
    // blackboard with chalk being written
    final b = Rect.fromLTWH(w * 0.5, h * 0.12, w * 0.44, h * 0.34);
    c.drawRect(b, Paint()..color = const Color(0xFF0E2A1E));
    c.drawRect(b, Paint()..color = const Color(0xFF6A4A2A)..style = PaintingStyle.stroke..strokeWidth = 4);
    final prog = (t / 12 * 2) % 1.0;
    final chalk = Path();
    for (int i = 0; i < 4; i++) {
      final y = b.top + 14 + i * 18;
      final len = (b.width - 24) * (i / 4 < prog ? min(1.0, (prog - i / 4) * 4) : 0.0);
      chalk.moveTo(b.left + 12, y);
      for (double x = 0; x < len; x += 6) {
        chalk.lineTo(b.left + 12 + x, y + sin(x * 0.7 + i) * 3);
      }
    }
    c.drawPath(chalk, Paint()..color = Colors.white.withValues(alpha: 0.8)..style = PaintingStyle.stroke..strokeWidth = 1.6);
    // desks
    for (int r = 0; r < 3; r++) {
      for (int i = 0; i < 4; i++) {
        final x = w * (0.12 + i * 0.22) - r * 4;
        final y = h * (0.62 + r * 0.12);
        c.drawRect(Rect.fromLTWH(x, y, w * 0.14, 8), Paint()..color = const Color(0xFF5A3A1E));
        c.drawRect(Rect.fromLTWH(x + 6, y + 8, 4, h * 0.08), Paint()..color = const Color(0xFF1A110A));
        c.drawRect(Rect.fromLTWH(x + w * 0.14 - 10, y + 8, 4, h * 0.08), Paint()..color = const Color(0xFF1A110A));
      }
    }
    // wall clock with a ticking second hand
    final cl = Offset(w * 0.36, h * 0.2);
    c.drawCircle(cl, 18, Paint()..color = const Color(0xFFEDE6D8));
    c.drawCircle(cl, 18, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
    final sec = (t.floor() % 60) * _tau / 60;
    c.drawLine(cl, cl + Offset(sin(sec), -cos(sec)) * 15, Paint()..color = const Color(0xFFC0392B)..strokeWidth = 1.5);
    c.drawLine(cl, cl + const Offset(0, -10), Paint()..color = Colors.black..strokeWidth = 2);
    c.drawLine(cl, cl + const Offset(7, 2), Paint()..color = Colors.black..strokeWidth = 2);
  }

  // -------------------------------------------------------------- airport
  static void airport(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF060C1C), Color(0xFF16254A)], 0.62);
    for (int i = 0; i < 30; i++) {
      c.drawCircle(Offset(_pts[i].dx * w, _pts[i].dy * h * 0.4), 1, Paint()..color = Colors.white.withValues(alpha: 0.5));
    }
    // runway
    c.drawRect(Rect.fromLTWH(0, h * 0.62, w, h * 0.38), Paint()..color = const Color(0xFF14171C));
    for (int i = 0; i < 8; i++) {
      final on = ((t * 2 + i * 0.3) % 2) < 1.2;
      for (final y in [h * 0.64, h * 0.97]) {
        glow(c, Offset(w * (0.06 + i * 0.13), y), on ? 9 : 4, const Color(0xFF4DA8FF));
      }
      c.drawRect(Rect.fromCenter(center: Offset(w * (0.06 + i * 0.13), h * 0.8), width: 26, height: 3), Paint()..color = Colors.white30);
    }
    // plane crossing the sky with nav lights
    final px = -60 + (t / 12) * (w + 160);
    final py = h * 0.24 + sin(t * 0.5) * 3;
    final body = Path()..moveTo(px, py)..lineTo(px + 54, py - 3)..lineTo(px + 60, py + 2)..lineTo(px + 6, py + 6)..close();
    c.drawPath(body, Paint()..color = const Color(0xFF2A3038));
    c.drawPath(Path()..moveTo(px + 22, py + 2)..lineTo(px + 34, py + 20)..lineTo(px + 40, py + 20)..lineTo(px + 38, py)..close(), Paint()..color = const Color(0xFF2A3038));
    final blink = (t * 1.5) % 1 < 0.15;
    glow(c, Offset(px + 34, py + 20), blink ? 10 : 3, const Color(0xFFFF3B30));
    glow(c, Offset(px + 4, py + 2), 5, const Color(0xFF29D67A));
    // terminal
    c.drawRect(Rect.fromLTWH(w * 0.1, h * 0.46, w * 0.5, h * 0.17), Paint()..color = const Color(0xFF1A2230));
    for (int i = 0; i < 10; i++) {
      c.drawRect(Rect.fromLTWH(w * 0.12 + i * w * 0.048, h * 0.5, w * 0.04, h * 0.08), Paint()..color = const Color(0xFFFFD27A).withValues(alpha: 0.35 + 0.35 * ((sin(i * 1.7 + t * 0.5) + 1) / 2)));
    }
    // control tower
    c.drawRect(Rect.fromLTWH(w * 0.78, h * 0.28, 12, h * 0.34), Paint()..color = const Color(0xFF1A2230));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.75, h * 0.2, 36, 18), const Radius.circular(4)), Paint()..color = const Color(0xFF2B4A6A));
    final beaconA = (t * _tau / 2);
    glow(c, Offset(w * 0.78 + 6, h * 0.19), 10 + 8 * max(0, sin(beaconA)), const Color(0xFFFF3B30));
  }

  // -------------------------------------------------------------- tower
  static void tower(Canvas c, Size s, double t) {
    final w = s.width, h = s.height;
    sky(c, s, const [Color(0xFF080C1E), Color(0xFF1C2744)]);
    final moon = Offset(w * 0.2, h * 0.2);
    glow(c, moon, 70, const Color(0x55DFE8FF));
    c.drawCircle(moon, 16, Paint()..color = const Color(0xFFEAF0FF));
    for (int i = 0; i < 3; i++) {
      final x = ((t / 12 * (w + 200)) * (0.4 + i * 0.3) + i * 90) % (w + 200) - 100;
      c.drawOval(Rect.fromCenter(center: Offset(x, h * (0.18 + i * 0.1)), width: 120, height: 22), Paint()..color = const Color(0xFF0A1024).withValues(alpha: 0.55));
    }
    // tower body
    final tw = w * 0.3, cx = w * 0.62;
    c.drawRect(Rect.fromLTWH(cx - tw / 2, h * 0.3, tw, h * 0.7), Paint()..color = const Color(0xFF0E131F));
    final roof = Path()..moveTo(cx - tw / 2 - 8, h * 0.3)..lineTo(cx, h * 0.08)..lineTo(cx + tw / 2 + 8, h * 0.3)..close();
    c.drawPath(roof, Paint()..color = const Color(0xFF0A0E18));
    // clock face
    final face = Offset(cx, h * 0.42);
    c.drawCircle(face, tw * 0.36, Paint()..color = const Color(0xFFE8E0C8));
    c.drawCircle(face, tw * 0.36, Paint()..color = const Color(0xFF2A2018)..style = PaintingStyle.stroke..strokeWidth = 4);
    for (int i = 0; i < 12; i++) {
      final a = i * _tau / 12;
      c.drawLine(face + Offset(sin(a), -cos(a)) * tw * 0.3, face + Offset(sin(a), -cos(a)) * tw * 0.34, Paint()..color = Colors.black..strokeWidth = 2);
    }
    final minute = (t / 12) * _tau;
    final hour = minute / 12 + 3.9;
    c.drawLine(face, face + Offset(sin(minute), -cos(minute)) * tw * 0.3, Paint()..color = Colors.black..strokeWidth = 3);
    c.drawLine(face, face + Offset(sin(hour), -cos(hour)) * tw * 0.2, Paint()..color = Colors.black..strokeWidth = 4);
    final sec = (t * 2).floor() * _tau / 24; // ticks
    c.drawLine(face, face + Offset(sin(sec), -cos(sec)) * tw * 0.33, Paint()..color = const Color(0xFFC0392B)..strokeWidth = 1.3);
    glow(c, face, tw * 0.5, const Color(0x22FFE9A8));
    // belfry window, lit
    c.drawRect(Rect.fromCenter(center: Offset(cx, h * 0.62), width: 22, height: 36), Paint()..color = const Color(0xFFFFC060).withValues(alpha: 0.5 + 0.3 * sin(t * 2.3)));
    // pigeons
    for (int i = 0; i < 4; i++) {
      final p = ((t / 6 + i * 0.23) % 1.0);
      final o = Offset(w * p * 1.2 - 20, h * (0.3 + 0.08 * i) + sin(p * 12 + i) * 8);
      final flap = sin(t * 14 + i) * 3;
      c.drawLine(o, o.translate(-6, -3 + flap), Paint()..color = Colors.black87..strokeWidth = 1.6);
      c.drawLine(o, o.translate(6, -3 + flap), Paint()..color = Colors.black87..strokeWidth = 1.6);
    }
  }
}
