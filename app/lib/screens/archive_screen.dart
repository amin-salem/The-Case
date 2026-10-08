import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/offline.dart';
import '../widgets/scene.dart';
import 'case_screen.dart';
import 'dialogs.dart';

/// Opens a case from a list: an old locked case is unlocked with coins first (after asking).
/// Returns once the player leaves the case.
Future<void> openCaseRow(BuildContext context, CaseRow row) async {
  if (row.locked) {
    if (!needOnline(context)) return;
    final ok = await confirm(context, 'باز کردن پرونده‌ی قدیمی',
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
  Sfx.i.ambient('amb_home', volume: 0.28);
}

enum _Filter { all, unsolved, free, three }

/// Every earlier case in a grid, with filters.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<CaseRow>? _rows;
  String? _error;
  _Filter _filter = _Filter.all;

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
      };

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final solved = rows?.where((r) => r.solved).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: K.night,
        title: Text('بایگانی', style: tDisplay(20)),
        actions: [
          if (rows != null)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Center(
                child: Text('${fa(solved)} از ${fa(rows.length)} حل شده',
                    style: tBody(13, color: K.brass, w: FontWeight.w900)),
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
              SliverToBoxAdapter(child: _filters()),
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
                _grid(rows.where(_keep).toList()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _filters() {
    const labels = {_Filter.all: 'همه', _Filter.unsolved: 'حل‌نشده', _Filter.free: 'رایگان', _Filter.three: '۳ ستاره'};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        for (final f in _Filter.values)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(labels[f]!, style: tBody(13, w: FontWeight.w700, color: _filter == f ? K.ink : K.text)),
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

  Widget _grid(List<CaseRow> rows) {
    if (rows.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(_filter == _Filter.all ? 'هنوز پرونده‌ی قدیمی‌ای نیست.' : 'پرونده‌ای با این فیلتر نیست.',
              textAlign: TextAlign.center, style: tBody(15, color: K.textSoft)),
        ),
      );
    }
    // the card grows with the system font, so the text never overflows
    final extent = 98 + 20 + MediaQuery.textScalerOf(context).scale(76);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, mainAxisExtent: extent),
        delegate: SliverChildBuilderDelegate((_, i) => _card(rows[i]), childCount: rows.length),
      ),
    );
  }

  Widget _card(CaseRow c) {
    final Widget status;
    if (c.solved) {
      status = Stars(count: c.stars, size: 18);
    } else if (c.locked) {
      status = Row(mainAxisSize: MainAxisSize.min, children: [
        const CoinIcon(size: 16),
        const SizedBox(width: 4),
        Text(fa(c.unlockCost), style: tBody(13, color: K.brass, w: FontWeight.w900)),
      ]);
    } else if (c.failed) {
      status = Text('باخت', style: tBody(12.5, color: K.stamp, w: FontWeight.w900));
    } else {
      status = Text('حل‌نشده', style: tBody(12.5, color: K.textSoft, w: FontWeight.w700));
    }
    return GestureDetector(
      onTap: () => _open(c),
      child: Container(
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.solved ? K.brass.withValues(alpha: 0.45) : K.night3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 98,
            child: Stack(fit: StackFit.expand, children: [
              Opacity(
                opacity: c.locked ? 0.4 : 1,
                child: AnimatedScene(scene: c.scene, height: 98, animated: false, dim: c.locked ? 0.3 : 0),
              ),
              if (c.locked)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), shape: BoxShape.circle),
                    child: const Icon(Icons.lock_rounded, color: K.brass, size: 24),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('شماره‌ی ${fa(c.number)}', maxLines: 1, style: tBody(11, color: K.textSoft)),
                Text(c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tBody(15, w: FontWeight.w900, color: c.locked ? K.textSoft : K.text)),
                const Spacer(),
                status,
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
