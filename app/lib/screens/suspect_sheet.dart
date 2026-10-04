import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/typewriter.dart';
import 'case_screen.dart';

/// Interrogation: the suspect talks (animated), the player asks questions
/// and marks them as suspicious / innocent. Returns the new mark.
Future<SuspectMark?> showSuspect(BuildContext context, Suspect s, SuspectMark mark) {
  return showModalBottomSheet<SuspectMark>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SuspectSheet(s: s, mark: mark),
  );
}

class _SuspectSheet extends StatefulWidget {
  const _SuspectSheet({required this.s, required this.mark});
  final Suspect s;
  final SuspectMark mark;

  @override
  State<_SuspectSheet> createState() => _SuspectSheetState();
}

class _SuspectSheetState extends State<_SuspectSheet> {
  late SuspectMark _mark = widget.mark;
  int _asked = -1; // -1 = the first statement
  bool _talking = true;
  final Set<int> _seen = {};

  String get _line => _asked < 0 ? widget.s.statement : widget.s.questions[_asked].a;

  // Everyone gets nervous on the second question, so the face never gives the culprit away.
  Mood get _mood => _talking ? (_asked == 1 ? Mood.nervous : Mood.calm) : (_asked == 1 ? Mood.nervous : Mood.calm);

  void _ask(int i) => setState(() {
        _asked = i;
        _talking = true;
        _seen.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(9)))),
            const SizedBox(height: 10),
            // interrogation room: lamp light behind the suspect
            Container(
              height: 210,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const RadialGradient(center: Alignment(0, -0.6), radius: 0.9, colors: [Color(0xFF4A3B22), K.night]),
              ),
              child: Stack(children: [
                Center(child: AnimatedSuspect(avatar: s.avatar, size: 170, mood: _mood, talking: _talking)),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _markChip(),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Text(s.name, style: tDisplay(22)),
            Text('${s.role} · ${fa(s.age)} ساله', style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 10),
            // speech bubble
            Paper(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_asked >= 0)
                  Text('تو: ${s.questions[_asked].q}', style: tBody(13, color: K.inkSoft, w: FontWeight.w700)),
                Typewriter(
                  '«$_line»',
                  key: ValueKey(_asked),
                  style: tBody(16.5, color: K.ink),
                  onDone: () {
                    if (mounted) setState(() => _talking = false);
                  },
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text('بپرس:', style: tBody(14, w: FontWeight.w700)),
            const SizedBox(height: 6),
            for (int i = 0; i < s.questions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _ask(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _asked == i ? K.night3 : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: K.kraft.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      Icon(_seen.contains(i) ? Icons.check_circle_rounded : Icons.help_rounded,
                          color: _seen.contains(i) ? K.ok : K.kraft, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.questions[i].q, style: tBody(14.5))),
                    ]),
                  ),
                ),
              ),
            if (_asked >= 0)
              TextButton(onPressed: () => _ask(-1), child: Text('دوباره شنیدن حرف اولش', style: tBody(13, color: K.textSoft))),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: K.night, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.psychology_alt_rounded, color: K.stamp, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('انگیزه‌ی احتمالی: ${s.motive}', style: tBody(13.5, color: K.textSoft))),
              ]),
            ),
            const SizedBox(height: 12),
            StampButton(label: 'بستن', color: K.night3, onTap: () => Navigator.pop(context, _mark)),
          ]),
        ),
      ),
    );
  }

  Widget _markChip() {
    final (label, color) = switch (_mark) {
      SuspectMark.none => ('علامت بزن', K.textSoft),
      SuspectMark.suspicious => ('مشکوک', K.brass),
      SuspectMark.innocent => ('بی‌گناه', K.ok),
    };
    return GestureDetector(
      onTap: () => setState(() => _mark = SuspectMark.values[(_mark.index + 1) % SuspectMark.values.length]),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99), border: Border.all(color: color)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bookmark_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: tBody(12, color: color, w: FontWeight.w700)),
        ]),
      ),
    );
  }
}
