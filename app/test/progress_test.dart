import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/progress.dart';

void main() {
  test('a riddle day: locked riddles have no text, answers only after answering', () {
    final d = RiddleDay({
      'day': '2026-10-06',
      'items': [
        {'id': 'r01', 'slot': 1, 'title': 'یک', 'scene': 'office', 'free': true, 'answered': true, 'correct': true,
          'choice': 2, 'text': 'متن', 'clue': 'سرنخ', 'choices': ['a', 'b', 'c'], 'answer': 2, 'explain': 'چون'},
        {'id': 'r02', 'slot': 2, 'title': 'دو', 'scene': 'harbor', 'free': true, 'text': 'متن', 'clue': 'سرنخ',
          'choices': ['a', 'b', 'c']},
        {'id': 'r03', 'slot': 3, 'title': 'سه', 'scene': 'train', 'free': false, 'locked': true},
      ],
      'unlock_cost': 20,
      'reward': 10,
      'seconds': 60,
      'next_at': 1790000000,
    });
    expect(d.items.length, 3);
    expect(d.answered, 1);
    expect(d.correct, 1);
    expect(d.next?.id, 'r02');
    expect(d.items[2].choices, isEmpty);
    expect(d.items[1].answer, isNull);
    expect(d.items[0].answer, 2);
  });

  test('gains: empty when nothing was earned, and read from the server', () {
    expect(Gains(null).isEmpty, isTrue);
    expect(Gains({'xp': 5}).isEmpty, isTrue);
    final g = Gains({
      'xp': 40,
      'rank_up': 'کارآگاه',
      'missions_done': ['یک پرونده حل کن'],
      'achievements': [
        {'id': 'first_case', 'title': 'اولین پرونده', 'coins': 50}
      ],
    });
    expect(g.isEmpty, isFalse);
    expect(g.rankUp, 'کارآگاه');
    expect(g.achievements.single.coins, 50);
  });
}
