import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/main_shell.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/services/archive_picks.dart';
import 'package:the_case/widgets/archive_picks.dart';
import 'package:the_case/theme.dart';
import 'home_fixtures.dart';

CaseRow _row(String id, int n, {bool solved = false, bool failed = false, bool locked = true, int cost = 150, String cat = 'medical'}) =>
    CaseRow({'id': id, 'number': n, 'title': 'پرونده‌ی $id', 'category': cat, 'difficulty': 2, 'unlock_cost': cost,
      'locked': locked, 'solved': solved, 'failed': failed});

Map<String, dynamic> _body() => {
      'picks': [
        {'case_id': 'a1', 'reason': 'easy', 'solve_rate': 89, 'players': 40, 'unlock_cost': 150},
        {'case_id': 'a2', 'reason': 'popular', 'rating_avg': 4.6, 'rating_count': 25},
        {'case_id': 'a3', 'reason': 'taste', 'category': 'medical', 'category_solved': 3},
      ]
    };

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
      theme: buildTheme(),
      builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(textDirection: TextDirection.rtl, child: c!)),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('parsing', () {
    test('keeps the three reasons and their real numbers', () {
      final p = ArchivePick.parseAll(_body());
      expect(p.map((e) => e.label), ['آسان', 'پرطرفدار', 'سلیقه‌ی تو']);
      expect(p[0].explanation, contains('۸۹٪ کارآگاه‌ها حلش کردن'));
      expect(p[1].explanation, contains('۴٫۶'));
      expect(p[1].explanation, contains('۲۵ امتیاز'));
      expect(p[2].explanation, contains('۳ پرونده‌ی «پزشکی»'));
    });

    test('a strange or empty answer gives no picks and never throws', () {
      for (final b in [null, 5, 'x', {}, {'picks': 'no'}, {'picks': []}, {'picks': [5, {'reason': 'easy'}, {'case_id': 'a', 'reason': 'weird'}]}]) {
        expect(ArchivePick.parseAll(b), isEmpty, reason: '$b');
      }
    });

    test('at most three, one per case; a reason without numbers does not invent any', () {
      final many = {'picks': [for (var i = 0; i < 5; i++) {'case_id': 'a${i % 4}', 'reason': 'easy'}]};
      final p = ArchivePick.parseAll(many);
      expect(p.length, 3);
      expect(p.map((e) => e.caseId).toSet().length, 3);
      expect(p.first.explanation, isNot(contains('٪')));
    });

    test('only unsolved, not lost, not tonight\'s cases in the list can be shown', () {
      final picks = ArchivePick.parseAll({'picks': [for (final id in ['a1', 'a2', 'a3', 'gone']) {'case_id': id, 'reason': 'easy'}]});
      final rows = [_row('a1', 1), _row('a2', 2, solved: true), _row('a3', 3, failed: true)];
      expect(showablePicks(picks, rows).map((e) => e.row.id), ['a1']);
    });
  });

  group('the row', () {
    Future<void> pumpRow(WidgetTester t, List<CaseRow> opened, {double scale = 1, List<CaseRow>? rows}) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      final r = rows ?? [_row('a1', 1, cost: 120), _row('a2', 2, cost: 220), _row('a3', 3, cost: 180)];
      await t.pumpWidget(_host(
          ArchivePicksRow(items: showablePicks(ArchivePick.parseAll(_body()), r), solvedCount: 12, onOpen: opened.add),
          scale: scale));
    }

    testWidgets('three equal cards; tapping one changes the detail card; the button uses the chosen case', (t) async {
      final opened = <CaseRow>[];
      await pumpRow(t, opened);
      expect(find.text('پیشنهاد برای تو'), findsOneWidget);
      expect(find.textContaining('از روی ۱۲ پرونده'), findsOneWidget);
      final w = [for (var i = 0; i < 3; i++) t.getSize(find.byKey(ValueKey('archive-pick-$i'))).width];
      expect(w[0], closeTo(w[1], 0.5));
      expect(w[1], closeTo(w[2], 0.5));
      // RTL: the first card sits on the right
      expect(t.getTopLeft(find.byKey(const ValueKey('archive-pick-0'))).dx, greaterThan(t.getTopLeft(find.byKey(const ValueKey('archive-pick-1'))).dx));
      expect(find.text('باز کن · ۱۲۰ سکه'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('archive-pick-1')));
      await t.pump();
      expect(find.text('باز کن · ۲۲۰ سکه'), findsOneWidget);
      expect(find.textContaining('۴٫۶'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('archive-pick-open')));
      expect(opened.single.id, 'a2');
    });

    testWidgets('a free first-days price reads «رایگان»; an already opened case just opens', (t) async {
      final opened = <CaseRow>[];
      await pumpRow(t, opened, rows: [_row('a1', 1, cost: 0), _row('a2', 2, locked: false), _row('a3', 3)]);
      expect(find.text('باز کن · رایگان'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('archive-pick-1')));
      await t.pump();
      expect(find.text('باز کن'), findsOneWidget);
    });

    testWidgets('nothing to show means no widget at all', (t) async {
      await pumpRow(t, [], rows: [_row('zz', 9)]);
      expect(find.byKey(const ValueKey('archive-picks')), findsNothing);
      expect(find.text('پیشنهاد برای تو'), findsNothing);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('large text $scale: no overflow, the button stays tappable', (t) async {
        await pumpRow(t, [], scale: scale);
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byKey(const ValueKey('archive-pick-open'))).height, greaterThanOrEqualTo(44));
      });
    }
  });

  group('the archive tab and the weekend tab', () {
    late List<String> events;
    late bool picksFail;

    Future<void> setup(WidgetTester t, {Map<String, dynamic>? picks, bool fail = false}) async {
      await seedHome();
      events = [];
      picksFail = fail;
      Api.i.httpClient = MockClient((r) async {
        if (r.url.path == '/v1/cases') return jsonResponse(casesBody());
        if (r.url.path == '/v1/cases/picks') {
          if (picksFail) return jsonResponse({'detail': 'boom'}, 500);
          return jsonResponse(picks ?? _body());
        }
        if (r.url.path == '/v1/events') {
          for (final e in (jsonDecode(r.body)['events'] as List)) {
            events.add('${e['name']}|${jsonEncode(e['props'])}');
          }
          return jsonResponse({'stored': 1});
        }
        if (r.url.path == '/v1/missions') return jsonResponse(missionsBody());
        return jsonResponse({});
      });
      MainShell.resetWeekendTabLog();
      await pumpApp(t);
    }

    Future<void> goTo(WidgetTester t, String label) async {
      await t.tap(find.text(label).last);
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
    }

    testWidgets('the archive shows the row on top; the filters and the list stay', (t) async {
      await setup(t);
      await goTo(t, 'بایگانی');
      expect(find.byKey(const ValueKey('archive-picks')), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
    });

    testWidgets('a server error on the suggestions hides the row and nothing else', (t) async {
      await setup(t, fail: true);
      await goTo(t, 'بایگانی');
      expect(find.byKey(const ValueKey('archive-picks')), findsNothing);
      expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
    });

    testWidgets('no picks, no row', (t) async {
      await setup(t, picks: {'picks': []});
      await goTo(t, 'بایگانی');
      expect(find.byKey(const ValueKey('archive-picks')), findsNothing);
    });

    testWidgets('opening the «آخر هفته» tab logs one event per launch, with no props', (t) async {
      await setup(t);
      await goTo(t, 'آخر هفته');
      await goTo(t, 'خانه');
      await goTo(t, 'آخر هفته');
      expect(events.where((e) => e.startsWith('weekend_tab_open')).toList(), ['weekend_tab_open|{}']);
    });
  });
}
