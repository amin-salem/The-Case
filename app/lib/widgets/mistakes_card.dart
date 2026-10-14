import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'character.dart';

/// On the result screen of a case the player solved: every wrong accusation, in order, in red,
/// so they can see what they got wrong. Never shown for a lost case or a clean solve.
class MistakesCard extends StatelessWidget {
  const MistakesCard({super.key, required this.caseData, required this.tries, required this.proof});
  final CaseData caseData;
  final List<WrongTry> tries;
  final List<String> proof; // the evidence that closed the case

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: tBody(11, color: K.night, w: FontWeight.w900)),
      );

  Widget _suspectRow(WrongTry t, int n) {
    final s = caseData.suspect(t.suspect);
    final right = t.proofWrong || t.motiveWrong; // the right person, something else was wrong
    final color = right ? K.ok : K.stamp;
    final note = switch (t.kind) {
      'wrong_proof' => 'قاتل درست بود، اما مدرک غلط',
      'wrong_motive' => 'قاتل و مدرک درست، اما انگیزه غلط',
      'hasty' => 'اتهام بدون بررسی کافی بود',
      _ => 'بی‌گناه بود',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: right ? K.night2 : const Color(0xFF2A1A18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: right ? 1.5 : 2),
      ),
      child: Row(children: [
        SizedBox(width: 44, height: 44, child: ClipOval(child: AnimatedSuspect(avatar: s.avatar, size: 44, mood: Mood.calm))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: tBody(14, w: FontWeight.w900)),
            Text(note, style: tBody(12.5, color: right ? K.ok : K.textSoft)),
          ]),
        ),
        _tag('اتهام ${fa(n)}', K.stamp),
      ]),
    );
  }

  Widget _card(String title, String text, {required bool good}) => Container(
        margin: const EdgeInsetsDirectional.only(start: 20),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: good ? K.paper : const Color(0xFFE6D7D2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: good ? K.ok : K.stamp, width: 2.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: tBody(14, color: K.ink, w: FontWeight.w900)),
              if (text.isNotEmpty) Text(text, style: tBody(12.5, color: K.ink)),
            ]),
          ),
          Icon(good ? Icons.check_rounded : Icons.close_rounded, color: good ? K.ok : K.stamp, size: 22),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < tries.length; i++) {
      final t = tries[i];
      rows.add(_suspectRow(t, i + 1));
      if (t.proofWrong) {
        rows.add(_card(caseData.evidenceById(t.evidence)?.title ?? '', 'این مدرک دروغ او را ثابت نمی‌کرد.', good: false));
      } else if (t.motiveWrong && t.motive != null) {
        final why = [for (final m in caseData.motives) if (m.id == t.motive) m.text];
        rows.add(_card(why.isEmpty ? '' : why.first, 'این انگیزه‌ی واقعی نبود.', good: false));
      }
    }
    final closer = proof.isEmpty ? null : caseData.evidenceById(proof.first);
    if (closer != null) rows.add(_card(closer.title, 'مدرکی که پرونده را بست.', good: true));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.stamp, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.close_rounded, color: K.stamp, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('اشتباه‌های تو در این پرونده', style: tBody(16, w: FontWeight.w900))),
          Text('${fa(tries.length)} اتهام', style: tBody(13, color: K.textSoft)),
        ]),
        const SizedBox(height: 12),
        for (int i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: 8), rows[i]],
      ]),
    );
  }
}
