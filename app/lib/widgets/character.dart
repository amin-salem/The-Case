import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';

/// Moods change the face while a suspect talks.
enum Mood { calm, nervous, angry, sad }

const _skins = [Color(0xFFF3D2B3), Color(0xFFE2B48D), Color(0xFFC68E64), Color(0xFF8D5A3B)];

Color _hex(String h, [Color fallback = const Color(0xFF333333)]) {
  final s = h.replaceAll('#', '');
  final v = int.tryParse(s.length == 6 ? 'FF$s' : s, radix: 16);
  return v == null ? fallback : Color(v);
}

Color _shade(Color c, double t) => Color.lerp(c, Colors.black, t)!;
Color _tint(Color c, double t) => Color.lerp(c, Colors.white, t)!;

/// A suspect portrait (head and shoulders) that breathes, blinks and
/// talks. Everything is drawn in code from the case's avatar description.
class AnimatedSuspect extends StatefulWidget {
  const AnimatedSuspect({super.key, required this.avatar, this.size = 120, this.mood = Mood.calm, this.talking = false});
  final AvatarSpec avatar;
  final double size;
  final Mood mood;
  final bool talking;

  @override
  State<AnimatedSuspect> createState() => _AnimatedSuspectState();
}

class _AnimatedSuspectState extends State<AnimatedSuspect> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  final _rng = Random();
  double _nextBlink = 1.5;
  double _blinkStart = -1;
  double _t = 0;
  double _clock = 0;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      final v = _c.value;
      var dt = v - _last;
      if (dt < 0) dt += 1;
      _last = v;
      _clock += dt * 4; // seconds
      if (_clock > _nextBlink && _blinkStart < 0) {
        _blinkStart = _clock;
      }
      if (_blinkStart >= 0 && _clock - _blinkStart > 0.16) {
        _blinkStart = -1;
        _nextBlink = _clock + 2 + _rng.nextDouble() * 3;
      }
      setState(() => _t = v);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kPortraits.contains(widget.avatar.portrait)) return _portrait();
    final blink = _blinkStart >= 0 ? sin((_clock - _blinkStart) / 0.16 * pi) : 0.0;
    return CustomPaint(
      size: Size(widget.size, widget.size * 1.1),
      painter: CharacterPainter(widget.avatar,
          breath: sin(_t * 2 * pi), blink: blink.clamp(0.0, 1.0), mood: widget.mood,
          mouth: widget.talking ? (0.5 + 0.5 * sin(_clock * 14)).abs() : 0,
          gaze: widget.mood == Mood.nervous ? sin(_clock * 1.7) * 2.2 : sin(_clock * 0.5) * 0.8),
    );
  }

  /// A painted portrait that breathes slowly; nervous suspects sway, the caught culprit goes dark.
  Widget _portrait() {
    final w = widget.size, h = widget.size * 1.1;
    final m = widget.mood;
    final dx = m == Mood.nervous ? sin(_clock * 1.7) * w * 0.012 : 0.0;
    return SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(w * 0.12),
        child: Stack(fit: StackFit.expand, children: [
          Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(
              scale: 1.04 + 0.012 * sin(_t * 2 * pi) + (widget.talking ? 0.006 * sin(_clock * 9) : 0),
              child: Image.asset('assets/portraits/${widget.avatar.portrait}.webp',
                  fit: BoxFit.cover, alignment: const Alignment(0, -0.4), filterQuality: FilterQuality.medium),
            ),
          ),
          if (m == Mood.sad) const ColoredBox(color: Color(0x66000000)),
          if (m == Mood.nervous) const ColoredBox(color: Color(0x14C0392B)),
        ]),
      ),
    );
  }
}

/// Painted portraits shipped with the app (assets/portraits). A suspect whose avatar names one of
/// these is shown with it; everyone else is drawn by CharacterPainter.
const Set<String> kPortraits = {'m_mid_business', 'm_young_worker', 'f_young_nurse', 'f_old_grandma'};

/// Draws a character in a 200 x 220 box, scaled to the widget size.
class CharacterPainter extends CustomPainter {
  CharacterPainter(this.a, {this.breath = 0, this.blink = 0, this.mood = Mood.calm, this.mouth = 0, this.gaze = 0});
  final AvatarSpec a;
  final double breath; // -1..1
  final double blink; // 0 open .. 1 closed
  final Mood mood;
  final double mouth; // 0 closed .. 1 open
  final double gaze; // eye offset

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 220);
    final skin = _skins[a.skin.clamp(0, 3)];
    final hair = _hex(a.hairColor);
    final outfit = _hex(a.outfit, const Color(0xFF3B4A5E));
    final female = a.gender == 'f';
    final old = a.age == 'old';
    final lift = breath * 1.6;
    final ink = Paint()
      ..color = const Color(0xFF1A1410)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // ---- hijab back / long hair behind the shoulders
    if (a.hair == 'hijab') {
      final back = Path()
        ..moveTo(52, 92 - lift)
        ..quadraticBezierTo(46, 160, 30, 220)
        ..lineTo(170, 220)
        ..quadraticBezierTo(154, 160, 148, 92 - lift)
        ..close();
      canvas.drawPath(back, Paint()..color = _shade(hair, 0.15));
    } else if (a.hair == 'long') {
      final back = Path()
        ..moveTo(58, 70 - lift)
        ..quadraticBezierTo(44, 140, 56, 182)
        ..lineTo(144, 182)
        ..quadraticBezierTo(156, 140, 142, 70 - lift)
        ..close();
      canvas.drawPath(back, Paint()..color = _shade(hair, 0.1));
    }

    // ---- shoulders / clothes
    final body = Path()
      ..moveTo(22, 220)
      ..quadraticBezierTo(26, 168 - lift, 70, 156 - lift)
      ..lineTo(130, 156 - lift)
      ..quadraticBezierTo(174, 168 - lift, 178, 220)
      ..close();
    canvas.drawPath(
        body,
        Paint()
          ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [_tint(outfit, 0.08), _shade(outfit, 0.25)])
              .createShader(const Rect.fromLTWH(20, 150, 160, 70)));
    canvas.drawPath(body, ink);

    // neck
    final neck = Rect.fromLTWH(84, 128 - lift, 32, 34);
    canvas.drawRect(neck, Paint()..color = _shade(skin, 0.12));

    // collar / accessories
    switch (a.accessory) {
      case 'tie':
        final collar = Path()
          ..moveTo(78, 156 - lift)
          ..lineTo(100, 178 - lift)
          ..lineTo(122, 156 - lift);
        canvas.drawPath(collar, Paint()..color = const Color(0xFFF1F1F1)..style = PaintingStyle.stroke..strokeWidth = 7);
        final tie = Path()
          ..moveTo(100, 166 - lift)
          ..lineTo(92, 176 - lift)
          ..lineTo(100, 214 - lift)
          ..lineTo(108, 176 - lift)
          ..close();
        canvas.drawPath(tie, Paint()..color = const Color(0xFF8E1C1C));
      case 'badge':
        canvas.drawPath(
            Path()
              ..moveTo(138, 182 - lift)
              ..lineTo(146, 178 - lift)
              ..lineTo(154, 182 - lift)
              ..lineTo(152, 194 - lift)
              ..lineTo(146, 198 - lift)
              ..lineTo(140, 194 - lift)
              ..close(),
            Paint()..color = const Color(0xFFD4A84B));
      case 'apron':
        canvas.drawLine(Offset(78, 158 - lift), const Offset(84, 220), Paint()..color = const Color(0xFFE8E2D4)..strokeWidth = 7);
        canvas.drawLine(Offset(122, 158 - lift), const Offset(116, 220), Paint()..color = const Color(0xFFE8E2D4)..strokeWidth = 7);
      case 'scarf':
        canvas.drawOval(Rect.fromCenter(center: Offset(100, 158 - lift), width: 70, height: 18),
            Paint()..color = _shade(hair, 0.05));
      default:
        final collar = Path()
          ..moveTo(80, 156 - lift)
          ..lineTo(100, 170 - lift)
          ..lineTo(120, 156 - lift);
        canvas.drawPath(collar, Paint()..color = _shade(outfit, 0.35)..style = PaintingStyle.stroke..strokeWidth = 5);
    }

    // ---- head
    final headC = Offset(100, 92 - lift * 0.6);
    final head = Rect.fromCenter(center: headC, width: female ? 74 : 80, height: female ? 92 : 96);
    if (a.hair == 'hijab') {
      final frame = Rect.fromCenter(center: headC.translate(0, 2), width: 104, height: 122);
      canvas.drawOval(frame, Paint()..color = hair);
      canvas.drawOval(frame, ink);
    }
    // ears
    if (a.hair != 'hijab' && a.hair != 'long') {
      for (final dx in [-1.0, 1.0]) {
        final ear = Rect.fromCenter(center: headC.translate(dx * (head.width / 2 + 1), 4), width: 14, height: 22);
        canvas.drawOval(ear, Paint()..color = _shade(skin, 0.06));
        canvas.drawOval(ear, ink..strokeWidth = 2);
      }
    }
    canvas.drawOval(head, Paint()..color = skin);
    // soft shading on one side
    canvas.save();
    canvas.clipPath(Path()..addOval(head));
    canvas.drawRect(Rect.fromLTWH(head.center.dx + 8, head.top, head.width, head.height),
        Paint()..color = _shade(skin, 0.1).withValues(alpha: 0.5));
    canvas.restore();
    canvas.drawOval(head, ink..strokeWidth = 2.4);

    // ---- hair on top
    _hairTop(canvas, head, hair, ink);

    // ---- face
    final eyeY = headC.dy - 4;
    final eyeDx = female ? 15.0 : 16.0;
    final brow = switch (mood) { Mood.angry => 5.0, Mood.nervous => -4.0, Mood.sad => -3.0, Mood.calm => 0.0 };
    final browPaint = Paint()
      ..color = old ? const Color(0xFFB8B8B8) : _shade(hair, 0.2)
      ..strokeWidth = 3.6
      ..strokeCap = StrokeCap.round;
    for (final s in [-1.0, 1.0]) {
      final inner = Offset(100 + s * 7, eyeY - 12 + (mood == Mood.angry ? 3 : 0) + (mood == Mood.sad ? -2 : 0));
      final outer = Offset(100 + s * 25, eyeY - 13 + (mood == Mood.angry ? -1 : brow * 0.4));
      canvas.drawLine(inner.translate(0, brow > 0 ? 0 : brow * 0.5), outer, browPaint);
    }
    for (final s in [-1.0, 1.0]) {
      final c = Offset(100 + s * eyeDx, eyeY);
      final h = 9.0 * (1 - blink);
      if (h < 1.5) {
        canvas.drawLine(c.translate(-6, 0), c.translate(6, 0), ink..strokeWidth = 2.2);
      } else {
        canvas.drawOval(Rect.fromCenter(center: c, width: 15, height: h), Paint()..color = Colors.white);
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCenter(center: c, width: 15, height: h)));
        canvas.drawCircle(c.translate(gaze, 0.5), 4.2, Paint()..color = const Color(0xFF2B1D14));
        canvas.drawCircle(c.translate(gaze + 1.4, -1), 1.2, Paint()..color = Colors.white);
        canvas.restore();
        canvas.drawOval(Rect.fromCenter(center: c, width: 15, height: h), ink..strokeWidth = 1.6);
        if (female) {
          canvas.drawLine(c.translate(s * 6, -h / 2 + 1), c.translate(s * 9, -h / 2 - 2), ink..strokeWidth = 1.6);
        }
      }
    }
    if (old) {
      final w = Paint()
        ..color = _shade(skin, 0.3)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (final s in [-1.0, 1.0]) {
        canvas.drawArc(Rect.fromCenter(center: Offset(100 + s * 26, eyeY + 2), width: 8, height: 10), s > 0 ? -0.6 : pi - 0.4, 1.0, false, w);
      }
      canvas.drawLine(Offset(90, headC.dy - 30), Offset(110, headC.dy - 30), w);
    }
    // nose
    final nose = Path()
      ..moveTo(100, eyeY + 4)
      ..quadraticBezierTo(97, eyeY + 18, 94, eyeY + 20)
      ..quadraticBezierTo(100, eyeY + 23, 106, eyeY + 20);
    canvas.drawPath(nose, ink..strokeWidth = 2);

    // beard / mustache
    final mouthY = eyeY + 33;
    switch (a.beard) {
      case 'full':
        final beard = Path()
          ..moveTo(head.left + 6, headC.dy + 4)
          ..quadraticBezierTo(head.left + 6, head.bottom + 8, 100, head.bottom + 10)
          ..quadraticBezierTo(head.right - 6, head.bottom + 8, head.right - 6, headC.dy + 4)
          ..quadraticBezierTo(100, mouthY + 2, head.left + 6, headC.dy + 4)
          ..close();
        canvas.drawPath(beard, Paint()..color = old ? const Color(0xFFCFCFCF) : hair);
      case 'stubble':
        canvas.save();
        canvas.clipPath(Path()..addOval(head));
        canvas.drawRect(Rect.fromLTWH(head.left, mouthY - 10, head.width, 40),
            Paint()..color = _shade(hair, 0).withValues(alpha: 0.18));
        canvas.restore();
      default:
        break;
    }
    if (a.beard == 'mustache' || a.beard == 'full') {
      final m = Path()
        ..moveTo(86, mouthY - 4)
        ..quadraticBezierTo(100, mouthY - 12, 114, mouthY - 4)
        ..quadraticBezierTo(100, mouthY - 6, 86, mouthY - 4)
        ..close();
      canvas.drawPath(m, Paint()..color = old ? const Color(0xFFBDBDBD) : _shade(hair, 0.1));
      canvas.drawPath(m, Paint()..color = (old ? const Color(0xFFBDBDBD) : _shade(hair, 0.1))..style = PaintingStyle.stroke..strokeWidth = 4);
    }

    // mouth
    final lip = female ? const Color(0xFFB0485A) : const Color(0xFF7A3B2E);
    if (mouth > 0.05) {
      canvas.drawOval(Rect.fromCenter(center: Offset(100, mouthY + 2), width: 14, height: 3 + 9 * mouth),
          Paint()..color = const Color(0xFF3A1414));
    } else {
      final curve = switch (mood) { Mood.calm => 2.0, Mood.nervous => -1.0, Mood.angry => -3.0, Mood.sad => -4.0 };
      final m = Path()
        ..moveTo(90, mouthY)
        ..quadraticBezierTo(100, mouthY + curve * 1.5, 110, mouthY + (mood == Mood.nervous ? 2 : 0));
      canvas.drawPath(m, Paint()..color = lip..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round);
    }

    // glasses
    if (a.glasses) {
      final g = Paint()
        ..color = const Color(0xFF151515)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6;
      for (final s in [-1.0, 1.0]) {
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(100 + s * eyeDx, eyeY + 1), width: 25, height: 19),
            const Radius.circular(6));
        canvas.drawRRect(r, Paint()..color = const Color(0x22BFE3FF));
        canvas.drawRRect(r, g);
      }
      canvas.drawLine(Offset(100 - eyeDx + 12.5, eyeY), Offset(100 + eyeDx - 12.5, eyeY), g);
    }

    // nervous sweat drop
    if (mood == Mood.nervous) {
      final d = Path()
        ..moveTo(head.right - 6, head.top + 24)
        ..quadraticBezierTo(head.right + 2, head.top + 36, head.right - 6, head.top + 40)
        ..quadraticBezierTo(head.right - 14, head.top + 36, head.right - 6, head.top + 24)
        ..close();
      canvas.drawPath(d, Paint()..color = const Color(0xCC8FD3FF));
    }
    canvas.restore();
  }

  void _hairTop(Canvas canvas, Rect head, Color hair, Paint ink) {
    final p = Paint()..color = hair;
    switch (a.hair) {
      case 'bald':
        canvas.drawArc(Rect.fromLTWH(head.left - 2, head.center.dy - 16, 14, 30), pi * 0.6, pi * 0.9, false,
            Paint()..color = hair..style = PaintingStyle.stroke..strokeWidth = 6);
        canvas.drawArc(Rect.fromLTWH(head.right - 12, head.center.dy - 16, 14, 30), -pi * 0.5, pi * 0.9, false,
            Paint()..color = hair..style = PaintingStyle.stroke..strokeWidth = 6);
        canvas.drawOval(Rect.fromCenter(center: head.topCenter.translate(-10, 18), width: 18, height: 8),
            Paint()..color = Colors.white.withValues(alpha: 0.35));
      case 'short':
        final cap = Path()
          ..moveTo(head.left - 1, head.center.dy - 6)
          ..quadraticBezierTo(head.left - 2, head.top - 8, head.center.dx, head.top - 8)
          ..quadraticBezierTo(head.right + 2, head.top - 8, head.right + 1, head.center.dy - 6)
          ..quadraticBezierTo(head.right - 6, head.top + 14, head.center.dx + 8, head.top + 14)
          ..quadraticBezierTo(head.left + 10, head.top + 12, head.left - 1, head.center.dy - 6)
          ..close();
        canvas.drawPath(cap, p);
        canvas.drawPath(cap, ink..strokeWidth = 2);
      case 'slick':
        final cap = Path()
          ..moveTo(head.left - 1, head.center.dy - 2)
          ..quadraticBezierTo(head.left, head.top - 10, head.center.dx + 6, head.top - 9)
          ..quadraticBezierTo(head.right + 4, head.top - 4, head.right + 1, head.center.dy - 2)
          ..quadraticBezierTo(head.right - 10, head.top + 8, head.left + 8, head.top + 18)
          ..close();
        canvas.drawPath(cap, p);
        canvas.drawPath(cap, ink..strokeWidth = 2);
        canvas.drawLine(head.topCenter.translate(-14, 2), head.topCenter.translate(18, -4),
            Paint()..color = _tint(hair, 0.3)..strokeWidth = 2);
      case 'curly':
        for (int i = 0; i < 11; i++) {
          final ang = pi + i * pi / 10;
          final c = head.center.translate(cos(ang) * head.width * 0.5, sin(ang) * head.height * 0.5 + 6);
          canvas.drawCircle(c, 11, p);
        }
        canvas.drawCircle(head.topCenter.translate(0, 6), 13, p);
      case 'long':
        final top = Path()
          ..moveTo(head.left - 4, head.bottom - 10)
          ..quadraticBezierTo(head.left - 6, head.top - 10, head.center.dx, head.top - 8)
          ..quadraticBezierTo(head.right + 6, head.top - 10, head.right + 4, head.bottom - 10)
          ..lineTo(head.right - 4, head.center.dy)
          ..quadraticBezierTo(head.center.dx + 10, head.top + 10, head.center.dx - 6, head.top + 16)
          ..quadraticBezierTo(head.left + 8, head.top + 20, head.left + 4, head.center.dy)
          ..close();
        canvas.drawPath(top, p);
        canvas.drawPath(top, ink..strokeWidth = 2);
      case 'cap':
        final crown = Path()
          ..moveTo(head.left - 2, head.center.dy - 12)
          ..quadraticBezierTo(head.left, head.top - 14, head.center.dx, head.top - 14)
          ..quadraticBezierTo(head.right, head.top - 14, head.right + 2, head.center.dy - 12)
          ..close();
        final capColor = _shade(_hex(a.outfit), 0.15);
        canvas.drawPath(crown, Paint()..color = capColor);
        canvas.drawPath(crown, ink..strokeWidth = 2);
        final brim = RRect.fromRectAndRadius(
            Rect.fromLTWH(head.left - 6, head.center.dy - 16, head.width + 30, 9), const Radius.circular(5));
        canvas.drawRRect(brim, Paint()..color = _shade(capColor, 0.2));
      case 'hijab':
        // fabric edge over the forehead
        final edge = Path()
          ..moveTo(head.left - 4, head.center.dy)
          ..quadraticBezierTo(head.left - 2, head.top - 6, head.center.dx, head.top - 4)
          ..quadraticBezierTo(head.right + 2, head.top - 6, head.right + 4, head.center.dy)
          ..quadraticBezierTo(head.right - 6, head.top + 12, head.center.dx, head.top + 12)
          ..quadraticBezierTo(head.left + 6, head.top + 12, head.left - 4, head.center.dy)
          ..close();
        canvas.drawPath(edge, Paint()..color = _tint(hair, 0.06));
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CharacterPainter o) =>
      o.breath != breath || o.blink != blink || o.mood != mood || o.mouth != mouth || o.gaze != gaze || o.a != a;
}

/// The player's detective portraits (picked in the profile).
final List<AvatarSpec> kDetectives = [
  AvatarSpec({'gender': 'm', 'age': 'mid', 'skin': 1, 'hair': 'cap', 'hairColor': '#2a2a2a', 'beard': 'stubble', 'outfit': '#5d4037', 'accessory': 'none'}),
  AvatarSpec({'gender': 'f', 'age': 'young', 'skin': 0, 'hair': 'hijab', 'hairColor': '#263238', 'glasses': true, 'outfit': '#37474f', 'accessory': 'scarf'}),
  AvatarSpec({'gender': 'm', 'age': 'old', 'skin': 2, 'hair': 'bald', 'hairColor': '#bdbdbd', 'beard': 'mustache', 'glasses': true, 'outfit': '#263238', 'accessory': 'tie'}),
  AvatarSpec({'gender': 'f', 'age': 'mid', 'skin': 1, 'hair': 'hijab', 'hairColor': '#6d1b1b', 'outfit': '#3e2723', 'accessory': 'scarf'}),
  AvatarSpec({'gender': 'm', 'age': 'young', 'skin': 0, 'hair': 'curly', 'hairColor': '#1a1a1a', 'glasses': true, 'outfit': '#1b3a4b', 'accessory': 'none'}),
  AvatarSpec({'gender': 'm', 'age': 'mid', 'skin': 3, 'hair': 'short', 'hairColor': '#111111', 'beard': 'full', 'outfit': '#212121', 'accessory': 'badge'}),
];
