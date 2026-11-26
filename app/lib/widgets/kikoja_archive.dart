import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import 'id_card.dart' show toJalali;
import 'kikoja_card.dart';

const _months = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
const _weekdays = ['', 'دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه']; // DateTime.weekday 1 = Monday

/// «کی کجا؟» inside the archive tab (Amin, 25 Nov 2026): the last days, three tiles each. A day's tiles open the same game
/// page as today's (`back` = how many days ago); the free level is free, the paid ones cost the same coins as today.
class KikojaArchiveView extends StatefulWidget {
  const KikojaArchiveView({super.key});

  @override
  State<KikojaArchiveView> createState() => _KikojaArchiveViewState();
}

class _KikojaArchiveViewState extends State<KikojaArchiveView> {
  Map<String, dynamic>? _data;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await Api.i.kikojaArchive();
    if (!mounted) return;
    setState(() {
      _data = d;
      _loaded = true;
    });
  }

  List<Map<String, dynamic>> _list(Object? v) => ((v as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();

  String _label(Map<String, dynamic> day) {
    if (day['back'] == 1) return 'دیروز';
    final d = DateTime.tryParse('${day['date']}');
    if (d == null) return '';
    final j = toJalali(d);
    return '${_weekdays[d.weekday]} ${fa(j[2])} ${_months[j[1] - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass)));
    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final solved = (data['solved'] as int?) ?? 0, total = (data['total'] as int?) ?? 0;
    final coins = (data['coins'] as int?) ?? Api.i.coins;
    return Padding(
      key: const ValueKey('kikoja-archive'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fa(solved), style: tDisplay(44, color: K.brass)),
            const SizedBox(width: 8),
            Text('از ${fa(total)} معما', style: tBody(14, color: K.textSoft)),
          ]),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: '${fa(solved)} از ${fa(total)} حل شده',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: total == 0 ? 0 : solved / total, minHeight: 6, backgroundColor: K.night3, color: K.brass),
          ),
        ),
        for (final day in _list(data['days'])) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(_label(day), style: tBody(13, color: day['back'] == 1 ? K.text : K.textSoft, w: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            for (final (i, l) in _list(day['levels']).indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _ArchiveTile(
                  l: l,
                  onTap: () => openKikojaTile(context, l, coins: coins, siblings: _list(day['levels']), reload: _load, back: (day['back'] as int?) ?? 1),
                ),
              ),
            ],
          ]),
        ],
      ]),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({required this.l, required this.onTap});
  final Map<String, dynamic> l;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = '${l['level']}';
    final solved = l['solved'] == true, failed = l['failed'] == true, open = l['open'] == true;
    final price = (l['price'] as int?) ?? 0, stars = (l['stars'] as int?) ?? 0;
    final lit = solved || (open && !failed);
    final name = const {'easy': 'آسان', 'medium': 'متوسط', 'hard': 'سخت'}[level] ?? '';
    final state = solved ? 'حل شده' : failed ? 'بسته شده' : open ? 'باز' : 'قفل، ${fa(price)} سکه';
    return Semantics(
      button: true,
      label: '$name، $state',
      child: GestureDetector(
        key: ValueKey('kikoja-archive-$level-${l['id']}'),
        onTap: onTap,
        child: Container(
          height: 98,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: solved ? const Color(0xFF25231E) : failed ? const Color(0xFF1C1D20) : open ? const Color(0xFF2E281B) : const Color(0xFF1D1E21),
            border: Border.all(color: failed ? K.stamp.withValues(alpha: 0.55) : open && !solved ? K.brass : K.night3, width: open && !solved || failed ? 1.5 : 1),
          ),
          child: Column(children: [
            Expanded(
              child: Center(
                child: ColorFiltered(
                  colorFilter: lit ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : const ColorFilter.matrix(<double>[0.3, 0.3, 0.3, 0, 0, 0.3, 0.3, 0.3, 0, 0, 0.3, 0.3, 0.3, 0, 0, 0, 0, 0, 0.7, 0]),
                  child: MiniPlan(house: '${l['house']}', target: '${l['target']}', lit: lit),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(children: [
              DifficultyBar(kikojaDifficulty[level], compact: true),
              const Spacer(),
              if (solved)
                for (var i = 0; i < 3; i++) Icon(Icons.shield_rounded, size: 12, color: i < stars ? K.brass : K.night3)
              else if (!open && !failed) ...[
                const CoinIcon(size: 13),
                const SizedBox(width: 3),
                Text(fa(price), style: tBody(12, w: FontWeight.w900)),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

/// A small night plan of a house (rooms as tiles, the room of the crime marked), enough to tell the puzzles apart at a glance.
/// Qolhak is 3 × 2 rooms, Kashan 3 × 3 (the same grids as the game page).
class MiniPlan extends StatelessWidget {
  const MiniPlan({super.key, required this.house, required this.target, this.lit = true});
  final String house, target;
  final bool lit;

  static const _qolhak = [
    ['yard', 'salon', 'lib'],
    ['kitchen', 'hall', 'study'],
  ];
  static const _kashan = [
    ['shah', 'porch', 'upper'],
    ['lib', 'court', 'kitchen'],
    ['guest', 'hashti', 'store'],
  ];

  @override
  Widget build(BuildContext context) {
    final grid = house == 'kashan' ? _kashan : _qolhak;
    final h = house == 'kashan' ? 46.0 : 34.0;
    return AspectRatio(
      aspectRatio: 3 / (grid.length),
      child: SizedBox(
        height: h,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: K.kraft.withValues(alpha: 0.85)),
          child: Column(children: [
            for (final row in grid)
              Expanded(
                child: Row(children: [
                  for (final room in row.reversed) // the rows list left to right as on the page; an RTL Row starts at the right
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(0.8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1.5),
                          color: room == target ? const Color(0xFF5A4520) : const Color(0xFF211F1B),
                        ),
                        child: room == target ? Center(child: Container(width: 4.5, height: 4.5, decoration: const BoxDecoration(shape: BoxShape.circle, color: K.brass))) : null,
                      ),
                    ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
