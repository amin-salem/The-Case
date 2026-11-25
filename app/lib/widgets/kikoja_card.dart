import 'package:flutter/material.dart';

import '../screens/dialogs.dart';
import '../screens/kikoja_screen.dart';
import '../services/api.dart';
import '../theme.dart';
import 'kikoja_archive.dart' show MiniPlan;

/// «کی کجا؟» on the home screen (Amin, 25 Nov 2026): three tiles for today (easy, medium, hard). Easy is free, the other two
/// open for coins. Shown only when the server shows the game to this player (testers first). It asks the server for the
/// tiles itself and reloads them every time a game screen closes.
class KikojaHomeCard extends StatefulWidget {
  const KikojaHomeCard({super.key});

  @override
  State<KikojaHomeCard> createState() => _KikojaHomeCardState();
}

class _KikojaHomeCardState extends State<KikojaHomeCard> {
  Map<String, dynamic>? _today;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await Api.i.kikojaToday();
    if (mounted) setState(() => _today = t);
  }

  List<Map<String, dynamic>> get _levels => ((_today?['levels'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  Future<void> _tap(Map<String, dynamic> l) async {
    await openKikojaTile(context, l, coins: (_today?['coins'] as int?) ?? Api.i.coins, siblings: _levels, reload: _load);
  }

  /// «فردا ساعت ۹ صبح» once all three are solved; otherwise the hours left in the day.
  String _footer() {
    final done = _levels.isNotEmpty && _levels.every((l) => l['solved'] == true);
    final at = DateTime.tryParse('${_today?['next_at'] ?? ''}');
    if (!done || at == null) return '';
    final left = at.difference(DateTime.now());
    final h = left.inHours;
    return h >= 1 ? 'معماهای تازه · ${fa(h)} ساعت دیگه' : 'معماهای تازه · کمتر از یک ساعت دیگه';
  }

  @override
  Widget build(BuildContext context) {
    final ls = _levels;
    if (_today == null || ls.isEmpty) return const SizedBox.shrink();
    final foot = _footer();
    final fresh = ls.any((l) => l['open'] == true && l['solved'] != true && l['failed'] != true);
    return Container(
      key: const ValueKey('kikoja-card'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF3A2E14), Color(0xFF221E16), K.night2]),
        border: Border.all(color: K.brass.withValues(alpha: 0.7), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Stack(children: [
        // the house of the first puzzle, faint, behind the title (a hint of what the game is)
        Positioned(
          left: -24,
          top: -10,
          child: Opacity(
            opacity: 0.35,
            child: Transform.rotate(angle: -0.14, child: SizedBox(width: 130, child: MiniPlan(house: '${ls.first['house']}', target: '${ls.first['target']}'))),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('کی کجا؟', style: tDisplay(27)),
              if (fresh) ...[
                const SizedBox(width: 10),
                Container(key: const ValueKey('kikoja-dot'), width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: K.brass)),
              ],
            ]),
            const SizedBox(height: 14),
            Row(children: [
              for (var i = 0; i < ls.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _Tile(l: ls[i], onTap: () => _tap(ls[i]))),
              ],
            ]),
            if (foot.isNotEmpty) ...[
              const SizedBox(height: 10),
              Center(child: Text(foot, style: tBody(12, color: K.textSoft))),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Opens a tile of «کی کجا؟» (today's or an archive day's): the game when it is open, the unlock sheet when it is paid and closed.
/// When the page asks for the next level (`'next'`), the next unsolved sibling is opened the same way.
Future<void> openKikojaTile(BuildContext context, Map<String, dynamic> l,
    {required int coins, required List<Map<String, dynamic>> siblings, required Future<void> Function() reload, int back = 0}) async {
  Future<void> play(String level) async {
    final r = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => KikojaScreen(level: level, back: back)));
    await reload();
    if (r != 'next' || !context.mounted) return;
    final i = siblings.indexWhere((x) => x['level'] == level);
    final next = i >= 0 ? siblings.skip(i + 1).where((x) => x['solved'] != true).firstOrNull : null;
    if (next != null) await openKikojaTile(context, next, coins: coins, siblings: siblings, reload: reload, back: back);
  }

  if (l['open'] == true) return play('${l['level']}');
  final ok = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _UnlockSheet(level: l, coins: coins, back: back),
  );
  await reload();
  if (ok == true && context.mounted) await play('${l['level']}');
}

const _levelFa = {'easy': 'آسان', 'medium': 'متوسط', 'hard': 'سخت'};

class _Tile extends StatelessWidget {
  const _Tile({required this.l, required this.onTap});
  final Map<String, dynamic> l;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = '${l['level']}';
    final solved = l['solved'] == true, failed = l['failed'] == true, open = l['open'] == true;
    final price = (l['price'] as int?) ?? 0;
    final stars = (l['stars'] as int?) ?? 0;
    final bars = const {'easy': 1, 'medium': 2, 'hard': 3}[level] ?? 1;
    Widget status;
    if (solved) {
      status = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (var i = 0; i < 3; i++) Icon(Icons.shield_rounded, size: 15, color: i < stars ? K.brass : K.night3),
      ]);
    } else if (failed) {
      status = Text('بسته شد', style: tBody(12, color: K.stamp, w: FontWeight.w900));
    } else if (open) {
      status = Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
        decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(99)),
        child: Text(price == 0 ? 'رایگان' : 'باز شده', style: tBody(12.5, color: K.night, w: FontWeight.w900)),
      );
    } else {
      status = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const _Coin(),
        const SizedBox(width: 4),
        Text(fa(price), style: tBody(13, color: K.brass, w: FontWeight.w900)),
      ]);
    }
    return Semantics(
      button: true,
      label: '${_levelFa[level]}',
      child: GestureDetector(
        key: ValueKey('kikoja-tile-$level'),
        onTap: onTap,
        child: Container(
          height: 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: solved ? const Color(0xFF25231E) : price == 0 && open ? const Color(0x29E0A526) : const Color(0x9917181A),
            border: Border.all(color: solved ? Colors.transparent : price == 0 && open && !failed ? K.brass : K.brass.withValues(alpha: 0.25), width: price == 0 && open && !solved ? 1.5 : 1),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Container(width: 4, height: 6.0 + i * 4, decoration: BoxDecoration(borderRadius: BorderRadius.circular(2), color: i < bars ? K.brass : K.night)),
              ],
            ]),
            const SizedBox(height: 6),
            Text(_levelFa[level] ?? '', style: tBody(15, w: FontWeight.w900, color: solved ? K.textSoft : K.text)),
            const SizedBox(height: 4),
            status,
          ]),
        ),
      ),
    );
  }
}

class _Coin extends StatelessWidget {
  const _Coin();
  @override
  Widget build(BuildContext context) =>
      Container(width: 13, height: 13, decoration: BoxDecoration(shape: BoxShape.circle, color: K.brass, border: Border.all(color: const Color(0xFF9C7420), width: 3)));
}

/// The paid level's door: what is inside (counts only, never a statement), the price and the balance; one tap opens it.
class _UnlockSheet extends StatefulWidget {
  const _UnlockSheet({required this.level, required this.coins, this.back = 0});
  final Map<String, dynamic> level;
  final int coins;
  final int back;

  @override
  State<_UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends State<_UnlockSheet> {
  bool _busy = false;

  Future<void> _unlock() async {
    final price = (widget.level['price'] as int?) ?? 0;
    setState(() => _busy = true);
    try {
      await Api.i.kikojaAction('${widget.level['level']}', 'unlock', const {}, back: widget.back);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (e.code == 'not_enough_coins') {
        final nav = Navigator.of(context);
        final ctx = context;
        nav.pop(false);
        if (ctx.mounted) await showNeedCoins(ctx, e.need > 0 ? e.need : price, what: 'این معما', starter: true);
      } else {
        toast(context, Api.friendly(e));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, Api.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.level;
    final price = (l['price'] as int?) ?? 0;
    final house = l['house'] == 'kashan' ? 'خانه‌ی تاریخیِ کاشان' : 'خانه‌ی باغِ قلهک';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 22),
        decoration: const BoxDecoration(color: K.night2, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 18),
          Text('معمای ${_levelFa[l['level']] ?? ''}', style: tDisplay(24)),
          const SizedBox(height: 4),
          Text(house, style: tBody(13.5, color: K.kraft, w: FontWeight.w700)),
          const SizedBox(height: 10),
          Text('${fa((l['n'] as int? ?? 0))} مظنون · ${fa((l['T'] as int? ?? 0))} ساعت', style: tBody(14, color: K.textSoft)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              key: const ValueKey('kikoja-unlock'),
              onPressed: _busy ? null : _unlock,
              style: FilledButton.styleFrom(backgroundColor: K.brass, foregroundColor: K.night, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('باز کردن', style: tBody(16.5, color: K.night, w: FontWeight.w900)),
                const SizedBox(width: 10),
                const _Coin(),
                const SizedBox(width: 4),
                Text(fa(price), style: tBody(16.5, color: K.night, w: FontWeight.w900)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text('موجودی ${fa(widget.coins)}', style: tBody(12.5, color: K.textSoft)),
        ]),
      ),
    );
  }
}
