import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/album.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/first_guess.dart';

Map<String, dynamic> _album() => {
      'cards': [
        {
          'id': 'c001', 'number': 1, 'group': 'cat:medical', 'weekend': false, 'solved': true, 'stars': 3,
          'title': 'عنوان', 'location': 'جا', 'line': 'پزشک شیفت شب',
          'culprit': {'name': 'دکتر الف', 'role': 'پزشک', 'avatar': {'gender': 'f', 'hair': 'long'}},
        },
        {'id': 'c002', 'number': 2, 'group': 'cat:medical', 'weekend': false, 'solved': false, 'stars': 0, 'open': false, 'price': 120, 'failed': false},
      ],
      'groups': [
        {'key': 'cat:medical', 'title': 'پزشکی', 'icon': 'medical_services', 'total': 2, 'solved': 1, 'complete': false},
        {'key': 'scene:train', 'title': 'قطار', 'icon': 'place', 'total': 3, 'solved': 3, 'complete': true},
      ],
      'groups_done': 1,
      'rewards': [
        {'id': 'frame_album', 'title': 'قاب آلبوم', 'need': 1, 'owned': true},
        {'id': 'frame_album_noir', 'title': 'قاب نوآر آلبوم', 'need': 4, 'owned': false},
      ],
      'new': [
        {'id': 'frame_album', 'kind': 'frame', 'title': 'قاب آلبوم'}
      ],
      'solved': 1,
      'total': 2,
    };

void main() {
  test('album parses solved cards and silhouettes; a silhouette has no title or culprit', () {
    final a = Album(_album());
    expect(a.solved, 1);
    expect(a.total, 2);
    expect(a.groupsDone, 1);
    expect(a.newRewards, ['قاب آلبوم']);
    final solved = a.cards.first, dark = a.cards.last;
    expect(solved.solved && solved.culprit != null && solved.culpritName == 'دکتر الف', isTrue);
    expect(solved.stars, 3);
    expect(dark.solved, isFalse);
    expect(dark.title, '');
    expect(dark.culprit, isNull);
    expect(dark.culpritName, '');
    expect(dark.price, 120);
    expect(a.inGroup('cat:medical').length, 2);
    expect(a.groups.first.category, 'medical');
    expect(a.groups.last.category, '');
    expect(a.rewards.last.owned, isFalse);
  });

  test('album survives an empty or odd answer', () {
    final a = Album({'cards': 'x', 'groups': null});
    expect(a.cards, isEmpty);
    expect(a.groups, isEmpty);
    expect(a.total, 0);
  });

  test('first guess: own guess, hidden percentages and the crowd', () {
    final none = FirstGuess({'guess': null, 'community': null, 'culprit': null, 'correct': null});
    expect(none.guess, isNull);
    expect(none.hasCommunity, isFalse);
    final g = FirstGuess({
      'guess': 's2', 'culprit': 's1', 'correct': false,
      'community': {'total': 26, 'unknown_pct': 19, 'suspects': [{'id': 's1', 'pct': 58}, {'id': 's2', 'pct': 23}]},
    });
    expect(g.guess, 's2');
    expect(g.correct, isFalse);
    expect(g.hasCommunity, isTrue);
    expect(g.suspects['s1'], 58);
    expect(g.total, 26);
    expect(FirstGuess({'guess': '?'}).guess, FirstGuess.unknown);
  });

  testWidgets('the first-guess card shows nothing without a guess and the verdict with one', (tester) async {
    final c = CaseData({
      'id': 'c9', 'number': 9, 'title': 'ت', 'location': 'ل', 'scene': 'office', 'difficulty': 2, 'intro': 'ا',
      'suspects': [
        for (final id in ['s1', 's2', 's3']) {'id': id, 'name': 'مظنون $id', 'role': 'ر', 'intro': 'معرفی', 'questions': []}
      ],
      'evidence': [],
    });
    Future<void> show(FirstGuess? g) => tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Directionality(textDirection: TextDirection.rtl, child: FirstGuessCard(caseData: c, guess: g)))));
    await show(null);
    expect(find.byKey(const ValueKey('first-guess-line')), findsNothing);
    await show(FirstGuess({'guess': null}));
    expect(find.byKey(const ValueKey('first-guess-line')), findsNothing);
    await show(FirstGuess({'guess': 's2', 'culprit': 's1', 'correct': false}));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('مظنون s2'), findsOneWidget);
    expect(find.textContaining('درست نبود'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
