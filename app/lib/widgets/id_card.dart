import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../screens/achievements_screen.dart' show kAchievementGroups;
import '../services/api.dart';
import '../theme.dart';

// =====================================================================================================================
// The detective ID card (app 1.44): one card per detective, dressed by his league. It is the profile's centre piece, it
// opens from a board row, and it is what he shares. Minimal on purpose: status is shown by material and colour, not words.
// =====================================================================================================================

/// League names, by the index the server sends (`weekboard.LEAGUES`).
const List<String> kLeagueNames = ['تازه‌کار', 'کارآگاه', 'بازرس', 'سرپرست'];

/// The league a profile rank (index into the server's ranks) belongs to. Same ranges as `weekboard.LEAGUE_FROM_RANK`:
/// ranks 0-3, 4-7, 8-11 and 12 and up.
int leagueOfRank(int rank) => rank >= 12 ? 3 : rank >= 8 ? 2 : rank >= 4 ? 1 : 0;

/// How a league looks: leather and copper, steel, black and gold, royal blue with a hologram.
class LeagueLook {
  const LeagueLook({
    required this.gradient,
    required this.texture,
    required this.textureOpacity,
    required this.textureBlend,
    required this.accent,
    required this.ink,
    required this.glow,
    required this.chip,
    required this.sheen,
    required this.holo,
    required this.shield,
  });

  final List<Color> gradient;
  final String texture;
  final double textureOpacity;
  final BlendMode textureBlend;
  final Color accent, ink, glow;
  final List<Color> chip;
  final double sheen; // 0 = none
  final bool holo;
  final String shield; // assets/leagues/league_N.webp

  Color get line => accent.withValues(alpha: 0.32);
  Color get edge => accent.withValues(alpha: 0.55);

  static LeagueLook of(int league) => _looks[league.clamp(0, _looks.length - 1)];

  static const List<LeagueLook> _looks = [
    LeagueLook(
      gradient: [Color(0xFF5A3D24), Color(0xFF3A2716), Color(0xFF24180D)],
      texture: 'assets/textures/kraft.webp',
      textureOpacity: 0.38,
      textureBlend: BlendMode.multiply,
      accent: Color(0xFFE2B27E),
      ink: Color(0xFFF6E8D6),
      glow: Color(0xFF9A6537),
      chip: [Color(0xFFE9B98A), Color(0xFFA8662F)],
      sheen: 0,
      holo: false,
      shield: 'assets/leagues/league_0.webp',
    ),
    LeagueLook(
      gradient: [Color(0xFF3C4757), Color(0xFF252D39), Color(0xFF141920)],
      texture: 'assets/textures/steel.webp',
      textureOpacity: 0.55,
      textureBlend: BlendMode.overlay,
      accent: Color(0xFFDCE5F1),
      ink: Color(0xFFF2F5F9),
      glow: Color(0xFF7F8EA3),
      chip: [Color(0xFFF2F5F9), Color(0xFF8E9AAB)],
      sheen: 0.35,
      holo: false,
      shield: 'assets/leagues/league_1.webp',
    ),
    LeagueLook(
      gradient: [Color(0xFF2B2414), Color(0xFF17140D), Color(0xFF0B0A07)],
      texture: 'assets/textures/paper.webp',
      textureOpacity: 0.07,
      textureBlend: BlendMode.screen,
      accent: Color(0xFFF4CF73),
      ink: Color(0xFFFBF1D8),
      glow: Color(0xFFE0A526),
      chip: [Color(0xFFFBE7A6), Color(0xFFC8901E)],
      sheen: 0.55,
      holo: false,
      shield: 'assets/leagues/league_2.webp',
    ),
    LeagueLook(
      gradient: [Color(0xFF1E3388), Color(0xFF14205A), Color(0xFF090F2E)],
      texture: 'assets/textures/steel.webp',
      textureOpacity: 0.35,
      textureBlend: BlendMode.overlay,
      accent: Color(0xFFF6D27A),
      ink: Color(0xFFF4F2FF),
      glow: Color(0xFF5A78FF),
      chip: [Color(0xFFFBE7A6), Color(0xFFC8901E)],
      sheen: 0.7,
      holo: true,
      shield: 'assets/leagues/league_3.webp',
    ),
  ];

  /// The soft glow at the top of the screen that carries the league colour.
  Color get pageGlow => glow.withValues(alpha: 0.30);
}

/// One recent badge on an ID card (title, its group for the icon, 0/1/2 = bronze/silver/gold).
class CardBadge {
  const CardBadge({required this.title, required this.group, required this.metal});
  final String title, group;
  final int metal;
}

/// Everything a card shows. Built from a profile (the player's own card) or from a board row (someone else's).
class IdCardData {
  const IdCardData({
    required this.name,
    required this.title,
    required this.avatarId,
    required this.league,
    this.memberNo = 0,
    this.since,
    this.solved = 0,
    this.stars = 0,
    this.bestStreak = 0,
    this.fastest = 0,
    this.rank = 0,
    this.inviteCode = '',
    this.recent = const [],
  });

  final String name, title, avatarId;
  final int league; // 0..3
  final int memberNo; // 0 = unknown (offline or an old server)
  final DateTime? since;
  final int solved, stars, bestStreak;
  final int fastest; // seconds, 0 = none yet
  final int rank; // place on the board it was opened from (0 = none)
  final String inviteCode; // only on the player's own card: the QR and the code on the back
  final List<CardBadge> recent;

  /// The player's own card. [c] (his player card from the server) fills what the profile does not have.
  factory IdCardData.mine(Profile p, PlayerCard? c) => IdCardData(
        name: p.nickname,
        title: p.rankTitle,
        avatarId: p.avatarId,
        league: leagueOfRank(p.rank),
        memberNo: c?.memberNo ?? 0,
        since: c?.since,
        solved: p.casesSolved,
        stars: p.starsTotal,
        bestStreak: p.bestStreak,
        fastest: c?.fastest ?? 0,
        inviteCode: p.inviteCode,
        recent: [for (final a in c?.recent ?? const <({String title, String group, int metal})>[]) CardBadge(title: a.title, group: a.group, metal: a.metal)],
      );

  /// Another detective's card, from the board row he was opened from and his player card.
  factory IdCardData.of(LeaderRow r, PlayerCard? c) => IdCardData(
        name: r.nickname,
        title: c != null && c.rankTitle.isNotEmpty ? c.rankTitle : r.rankTitle,
        avatarId: r.avatarId,
        league: c?.league ?? 0,
        memberNo: c?.memberNo ?? 0,
        since: c?.since,
        solved: c?.casesSolved ?? 0,
        stars: c?.starsTotal ?? 0,
        bestStreak: c?.bestStreak ?? 0,
        fastest: c?.fastest ?? 0,
        rank: r.rank,
        recent: [for (final a in c?.recent ?? const <({String title, String group, int metal})>[]) CardBadge(title: a.title, group: a.group, metal: a.metal)],
      );
}

// ---------------------------------------------------------------------------------------------------- small helpers

/// Gregorian date to the Persian (Jalali) calendar: [year, month, day].
List<int> toJalali(DateTime d) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy = d.year, gm = d.month, gd = d.day;
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + ((gy2 + 3) ~/ 4) - ((gy2 + 99) ~/ 100) + ((gy2 + 399) ~/ 400) + gd + gdm[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return [jy, jm, jd];
}

/// «۱۴۰۵/۰۶»: the year and month a detective joined.
String joinedText(DateTime d) {
  final j = toJalali(d.toLocal());
  return '${fa(j[0]).replaceAll('٬', '')}/${fa(j[1]).padLeft(2, '۰')}';
}

/// «۳:۴۱» for 221 seconds; «—» when there is none.
String fastestText(int seconds) {
  if (seconds <= 0) return '—';
  final m = seconds ~/ 60, s = seconds % 60;
  return '${fa(m)}:${fa(s).padLeft(2, '۰')}';
}

/// The card number: «۰۴۱۸۲», or «—» while it is unknown.
String memberNoText(int n) => n <= 0 ? '—' : fa(n).replaceAll('٬', '').padLeft(5, '۰');

// ------------------------------------------------------------------------------------------------------ the card

/// The card itself: front and back, flipping when tapped. [onFlip] tells the screen which side is up (for the dots).
class IdCard extends StatefulWidget {
  const IdCard({super.key, required this.data, this.boundaryKey, this.onFlip, this.startOnBack = false});
  final IdCardData data;
  final GlobalKey? boundaryKey; // wrap the front in a RepaintBoundary so it can be shared as a picture
  final ValueChanged<bool>? onFlip;
  final bool startOnBack;

  @override
  State<IdCard> createState() => _IdCardState();
}

class _IdCardState extends State<IdCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _back = false;

  @override
  void initState() {
    super.initState();
    _back = widget.startOnBack;
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650), value: _back ? 1 : 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _flip() {
    setState(() => _back = !_back);
    widget.onFlip?.call(_back);
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _c.value = _back ? 1 : 0;
    } else {
      _c.animateTo(_back ? 1 : 0, curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = LeagueLook.of(widget.data.league);
    return MediaQuery.withNoTextScaling(
      child: GestureDetector(
        key: const ValueKey('id-card'),
        behavior: HitTestBehavior.opaque,
        onTap: _flip,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: look.glow.withValues(alpha: 0.38), blurRadius: 40, offset: const Offset(0, 22), spreadRadius: -8),
              const BoxShadow(color: Color(0x80000000), blurRadius: 30, offset: Offset(0, 14)),
            ],
          ),
          child: AspectRatio(
            aspectRatio: 358 / 226,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final angle = _c.value * math.pi;
                final showBack = angle > math.pi / 2;
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0011)
                    ..rotateY(angle),
                  child: showBack
                      ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationY(math.pi),
                          child: _Face(look: look, child: _Back(data: widget.data, look: look)),
                        )
                      : RepaintBoundary(
                          key: widget.boundaryKey,
                          child: _Face(look: look, child: _Front(data: widget.data, look: look)),
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's body: league material, a fine wave pattern, a one-time light sweep. Content is laid out on a 358 x 226
/// canvas that scales to the card's width (a narrow phone shrinks the card, never breaks it).
class _Face extends StatefulWidget {
  const _Face({required this.look, required this.child});
  final LeagueLook look;
  final Widget child;

  @override
  State<_Face> createState() => _FaceState();
}

class _FaceState extends State<_Face> with SingleTickerProviderStateMixin {
  late final AnimationController _sheen;

  @override
  void initState() {
    super.initState();
    // one sweep when the card appears (not a loop: a looping animation would keep every screen "busy")
    _sheen = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (!reduce && widget.look.sheen > 0) _sheen.forward();
    });
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: l.gradient, stops: const [0, .55, 1]),
          ),
        ),
        if (l.holo)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment(.6, -1.1), radius: 1.2, colors: [Color(0x737FA2FF), Color(0x007FA2FF)]),
            ),
          ),
        Opacity(
          opacity: l.textureOpacity,
          child: Image.asset(l.texture, fit: BoxFit.cover, color: null, colorBlendMode: l.textureBlend, errorBuilder: (_, __, ___) => const SizedBox()),
        ),
        CustomPaint(painter: _WavePainter(l.accent.withValues(alpha: 0.14))),
        if (l.holo)
          Opacity(
            opacity: 0.38,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: SweepGradient(
                  center: const Alignment(-.6, .6),
                  colors: [
                    const Color(0x00FF78BE),
                    const Color(0x4DFF78BE),
                    const Color(0x4D78DCFF),
                    const Color(0x4DFFE678),
                    const Color(0x00FF78BE),
                  ],
                ),
              ),
            ),
          ),
        FittedBox(fit: BoxFit.fill, child: SizedBox(width: 358, height: 226, child: widget.child)),
        if (l.sheen > 0)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _sheen,
              builder: (context, _) => CustomPaint(painter: _SheenPainter(_sheen.value, l.sheen)),
            ),
          ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: l.edge, width: 1)),
          ),
        ),
      ]),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (var k = 0; k < 9; k++) {
      final path = Path();
      final base = size.height * (0.18 + k * 0.1);
      for (double x = -10; x <= size.width + 10; x += 6) {
        final y = base + 3.2 * math.sin(x / 22 + k * .7);
        if (x == -10) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => old.color != color;
}

class _SheenPainter extends CustomPainter {
  _SheenPainter(this.t, this.strength);
  final double t, strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final x = size.width * (1.3 - t * 1.8); // right to left (RTL)
    final rect = Rect.fromLTWH(x - 40, -10, 80, size.height + 20);
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        const Color(0x00FFFFFF),
        Color.fromRGBO(255, 255, 255, 0.5 * strength),
        const Color(0x00FFFFFF),
      ]).createShader(rect);
    canvas.save();
    canvas.translate(x, size.height / 2);
    canvas.rotate(0.31);
    canvas.translate(-x, -size.height / 2);
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheenPainter old) => old.t != t;
}

// ------------------------------------------------------------------------------------------------------- the front

class _Front extends StatelessWidget {
  const _Front({required this.data, required this.look});
  final IdCardData data;
  final LeagueLook look;

  Widget _label(String t) => Text(t, style: tBody(9.5, color: look.ink.withValues(alpha: 0.5), w: FontWeight.w700).copyWith(height: 1.2));

  @override
  Widget build(BuildContext context) {
    final d = data;
    return Stack(children: [
      // top strip: shield, title, the game's name
      PositionedDirectional(
        top: 0,
        start: 0,
        end: 0,
        height: 40,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: look.line))),
          child: Row(children: [
            Image.asset(look.shield, width: 28, height: 28, fit: BoxFit.contain),
            const SizedBox(width: 8),
            Expanded(child: Text('کارت شناسایی کارآگاه', maxLines: 1, style: tBody(12, color: look.ink, w: FontWeight.w900).copyWith(height: 1.2))),
            Text('پرونده', style: tDisplay(18, color: look.accent).copyWith(height: 1.1)),
          ]),
        ),
      ),
      // the photo, like a national ID: portrait rectangle
      PositionedDirectional(
        top: 54,
        start: 16,
        width: 96,
        height: 120,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: const Color(0x40000000),
            border: Border.all(color: look.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset('assets/avatars/${d.avatarId}.webp',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => const Icon(Icons.person_rounded, size: 56, color: K.textSoft)),
        ),
      ),
      // the chip
      PositionedDirectional(
        end: 18,
        top: 60,
        child: Container(
          width: 42,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: look.chip),
            border: Border.all(color: const Color(0x4D000000)),
          ),
          child: CustomPaint(painter: _ChipPainter()),
        ),
      ),
      // the faint copy of the photo (a security feature of real cards)
      PositionedDirectional(
        end: 18,
        bottom: 18,
        width: 42,
        height: 52,
        child: Opacity(
          opacity: 0.22,
          child: ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset('assets/avatars/${d.avatarId}.webp',
                  fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ),
        ),
      ),
      // the fields
      PositionedDirectional(
        top: 54,
        start: 128,
        end: 74,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _label('نام'),
          FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: Text(d.name, maxLines: 1, style: tDisplay(28, color: look.ink).copyWith(height: 1.05))),
          const SizedBox(height: 6),
          _label('درجه'),
          Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13.5, color: look.accent, w: FontWeight.w900).copyWith(height: 1.25)),
          const SizedBox(height: 7),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('شماره'),
                Text(memberNoText(d.memberNo), style: tBody(12.5, color: look.ink, w: FontWeight.w800).copyWith(height: 1.25)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label('عضویت'),
                Text(d.since == null ? '—' : joinedText(d.since!),
                    maxLines: 1, style: tBody(12.5, color: look.ink, w: FontWeight.w800).copyWith(height: 1.25)),
              ]),
            ),
          ]),
        ]),
      ),
      if (d.rank > 0)
        PositionedDirectional(
          start: 16,
          bottom: 16,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0x4D000000), borderRadius: BorderRadius.circular(999)),
            child: Text('رتبه‌ی ${fa(d.rank)}', style: tBody(12, color: look.accent, w: FontWeight.w900).copyWith(height: 1.2)),
          ),
        ),
    ]);
  }
}

class _ChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = const Color(0x61000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final w = s.width, h = s.height;
    canvas.drawLine(Offset(w * .36, 0), Offset(w * .36, h * .31), p);
    canvas.drawLine(Offset(w * .64, 0), Offset(w * .64, h * .31), p);
    canvas.drawLine(Offset(w * .36, h * .69), Offset(w * .36, h), p);
    canvas.drawLine(Offset(w * .64, h * .69), Offset(w * .64, h), p);
    canvas.drawLine(Offset(0, h * .34), Offset(w * .33, h * .34), p);
    canvas.drawLine(Offset(0, h * .66), Offset(w * .33, h * .66), p);
    canvas.drawLine(Offset(w, h * .34), Offset(w * .67, h * .34), p);
    canvas.drawLine(Offset(w, h * .66), Offset(w * .67, h * .66), p);
    canvas.drawLine(Offset(w * .4, h * .5), Offset(w * .6, h * .5), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// -------------------------------------------------------------------------------------------------------- the back

class _Back extends StatelessWidget {
  const _Back({required this.data, required this.look});
  final IdCardData data;
  final LeagueLook look;

  Widget _stat(String value, String label, {bool accent = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(value, maxLines: 1, style: tDisplay(26, color: accent ? look.accent : look.ink).copyWith(height: 1.05)),
        Text(label, maxLines: 1, style: tBody(10.5, color: look.ink.withValues(alpha: 0.55), w: FontWeight.w700).copyWith(height: 1.3)),
      ]);

  @override
  Widget build(BuildContext context) {
    final d = data;
    const qrInk = Color(0xFF15120A);
    return Stack(children: [
      PositionedDirectional(
        top: 24,
        start: 20,
        end: 128,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: _stat(fa(d.solved), 'پرونده حل کرده', accent: true)),
            Expanded(child: _stat(fa(d.stars), 'پلاک')),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _stat('${fa(d.bestStreak)} شب', 'بهترین زنجیره')),
            Expanded(child: _stat(fastestText(d.fastest), 'سریع‌ترین حل')),
          ]),
        ]),
      ),
      // own card: the QR of the store page and the invite code. Someone else's card: his league shield.
      PositionedDirectional(
        top: 20,
        end: 18,
        width: 92,
        child: d.inviteCode.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Image.asset(look.shield, width: 92, height: 92, fit: BoxFit.contain),
              )
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFF6F2E8), borderRadius: BorderRadius.circular(10)),
                  child: QrImageView(
                    data: Api.i.shareUrl,
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFFF6F2E8),
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: qrInk),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: qrInk),
                  ),
                ),
                const SizedBox(height: 4),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(d.inviteCode, style: tBody(10.5, color: look.accent, w: FontWeight.w800).copyWith(height: 1.2)),
                ),
              ]),
      ),
      // the strip at the bottom: the game's line and its icon
      PositionedDirectional(
        start: 0,
        end: 0,
        bottom: 0,
        height: 46,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(color: const Color(0x38000000), border: Border(top: BorderSide(color: look.line))),
          child: Row(children: [
            Expanded(
              child: Text.rich(
                TextSpan(style: tBody(12.5, color: look.ink.withValues(alpha: 0.75), w: FontWeight.w700), children: [
                  const TextSpan(text: 'هر شب یک '),
                  TextSpan(text: 'پرونده', style: tBody(12.5, color: look.accent, w: FontWeight.w900)),
                  const TextSpan(text: ' تازه'),
                ]),
                maxLines: 1,
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                boxShadow: [BoxShadow(color: look.edge, spreadRadius: 1), const BoxShadow(color: Color(0x73000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/icon/logo.webp', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------------------------------ small shared widgets

/// The two dots under a card: which side is up. Minimal: the one that is up is long and in the league colour.
class CardDots extends StatelessWidget {
  const CardDots({super.key, required this.back, required this.look});
  final bool back;
  final LeagueLook look;

  Widget _dot(bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: on ? 20 : 6,
        height: 6,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: on ? look.accent : const Color(0x33FFFFFF)),
      );

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [_dot(!back), const SizedBox(width: 6), _dot(back)]);
}

/// A medal base with the badge's icon in its hole. [metal]: 0 bronze, 1 silver, 2 gold.
class MedalBadge extends StatelessWidget {
  const MedalBadge({super.key, required this.group, required this.metal, this.size = 64});
  final String group;
  final int metal;
  final double size;

  static const _bases = ['assets/medals/medal_bronze.webp', 'assets/medals/medal_silver.webp', 'assets/medals/medal_gold.webp'];
  static const _inks = [Color(0xFFEFC394), Color(0xFFE1E5EB), Color(0xFFF4CF73)];

  @override
  Widget build(BuildContext context) {
    final m = metal.clamp(0, 2);
    final icon = kAchievementGroups[group]?.$1 ?? Icons.military_tech_rounded;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        Image.asset(_bases[m], width: size, height: size, fit: BoxFit.contain),
        Icon(icon, size: size * 0.38, color: _inks[m]),
      ]),
    );
  }
}

/// The three newest badges under a card: medal and name, nothing else.
class RecentBadges extends StatelessWidget {
  const RecentBadges({super.key, required this.badges});
  final List<CardBadge> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const SizedBox.shrink();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final b in badges)
        Expanded(
          child: Column(children: [
            MedalBadge(group: b.group, metal: b.metal),
            const SizedBox(height: 4),
            Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: tBody(12, color: const Color(0xFFDAD5C9), w: FontWeight.w800).copyWith(height: 1.35)),
          ]),
        ),
      for (var i = badges.length; i < 3; i++) const Expanded(child: SizedBox()),
    ]);
  }
}

/// Renders the card under [boundaryKey] (its front) to a PNG and shares it with [text] through the share sheet.
/// Returns false when the picture could not be made (the caller says so).
Future<bool> shareCardImage(GlobalKey boundaryKey, String text) async {
  try {
    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return false;
    final image = await ro.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return false;
    await SharePlus.instance.share(ShareParams(
      text: text,
      files: [XFile.fromData(bytes.buffer.asUint8List(), mimeType: 'image/png', name: 'card.png')],
      fileNameOverrides: const ['card.png'],
    ));
    return true;
  } catch (e) {
    debugPrint('card image: $e');
    return false;
  }
}
