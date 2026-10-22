import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/case_clock.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/whats_new_ui.dart';
import '../services/whats_new.dart';
import '../widgets/typewriter.dart';
import 'case_screen.dart';

/// Interrogation: the suspect talks (animated), the player asks questions
/// and marks them as suspicious / innocent. Returns the new mark.
/// Weekend case (new format): what the sheet needs to let the player show evidence cards to this suspect.
class WeekendShow {
  WeekendShow({required this.caseId, required this.evidence, required this.shows, required this.left, this.onProgress});
  final String caseId;
  final List<Evidence> evidence;
  final List<ShowNote> shows;
  final int left;
  final void Function(Progress)? onProgress;
}

Future<SuspectMark?> showSuspect(BuildContext context, Suspect s, SuspectMark mark,
    {void Function(SuspectMark)? onMark, WeekendShow? weekend, Future<void> Function(Suspect, int)? onLinkClaim}) {
  return showModalBottomSheet<SuspectMark>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true, // keeps the top below the status bar; the sheet pads its own bottom
    backgroundColor: Colors.transparent,
    builder: (_) => _SuspectSheet(s: s, mark: mark, onMark: onMark, weekend: weekend, onLinkClaim: onLinkClaim),
  );
}

class _SuspectSheet extends StatefulWidget {
  const _SuspectSheet({required this.s, required this.mark, this.onMark, this.weekend, this.onLinkClaim});
  final Future<void> Function(Suspect, int)? onLinkClaim;
  final WeekendShow? weekend;
  final Suspect s;
  final SuspectMark mark;
  /// Called at once on every tap, so the mark is kept even if the sheet is swiped away.
  final void Function(SuspectMark)? onMark;

  @override
  State<_SuspectSheet> createState() => _SuspectSheetState();
}

class _SuspectSheetState extends State<_SuspectSheet> {
  late SuspectMark _mark = widget.mark;
  int _asked = -1; // -1 = the first statement
  bool _talking = true;
  final Set<int> _seen = {};
  int _turn = 0; // new Typewriter each time a question is asked

  // weekend case: evidence shown to this suspect
  late List<ShowNote> _shows = [...?widget.weekend?.shows];
  late int _left = widget.weekend?.left ?? 0;
  String? _showTitle, _showLine; // the card just shown and what the suspect said
  bool _showing = false;

  String get _line => _showLine ?? (_asked < 0 ? widget.s.statement : widget.s.questions[_asked].a);

  Future<void> _pickEvidence() async {
    WhatsNew.i.tagOpened('show_evidence');
    final w = widget.weekend!;
    final id = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: K.night2,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          Text('کدوم مدرک رو نشونش بدی؟', style: tDisplay(18)),
          const SizedBox(height: 4),
          Text(_left > 0 ? '${fa(_left)} مدرک نمایش مانده' : 'مدرک نمایشی نمونده؛ مدارکی که قبلاً نشونش دادی رایگانه',
              style: tBody(12.5, color: K.textSoft)),
          const SizedBox(height: 10),
          for (final e in w.evidence)
            Builder(builder: (_) {
              final done = _shows.any((x) => x.evidence == e.id);
              final locked = !done && _left <= 0;
              return Opacity(
                opacity: locked ? 0.45 : 1,
                child: ListTile(
                  onTap: locked ? null : () => Navigator.pop(ctx, e.id),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  leading: Icon(done ? Icons.check_circle_rounded : Icons.description_rounded, color: done ? K.ok : K.brass),
                  title: Text(e.title, style: tBody(14.5, w: FontWeight.w700)),
                  subtitle: Text(done ? 'قبلاً نشونش دادی؛ دوباره شنیدن رایگانه' : 'نشان بده',
                      style: tBody(12, color: K.textSoft)),
                ),
              );
            }),
        ]),
      ),
    );
    if (id == null || !mounted) return;
    final e = w.evidence.firstWhere((x) => x.id == id);
    setState(() => _showing = true);
    try {
      final r = await Api.i.showEvidence(w.caseId, widget.s.id, id);
      if (!mounted) return;
      if (r.progress != null) {
        w.onProgress?.call(r.progress!);
        _shows = [...r.progress!.shows];
        _left = r.progress!.showsLeft;
      }
      setState(() {
        _showTitle = e.title;
        _showLine = r.text;
        _talking = true;
        _turn++;
      });
    } on ApiException catch (ex) {
      if (mounted) toast(context, Api.errorText(ex.code));
    } finally {
      if (mounted) setState(() => _showing = false);
    }
  }

  // Everyone gets nervous on the second question, so the face never gives the culprit away.
  Mood get _mood => _talking ? (_asked == 1 ? Mood.nervous : Mood.calm) : (_asked == 1 ? Mood.nervous : Mood.calm);

  void _ask(int i) {
    CaseClock.i.asked(widget.s.id, i);
    _askState(i);
  }

  void _askState(int i) => setState(() {
        _asked = i;
        _showLine = _showTitle = null;
        _talking = true;
        _turn++;
        _seen.add(i);
      });

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
      decoration: const BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
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
                if (_showTitle != null)
                  Text('تو: «$_showTitle» رو نشونش دادی.', style: tBody(13, color: K.inkSoft, w: FontWeight.w700))
                else if (_asked >= 0)
                  Text('تو: ${s.questions[_asked].q}', style: tBody(13, color: K.inkSoft, w: FontWeight.w700)),
                Typewriter(
                  '«$_line»',
                  key: ValueKey(_turn),
                  style: tBody(16.5, color: K.ink),
                  onDone: () {
                    if (mounted) setState(() => _talking = false);
                  },
                ),
              ]),
            ),
            if (widget.onLinkClaim != null && _showLine == null)
              Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(
                onPressed: () => widget.onLinkClaim!(s, _asked),
                icon: const Icon(Icons.add_link_rounded, size: 19), label: const Text('یادداشت و پیوند مدرک'))),
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
            if (widget.weekend != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: K.night3, borderRadius: BorderRadius.circular(12), border: Border.all(color: K.brass.withValues(alpha: 0.6))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    const Icon(Icons.fact_check_rounded, color: K.brass),
                    const SizedBox(width: 8),
                    Text('نشان دادن مدرک', style: tBody(15, w: FontWeight.w900)),
                    const SizedBox(width: 8),
                    const NewTag('show_evidence'),
                    const Spacer(),
                    Text('${fa(_left)} مانده', style: tBody(12.5, color: K.textSoft)),
                  ]),
                  const SizedBox(height: 4),
                  Text('همه‌ی واکنش‌ها یکی نیست؛ شاید یکی لو بره.', style: tBody(12.5, color: K.textSoft)),
                  const SizedBox(height: 8),
                  StampButton(label: _showing ? 'صبر کن...' : 'یک مدرک نشونش بده', icon: Icons.visibility_rounded, onTap: _showing ? null : _pickEvidence),
                ]),
              ),
            ],
            if (_asked >= 0 || _showLine != null)
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
      onTap: () {
        setState(() => _mark = SuspectMark.values[(_mark.index + 1) % SuspectMark.values.length]);
        widget.onMark?.call(_mark);
      },
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

