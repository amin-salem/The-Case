import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/archive_picks.dart';
import '../theme.dart';
import 'category.dart';

/// «پیشنهاد برای تو» on top of the archive: up to three equal cards (tap = select) and a detail card with the real reason
/// and one button that uses the normal unlock flow ([onOpen] = `openCaseRow`). Hidden when there is nothing to show.
class ArchivePicksRow extends StatefulWidget {
  const ArchivePicksRow({super.key, required this.items, required this.solvedCount, required this.onOpen});

  final List<({ArchivePick pick, CaseRow row})> items;
  final int solvedCount;
  final void Function(CaseRow row) onOpen;

  @override
  State<ArchivePicksRow> createState() => _ArchivePicksRowState();
}

class _ArchivePicksRowState extends State<ArchivePicksRow> {
  int _sel = 0;

  static Color _tag(String reason) => switch (reason) {
        'easy' => const Color(0xFF3E6B4E),
        'popular' => const Color(0xFFB23A2A),
        _ => const Color(0xFF8A5A00),
      };

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final sel = items[_sel.clamp(0, items.length - 1)];
    final r = sel.row;
    return Container(
      key: const ValueKey('archive-picks'),
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: 'پیشنهاد برای تو', style: tBody(14, w: FontWeight.w900)),
          if (widget.solvedCount > 0)
            TextSpan(text: '  · از روی ${fa(widget.solvedCount)} پرونده‌ای که حل کردی', style: tBody(11.5, color: K.textSoft)),
        ])),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _card(i, items[i])),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          key: const ValueKey('archive-pick-detail'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: K.night2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: K.night3),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(r.title, style: tBody(14.5, w: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(sel.pick.explanation, style: tBody(12.5, color: K.textSoft)),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: FilledButton(
                key: const ValueKey('archive-pick-open'),
                style: FilledButton.styleFrom(backgroundColor: K.brass, foregroundColor: K.night),
                onPressed: () => widget.onOpen(r),
                child: Text(
                    !r.locked ? 'باز کن' : r.unlockCost == 0 ? 'باز کن · رایگان' : 'باز کن · ${fa(r.unlockCost)} سکه',
                    style: tBody(14, w: FontWeight.w900, color: K.night)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _card(int i, ({ArchivePick pick, CaseRow row}) it) {
    final on = i == _sel.clamp(0, widget.items.length - 1);
    final r = it.row;
    final cat = categoryName(r.category);
    return Semantics(
      button: true,
      selected: on,
      child: InkWell(
        key: ValueKey('archive-pick-$i'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _sel = i),
        child: Container(
          constraints: const BoxConstraints(minHeight: 150, minWidth: 44),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: K.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? K.brass : Colors.transparent, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: _tag(it.pick.reason), borderRadius: BorderRadius.circular(99)),
              child: Text(it.pick.label, style: tBody(10.5, w: FontWeight.w900, color: Colors.white)),
            ),
            const SizedBox(height: 6),
            Text('پرونده‌ی ${fa(r.number)}', style: tBody(11, w: FontWeight.w800, color: K.inkSoft)),
            const SizedBox(height: 4),
            Expanded(child: Text(r.title, style: tBody(13, w: FontWeight.w900, color: K.ink))),
            Text('${cat.isEmpty ? '' : '$cat · '}سختی ${fa(r.difficulty)}', style: tBody(11, w: FontWeight.w700, color: K.inkSoft)),
            const SizedBox(height: 4),
            Text(!r.locked ? 'باز شده' : r.unlockCost == 0 ? 'رایگان' : '${fa(r.unlockCost)} سکه',
                style: tBody(12, w: FontWeight.w900, color: K.ink)),
          ]),
        ),
      ),
    );
  }
}
