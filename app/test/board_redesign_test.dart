import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/leaderboard_screen.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/services/board_text.dart';
import 'package:the_case/theme.dart';

http.Response response(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> row(int rank, {int value = 100, bool me = false, String pid = '', int stars = 3}) => {
      'rank': rank,
      'nickname': 'کارآگاه$rank',
      'avatar': 0,
      'value': value,
      'stars': stars,
      'me': me,
      'rank_title': 'بازرس',
      'pid': pid.isEmpty ? 'p$rank' : pid,
    };

Map<String, dynamic> dailyBoard({bool oldServer = false}) => {
      'period': 'daily',
      'title': 'پرونده‌ی امروز: زنگِ ساعتِ سه',
      'top': [row(1, value: 582), row(2, value: 640), row(3, value: 681, me: true)],
      'me': row(3, value: 681, me: true),
      if (!oldServer) 'gap': {'next_rank': 2, 'diff': 42, 'unit': 'seconds'},
      if (!oldServer) 'daily': {'solved': 14, 'fastest': 582, 'median': 798},
    };

Future<void> pump(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
  await t.pump(const Duration(milliseconds: 300));
}

/// The app is Persian: the tests lay everything out right to left, like the real app.
Widget host(Widget child, {double scale = 1.0}) => MaterialApp(
      theme: buildTheme(),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: w!),
      ),
      home: Scaffold(body: child),
    );

void main() {
  late List<Uri> requests;

  void server(Map<String, Object? Function(Uri)> routes) {
    requests = [];
    Api.i.httpClient = MockClient((r) async {
      requests.add(r.url);
      final h = routes[r.url.path];
      if (h == null) return response({'detail': 'nope'}, 404);
      final out = h(r.url);
      return out is http.Response ? out : response(out as Object);
    });
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'player': 'p', 'secret': 's', 'token': 't',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
    await Api.i.init();
    Api.i.online = true;
    Api.i.profile = Profile({'player_id': 'p', 'coins': 500});
  });

  group('texts', () {
    test('time and gap lines', () {
      expect(boardTime(582), '۹:۴۲');
      expect(boardTime(3900), '۱:۰۵:۰۰');
      expect(boardTime(-4), '۰:۰۰');
      expect(gapLine(RankGap({'next_rank': 4, 'diff': 12, 'unit': 'plaque'})), '۱۲ امتیاز تا رتبه‌ی بالاتر (رتبه‌ی ۴)');
      expect(gapLine(RankGap({'next_rank': 1, 'diff': 42, 'unit': 'seconds'})), contains('۴۲ ثانیه تا رتبه‌ی بالاتر'));
      expect(gapLine(RankGap({'next_rank': 1, 'diff': 3, 'unit': 'nights'})), contains('۳ شب'));
      expect(gapLine(null), isNull);
      expect(gapLine(RankGap({'next_rank': 0, 'diff': 0, 'unit': 'plaque'})), isNull);
    });

    test('tonight line drops what it does not know', () {
      expect(dailyStatsLine(DailyStats({'solved': 14, 'fastest': 582, 'median': 798})), '۱۴ کارآگاه حلش کردن · میانه ۱۳:۱۸');
      expect(dailyStatsLine(DailyStats({'solved': 3, 'fastest': null, 'median': null})), '۳ کارآگاه حلش کردن');
      expect(dailyStatsLine(DailyStats({'solved': 0})), isNull);
      expect(dailyStatsLine(null), isNull);
    });

    test('an old server still parses (no gap, no stats, no ids, no paging)', () {
      final lb = Leaderboard(dailyBoard(oldServer: true)..['top'] = [{'rank': 1, 'nickname': 'a', 'avatar': 0, 'value': 9}]);
      expect(lb.gap, isNull);
      expect(lb.daily, isNull);
      expect(lb.nextOffset, isNull);
      expect(lb.top.single.pid, '');
      expect(lb.myBest, 0);
    });

    test('streak board and player card parse', () {
      final s = Leaderboard.streaks({'top': [row(1, value: 30)], 'me': null, 'my_best': 19, 'next_offset': 30});
      expect(s.period, 'streak');
      expect(s.myBest, 19);
      expect(s.nextOffset, 30);
      final c = PlayerCard({'pid': 'x', 'nickname': 'n', 'avatar': 1, 'cases_solved': 41, 'streak': 6, 'best_streak': 19,
        'league_history': [{'week': '2026-11-06', 'league': 'بازرس'}]});
      expect(c.casesSolved, 41);
      expect(c.leagueHistory.single.league, 'بازرس');
      expect(PlayerCard({}).leagueHistory, isEmpty);
    });
  });

  testWidgets('daily: tonight stats, my gap line, and the podium is right to left (2 – 1 – 3)', (t) async {
    server({'/v1/leaderboard': (_) => dailyBoard()});
    await t.pumpWidget(host(const LeaderboardBoard('daily')));
    await pump(t);
    expect(find.byKey(const ValueKey('daily-stats-line')), findsOneWidget);
    expect(find.text('۱۴ کارآگاه'), findsOneWidget);
    expect(find.textContaining('میانه ۱۳:۱۸'), findsOneWidget);
    expect(find.textContaining('سریع‌ترین'), findsNothing);
    expect(find.text('پرونده‌ی امشب'), findsNothing);
    expect(find.textContaining('۴۲ ثانیه تا رتبه‌ی بالاتر'), findsOneWidget);
    double x(int rank) => t.getCenter(find.byKey(ValueKey('podium-$rank'))).dx;
    expect(x(2), greaterThan(x(1)), reason: 'second place sits on the right');
    expect(x(1), greaterThan(x(3)));
  });

  testWidgets('daily from an old server: no stats line, no gap line, the board still shows', (t) async {
    server({'/v1/leaderboard': (_) => dailyBoard(oldServer: true)});
    await t.pumpWidget(host(const LeaderboardBoard('daily')));
    await pump(t);
    expect(find.byKey(const ValueKey('daily-stats-line')), findsNothing);
    expect(find.textContaining('تا رتبه‌ی بالاتر'), findsNothing);
    expect(find.text('کارآگاه1'), findsOneWidget);
  });

  testWidgets('tapping a podium place opens his ID card with real numbers and closes in one tap', (t) async {
    server({
      '/v1/leaderboard': (_) => dailyBoard(),
      '/v1/players/p1/card': (_) => {'pid': 'p1', 'nickname': 'کارآگاه1', 'avatar': 0, 'rank_title': 'بازرس', 'cases_solved': 41,
        'stars_total': 90, 'streak': 6, 'best_streak': 19, 'league': 2, 'league_name': 'بازرس', 'member_no': 12, 'since': 1760000000, 'fastest': 221,
        'recent': [{'title': 'پرونده‌خوار', 'group': 'cases', 'metal': 1, 'at': 1}], 'league_history': [{'week': '2026-11-06', 'league': 'بازرس'}]},
    });
    await t.pumpWidget(host(const LeaderboardBoard('daily')));
    await pump(t);
    await t.tap(find.byKey(const ValueKey('podium-1')));
    await pump(t);
    expect(find.byKey(const ValueKey('player-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('id-card')), findsOneWidget);
    expect(find.text('کارآگاه1'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('id-card'))); // flip: the back has his numbers
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('۴۱'), findsOneWidget);
    expect(find.text('۱۹ شب'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-badges')), findsOneWidget);
    expect(find.text('پرونده‌خوار'), findsOneWidget);
    expect(requests.last.path, '/v1/players/p1/card');
    await t.tap(find.byKey(const ValueKey('player-sheet-close')));
    await pump(t);
    expect(find.byKey(const ValueKey('player-sheet')), findsNothing);
  });

  testWidgets('player sheet: a failing card shows a calm retry state, never a crash', (t) async {
    server({'/v1/leaderboard': (_) => dailyBoard(), '/v1/players/p2/card': (_) => response({'detail': 'no_player'}, 404)});
    await t.pumpWidget(host(const LeaderboardBoard('daily')));
    await pump(t);
    await t.tap(find.byKey(const ValueKey('podium-2')));
    await pump(t);
    expect(find.byKey(const ValueKey('player-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('id-card')), findsNothing);
    expect(find.byKey(const ValueKey('player-sheet-close')), findsOneWidget); // the way out is always there
    expect(t.takeException(), isNull);
  });

  testWidgets('rows without an id (an old server) are not tappable', (t) async {
    final b = dailyBoard(oldServer: true);
    b['top'] = [for (int i = 1; i <= 3; i++) {...row(i, value: 500 + i), 'pid': ''}];
    server({'/v1/leaderboard': (_) => b});
    await t.pumpWidget(host(const LeaderboardBoard('daily')));
    await pump(t);
    await t.tap(find.byKey(const ValueKey('podium-1')));
    await pump(t);
    expect(find.byKey(const ValueKey('player-sheet')), findsNothing);
    expect(requests.where((u) => u.path.contains('/card')), isEmpty);
  });

  testWidgets('«همیشه»: the streak board switch, the record line, the gap in nights', (t) async {
    server({
      '/v1/leaderboard': (_) => {'period': 'all', 'title': 'همه', 'top': [row(1, value: 50)], 'me': null},
      '/v1/leaderboard/streaks': (_) => {
        'top': [row(1, value: 30), row(2, value: 20), row(3, value: 14, me: true)],
        'me': row(3, value: 14, me: true),
        'my_best': 19,
        'gap': {'next_rank': 2, 'diff': 7, 'unit': 'nights'},
      },
    });
    await t.pumpWidget(host(const LeaderboardBoard('all')));
    await pump(t);
    expect(find.byKey(const ValueKey('streak-sub')), findsNothing);
    await t.tap(find.byKey(const ValueKey('mode-streak')));
    await pump(t);
    expect(requests.any((u) => u.path == '/v1/leaderboard/streaks'), isTrue);
    expect(find.textContaining('رکورد خودت: ۱۹ شب'), findsOneWidget);
    expect(find.textContaining('۷ شب تا رتبه‌ی بالاتر'), findsOneWidget);
    expect(find.text('۳۰ شب'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('mode-stars')));
    await pump(t);
    expect(find.byKey(const ValueKey('streak-sub')), findsNothing);
  });

  testWidgets('«همیشه»: the streak board from a server that fails keeps the switch and shows a calm error', (t) async {
    server({'/v1/leaderboard': (_) => {'period': 'all', 'title': 'همه', 'top': [row(1, value: 50)], 'me': null},
      '/v1/leaderboard/streaks': (_) => response({'detail': 'x'}, 404)});
    await t.pumpWidget(host(const LeaderboardBoard('all')));
    await pump(t);
    await t.tap(find.byKey(const ValueKey('mode-streak')));
    await pump(t);
    expect(find.byKey(const ValueKey('mode-stars')), findsOneWidget);
    expect(find.byKey(const ValueKey('lb-state')), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // the error view's own retry timer must not outlive the test
    await t.pump(const Duration(seconds: 15));
  });

  testWidgets('paging: «بیشتر نشون بده» loads the next page once and goes away on the last page', (t) async {
    server({'/v1/leaderboard': (u) {
      final off = int.tryParse(u.queryParameters['offset'] ?? '') ?? 0;
      return {
        'period': 'all', 'title': 'همه', 'me': null,
        'top': [for (int i = off + 1; i <= off + 5; i++) row(i, value: 1000 - i)],
        'next_offset': off == 0 ? 5 : null,
      };
    }});
    await t.pumpWidget(host(const LeaderboardBoard('all')));
    await pump(t);
    await t.dragUntilVisible(find.byKey(const ValueKey('lb-more')), find.byType(ListView), const Offset(0, -200));
    await t.tap(find.byKey(const ValueKey('lb-more')));
    await pump(t);
    expect(requests.last.queryParameters['offset'], '5');
    expect(find.byKey(const ValueKey('lb-more')), findsNothing);
    await t.dragUntilVisible(find.text('کارآگاه10'), find.byType(ListView), const Offset(0, -200));
    expect(find.text('کارآگاه10'), findsOneWidget);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets('no overflow at text scale $scale (daily with stats, gap and my pinned row)', (t) async {
      server({'/v1/leaderboard': (_) => dailyBoard()});
      await t.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(host(const LeaderboardBoard('daily'), scale: scale));
      await pump(t);
      expect(find.byKey(const ValueKey('daily-stats-line')), findsOneWidget);
      final e = t.takeException();
      if (e != null) debugPrint('OVERFLOW DETAILS: $e');
      expect(e, isNull);
    });
  }
}
