import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/story.dart';
import 'package:the_case/widgets/story_choice.dart';

Widget host(Widget child, {double width = 360, double scale = 1.3}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
        ),
      ),
    );

void main() {
  final stateJson = {
    'chapter_id': 's01ch01',
    'chapter': 1,
    'done': false,
    'step': 2,
    'total': 5,
    'scene': {
      'id': 'b',
      'text': 'باران می‌بارید.',
      'speaker': 'partner',
      'ending': false,
      'options': [
        {'id': 'b1', 'title': 'با کیوسک‌دار حرف بزن', 'sub': 'شاهد دیده', 'locked': false},
        {'id': 'b2', 'title': 'دفتر حساب را ببین', 'sub': '', 'locked': true, 'reason': 'قفل است: به یک سرنخ از فصل ۱ نیاز داری'},
      ],
    },
    'board': {
      'people': [
        {'id': 'p1', 'name': 'عباس', 'role': '', 'state': 'friendly', 'text': 'با تو راحت است'},
        {'id': 'p2', 'name': 'قاسم', 'role': '', 'state': 'unmet', 'text': 'هنوز ندیده‌ای'},
      ],
      'clues': [
        {'id': 'k1', 'title': 'دفتر قدیمی', 'text': 'یک دفتر', 'status': 'held', 'by_choice': true},
        {'id': 'k2', 'title': 'رد پا', 'text': null, 'status': 'missed', 'by_choice': false},
        {'id': 'k3', 'title': null, 'text': null, 'status': 'open', 'by_choice': false},
      ],
    },
  };

  test('chapter state parses scene, options and board', () {
    final s = ChapterState(stateJson);
    expect(s.chapter, 1);
    expect(s.step, 2);
    expect(s.total, 5);
    expect(s.done, isFalse);
    expect(s.scene.isPartner, isTrue);
    expect(s.scene.options.length, 2);
    expect(s.scene.options[1].locked, isTrue);
    expect(s.scene.options[1].reason, contains('فصل ۱'));
    expect(s.board.held, 1);
  });

  test('state parsing survives missing fields', () {
    final s = ChapterState(const {});
    expect(s.scene.options, isEmpty);
    expect(s.total, 1);
    expect(s.board.clues, isEmpty);
  });

  test('season board parses people and clues', () {
    final b = SeasonBoard({
      'people': (stateJson['board'] as Map)['people'],
      'clues': (stateJson['board'] as Map)['clues'],
      'held': 1,
      'total': 3,
      'continue_chapter': 1,
    });
    expect(b.people.map((p) => p.state), ['friendly', 'unmet']);
    expect(b.clues.map((c) => c.status), ['held', 'missed', 'open']);
    expect(b.clues[0].held && b.clues[0].byChoice, isTrue);
    expect(b.clues[1].missed, isTrue);
    expect(b.clues[2].title, isNull);
    expect(b.held, 1);
    expect(b.total, 3);
    expect(b.continueChapter, 1);
    expect(SeasonBoard(const {}).continueChapter, isNull);
  });

  testWidgets('a normal option shows number, title and subtitle and can be tapped', (tester) async {
    final o = ChapterState(stateJson).scene.options[0];
    var taps = 0;
    await tester.pumpWidget(host(ChoiceCard(option: o, index: 1, onTap: () => taps++)));
    expect(find.text('با کیوسک‌دار حرف بزن'), findsOneWidget);
    expect(find.text('شاهد دیده'), findsOneWidget);
    expect(find.text('۱'), findsOneWidget);
    await tester.tap(find.byType(ChoiceCard));
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a locked option shows the lock and the reason and does not react', (tester) async {
    final o = ChapterState(stateJson).scene.options[1];
    var taps = 0;
    await tester.pumpWidget(host(ChoiceCard(option: o, index: 2, onTap: () => taps++)));
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(find.text('قفل است: به یک سرنخ از فصل ۱ نیاز داری'), findsOneWidget);
    await tester.tap(find.byType(ChoiceCard));
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('board tiles render: people states and clue states', (tester) async {
    final s = ChapterState(stateJson);
    await tester.pumpWidget(host(Column(children: [
      for (final p in s.board.people) PersonTile(person: p),
      for (final c in s.board.clues) ClueTile(clue: c),
    ])));
    expect(find.text('با تو راحت است'), findsOneWidget);
    expect(find.text('هنوز ندیده‌ای'), findsWidgets);
    expect(find.text('انتخاب تو'), findsOneWidget);
    expect(find.text('راهی که نرفتی'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
