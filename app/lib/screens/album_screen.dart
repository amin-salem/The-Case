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
    return Container(
      key: const ValueKey('album-header'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14), border: Border.all(color: K.brass.withValues(alpha: 0.35))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${fa(a.solved)} مجرم از ${fa(a.total)} پرونده توی آلبومته', style: tBody(15, w: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('هر پرونده‌ای که حل کنی (شبانه، بایگانی یا آخر هفته) مجرمش یه کارت می‌شه. یه گروه رو کامل کنی، قاب مخصوص می‌گیری.',
            style: tBody(12.5, color: K.textSoft)),
        if (a.rewards.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final r in a.rewards)
              Expanded(
                child: Row(children: [
                  Opacity(opacity: r.owned ? 1 : 0.4, child: AvatarWithFrame(avatar: avatar, frame: r.id, size: 52)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.owned ? r.title : '${r.title}\n${fa(r.need)} گروه کامل',
                        style: tBody(12, color: r.owned ? K.brass : K.textSoft, w: FontWeight.w800)),
                  ),
                ]),
              ),
          ]),
        ],
      ]),
    );
  }

  List<Widget> _group(Album a, AlbumGroup g) {
    final cards = a.inGroup(g.key);
    final icon = kCategories[g.category]?.icon ?? Icons.folder_special_rounded;
    return [
      Padding(
        key: ValueKey('album-group-${g.key}'),
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Row(children: [
          Icon(icon, size: 18, color: g.complete ? K.brass : K.kraft),
          const SizedBox(width: 6),
          Expanded(child: Text(g.title, style: tDisplay(17))),
          Text(g.complete ? 'کامل شد' : '${fa(g.solved)} از ${fa(g.total)}',
              style: tBody(12.5, color: g.complete ? K.brass : K.textSoft, w: FontWeight.w800)),
        ]),
      ),
      LayoutBuilder(builder: (context, box) {
        const gap = 8.0;
        final w = (box.maxWidth - gap * 2) / 3;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final c in cards)
            SizedBox(
              width: w,
              height: w * 1.35,
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

/// One album card: the culprit's portrait (painted, or drawn in code when the case has none) for a solved case, a dark
/// silhouette with «؟» for the others. Always has graphics.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.card});
  final AlbumCard card;

  @override
  Widget build(BuildContext context) {
    final c = card;
    return Container(
      decoration: BoxDecoration(
        color: c.solved ? K.paper : K.night2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.solved ? K.brass : K.night3, width: c.solved ? 2 : 1),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox.expand(
              child: c.solved && c.culprit != null
                  ? FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SuspectPortrait(c.culprit!, size: 120))
                  : Container(
                      color: K.night,
                      child: Icon(Icons.person_rounded, size: 54, color: K.night3),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (c.solved) ...[
          Text(c.culpritName, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.ink, w: FontWeight.w900)),
          Text('پرونده ${fa(c.number)}', style: tBody(10.5, color: K.inkSoft)),
        ] else ...[
          Text('؟', style: tDisplay(16, color: K.textSoft)),
          Text(c.open ? 'باز برای تو' : '${fa(c.price)} سکه', maxLines: 1, style: tBody(10.5, color: K.brass, w: FontWeight.w800)),
        ],
      ]),
    );
  }
}
