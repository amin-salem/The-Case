import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/result_screen.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/services/starter_offer.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/next_case_card.dart';
import 'package:the_case/widgets/starter_sheet.dart';

http.Response _json(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: home,
    );

CaseRow _row({int? rate}) => CaseRow({'id': 'c044', 'number': 44, 'title': 'پنجره‌ای که راه خروج نبود', 'category': '', 'difficulty': 4,
      'unlock_cost': 180, 'locked': true, 'suspect_count': 5, if (rate != null) 'solve_rate': rate});

final _case = CaseData({'id': 'solved-case', 'title': 'پروندهٔ آزمون', 'scene': 'office',
  'suspects': [{'id': 'a', 'name': 'مظنون', 'avatar': <String, dynamic>{}}],
  'evidence': [{'id': 'e', 'title': 'مدرک', 'text': 'متن مدرک'}]});
final _result = AccuseResult({'result': 'solved', 'culprit': 'a', 'stars': 3, 'reward': 30, 'explanation': 'توضیح کوتاه'});

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  final events = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({'player': 'p1', 'secret': 's1', 'token': 't1',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
    await Api.i.init();
    Api.i.online = true;
    Api.i.profile = Profile({'player_id': 'p1', 'coins': 85, 'cases_solved': 4, 'secured': true});
    Api.i.config = {'prices': {'starter_pack': '۷۹٬۰۰۰ تومان'}, 'economy': {'products': {'starter_pack': {'coins': 1000, 'no_ads': true}}, 'hint_costs': [40, 80, 120]}};
    events.clear();
    Api.i.httpClient = MockClient((r) async {
      if (r.url.path == '/v1/events') {
        for (final e in (jsonDecode(r.body)['events'] as List)) {
          events.add(e['name'] as String);
        }
        return _json({'stored': 1});
      }
      if (r.url.path == '/v1/cases') {
        return _json({'next_case_at': DateTime.now().add(const Duration(hours: 20)).millisecondsSinceEpoch ~/ 1000,
          'archive': [
            {'id': 'c044', 'number': 44, 'title': 'پنجره‌ای که راه خروج نبود', 'difficulty': 2, 'unlock_cost': 180, 'locked': true, 'suspect_count': 5},
            {'id': 'c030', 'number': 30, 'title': 'حل‌شده', 'difficulty': 2, 'unlock_cost': 150, 'locked': true, 'solved': true},
          ]});
      }
      return _json(<String, dynamic>{});
    });
  });
  tearDown(() => Api.i.config = const {});

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('card: title, meta, one button, no invented rate (text scale $scale)', (t) async {
      var short = 0, open = 0;
      await t.pumpWidget(_app(Scaffold(body: SingleChildScrollView(child: NextCaseCard(row: _row(), coins: 85, onOpen: () => open++, onShort: () => short++, onMore: () {}))), scale: scale));
      expect(find.text('هنوز ذهنت گرمه؛ یکی دیگه؟'), findsOneWidget);
      expect(find.text('پنجره‌ای که راه خروج نبود'), findsOneWidget);
      expect(find.textContaining('۵ مظنون'), findsOneWidget);
      expect(find.textContaining('سختی ۴ از ۵'), findsOneWidget);
      expect(find.byKey(const ValueKey('next-case-rate')), findsNothing);
      expect(find.textContaining('۹۵ سکه کم داری'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('next-case-open')));
      await t.tap(find.byKey(const ValueKey('next-case-open')));
      expect(short, 1);
      expect(open, 0);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('card: the solve rate line appears only when the server sent one', (t) async {
    await t.pumpWidget(_app(Scaffold(body: NextCaseCard(row: _row(rate: 73), coins: 500, onOpen: () {}, onShort: () {}, onMore: () {}))));
    expect(find.text('۷۳٪ کارآگاه‌ها حلش کردن'), findsOneWidget);
    expect(find.text('باز کن · ۱۸۰ سکه'), findsOneWidget);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('sheet: 1000 coins, no ads, real price, one tap closes (text scale $scale)', (t) async {
      await t.pumpWidget(_app(Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => maybeShowStarterSheet(c, StarterMoment.firstSolve), child: const Text('go')))), scale: scale));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('۱٬۰۰۰ سکه'), findsOneWidget);
      expect(find.text('+ همیشه بدون تبلیغ'), findsOneWidget);
      expect(find.text('فقط یک بار برای هر حساب'), findsOneWidget);
      expect(find.textContaining('۷۹٬۰۰۰ تومان'), findsOneWidget);
      expect(find.text('اولین پرونده‌ات رو حل کردی'), findsOneWidget);
      expect(find.text('این پیشنهاد در کل فقط دو بار نشونت داده می‌شه'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const ValueKey('starter-later')));
      await t.tap(find.byKey(const ValueKey('starter-later')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('starter-sheet')), findsNothing);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      expect(events, containsAll(['starter_offer_shown', 'starter_offer_closed']));
    });
  }

  testWidgets('sheet: shown twice in the lifetime of the account, the third time never; ✕ closes too', (t) async {
    await t.pumpWidget(_app(Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => maybeShowStarterSheet(c, StarterMoment.lackCoins, need: 80, what: 'این سرنخ'), child: const Text('go'))))));
    for (var i = 0; i < 2; i++) {
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.text('برای این سرنخ ۸۰ سکه لازم داری'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('starter-x')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('starter-sheet')), findsNothing);
    }
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('starter-sheet')), findsNothing);
    expect(StarterOffer.shown(), 2);
  });

  testWidgets('sheet: never for a player who already bought it or when the store has no such product', (t) async {
    Api.i.profile = Profile({'player_id': 'p1', 'coins': 85, 'no_ads': true});
    await t.pumpWidget(_app(Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => maybeShowStarterSheet(c, StarterMoment.firstSolve), child: const Text('go'))))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('starter-sheet')), findsNothing);
    Api.i.profile = Profile({'player_id': 'p1', 'coins': 85});
    Api.i.config = const {};
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('starter-sheet')), findsNothing);
    expect(StarterOffer.shown(), 0);
  });

  testWidgets('result screen: a suggested case with one button; short on coins opens the starter sheet once', (t) async {
    await t.pumpWidget(_app(ResultScreen(caseData: _case, result: _result)));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 5));
    final card = find.byKey(const ValueKey('next-case-card'));
    await t.scrollUntilVisible(card, 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('پنجره‌ای که راه خروج نبود'), findsOneWidget);
    expect(find.text('حل‌شده'), findsNothing); // a solved archive case is never suggested
    expect(find.byKey(const ValueKey('next-case-rate')), findsNothing);
    expect(find.byKey(const ValueKey('next-opening')), findsOneWidget);
    await t.tap(find.text('باز کن · ۱۸۰ سکه (۹۵ سکه کم داری)'));
    await _settle(t);
    expect(find.byKey(const ValueKey('starter-sheet')), findsOneWidget);
    expect(find.text('برای باز کردن این پرونده ۹۵ سکه لازم داری'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('starter-later')));
    await _settle(t);
    expect(find.byKey(const ValueKey('starter-sheet')), findsNothing);
    expect(StarterOffer.shown(), 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });
}
