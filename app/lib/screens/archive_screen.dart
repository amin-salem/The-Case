import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/offline.dart';
import '../widgets/rate_card.dart';
import '../widgets/scene.dart';
import 'case_screen.dart';
import 'dialogs.dart';
import 'shop_screen.dart';

/// Opens a case from a list: an old locked case is unlocked with coins first (after asking).
/// Returns once the player leaves the case.
Future<void> openCaseRow(BuildContext context, CaseRow row) async {
  if (row.locked) {
    if (!needOnline(context)) return;
    final ok = row.weekend
        ? await confirm(context, 'باز کردن پرونده‌ی آخر هفته',
            'این پرونده‌ی آخر هفته بسته شده. هر دو فصلش با هم باز می‌شه و جایزه‌ی پرونده‌ی عادی داره. قیمتش از پرونده‌های دیگه‌ی بایگانی بیشتره: ${fa(row.unlockCost)} سکه.',
            'باز کن · ${fa(row.unlockCost)} سکه')
        : await confirm(context, 'باز کردن پرونده‌ی قدیمی',
            'این پرونده مال روزهای قبله. با ${fa(row.unlockCost)} سکه بازش کن.', 'باز کن');
    if (!ok || !context.mounted) return;
    try {
      await Api.i.unlockCase(row.id);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      if (e.code == 'not_enough_coins') {
        await showNeedCoins(context, row.unlockCost);
      } else {
        toast(context, Api.friendly(e));
      }
      return;
    } catch (e) {
      if (context.mounted) toast(context, Api.friendly(e));
      return;
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaseScreen(caseId: row.id)));
  Sfx.i.ambient('amb_home', volume: Sfx.homeVolume);
}

enum _Filter { all, unsolved, free, three, unrated }

enum _Sort { newest, oldest, best, popular }

/// Every earlier case: a progress header, filters and sorting, and wide cards with the scene, the state
/// (stars / price / lost) and the detectives' rating.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<CaseRow>? _rows;
  String? _error;
  _Filter _filter = _Filter.all;
  _Sort _sort = _Sort.newest;

  static const _filterLabels = {
    _Filter.all: 'همه',
    _Filter.unsolved: 'حل‌نشده',
    _Filter.free: 'باز',
    _Filter.three: '۳ پلاک',
    _Filter.unrated: 'امتیاز ندادم',
  };
  static const _sortLabels = {
    _Sort.newest: 'تازه‌ترین',
    _Sort.oldest: 'قدیمی‌ترین',
    _Sort.best: 'بهترین امتیاز',
    _Sort.popular: 'محبوب‌ترین',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await Api.i.cases();
      if (mounted) {
        setState(() {
          _rows = c.archive;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = Api.friendly(e));
    }
  }

  Future<void> _refresh() async {
    if (!Api.i.online) await Api.i.reconnect();
    await _load();
  }

  Future<void> _open(CaseRow row) async {
    await openCaseRow(context, row);
    if (mounted) _load();
  }

  bool _keep(CaseRow r) => switch (_filter) {
        _Filter.all => true,
        _Filter.unsolved => !r.solved,
        _Filter.free => !r.locked,
        _Filter.three => r.solved && r.stars >= 3,
        _Filter.unrated => r.solved && r.myRating == 0,
      };

  List<CaseRow> _shown(List<CaseRow> rows) {
    final l = rows.where(_keep).toList();
    switch (_sort) {
      case _Sort.newest:
        l.sort((a, b) => b.publish.compareTo(a.publish));
      case _Sort.oldest:
        l.sort((a, b) => a.publish.compareTo(b.publish));
      case _Sort.best:
        // rated cases first, the best average first; more voters win a tie
        l.sort((a, b) {
          if ((a.ratingCount > 0) != (b.ratingCount > 0)) return a.ratingCount > 0 ? -1 : 1;
          final c = b.ratingAvg.compareTo(a.ratingAvg);
          return c != 0 ? c : b.ratingCount.compareTo(a.ratingCount);
        });
      case _Sort.popular:
        l.sort((a, b) => b.solvers.compareTo(a.solvers));
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: K.night,
        title: Text('بایگانی', style: tDisplay(20)),
        actions: [
          ListenableBuilder(
            listenable: Api.i,
            builder: (_, __) => Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: CoinChip(
                  coins: Api.i.profile?.coins ?? 0,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ShopScreen())),
                ),
              ),
            ),
          ),
        ],
      ),
      body: GrainBackground(
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: K.stamp,
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              const SliverToBoxAdapter(child: OfflineBanner(margin: EdgeInsets.fromLTRB(16, 10, 16, 0))),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _summary(rows)),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _filters()),
              if (rows == null && _error == null)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                )
              else if (rows == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center, style: tBody(15)),
                  ),
                )
              else
                _list(_shown(rows)),
            ]),
          ),
        ),
      ),
    );
  }

  /// Progress and the coin hint: how much of the archive is done, and what an old case costs.
  Widget _summary(List<CaseRow> rows) {
    final solved = rows.where((r) => r.solved).length;
    final stars = rows.where((r) => r.solved).fold<int>(0, (a, r) => a + r.stars);
    final locked = rows.where((r) => r.locked).toList();
    final minCost = locked.isEmpty ? 0 : locked.map((r) => r.unlockCost).reduce((a, b) => a < b ? a : b);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.brass.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fa(solved), style: tDisplay(30, color: K.brass)),
          const SizedBox(width: 6),
          Expanded(child: Text('از ${fa(rows.length)} پرونده‌ی بایگانی حل شده', style: tBody(13.5, color: K.textSoft))),
          const Icon(Icons.local_police_rounded, color: K.brass, size: 20),
          const SizedBox(width: 2),
          Text(fa(stars), style: tBody(15, w: FontWeight.w900, color: K.brass)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
              value: rows.isEmpty ? 0 : solved / rows.length, minHeight: 7, backgroundColor: K.night3, color: K.brass),
        ),
        if (locked.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            const CoinIcon(size: 15),
            const SizedBox(width: 6),
            Expanded(
              child: Text('هر پرونده‌ی قدیمی از ${fa(minCost)} سکه باز می‌شه؛ پلاک و جایزه‌ی حلش مال خودته.',
                  style: tBody(12, color: K.textSoft)),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        PopupMenuButton<_Sort>(
          tooltip: 'مرتب‌سازی',
          color: K.night2,
          initialValue: _sort,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            for (final e in _sortLabels.entries)
              PopupMenuItem<_Sort>(value: e.key, child: Text(e.value, style: tBody(14, w: e.key == _sort ? FontWeight.w900 : FontWeight.w400))),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: K.night2, borderRadius: BorderRadius.circular(999), border: Border.all(color: K.brass.withValues(alpha: 0.5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.swap_vert_rounded, color: K.brass, size: 18),
              const SizedBox(width: 4),
              Text(_sortLabels[_sort]!, style: tBody(13, w: FontWeight.w700)),
            ]),
          ),
        ),
        for (final f in _Filter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_filterLabels[f]!, style: tBody(13, w: FontWeight.w700, color: _filter == f ? K.ink : K.text)),
              selected: _filter == f,
              showCheckmark: false,
              selectedColor: K.brass,
              backgroundColor: K.night2,
              side: BorderSide(color: _filter == f ? K.brass : K.night3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              onSelected: (_) => setState(() => _filter = f),
            ),
          ),
      ]),
    );
  }

  Widget _list(List<CaseRow> rows) {
    if (rows.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_filter == _Filter.all ? 'هنوز پرونده‌ی قدیمی‌ای نیست.' : 'پرونده‌ای با این فیلتر نیست.',
              textAlign: TextAlign.center, style: tBody(15, color: K.textSoft)),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      sliver: SliverList.separated(
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _card(rows[i]),
      ),
    );
  }

  /// The right-hand state of a card: stars when solved, a price button when locked, otherwise the plain state.
  Widget _state(CaseRow c) {
    if (c.solved) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Plaques(count: c.stars, size: 20),
        if (c.myRating == 0) ...[
          const SizedBox(width: 10),
          Text('امتیاز بده', style: tBody(12.5, color: K.brass, w: FontWeight.w900)),
        ],
      ]);
    }
    if (c.locked) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
        decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const CoinIcon(size: 16),
          const SizedBox(width: 5),
          Text('${fa(c.unlockCost)} · باز کن', style: tBody(13, color: K.ink, w: FontWeight.w900).copyWith(height: 1.3)),
        ]),
      );
    }
    if (c.failed) return Text('باختی؛ دوباره امتحان کن', style: tBody(12.5, color: K.stamp, w: FontWeight.w900));
    return Text('باز · حل‌نشده', style: tBody(12.5, color: K.textSoft, w: FontWeight.w700));
  }

  Widget _card(CaseRow c) {
    // the banner grows with the system font so the title never overflows
    final double banner = 96 + 28 * (MediaQuery.textScalerOf(context).scale(10) / 10 - 1).clamp(0.0, 1.0).toDouble();
    return GestureDetector(
      onTap: () => _open(c),
      child: Container(
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.solved ? K.brass.withValues(alpha: 0.55) : K.night3, width: c.solved ? 1.5 : 1),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: banner,
            child: Stack(fit: StackFit.expand, children: [
              Opacity(
                opacity: c.locked ? 0.55 : 1,
                child: AnimatedScene(scene: c.scene, height: banner, animated: false, dim: c.locked ? 0.3 : 0.05),
              ),
              // darkening toward the bottom, so the title reads on any scene
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xE617181A)],
                    stops: [0.35, 1],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _chip('شماره‌ی ${fa(c.number)}', K.night, K.text),
                  if (c.weekend) ...[const SizedBox(width: 6), _chip('آخر هفته', K.stamp, K.night)],
                ]),
              ),
              if (c.solved)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: K.brass, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: K.ink, size: 18),
                  ),
                )
              else if (c.locked)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                    child: const Icon(Icons.lock_rounded, color: K.brass, size: 17),
                  ),
                ),
              Positioned(
                right: 12,
                left: 12,
                bottom: 8,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tDisplay(19, color: c.locked ? K.textSoft : K.text)),
                  Row(children: [
                    const Icon(Icons.place_rounded, size: 13, color: K.kraft),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(c.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11.5, color: K.textSoft)),
                    ),
                    DifficultyBar(c.difficulty, compact: true),
                  ]),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            child: Row(children: [
              Flexible(child: _state(c)),
              const Spacer(),
              if (c.ratingCount > 0)
                RatingChip(avg: c.ratingAvg, count: c.ratingCount, comments: c.commentCount, size: 12.5)
              else
                Text('هنوز امتیازی نیست', style: tBody(11.5, color: K.textSoft)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: tBody(11, color: fg, w: FontWeight.w900).copyWith(height: 1.4)),
      );
}
