import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';

void main() {
  test('weekly board: the server gives the week end and the leagues', () {
    final lb = Leaderboard({
      'period': 'weekly',
      'title': 'این هفته · لیگ بازرس',
      'top': [
        {'rank': 1, 'nickname': 'الف', 'avatar': 0, 'value': 9, 'stars': 9, 'me': true}
      ],
      'me': null,
      'week_ends_at': 1792000000,
      'league': 2,
      'my_league': 2,
      'leagues': [
        {'id': 0, 'name': 'تازه‌کار'},
        {'id': 1, 'name': 'کارآگاه'},
        {'id': 2, 'name': 'بازرس'},
        {'id': 3, 'name': 'سرپرست'},
      ],
    });
    expect(lb.weekEndsAt!.millisecondsSinceEpoch, 1792000000 * 1000);
    expect(lb.league, 2);
    expect(lb.myLeague, 2);
    expect(lb.leagues.length, 4);
  });

  test('an old server (no leagues, no week end) still parses', () {
    final lb = Leaderboard({'period': 'weekly', 'title': 'این هفته', 'top': [], 'me': null});
    expect(lb.weekEndsAt, isNull);
    expect(lb.league, isNull);
    expect(lb.leagues, isEmpty);
  });
}
