import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:the_case/screens/main_shell.dart';
import 'package:the_case/services/api.dart';
import 'home_fixtures.dart';

void main() {
  Future<void> open(WidgetTester t, {double scale = 1}) async {
    await seedHome();
    Api.i.httpClient = MockClient((r) async {
      if (r.url.path == '/v1/cases') return jsonResponse(casesBody());
      if (r.url.path == '/v1/missions') return jsonResponse(missionsBody());
      if (r.url.path == '/v1/cases/picks') return jsonResponse({'detail': 'none'}, 404);
      return jsonResponse({});
    });
    MainShell.resetWeekendTabLog();
    await pumpApp(t, scale: scale);
    await t.tap(find.text('بایگانی').last);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('one search field and one filter button; the sheet has three groups (font scale $scale)', (t) async {
      await open(t, scale: scale);
      expect(find.byKey(const ValueKey('archive-search')), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-filter-button')), findsOneWidget);
      // the old always-visible chip rows are gone
      expect(find.byKey(const ValueKey('filter-chip-solved')), findsNothing);
      expect(find.byKey(const ValueKey('archive-filter-badge')), findsNothing);
      await t.tap(find.byKey(const ValueKey('archive-filter-button')));
      await settle(t);
      expect(find.text('اصلی'), findsOneWidget);
      expect(find.text('ترتیب'), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-chip-all')), findsOneWidget);
      expect(find.byKey(const ValueKey('sort-chip-hardest')), findsOneWidget);
      expect(find.textContaining('نشان بده · '), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('choosing an option shows the badge, the summary line and the count; clear removes them', (t) async {
    await open(t);
    await t.tap(find.byKey(const ValueKey('archive-filter-button')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('sort-chip-hardest')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('archive-filter-show')));
    await settle(t);
    expect(find.byKey(const ValueKey('archive-filter-badge')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('archive-filter-badge')), matching: find.text('۱')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('archive-summary-line')), matching: find.textContaining('سخت‌ترین')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('archive-filter-button')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('archive-filter-clear')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('archive-filter-show')));
    await settle(t);
    expect(find.byKey(const ValueKey('archive-filter-badge')), findsNothing);
    expect(find.descendant(of: find.byKey(const ValueKey('archive-summary-line')), matching: find.textContaining('تازه‌ترین')), findsOneWidget);
  });
}
