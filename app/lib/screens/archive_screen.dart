import 'package:flutter/material.dart';
import '../widgets/state_view.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/archive_logic.dart';
import '../services/archive_picks.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/category.dart';
import '../widgets/gift_case.dart';
import '../widgets/offline.dart';
import '../widgets/archive_picks.dart';
import '../widgets/archive_stats.dart';
import '../widgets/scene.dart';
import 'album_screen.dart';
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
    final rewardText = rewards.isEmpty ? '' : '\nپاداش پایه‌ی حل: ${fa(rewards[1] ?? 0)} تا ${fa(rewards[3] ?? 0)} سکه؛ بسته به پلاک‌ها.';
    final lost = row.failed;
    final ok = await confirm(context,
        changed ? 'قیمت پرونده تغییر کرده' : lost ? 'فرصت دوباره' : row.weekend ? 'باز کردن پرونده‌ی آخر هفته' : 'باز کردن پرونده‌ی قدیمی',
        lost
            ? (row.weekend
                ? 'این پرونده رو باختی و بسته شده. با ${fa(quote)} سکه دوباره باز می‌شه و ${fa(3)} فرصت تازه داری؛ این دور تو جدول هفته حساب نمی‌شه.$rewardText'
                : 'این پرونده رو باختی و بسته شده. با ${fa(quote)} سکه (دو برابر قیمت عادی) دوباره باز می‌شه و ${fa(3)} فرصت تازه داری؛ این دور تو رتبه‌بندی شبانه حساب نمی‌شه.$rewardText')
            : quote == 0
                ? 'این پرونده برای کارآگاه‌های تازه، برای چند ساعت رایگانه. بازش کن و دنبال مجرم بگرد.$rewardText'
                : '${row.weekend ? 'همه‌ی فصل‌های این پرونده‌ی بسته‌شده با هم باز می‌شن.' : 'این پرونده مال روزهای قبله.'} با ${fa(quote)} سکه بازش کن.$rewardText',
        lost ? 'دوباره باز کن · ${fa(quote)} سکه' : quote == 0 ? 'باز کن · رایگان' : 'باز کن · ${fa(quote)} سکه');
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
        await showNeedCoins(context, e.need > 0 ? e.need : quote, what: 'باز کردن این پرونده', starter: true);
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
  List<ArchivePick> _picks = const []; // «پیشنهاد برای تو»; empty = no row (none, offline, error, old server)
  Object? _error; // why the list could not load (null = fine)
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
      if (mounted) setState(() => _error = e);
      return;
    }
    // the suggestions come after the list and never block it; any failure just leaves the row out
    final picks = await Api.i.archivePicks();
    if (mounted) setState(() => _picks = picks);
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
          IconButton(
            key: const ValueKey('open-album'),
            tooltip: 'آلبوم مجرم‌ها',
            icon: const Icon(Icons.collections_bookmark_rounded, color: K.brass),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AlbumScreen())),
          ),
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
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _giftPin(rows)),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _summary(rows)),
              if (rows != null && _nudgeVisible(rows)) SliverToBoxAdapter(child: _rateNudge(rows)),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _picksRow(rows)),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _searchRow(rows)),
              if (rows != null && rows.isNotEmpty) SliverToBoxAdapter(child: _summaryLine(rows)),
              if (rows == null && _error == null)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                )
              else if (rows == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: StateView.forError(_error!, key: const ValueKey('archive-state'), onRetry: _refresh),
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

  /// The promo case that is free for this new detective, pinned above everything else (the same card as on the home page).
  Widget _giftPin(List<CaseRow> rows) {
    final c = giftCase(rows, DateTime.now());
    if (c == null) return const SizedBox.shrink();
    return GiftCaseCard(row: c, onOpen: () => _open(c), margin: const EdgeInsets.fromLTRB(16, 10, 16, 0));
  }

  Widget _picksRow(List<CaseRow> rows) {
    final items = showablePicks(_picks, rows);
    if (items.isEmpty) return const SizedBox.shrink();
    return ArchivePicksRow(items: items, solvedCount: rows.where((r) => r.solved).length, onOpen: _open);
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

  /// One search field and ONE filter button (with a count badge); everything else lives in the filter sheet.
  Widget _searchRow(List<CaseRow> rows) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(children: [
          Expanded(child: _searchBox()),
          const SizedBox(width: 8),
          _filterButton(rows),
        ]),
      );

  int get _activeCount => (_filter != ArchiveFilter.all ? 1 : 0) + (_cat.isNotEmpty ? 1 : 0) + (_sort != ArchiveSort.newest ? 1 : 0);

  Widget _filterButton(List<CaseRow> rows) {
    final n = _activeCount;
    return Stack(clipBehavior: Clip.none, children: [
      Semantics(
        button: true,
        label: 'فیلتر',
        child: InkWell(
          key: const ValueKey('archive-filter-button'),
          onTap: () => _openFilterSheet(rows),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: n > 0 ? K.brass : K.night3, width: 2),
            ),
            child: const Icon(Icons.tune_rounded, color: K.brass, size: 22),
          ),
        ),
      ),
      if (n > 0)
        PositionedDirectional(
          end: -7,
          top: -7,
          child: Container(
            key: const ValueKey('archive-filter-badge'),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
            child: Text(fa(n), style: tBody(11, color: K.ink, w: FontWeight.w900).copyWith(height: 1.2)),
          ),
        ),
    ]);
  }

  /// «N پرونده · filter · topic · order»: what the list below shows right now.
  Widget _summaryLine(List<CaseRow> rows) {
    final parts = [
      if (_filter != ArchiveFilter.all) archiveFilterLabels[_filter]!,
      if (_cat.isNotEmpty) categoryName(_cat),
      archiveSortLabels[_sort]!,
    ];
    return Padding(
      key: const ValueKey('archive-summary-line'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text('${fa(_shown(rows).length)} پرونده · ${parts.join(' · ')}', style: tBody(12.5, color: K.textSoft, w: FontWeight.w700)),
    );
  }

  Future<void> _openFilterSheet(List<CaseRow> rows) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: K.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void upd(VoidCallback f) {
          setState(f);
          setSheet(() {});
        }

        final all = _rows ?? rows;
        final fCounts = archiveFilterCounts(all, category: _cat, query: _query);
        final cCounts = archiveCategoryCounts(all, filter: _filter, query: _query);
        final present = {for (final r in all) r.category}..remove('');

        Widget chip(String key, String label, bool on, VoidCallback tap) => InkWell(
              key: ValueKey(key),
              onTap: tap,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                constraints: const BoxConstraints(minHeight: 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? K.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? K.ink : K.paperDark.withValues(alpha: 0.9)),
                ),
                child: Text(label, style: tBody(13, color: on ? K.paper : K.ink, w: FontWeight.w800).copyWith(height: 1.3)),
              ),
            );

        Widget group(String title, List<Widget> chips) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: tBody(13, color: K.inkSoft, w: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: chips),
              const SizedBox(height: 14),
            ]);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text('فیلتر', style: tBody(17, color: K.ink, w: FontWeight.w900))),
                TextButton(
                  key: const ValueKey('archive-filter-clear'),
                  onPressed: _activeCount == 0
                      ? null
                      : () => upd(() {
                            _filter = ArchiveFilter.all;
                            _cat = '';
                            _sort = ArchiveSort.newest;
                          }),
                  child: Text('پاک کردن همه', style: tBody(13, color: K.stamp, w: FontWeight.w900)),
                ),
              ]),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    group('اصلی', [
                      for (final f in ArchiveFilter.values)
                        // an option that would show nothing is hidden, except «همه» and the one that is on
                        if (f == ArchiveFilter.all || f == _filter || (fCounts[f] ?? 0) > 0)
                          chip('filter-chip-${f.name}', archiveFilterLabels[f]!, _filter == f, () => upd(() => _filter = f)),
                    ]),
                    if (present.isNotEmpty)
                      group('موضوعی', [
                        chip('cat-chip-all', 'همه', _cat.isEmpty, () => upd(() => _cat = '')),
                        for (final e in kCategories.entries)
                          if (present.contains(e.key) && ((cCounts[e.key] ?? 0) > 0 || _cat == e.key))
                            chip('cat-chip-${e.key}', e.value.name, _cat == e.key, () => upd(() => _cat = e.key)),
                      ]),
                    group('ترتیب', [
                      for (final e in archiveSortLabels.entries)
                        chip('sort-chip-${e.key.name}', e.value, _sort == e.key, () => upd(() => _sort = e.key)),
                    ]),
                  ]),
                ),
              ),
              InkWell(
                key: const ValueKey('archive-filter-show'),
                onTap: () => Navigator.of(ctx).pop(),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: K.ink, borderRadius: BorderRadius.circular(14)),
                  child: Text('نشان بده · ${fa(_shown(all).length)} پرونده', style: tBody(15, color: K.paper, w: FontWeight.w900)),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _searchBox() => TextField(
          key: const ValueKey('archive-search'),
          controller: _searchCtl,
          textInputAction: TextInputAction.search,
          style: tBody(14),
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'جست‌وجو در نام، مکان یا شماره',
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
            contentPadding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: K.night3)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: K.night3)),
            focusedBorder:
                OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: K.brass.withValues(alpha: 0.7))),
          ),
      );

  Widget _list(List<CaseRow> rows) {
    if (rows.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: _narrowed
              ? StateView.empty(
                  key: const ValueKey('archive-empty'),
                  icon: Icons.search_off_rounded,
                  title: 'چیزی پیدا نشد',
                  body: 'پرونده‌ای با این فیلتر و جست‌وجو نیست؛ فیلترها رو پاک کن تا همه‌ی پرونده‌ها برگردن.',
                  primaryLabel: 'پاک کردن فیلترها',
                  onPrimary: _clearFilters)
              : StateView.empty(
                  key: const ValueKey('archive-empty'),
                  title: 'بایگانی هنوز خالیه',
                  body: 'پرونده‌های شب‌های قبل این‌جا جمع می‌شن؛ فعلاً سراغ پرونده‌ی امشب برو.',
                  primaryLabel: 'برو سراغ پرونده‌ی امشب',
                  onPrimary: () {
                    if (!widget.embedded) Navigator.of(context).maybePop();
                    MainShell.tab.value = MainShell.home;
                  }),
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
          Text('${c.unlockCost == 0 && !c.failed ? 'رایگان' : fa(c.unlockCost)} · ${c.failed ? 'فرصت دوباره' : 'باز کن'}', style: tBody(13, color: K.ink, w: FontWeight.w900).copyWith(height: 1.3)),
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
              child: Text('پاداش پایه‌ی حل: ${fa(c.baseSolveRewards[1] ?? 0)} تا ${fa(c.maxSolveReward ?? 0)} سکه',
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

