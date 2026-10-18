import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'character.dart';

const Set<String> _titles = {
  'مهندس', 'دکتر', 'حاج', 'حاجی', 'آقای', 'خانم', 'مش', 'کشیش', 'استاد', 'سرکار', 'سرگرد', 'آقا', 'مرحوم',
};

/// The name people use for a suspect in a sentence: the first word, without a title («دکتر», «حاج»...).
/// Falls back to the whole name when nothing else is left.
String suspectFirstName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  for (final p in parts) {
    if (!_titles.contains(p) && p.length >= 2) return p;
  }
  return name.trim();
}

/// The suspects that a piece of text names (by first name or full name), in the order of the suspect list.
List<Suspect> suspectsNamedIn(String text, List<Suspect> all) {
  const letter = r'[\p{L}‌]';
  final found = <Suspect>[];
  for (final s in all) {
    for (final n in {suspectFirstName(s.name), s.name.trim()}) {
      if (n.length < 2) continue;
      // not inside a longer word; «کاوه‌ی» (name + ZWNJ + ی) still counts, «علی‌اصغر» does not count as «علی»
      final re = RegExp('(?<!$letter)${RegExp.escape(n)}(?!\\p{L}|\u200c[^\\sی.,،؛:!؟?«»()-])', unicode: true);
      if (re.hasMatch(text)) {
        found.add(s);
        break;
      }
    }
  }
  return found;
}

/// «آدم‌های پرونده»: a horizontal, snapping rail of paper cards, one per suspect.
class CastStrip extends StatefulWidget {
  const CastStrip({super.key, required this.suspects, required this.onOpen});
  final List<Suspect> suspects;
  final void Function(Suspect) onOpen;

  @override
  State<CastStrip> createState() => _CastStripState();
}

class _CastStripState extends State<CastStrip> {
  static const double cardWidth = 150, gap = 10;
  PageController? _pc;
  double _fraction = 0;

  PageController _controller(double width) {
    final f = ((cardWidth + gap) / width).clamp(0.2, 1.0).toDouble();
    if (_pc == null || (f - _fraction).abs() > 0.001) {
      final old = _pc;
      _fraction = f;
      _pc = PageController(viewportFraction: f);
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    return _pc!;
  }

  @override
  void dispose() {
    _pc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.suspects;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('آدم‌های پرونده', style: tDisplay(18)),
        const SizedBox(width: 8),
        Expanded(
          child: Text('${fa(list.length)} مظنون · بکش و ببین',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12.5, color: K.textSoft)),
        ),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) {
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: SizedBox(
          height: 330,
          child: PageView.builder(
            key: const ValueKey('cast-rail'),
            controller: _controller(box.maxWidth),
            padEnds: false,
            itemCount: list.length,
            itemBuilder: (_, i) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: gap),
                child: _card(list[i]),
              ),
            ),
          ),
          ),
        );
      }),
    ]);
  }

  Widget _card(Suspect s) {
    return GestureDetector(
      onTap: () => widget.onOpen(s),
      child: Container(
        width: cardWidth,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: K.paper,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: DefaultTextStyle(
          style: tBody(12, color: K.ink),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Stack(children: [
              SuspectPortrait(s.avatar, size: cardWidth - 16),
              if (s.isNewcomer)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    key: ValueKey('newcomer-${s.id}'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(999)),
                    child: Text('تازه · شب دوم', style: tBody(11, color: Colors.white, w: FontWeight.w900)),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, color: K.ink, w: FontWeight.w900).copyWith(height: 1.4)),
            Text(s.role, maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(11.5, color: K.stamp, w: FontWeight.w900).copyWith(height: 1.4)),
            if (s.intro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(s.intro, maxLines: 4, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.ink).copyWith(height: 1.5)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// A small chip: a 24 px portrait and the first name. Tapping it opens the suspect peek.
class SuspectChip extends StatelessWidget {
  const SuspectChip({super.key, required this.suspect, required this.onTap});
  final Suspect suspect;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(3, 3, 10, 3),
        decoration: BoxDecoration(
          color: K.paperDark,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: K.inkSoft.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SuspectPortrait(suspect.avatar, size: 24, circle: true),
          const SizedBox(width: 6),
          Text(suspectFirstName(suspect.name), style: tBody(12, color: K.ink, w: FontWeight.w700).copyWith(height: 1.3)),
        ]),
      ),
    );
  }
}

/// The bottom sheet behind a chip: larger portrait, name, role · age, the intro line, and a way to the full file.
Future<void> showSuspectPeek(BuildContext context, Suspect s, {required VoidCallback onFull}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: K.night2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SuspectPortrait(s.avatar, size: 96),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(s.name, style: tDisplay(20)),
                Text('${s.role} · ${fa(s.age)} ساله', style: tBody(12.5, color: K.brass, w: FontWeight.w700)),
                if (s.intro.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(s.intro, style: tBody(14, color: K.text)),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: GhostButton(label: 'بستن', onTap: () => Navigator.pop(ctx))),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: StampButton(
                label: 'برگه‌ی کامل مظنون',
                height: 48,
                onTap: () {
                  Navigator.pop(ctx);
                  onFull();
                },
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}
