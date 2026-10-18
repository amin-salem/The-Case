import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/cast_strip.dart';

Map<String, dynamic> _suspect(String id, {int appears = 0}) => {
      'id': id,
      'name': 'مظنون $id',
      'role': 'نقش',
      'intro': 'یه جمله‌ی کوتاه درباره‌ی این آدم',
      'appears_chapter': appears,
      'avatar': <String, dynamic>{},
      'questions': <dynamic>[],
    };

void main() {
  test('format 3 case file: nights, newcomer and card chapters are parsed; old files still parse', () {
    final c = CaseData({
      'id': 'w050',
      'format': 3,
      'night1': {'question': 'کی دروغ می‌گه؟', 'open': true, 'reward': 10},
      'night2': {'opens_at': 1800000000, 'new_suspects': 1, 'new_cards': 4, 'open': false},
      'suspects': [_suspect('s1'), _suspect('s2', appears: 1)],
      'evidence': [
        {'id': 'e1', 'type': 'note', 'title': 'الف', 'text': 'ت', 'chapter': 1},
        {'id': 'e9', 'type': 'note', 'title': 'ب', 'text': 'ت', 'chapter': 2},
      ],
      'motives': [
        {'id': 'm1', 'text': 'یک'},
        {'id': 'm2', 'text': 'دو'}
      ],
    });
    expect(c.twoNights, isTrue);
    expect(c.twoPart, isTrue); // format 3 keeps the two-part accusation
    expect(c.night1!.open, isTrue);
    expect(c.night1!.reward, 10);
    expect(c.night2!.newCards, 4);
    expect(c.night2!.opensAt, isNotNull);
    expect(c.suspects.map((s) => s.isNewcomer), [false, true]);
    expect(c.evidence.map((e) => e.chapter), [1, 2]);

    final old = CaseData({'id': 'w002', 'format': 2, 'suspects': [_suspect('s1')], 'evidence': []});
    expect(old.twoPart, isTrue);
    expect(old.twoNights, isFalse);
    expect(old.night1, isNull);
    final older = CaseData({'id': 'w001', 'suspects': [], 'evidence': []});
    expect(older.twoPart, isFalse);
    expect(Evidence({'id': 'e1'}).chapter, 1);
  });

  test('progress carries the night-1 answer with its reveal; the case list carries the chapter-2 time', () {
    final p = Progress({
      'night1': {'pick': 's3', 'ok': false, 'reward': 0, 'liar': 's5', 'card': 'e3', 'explanation': 'چون...'}
    });
    expect(p.night1!.ok, isFalse);
    expect(p.night1!.liar, 's5');
    expect(Progress(<String, dynamic>{}).night1, isNull);

    final l = CasesList({
      'next_case_at': 1800000000,
      'archive': <dynamic>[],
      'weekly_next_chapter_at': 1800003600,
      'weekly_format': 3,
    });
    expect(l.weeklyFormat, 3);
    expect(l.weeklyNextChapterAt, isNotNull);
    expect(CasesList({'next_case_at': 1, 'archive': <dynamic>[]}).weeklyNextChapterAt, isNull);
  });

  testWidgets('the newcomer carries a «تازه · شب دوم» tag on the cast strip', (tester) async {
    final a = Suspect(_suspect('s1'));
    final b = Suspect(_suspect('s2', appears: 1));
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: CastStrip(suspects: [a, b], onOpen: (_) {})),
      ),
    ));
    expect(find.byKey(const ValueKey('newcomer-s2')), findsOneWidget);
    expect(find.byKey(const ValueKey('newcomer-s1')), findsNothing);
  });
}
