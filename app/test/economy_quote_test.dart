import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/archive_screen.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';

http.Response response(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
  headers: {'content-type': 'application/json; charset=utf-8'});
final row = CaseRow({'id': 'c-test', 'title': 'پرونده', 'locked': true, 'unlock_cost': 150,
  'base_solve_rewards': {'1': 10, '2': 20, '3': 30}});
Future<void> pump(WidgetTester t) async { await t.pump(); await t.pump(const Duration(milliseconds: 600)); await t.pump(); }
Future<void> open(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Builder(builder: (context) => Scaffold(
    body: TextButton(onPressed: () => unlockQuotedCase(context, row), child: const Text('خرید پرونده'))))));
  await t.tap(find.text('خرید پرونده')); await pump(t);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'player': 'p', 'secret': 's', 'token': 't',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
    await Api.i.init();
    Api.i.online = true;
    Api.i.profile = Profile({'player_id': 'p', 'coins': 500});
  });

  test('new reward fields are optional and difficulty fallback agrees with server policy', () {
    expect(CaseRow({}).baseSolveRewards, isEmpty);
    expect(CaseRow({'base_solve_rewards': 'bad'}).baseSolveRewards, isEmpty);
    expect(row.maxSolveReward, 30);
    expect(CaseRow({'base_solve_rewards': {'1': -2, 'bad': 3, '3': 45}}).baseSolveRewards, {3: 45});
    for (final value in [null, 0, 6, true, '5', 2.5]) {
      expect(CaseRow({'difficulty': value}).difficulty, 3);
      expect(CaseData({'difficulty': value}).difficulty, 3);
    }
  });

  testWidgets('changed quote is not retried until the player confirms the new visible amount', (t) async {
    final quotes = <int>[];
    Api.i.httpClient = MockClient((r) async {
      if (r.method == 'GET') return response({'player_id': 'p', 'coins': 280});
      quotes.add(jsonDecode(r.body)['expected_cost'] as int);
      return quotes.length == 1 ? response({'detail': {'error': 'price_changed', 'cost': 220}}, 409) : response({});
    });
    await open(t);
    expect(find.text('باز کن · ۱۵۰ سکه'), findsOneWidget);
    await t.tap(find.text('باز کن · ۱۵۰ سکه')); await pump(t);
    expect(quotes, [150]);
    expect(find.text('قیمت پرونده تغییر کرده'), findsOneWidget);
    expect(find.text('باز کن · ۲۲۰ سکه'), findsOneWidget);
    await t.tap(find.text('باز کن · ۲۲۰ سکه')); await pump(t);
    expect(quotes, [150, 220]);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('rejecting a new quote sends no further spending request', (t) async {
    var posts = 0;
    Api.i.httpClient = MockClient((r) async {
      posts++;
      return response({'detail': {'error': 'price_changed', 'cost': 180}}, 409);
    });
    await open(t);
    await t.tap(find.text('باز کن · ۱۵۰ سکه')); await pump(t);
    await t.tap(find.text('نه')); await pump(t);
    expect(posts, 1);
    expect(find.text('باز کن · ۱۸۰ سکه'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('insufficient funds displays the server amount, not a stale row quote', (t) async {
    Api.i.httpClient = MockClient((r) async => response({'detail': {'error': 'not_enough_coins', 'need': 370}}, 402));
    await open(t);
    await t.tap(find.text('باز کن · ۱۵۰ سکه')); await pump(t);
    expect(find.textContaining('۳۷۰ سکه لازمه'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
