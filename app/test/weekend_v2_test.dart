import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';

void main() {
  test('weekend format 2: case, shows, archive row and accusation result parse', () {
    final c = CaseData({
      'id': 'w002',
      'format': 2,
      'shows_per_chapter': 3,
      'motives': [
        {'id': 'm1', 'text': 'a'},
        {'id': 'm2', 'text': 'b'}
      ],
      'chapters': [
        {'title': 'فصل اول'}
      ],
      'chapters_total': 2,
    });
    expect(c.weekly, isTrue);
    expect(c.twoPart, isTrue);
    expect(c.showsPerChapter, 3);
    expect(CaseData({'id': 'w001', 'motives': [{'id': 'm1', 'text': 'a'}]}).twoPart, isFalse);

    final p = Progress({
      'attempts_left': 3,
      'shows': [
        {'s': 's1', 'e': 'e2', 't': 'نمی‌دونم'}
      ],
      'shows_left': 2,
    });
    expect(p.showsLeft, 2);
    expect(p.showFor('s1', 'e2')?.text, 'نمی‌دونم');
    expect(p.showFor('s1', 'e3'), isNull);

    expect(CaseRow({'id': 'w002', 'weekend': true, 'unlock_cost': 250}).weekend, isTrue);
    expect(CaseRow({'id': 'c001'}).weekend, isFalse);

    final r = AccuseResult({'result': 'solved', 'early_bonus': 50, 'how_right': false});
    expect(r.earlyBonus, 50);
    expect(r.howRight, isFalse);
    expect(AccuseResult({'result': 'solved'}).howRight, isNull);
  });
}
