import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../models/avatars.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import 'avatar_frame.dart';

/// «قفسه‌ی افتخار»: what the shelf shows, worked out from real data only (the profile, the avatar/frame catalog
/// and the case list). A part whose data is not available is null/empty and its line is hidden.
class ShelfData {
  const ShelfData({
    required this.avatar,
    required this.equippedFrame,
    required this.ownedFrames,
    required this.nextFrames,
    required this.threePlaque,
    required this.casesSolved,
    required this.bestStreak,
    required this.catalogKnown,
    required this.casesKnown,
  });

  final String avatar;
  final String equippedFrame;

  /// Frames the player owns (the equipped one first).
  final List<AvatarItem> ownedFrames;

  /// Up to [maxNext] locked frames: the closest goals first, then the cheapest shop frame.
  final List<AvatarItem> nextFrames;

  /// Solved with three plaques, newest case number first.
  final List<CaseRow> threePlaque;
  final int casesSolved, bestStreak;
  final bool catalogKnown, casesKnown;

  static const maxNext = 3;

  static ShelfData build({required Profile profile, AvatarCatalog? catalog, CasesList? cases}) {
    var owned = <AvatarItem>[];
    var next = <AvatarItem>[];
    if (catalog != null) {
      owned = [for (final f in catalog.frames) if (f.owned) f];
      owned.sort((a, b) => (a.id == catalog.frame ? 0 : 1).compareTo(b.id == catalog.frame ? 0 : 1)); // stable: equipped first
      final goals = [for (final f in catalog.frames) if (!f.owned && !f.isShop) f]
        ..sort((a, b) => b.fraction.compareTo(a.fraction));
      final shop = [for (final f in catalog.frames) if (!f.owned && f.isShop) f]..sort((a, b) => a.price.compareTo(b.price));
      next = [...goals.take(shop.isEmpty ? maxNext : maxNext - 1), ...shop.take(1)];
    }
    final rows = <CaseRow>[];
    if (cases != null) {
      final seen = <String>{};
      for (final r in [if (cases.today != null) cases.today!, if (cases.weekly != null) cases.weekly!, ...cases.archive]) {
        if (r.solved && r.stars >= 3 && seen.add(r.id)) rows.add(r);
      }
      rows.sort((a, b) => b.number.compareTo(a.number));
    }
    return ShelfData(
      avatar: catalog?.avatar ?? profile.avatarId,
      equippedFrame: catalog?.frame ?? profile.avatarFrame,
      ownedFrames: owned,
      nextFrames: next,
      threePlaque: rows,
      casesSolved: profile.casesSolved,
      bestStreak: profile.bestStreak,
      catalogKnown: catalog != null,
      casesKnown: cases != null,
    );
  }

  /// «۴۷ پرونده · ۲۹ با سه پلاک · بهترین زنجیره ۶۲ شب»; each part is left out when it is 0 or unknown.
  String get headline => [
        if (casesSolved > 0) '${fa(casesSolved)} پرونده',
        if (casesKnown && threePlaque.isNotEmpty) '${fa(threePlaque.length)} با سه پلاک',
        if (bestStreak > 0) 'بهترین زنجیره ${fa(bestStreak)} شب',
      ].join(' · ');
}

/// The shelf of the profile page: frames (owned and next), three-plaque cases on paper cards, and the headline numbers.
/// Wrap it in a [RepaintBoundary] with [boundaryKey] to turn it into a picture ([shareShelfImage]).
class HonorShelf extends StatelessWidget {
  const HonorShelf({super.key, required this.data, this.onFrames, this.onCase, this.boundaryKey});
  final ShelfData data;

  /// A frame (owned or locked) was tapped: the app opens the face-and-frame screen on its frames tab.
  final VoidCallback? onFrames;
  final ValueChanged<CaseRow>? onCase;
  final GlobalKey? boundaryKey;

  static const maxOwnedShown = 7;
  static const maxCards = 3;

  @override
  Widget build(BuildContext context) {
    final headline = data.headline;
    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(16), border: Border.all(color: K.brass.withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.emoji_events_rounded, color: K.brass, size: 22),
            const SizedBox(width: 6),
            Text('قفسه‌ی افتخار', style: tDisplay(16.5)),
          ]),
          if (headline.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(headline, key: const ValueKey('shelf-headline'), style: tBody(12.5, color: K.textSoft).copyWith(height: 1.55)),
          ],
          if (data.catalogKnown) ...[const SizedBox(height: 10), _frames()],
          if (data.casesKnown) ...[const SizedBox(height: 10), _cases(context)],
        ]),
      ),
    );
  }

  Widget _plank(Widget child) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
        decoration: BoxDecoration(
          color: const Color(0xFF3A2C1C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF4A3A25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          child,
          Container(
            height: 9,
            margin: const EdgeInsets.fromLTRB(-10, 8, -10, 0),
            decoration: const BoxDecoration(
              color: Color(0xFF5A4128),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
              boxShadow: [BoxShadow(color: Color(0xFF2A1D10), offset: Offset(0, 3))],
            ),
          ),
        ]),
      );

  // ------------------------------------------------------------------ frames

  Widget _frames() {
    final owned = data.ownedFrames;
    final shown = owned.take(maxOwnedShown).toList();
    final more = owned.length - shown.length;
    return _plank(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('قاب‌ها', style: tBody(12.5, color: const Color(0xFFE9CF9A), w: FontWeight.w900)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.start, children: [
        for (final f in shown)
          _FrameCell(
            key: ValueKey('shelf-frame-${f.id}'),
            onTap: onFrames,
            label: f.title,
            circle: AvatarWithFrame(avatar: data.avatar, frame: f.id, size: 58, animate: f.id == data.equippedFrame),
          ),
        if (more > 0)
          _FrameCell(
            key: const ValueKey('shelf-frames-more'),
            onTap: onFrames,
            label: '',
            circle: SizedBox(width: 58, height: 58, child: Center(child: Text('+${fa(more)}', style: tBody(13, color: K.textSoft, w: FontWeight.w800)))),
          ),
        for (final f in data.nextFrames)
          _FrameCell(
            key: ValueKey('shelf-next-${f.id}'),
            onTap: onFrames,
            label: f.title,
            hint: f.isShop ? 'فروشگاه' : (f.goal.isNotEmpty ? f.goal : null),
            circle: CustomPaint(
              painter: _DashedCirclePainter(color: const Color(0xFF6B5A40)),
              child: SizedBox(
                width: 58,
                height: 58,
                child: Center(child: Icon(f.isShop ? Icons.storefront_rounded : Icons.lock_outline_rounded, size: 22, color: const Color(0xFF8C7A5C))),
              ),
            ),
          ),
      ]),
      if (owned.isEmpty && data.nextFrames.isEmpty)
        Padding(padding: const EdgeInsets.only(top: 2), child: Text('هنوز قابی نیست', style: tBody(12, color: K.textSoft))),
    ]));
  }

  // ------------------------------------------------------------------ cases

  Widget _cases(BuildContext context) {
    final all = data.threePlaque;
    final more = all.length > maxCards ? all.length - (maxCards - 1) : 0;
    final cards = more > 0 ? all.take(maxCards - 1).toList() : all;
    const tilts = [-0.035, 0.026, -0.018];
    return _plank(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('پرونده‌های سه‌پلاکی', style: tBody(12.5, color: const Color(0xFFE9CF9A), w: FontWeight.w900)),
      const SizedBox(height: 8),
      if (all.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('هنوز پرونده‌ی سه‌پلاکی نداری؛ یه پرونده رو با هر سه پلاک حل کن تا اینجا بنشینه.',
              key: const ValueKey('shelf-cases-empty'), style: tBody(12, color: K.textSoft).copyWith(height: 1.6)),
        )
      else
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Transform.rotate(
                  angle: tilts[i % tilts.length],
                  child: _PaperCard(key: ValueKey('shelf-case-${cards[i].id}'), row: cards[i], onTap: onCase == null ? null : () => onCase!(cards[i])),
                ),
              ),
            ],
            for (int i = cards.length + (more > 0 ? 1 : 0); i < maxCards; i++) ...[const SizedBox(width: 8), const Expanded(child: SizedBox())],
            if (more > 0) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  key: const ValueKey('shelf-cases-more'),
                  constraints: const BoxConstraints(minHeight: 72),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF6B5A40))),
                  child: Text('+${fa(more)}', style: tBody(13, color: K.textSoft, w: FontWeight.w800)),
                ),
              ),
            ],
          ]),
        ),
    ]));
  }
}

class _PaperCard extends StatelessWidget {
  const _PaperCard({super.key, required this.row, this.onTap});
  final CaseRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: const Color(0xFFE9DDBF), borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('پرونده‌ی ${fa(row.number)}', style: tBody(11, color: const Color(0xFF2A2620), w: FontWeight.w900)),
            const SizedBox(height: 6),
            Text('★★★', style: tBody(12, color: const Color(0xFFB23A2A), w: FontWeight.w800)),
          ]),
        ),
      );
}

class _FrameCell extends StatelessWidget {
  const _FrameCell({super.key, required this.circle, required this.label, this.hint, this.onTap});
  final Widget circle;
  final String label;
  final String? hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 58, maxWidth: 78, minHeight: 48),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            circle,
            if (label.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: tBody(10.5, color: K.text, w: FontWeight.w700).copyWith(height: 1.3)),
            ],
            if (hint != null && hint!.isNotEmpty)
              Text(hint!, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: tBody(10, color: const Color(0xFF8C7A5C)).copyWith(height: 1.3)),
          ]),
        ),
      );
}

class _DashedCirclePainter extends CustomPainter {
  _DashedCirclePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 2;
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const dashes = 18;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter old) => old.color != color;
}

/// The text that goes with the shelf picture: spoiler-free (no case is named), the invite code and the usual link.
String shelfShareText(Profile p, ShelfData d, {int? friendCoins}) {
  final coins = friendCoins ?? Api.i.inviteNewPlayer;
  return [
    'قفسه‌ی افتخار من توی «پرونده» 🕵️ ${d.headline}'.trim(),
    'موقع شروع کد دعوت من رو بزن تا ${fa(coins)} سکه هدیه بگیری: ${p.inviteCode}',
    Api.i.shareUrl,
  ].join('\n');
}

/// Renders the shelf under [boundaryKey] to a PNG and shares it with [text] through the usual share sheet.
/// Returns false when the picture could not be made (the caller says so); the text is never lost silently.
Future<bool> shareShelfImage(GlobalKey boundaryKey, String text) async {
  try {
    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return false;
    final image = await ro.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return false;
    final png = bytes.buffer.asUint8List();
    await SharePlus.instance.share(ShareParams(
      text: text,
      files: [XFile.fromData(png, mimeType: 'image/png', name: 'shelf.png')],
      fileNameOverrides: const ['shelf.png'],
    ));
    return true;
  } catch (e) {
    debugPrint('shelf image: $e');
    return false;
  }
}
