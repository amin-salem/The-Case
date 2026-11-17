import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/services/api.dart';
import 'home_fixtures.dart';

Future<void> _seed({bool withIntro = true, bool solved = false}) async {
  await seedHome(casesSolved: 0);
  Api.i.httpClient = MockClient((r) async {
    if (r.url.path == '/v1/cases') {
      return jsonResponse({
        ...casesBody(),
        if (withIntro) 'intro': caseRow('intro01', 0, 'انگشترِ لبِ پنجره', solved: solved),
      });
    }
    if (r.url.path == '/v1/missions') return jsonResponse(missionsBody());
    return jsonResponse({});
  });
}

void main() {
  test('model: intro is read when sent and null otherwise', () {
    expect(CasesList({'next_case_at': 0, 'archive': [], 'intro': caseRow('intro01', 0, 'x')}).intro?.id, 'intro01');
    expect(CasesList({'next_case_at': 0, 'archive': []}).intro, isNull);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('home: the free first case card shows for a new player (scale $scale)', (t) async {
      await _seed();
      await pumpApp(t, scale: scale, size: const Size(360, 1800));
      // ignore: avoid_print
      print('TEXTS: ${t.widgetList<Text>(find.byType(Text)).map((w) => w.data).take(40).toList()}');
      expect(find.byKey(const ValueKey('home-intro')), findsOneWidget);
      expect(find.text('انگشترِ لبِ پنجره'), findsOneWidget);
      expect(find.text('پرونده‌ی اول · رایگان'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('home: no card without the case, and none once it is solved', (t) async {
    await _seed(withIntro: false);
    await pumpApp(t);
    expect(find.byKey(const ValueKey('home-intro')), findsNothing);
    await _seed(solved: true);
    await pumpApp(t);
    expect(find.byKey(const ValueKey('home-intro')), findsNothing);
  });
}
