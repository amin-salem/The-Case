/// Personal hypotheses only. These models never inspect solutions or score a deduction.
library;

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'models.dart';

const maxClaimLinks = 60;
const maxClaimNoteLength = 280;

String _fingerprint(Object value) => sha256.convert(utf8.encode(jsonEncode(value))).toString();
String evidenceRevision(Evidence evidence) => _fingerprint([evidence.title, evidence.text]);

enum ClaimRelation {
  contradiction('تعارض احتمالی'), support('پشتیبانی احتمالی'), checking('نیاز به بررسی');
  const ClaimRelation(this.label);
  final String label;
}

class ClaimChoice {
  ClaimChoice(this.suspect, [this.question])
      : key = '${suspect.id}/${question == null ? 'statement' : 'qa'}/${_fingerprint(question == null ? [suspect.statement] : [question.q, question.a])}';
  final Suspect suspect;
  final QA? question;
  final String key;
  String get label => question?.q ?? 'حرف اولیه';
  String get text => question?.a ?? suspect.statement;
}

List<ClaimChoice> claimChoices(CaseData c) => [
  for (final s in c.suspects) ...[
    if (s.statement.trim().isNotEmpty) ClaimChoice(s),
    for (final q in s.questions.take(64)) if (q.a.trim().isNotEmpty) ClaimChoice(s, q),
  ],
];

class ClaimLink {
  ClaimLink({required this.claim, required this.evidence, required this.revision,
    this.relation = ClaimRelation.checking, String note = ''})
      : note = String.fromCharCodes(note.runes.take(maxClaimNoteLength));
  final String claim, evidence, revision, note;
  final ClaimRelation relation;
  String get id => '$claim|$evidence';
  Map<String, dynamic> toJson() => {'v': 1, 'claim': claim, 'evidence': evidence,
    'revision': revision, 'relation': relation.name, 'note': note};

  ClaimChoice? resolveClaim(CaseData c) {
    for (final choice in claimChoices(c)) { if (choice.key == claim) return choice; }
    return null;
  }
  bool evidenceChanged(CaseData c) {
    final e = c.evidenceById(evidence);
    return e == null || evidenceRevision(e) != revision;
  }

  static List<ClaimLink> read(Object? raw) {
    if (raw is! List) return [];
    final links = <String, ClaimLink>{};
    for (final value in raw.take(maxClaimLinks)) {
      if (value is! Map || value['v'] != 1) continue;
      final claim = value['claim'], evidence = value['evidence'], revision = value['revision'];
      if (claim is! String || claim.length > 150 || claim.isEmpty ||
          evidence is! String || evidence.length > 64 || evidence.isEmpty ||
          revision is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(revision)) continue;
      final relation = ClaimRelation.values.where((r) => r.name == value['relation']).firstOrNull ?? ClaimRelation.checking;
      final link = ClaimLink(claim: claim, evidence: evidence, revision: revision, relation: relation,
        note: value['note'] is String ? value['note'] as String : '');
      links[link.id] = link;
    }
    return links.values.toList();
  }
}

/// Editing a pair merges it instead of creating a duplicate. Existing order/other notes stay intact.
List<ClaimLink> putClaimLink(List<ClaimLink> links, ClaimLink link, {String? replacing}) {
  final remaining = links.where((l) => l.id != replacing && l.id != link.id).toList();
  if (remaining.length >= maxClaimLinks) throw StateError('claim_note_limit');
  return [...remaining, link];
}
