import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/leaderboard_screen.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';

http.Response response(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

const _leagues = [
  {'id': 0, 'name': 'تازه‌کار', 'min_xp': 0, 'from_rank': 'کارآگاه تازه‌کار', 'to_rank': 'دستیار کارآگاه'},
  {'id': 1, 'name': 'کارآگاه', 'min_xp': 600, 'from_rank': 'کارآگاه', 'to_rank': 'کارآگاه ارشد'},
  {'id': 2, 'name': 'بازرس', 'min_xp': 2500, 'from_rank': 'بازرس', 'to_rank': 'سربازرس'},
  {'id': 3, 'name': 'سرپرست', 'min_xp': 6500, 'from_rank': 'کارآگاه نخبه', 'to_rank': 'افسانه'},
];

Map<String, dynamic> board(int league, {bool empty = false}) => {
      'period': 'weekly',
      'title': 'این هفته · لیگ ${_leagues[league]['name']}',
      'top': empty
          ? []
          : [
              {'rank': 1, 'nickname': 'نمونه$league', 'avatar': 0, 'value': 6, 'stars': 6, 'me': league == 1,
               'rank_title': 'سربازرس', 'league_name': _leagues[league]['name']},
            ],
      'me': null,
      'week_ends_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3 * 86400,
      'league': league,
      'my_league': 1,
      'leagues': _leagues,
    };

Future<void> pump(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

void installServer() {
  Api.i.httpClient = MockClient((r) async {
    if (r.url.path == '/v1/leaderboard') {
      final period = r.url.queryParameters['period'];
      final league = int.tryParse(r.url.queryParameters['league'] ?? '') ?? 1;
      if (period != 'weekly') {
        return response({'period': period, 'title': 'عنوان', 'top': [], 'me': null});
      }
      return response(board(league, empty: league == 3)); // the league «سرپرست» is empty
    }
    return response({});
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'player': 'p', 'secret': 's', 'token': 't',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
    await Api.i.init();
    Api.i.online = true;
    Api.i.profile = Profile({'player_id': 'p', 'coins': 500});
    installServer();
  });

  void expectAllChips(WidgetTester t, int selected) {
    for (int i = 0; i < 4; i++) {
      final chip = t.widget<ChoiceChip>(find.byKey(ValueKey('league-$i')));
      expect(chip.selected, i == selected, reason: 'chip $i, selected league is $selected');
    }
  }

  testWidgets('weekly board: every league chip stays while selecting each league, even an empty one', (t) async {
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: LeaderboardBoard('weekly'))));
    await pump(t);
    expectAllChips(t, 1); // my own league is the default
    for (final league in [0, 2, 3, 1, 3, 0]) {
      await t.tap(find.byKey(ValueKey('league-$league')));
      await t.pump(); // the request is still running: the switch must already be there
      expectAllChips(t, league);
      await pump(t);
      expectAllChips(t, league);
      if (league == 3) {
        expect(find.byKey(const ValueKey('lb-empty')), findsOneWidget);
        expect(find.textContaining('لیگ سرپرست'), findsWidgets);
      } else {
        expect(find.byKey(const ValueKey('lb-empty')), findsNothing);
      }
    }
  });

  testWidgets('weekly board: a failing request keeps the league switch so the player can pick another one', (t) async {
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: LeaderboardBoard('weekly'))));
    await pump(t);
    Api.i.httpClient = MockClient((r) async => response({'detail': 'x'}, 500));
    await t.tap(find.byKey(const ValueKey('league-2')));
    await pump(t);
    for (int i = 0; i < 4; i++) {
      expect(find.byKey(ValueKey('league-$i')), findsOneWidget);
    }
    installServer();
    await t.tap(find.byKey(const ValueKey('league-0')));
    await pump(t);
    expectAllChips(t, 0);
    expect(find.text('نمونه0'), findsOneWidget);
  });

  testWidgets('the long explanation is behind the «i» button and closes in one tap', (t) async {
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: const LeaderboardScreen()));
    await pump(t);
    expect(find.byKey(const ValueKey('lb-info-sheet')), findsNothing);
    expect(find.textContaining('جمعه‌ها ساعت ۲۱'), findsNothing); // not always visible any more
    await t.tap(find.byKey(const ValueKey('lb-info')));
    await pump(t);
    expect(find.byKey(const ValueKey('lb-info-sheet')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('lb-info-close')));
    await pump(t);
    expect(find.byKey(const ValueKey('lb-info-sheet')), findsNothing);
  });

  testWidgets('weekly «i»: prizes, the weekly clock, fair week, leagues with their rank ranges and ties are all in the sheet', (t) async {
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: const Scaffold(body: LeaderboardBoard('weekly'))));
    await pump(t);
    expect(find.textContaining('جمعه‌ها ساعت ۲۱'), findsNothing);
    await t.tap(find.byKey(const ValueKey('lb-info-inline')));
    await pump(t);
    for (final part in ['جمعه‌ها ساعت ۲۱', 'هفته‌ی منصفانه', 'اول ۱۲۰ سکه، دوم ۸۰ سکه، سوم ۵۰ سکه', 'اگه امتیازها برابر شد', 'از «بازرس» تا «سربازرس»']) {
      expect(find.textContaining(part, skipOffstage: false), findsOneWidget, reason: part);
    }
    await t.tap(find.text('فهمیدم'));
    await pump(t);
    expect(find.byKey(const ValueKey('lb-info-sheet')), findsNothing);
  });

  test('rows and leagues parse the new fields and an old server still works', () {
    final lb = Leaderboard(board(2));
    expect(lb.top.first.leagueName, 'بازرس');
    expect(lb.top.first.rankTitle, 'سربازرس');
    expect(lb.leagueInfos[2].fromRank, 'بازرس');
    expect(lb.leagueInfos[2].toRank, 'سربازرس');
    expect(lb.leagueInfos[2].minXp, 2500);
    final old = Leaderboard({'period': 'weekly', 'title': 't', 'top': [{'rank': 1, 'nickname': 'a', 'avatar': 0, 'value': 1}], 'me': null,
      'leagues': [{'id': 0, 'name': 'تازه‌کار'}]});
    expect(old.top.first.leagueName, '');
    expect(old.leagueInfos.single.fromRank, '');
  });
}
