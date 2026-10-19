import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/claim_notes.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/services/claim_note_store.dart';

CaseData sample({bool reversed = false, String answer = 'ساعت هشت اینجا بودم.', String evidence = 'ساعت هفت ثبت شده.'}) => CaseData({
  'id': 'c-test', 'title': 'پرونده', 'suspects': [{'id': 's1', 'name': 'مظنون', 'statement': 'من نرفتم.',
    'avatar': <String, dynamic>{}, 'questions': reversed
      ? [{'q': 'کی رفتی؟', 'a': 'دیروز.'}, {'q': 'کی رسیدی؟', 'a': answer}]
      : [{'q': 'کی رسیدی؟', 'a': answer}, {'q': 'کی رفتی؟', 'a': 'دیروز.'}]}],
  'evidence': [{'id': 'e1', 'title': 'رسید', 'text': evidence}],
});
ClaimLink linkFor(CaseData c, {String note = 'بررسی ساعت', ClaimRelation relation = ClaimRelation.checking}) => ClaimLink(
  claim: claimChoices(c).firstWhere((c) => c.label == 'کی رسیدی؟').key, evidence: 'e1',
  revision: evidenceRevision(c.evidence.first), note: note, relation: relation);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('claim references survive reordering and invalidate changed prose without losing the note', () {
    final link = linkFor(sample());
    expect(link.resolveClaim(sample(reversed: true))?.text, 'ساعت هشت اینجا بودم.');
    expect(link.resolveClaim(sample(answer: 'ساعت نه اینجا بودم.')), isNull);
    final restored = ClaimLink.read([link.toJson()]).single;
    expect(restored.note, 'بررسی ساعت');
    expect(restored.evidenceChanged(sample()), isFalse);
    expect(restored.evidenceChanged(sample(evidence: 'متن تازه')), isTrue);
  });
  test('editing/removing pairs preserves other links and enforces a bounded notebook', () {
    final c = sample(), a = linkFor(sample());
    final edited = linkFor(c, note: 'ویرایش', relation: ClaimRelation.support);
    final links = putClaimLink([a], edited, replacing: a.id);
    expect(links.length, 1);
    expect(links.single.relation, ClaimRelation.support);
    expect(links.single.note, 'ویرایش');
    expect(links.where((l) => l.id != edited.id), isEmpty);
    final full = [for (var i = 0; i < maxClaimLinks; i++) ClaimLink(claim: a.claim,
      evidence: 'e$i', revision: a.revision)];
    expect(() => putClaimLink(full, ClaimLink(claim: a.claim, evidence: 'overflow', revision: a.revision)), throwsStateError);
    expect(putClaimLink(full, a, replacing: full.first.id).length, maxClaimLinks - 1); // e1 pair merges
    expect(ClaimLink(claim: a.claim, evidence: 'e1', revision: a.revision,
      note: List.filled(500, '🙂').join()).note.runes.length, maxClaimNoteLength);
    expect(ClaimLink.read([null, 5, {}, {'v': 1, 'claim': 'x', 'evidence': 'e', 'revision': 'bad'}]), isEmpty);
  });
  test('legacy marks/pins migrate to only their existing account; offline reopening and account return persist', () async {
    final legacy = {'marks': {'s1': 'suspicious'}, 'pins': ['e1'], 'seen': ['e1'], 'future_field': 9};
    SharedPreferences.setMockInitialValues({'notes_c-test': jsonEncode(legacy)});
    final prefs = await SharedPreferences.getInstance();
    final store = ClaimNoteStore(prefs);
    await store.migrateLegacy('account-a');
    expect(store.load('account-a', 'c-test'), legacy);
    expect(store.load('account-b', 'c-test'), isEmpty);
    await store.save('account-a', 'c-test', {...store.load('account-a', 'c-test'), 'links': [linkFor(sample()).toJson()]});
    await ClaimNoteStore(prefs).migrateLegacy('account-b');
    expect(store.load('account-b', 'c-test'), isEmpty);
    await store.save('account-b', 'c-test', {'pins': ['another-card']});
    final reopened = ClaimNoteStore(prefs).load('account-a', 'c-test');
    expect(reopened['marks'], legacy['marks']);
    expect(reopened['pins'], legacy['pins']);
    expect(reopened['future_field'], 9);
    expect(ClaimLink.read(reopened['links']).single.note, 'بررسی ساعت');
    expect(store.load('account-a', 'another-case'), isEmpty);
    await store.removeAccount('account-a');
    expect(store.load('account-a', 'c-test'), isEmpty);
    expect(store.load('account-b', 'c-test')['pins'], ['another-card']);
  });
  test('unknown-owner legacy and malformed data are never adopted by a later account', () async {
    SharedPreferences.setMockInitialValues({'notes_c-test': '{"note":"old private text"}'});
    final prefs = await SharedPreferences.getInstance();
    final store = ClaimNoteStore(prefs);
    await store.migrateLegacy(null);
    await store.migrateLegacy('later-account');
    expect(store.load('later-account', 'c-test'), isEmpty);
    expect(store.load(null, 'c-test'), isEmpty);
    await prefs.setString('investigation_notes_v1:later-account:c-test', 'not json');
    expect(store.load('later-account', 'c-test'), isEmpty);
  });
}
