import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/archive_logic.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/category.dart';
import '../widgets/offline.dart';
import '../widgets/archive_stats.dart';
import '../widgets/scene.dart';
import 'case_screen.dart';
import 'dialogs.dart';
import 'main_shell.dart';
import 'shop_screen.dart';

/// Opens a case from a list: an old locked case is unlocked with coins first (after asking).
/// Returns once the player leaves the case.
Future<void> openCaseRow(BuildContext context, CaseRow row) async {
  if (row.locked) {
    final unlocked = await unlockQuotedCase(context, row);
    if (!context.mounted || !unlocked) return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaseScreen(caseId: row.id)));
  Sfx.i.ambient('amb_home', volume: Sfx.homeVolume);
}

/// The amount the player confirms is the amount sent to the server. A changed
/// quote always gets a new explicit confirmation; no silent retry/debit.
Future<bool> unlockQuotedCase(BuildContext context, CaseRow row) async {
  if (!needOnline(context)) return false;
  var quote = row.unlockCost;
  var changed = false;
  final account = Api.i.account;
  for (var tries = 0; tries < 5; tries++) {
    if (!context.mounted || Api.i.account != account) return false;
    final rewards = row.baseSolveRewards;
    final rewardText = rewards.isEmpty ? '' : '\nپاداش پایهٔ حل: ${fa(rewards[1] ?? 0)} تا ${fa(rewards[3] ?? 0)} سکه؛ بسته به پلاک‌ها.';
    final lost = row.failed;
    final ok = await confirm(context,
        changed ? 'قیمت پرونده تغییر کرده' : lost ? 'فرصت دوباره' : row.weekend ? 'باز کردن پرونده‌ی آخر هفته' : 'باز کردن پرونده‌ی قدیمی',
        lost
            ? 'این پرونده رو باختی و بسته شده. با ${fa(quote)} سکه (دو برابر قیمت عادی) دوباره باز می‌شه و ${fa(3)} فرصت تازه داری؛ این دور تو رتبه‌بندی شبانه حساب نمی‌شه.$rewardText'
            : '${row.weekend ? 'همهٔ فصل‌های این پروندهٔ بسته‌شده با هم باز می‌شن.' : 'این پرونده مال روزهای قبله.'} با ${fa(quote)} سکه بازش کن.$rewardText',
        lost ? 'دوباره باز کن · ${fa(quote)} سکه' : 'باز کن · ${fa(quote)} سکه');
    if (!ok || !context.mounted || Api.i.account != account) return false;
    try {
      await Api.i.unlockCase(row.id, expectedCost: quote);
      return true;
    } on ApiException catch (e) {
      if (!context.mounted) return false;
      if (e.code == 'price_changed' && e.need >= 0) {
        quote = e.need;
        changed = true;
        continue;
      }
      if (e.code == 'not_enough_coins') {
        await showNeedCoins(context, e.need > 0 ? e.need : quote);
      } else {
        toast(context, Api.friendly(e));
      }
      return false;
    } catch (e) {
      if (context.mounted) toast(context, Api.friendly(e));
      return false;
    }
  }
  if (context.mounted) toast(context, 'قیمت دوباره تغییر کرد؛ فهرست پرونده‌ها رو تازه کن.');
  return false;
}

/// Every earlier case: a progress header, filters and sorting, and wide cards with the scene, the state
/// (stars / price / lost) and the detectives' rating.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, this.embedded = false});

  /// True inside the bottom navigation: the tab keeps its filters and reloads each time it is opened.
  final bool embedded;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<CaseRow>? _rows;
  String? _error;
  ArchiveFilter _filter = ArchiveFilter.all;
  ArchiveSort _sort = ArchiveSort.newest;
  String _cat = ''; // topic filter ('' = all topics)
  String _query = ''; // search text
  final _searchCtl = TextEditingController();

  @override
  void dispose() {
    if (widget.embedded) MainShell.tab.removeListener(_onTab);
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.embedded) MainShell.tab.addListener(_onTab);
  }

  void _onTab() {
    if (MainShell.tab.value == MainShell.archive && mounted) _load();
  }

  Future<void> _load() async {
    try {
      final c = await Api.i.cases();
      if (mounted) {
        setState(() {
          _rows = c.archive;
          _error = null;
          // a topic that vanished from the list must not leave an invisible filter behind
          if (_cat.isNotEmpty && !c.archive.any((r) => r.category == _cat)) _cat = '';
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

  List<CaseRow> _shown(List<CaseRow> rows) => archiveSorted(
        archiveVisible(rows, filter: _filter, category: _cat, query: _query),
        _sort,
      );

  bool get _narrowed => _filter != ArchiveFilter.all || _cat.isNotEmpty || _query.trim().isNotEmpty;

  void _clearFilters() {
    _searchCtl.clear();
    setState(() {
      _filter = ArchiveFilter.all;
      _cat = '';
      _query = '';
    });
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
              if (rows != null && _nudgeVisible(rows)) SliverToBoxAdapter(child: _rateNudge(rows)),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _searchBox()),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _filters(rows)),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _categoryChips(rows)),
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

  // ---- gentle nudge to rate older solved cases (only on the phone: at most once per few days, one tap closes)
  static const _nudgeKey = 'rate_nudge_at';
  static const _nudgeEvery = Duration(days: 3);
  bool _nudgeHidden = false;

  int _unratedSolved(List<CaseRow> rows) => rows.where((r) => r.solved && r.myRating == 0).length;

  bool _nudgeVisible(List<CaseRow> rows) {
    if (_nudgeHidden || _unratedSolved(rows) == 0) return false;
    final last = Api.i.intPref(_nudgeKey);
    return DateTime.now().millisecondsSinceEpoch - last > _nudgeEvery.inMilliseconds;
  }

  void _closeNudge({bool showList = false}) {
    Api.i.setIntPref(_nudgeKey, DateTime.now().millisecondsSinceEpoch);
    setState(() {
      _nudgeHidden = true;
      if (showList) {
        _filter = ArchiveFilter.unrated; // the list of solved cases the player has not rated yet
        _sort = ArchiveSort.newest;
        _cat = '';
        _query = '';
        _searchCtl.clear();
      }
    });
  }

  Widget _rateNudge(List<CaseRow> rows) => Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: K.stamp.withValues(alpha: 0.5)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.star_rounded, color: K.brass, size: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('پرونده‌های قبلی رو هم امتیاز بده؛ نظرت کمک می‌کنه پرونده‌های بهتری بسازیم',
                    style: tBody(13.5, w: FontWeight.w700)),
              ),
            ),
            IconButton(
              tooltip: 'بستن',
              onPressed: _closeNudge,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.close_rounded, color: K.textSoft, size: 20),
            ),
          ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => _closeNudge(showList: true),
              icon: const Icon(Icons.star_border_rounded, color: K.brass, size: 20),
              label: Text('${fa(_unratedSolved(rows))} پرونده منتظر امتیازته؛ نشونم بده',
                  style: tBody(13.5, color: K.brass, w: FontWeight.w900)),
            ),
          ),
        ]),
      );

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

  Widget _searchBox() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TextField(
          key: const ValueKey('archive-search'),
          controller: _searchCtl,
          textInputAction: TextInputAction.search,
          style: tBody(14),
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'جست‌وجو در نام، مکان یا شماره‌ی پرونده',
            hintStyle: tBody(13, color: K.textSoft),
            prefixIcon: const Icon(Icons.search_rounded, color: K.textSoft, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'پاک کردن',
                    icon: const Icon(Icons.close_rounded, color: K.textSoft, size: 18),
                    onPressed: () {
                      _searchCtl.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: K.night2,
            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: K.night3)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: K.night3)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: K.brass.withValues(alpha: 0.7))),
          ),
        ),
      );

  Widget _filters(List<CaseRow> rows) {
    final counts = archiveFilterCounts(rows, category: _cat, query: _query);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        PopupMenuButton<ArchiveSort>(
          tooltip: 'مرتب‌سازی',
          color: K.night2,
          initialValue: _sort,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            for (final e in archiveSortLabels.entries)
              PopupMenuItem<ArchiveSort>(
                  value: e.key, child: Text(e.value, style: tBody(14, w: e.key == _sort ? FontWeight.w900 : FontWeight.w400))),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
                color: K.night2, borderRadius: BorderRadius.circular(999), border: Border.all(color: K.brass.withValues(alpha: 0.5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.swap_vert_rounded, color: K.brass, size: 18),
              const SizedBox(width: 4),
              Text(archiveSortLabels[_sort]!, style: tBody(13, w: FontWeight.w700)),
            ]),
          ),
        ),
        for (final f in ArchiveFilter.values)
          // a filter that would show nothing is hidden, except «همه» and the one that is on
          if (f == ArchiveFilter.all || f == _filter || (counts[f] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('filter-chip-${f.name}'),
                label: Text(f == ArchiveFilter.all ? archiveFilterLabels[f]! : '${archiveFilterLabels[f]} · ${fa(counts[f] ?? 0)}',
                    style: tBody(13, w: FontWeight.w700, color: _filter == f ? K.ink : K.text)),
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

  /// Topic chips (only the topics that exist in the archive), under the sort/filter row.
  Widget _categoryChips(List<CaseRow> rows) {
    final present = {for (final r in rows) r.category}..remove('');
    if (present.isEmpty) return const SizedBox.shrink();
    final counts = archiveCategoryCounts(rows, filter: _filter, query: _query);
    Widget chip(String key, String label, IconData? icon) {
      final on = _cat == key;
      final n = counts[key] ?? 0;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          key: ValueKey('cat-chip-${key.isEmpty ? 'all' : key}'),
          avatar: icon == null ? null : Icon(icon, size: 16, color: on ? K.ink : K.kraft),
          label: Text('$label · ${fa(n)}', style: tBody(13, w: FontWeight.w700, color: on ? K.ink : K.text)),
          selected: on,
          showCheckmark: false,
          selectedColor: K.kraft,
          backgroundColor: K.night2,
          side: BorderSide(color: on ? K.kraft : K.night3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          onSelected: (_) => setState(() => _cat = key),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(children: [
        chip('', 'همه‌ی موضوع‌ها', null),
        for (final e in kCategories.entries)
          if (present.contains(e.key) && ((counts[e.key] ?? 0) > 0 || _cat == e.key)) chip(e.key, e.value.name, e.value.icon),
      ]),
    );
  }

  Widget _list(List<CaseRow> rows) {
    if (rows.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(children: [
            Text(_narrowed ? 'پرونده‌ای با این فیلتر و جست‌وجو پیدا نشد.' : 'هنوز پرونده‌ی قدیمی‌ای نیست.',
                textAlign: TextAlign.center, style: tBody(15, color: K.textSoft)),
            if (_narrowed)
              TextButton(
                key: const ValueKey('archive-clear'),
                onPressed: _clearFilters,
                child: Text('پاک کردن فیلترها', style: tBody(14, color: K.brass, w: FontWeight.w900)),
              ),
          ]),
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
          Text('${fa(c.unlockCost)} · ${c.failed ? 'فرصت دوباره' : 'باز کن'}', style: tBody(13, color: K.ink, w: FontWeight.w900).copyWith(height: 1.3)),
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
                    if (c.category.isNotEmpty) ...[CategoryBadge(c.category, compact: true), const SizedBox(width: 6)],
                    DifficultyBar(c.difficulty, compact: true),
                  ]),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            // state on the right, the rating + comments block in its own fixed slot on the left edge
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: _state(c)),
              ),
              const SizedBox(width: 8),
              ArchiveStatsSlot(avg: c.ratingAvg, count: c.ratingCount, comments: c.commentCount),
            ]),
          ),
          if (!c.solved && !c.failed && c.baseSolveRewards.isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text('پاداش پایهٔ حل: ${fa(c.baseSolveRewards[1] ?? 0)} تا ${fa(c.maxSolveReward ?? 0)} سکه',
                style: tBody(12, color: K.textSoft))),
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

