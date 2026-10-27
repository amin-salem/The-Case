import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/album.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/avatar_frame.dart';
import '../widgets/category.dart';
import '../widgets/character.dart';
import '../widgets/offline.dart';
import 'archive_screen.dart';

/// «آلبوم مجرم‌ها»: every case the player solved puts its culprit here as a card. Cases not solved yet are dark
/// silhouettes (the server sends no title and no culprit for them); one tap on one opens that case through the
/// normal archive flow. Finishing a whole group gives a permanent frame.
class AlbumScreen extends StatefulWidget {
  const AlbumScreen({super.key});

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  Album? _album;
  String? _error;
  int _filter = 0; // 0 all, 1 groups with cards, 2 groups still open

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await Api.i.album();
      if (!mounted) return;
      setState(() {
        _album = a;
        _error = null;
      });
      if (a.newRewards.isNotEmpty) toast(context, 'قاب تازه گرفتی: ${a.newRewards.join('، ')}');
    } catch (e) {
      if (mounted) setState(() => _error = Api.friendly(e));
    }
  }

  /// A silhouette was tapped: find the case in the list and open it the way the archive does (it asks before it
  /// charges anything). Never a pop-up that blocks; the player can step back at once.
  Future<void> _invite(AlbumCard card) async {
    if (!needOnline(context)) return;
    try {
      final list = await Api.i.cases();
      final rows = [if (list.today != null) list.today!, if (list.weekly != null) list.weekly!, ...list.archive];
      final row = rows.where((r) => r.id == card.id).firstOrNull;
      if (!mounted) return;
      if (row == null) {
        toast(context, 'این پرونده هنوز توی بایگانی نیست.');
        return;
      }
      await openCaseRow(context, row);
      if (mounted) _load();
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
  }

  void _show(AlbumCard card) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.night2,
      builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(18), child: _detail(card))),
    );
  }

  Widget _detail(AlbumCard c) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 150, child: AspectRatio(aspectRatio: 0.8, child: _CardFace(card: c))),
      const SizedBox(height: 12),
      Text(c.culpritName, style: tDisplay(22)),
      Text(c.culpritRole, style: tBody(14, color: K.textSoft)),
      const SizedBox(height: 8),
      if (c.line.isNotEmpty) Text(c.line, textAlign: TextAlign.center, style: tBody(14)),
      const SizedBox(height: 8),
      Text('پرونده‌ی ${fa(c.number)} «${c.title}»', textAlign: TextAlign.center, style: tBody(13.5, color: K.brass, w: FontWeight.w800)),
      const SizedBox(height: 6),
      Plaques(count: c.stars, size: 22),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final a = _album;
    return Scaffold(
      appBar: AppBar(backgroundColor: K.night, title: Text('آلبوم مجرم‌ها', style: tDisplay(20))),
      body: GrainBackground(
        child: SafeArea(
          top: false,
          child: a == null
              ? Center(
                  child: _error == null
                      ? const CircularProgressIndicator(color: K.brass)
                      : Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: tBody(15))),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: K.stamp,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                    children: [
                      _header(a),
                      for (final g in a.groups) ..._group(a, g),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _header(Album a) {
    final avatar = Api.i.profile?.avatarId ?? 'det_01';
    final pct = a.total == 0 ? 0.0 : a.solved / a.total;
    final stars = a.cards.where((c) => c.solved).fold<int>(0, (n, c) => n + c.stars);
    final next = a.nextGroup;
    final reach = a.frameWithinReach;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        key: const ValueKey('album-header'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2B2414), K.night2]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: K.brass.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(
              width: 84,
              height: 84,
              child: CustomPaint(
                painter: _RingPainter(pct),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(fa(a.solved), style: tDisplay(24)),
                    Text('از ${fa(a.total)}', style: tBody(10.5, color: K.textSoft)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('مجرمِ توی آلبومت', style: tBody(12, color: K.textSoft)),
                Text('${fa(a.solved)} مجرم از ${fa(a.total)} پرونده', style: tDisplay(19, color: K.brass)),
                const SizedBox(height: 4),
                Text('هر پرونده‌ای که حل کنی مجرمش یه کارت می‌شه.', style: tBody(12, color: K.textSoft)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _stat(fa(a.groupsDone), 'گروه کامل'),
            const SizedBox(width: 8),
            _stat(fa(stars), 'پلاک جمع‌شده'),
            const SizedBox(width: 8),
            _stat('${fa((pct * 100).round())}٪', 'آلبوم پر شده'),
          ]),
        ]),
      ),
      if (next != null) ...[
        const SizedBox(height: 10),
        Container(
          key: const ValueKey('album-next'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: K.night2, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.brass.withValues(alpha: 0.5))),
          child: Row(children: [
            const Icon(Icons.flag_rounded, color: K.brass, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${fa(next.total - next.solved)} پرونده تا کامل شدن «${next.title}»', style: tBody(14, w: FontWeight.w900)),
                Text(reach != null ? 'با این گروه، «${reach.title}» رو می‌گیری.' : 'هر گروه کامل، یه قدم نزدیک‌تر به قاب بعدی.',
                    style: tBody(12, color: K.textSoft)),
              ]),
            ),
          ]),
        ),
      ],
      if (a.rewards.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [
          for (int i = 0; i < a.rewards.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: _reward(a.rewards[i], avatar)),
          ],
        ]),
      ],
      const SizedBox(height: 14),
      Row(children: [
        for (final f in [(0, 'همه'), (1, 'جمع‌شده‌ها'), (2, 'مونده‌ها')])
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: GestureDetector(
              key: ValueKey('album-filter-${f.$1}'),
              onTap: () => setState(() => _filter = f.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                    color: _filter == f.$1 ? K.brass : K.night2,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _filter == f.$1 ? K.brass : K.night3)),
                child: Text(f.$2, style: tBody(13, w: FontWeight.w800, color: _filter == f.$1 ? K.ink : K.textSoft)),
              ),
            ),
          ),
      ]),
    ]);
  }

  Widget _stat(String v, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [Text(v, style: tDisplay(20)), Text(label, style: tBody(10.5, color: K.textSoft))]),
        ),
      );

  Widget _reward(AlbumReward r, String avatar) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.night3)),
        child: Row(children: [
          Opacity(opacity: r.owned ? 1 : 0.4, child: AvatarWithFrame(avatar: avatar, frame: r.id, size: 50)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13, w: FontWeight.w900, color: r.owned ? K.brass : K.text)),
              Text(r.owned ? 'مال توئه' : '${fa(r.need)} گروه کامل', style: tBody(11, color: K.textSoft)),
            ]),
          ),
        ]),
      );

  List<Widget> _group(Album a, AlbumGroup g) {
    if (_filter == 1 && g.solved == 0) return const [];
    if (_filter == 2 && g.complete) return const [];
    final cards = a.inGroup(g.key);
    final icon = kCategories[g.category]?.icon ?? Icons.folder_special_rounded;
    return [
      Padding(
        key: ValueKey('album-group-${g.key}'),
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: g.complete ? K.brass : K.night2, borderRadius: BorderRadius.circular(9), border: Border.all(color: g.complete ? K.brass : K.night3)),
              child: Icon(g.complete ? Icons.check_rounded : icon, size: 19, color: g.complete ? K.ink : K.kraft),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(g.title, style: tDisplay(19))),
            Text(g.complete ? 'کامل شد' : '${fa(g.solved)} از ${fa(g.total)}',
                style: tBody(12.5, color: g.complete ? K.brass : K.textSoft, w: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (int i = 0; i < g.total; i++)
              Expanded(
                child: Container(
                  height: 5,
                  margin: EdgeInsetsDirectional.only(end: i == g.total - 1 ? 0 : 3),
                  decoration: BoxDecoration(color: i < g.solved ? K.brass : K.night3, borderRadius: BorderRadius.circular(3)),
                ),
              ),
          ]),
        ]),
      ),
      LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        final w = (box.maxWidth - gap * 2) / 3;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final c in cards)
            SizedBox(
              width: w,
              height: w * 1.4,
              child: GestureDetector(
                key: ValueKey('album-card-${c.id}'),
                onTap: () => c.solved ? _show(c) : _invite(c),
                child: _CardFace(card: c),
              ),
            ),
        ]);
      }),
    ];
  }
}

/// The ring of the album: fills from the top and turns counter-clockwise (the app reads right to left).
class _RingPainter extends CustomPainter {
  _RingPainter(this.frac);
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - 5);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 8..color = K.night3);
    if (frac > 0) {
      canvas.drawArc(r, -math.pi / 2, -math.pi * 2 * frac.clamp(0.0, 1.0), false,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round..color = K.brass);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.frac != frac;
}

/// One album card: the culprit's portrait fills the card for a solved case (name and plaques over a dark fade), a dark
/// silhouette with «؟» for the others. Always has graphics.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card});
  final AlbumCard card;

  @override
  Widget build(BuildContext context) {
    final c = card;
    final gold = c.solved && c.stars >= 3;
    return Container(
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold ? K.brass : (c.solved ? K.kraft.withValues(alpha: 0.7) : K.night3), width: gold ? 2 : 1),
        boxShadow: gold ? [BoxShadow(color: K.brass.withValues(alpha: 0.28), blurRadius: 10)] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(fit: StackFit.expand, children: [
          if (c.solved && c.culprit != null)
            FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SuspectPortrait(c.culprit!, size: 120))
          else
            Container(color: K.night, child: Icon(Icons.person_rounded, size: 64, color: K.night3)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 18, 6, 6),
              decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xE6000000)])),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (c.solved) ...[
                  Text(c.culpritName, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: Colors.white, w: FontWeight.w900)),
                  Text('پرونده ${fa(c.number)}', style: tBody(10, color: Colors.white70)),
                  const SizedBox(height: 2),
                  Plaques(count: c.stars, size: 11),
                ] else ...[
                  Text('مجرم ناشناس', maxLines: 1, style: tBody(11.5, color: K.textSoft, w: FontWeight.w800)),
                  Text(c.open ? 'باز برای تو' : '${fa(c.price)} سکه', maxLines: 1, style: tBody(10.5, color: K.brass, w: FontWeight.w800)),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
