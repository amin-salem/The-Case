import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/accuse_screen.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';

final _case = CaseData({
  'id': 'test-case', 'title': 'پروندهٔ آزمون',
  'suspects': [
    for (final id in ['a', 'b', 'c'])
      {'id': id, 'name': 'مظنون $id', 'avatar': <String, dynamic>{}},
  ],
  'evidence': [
    {'id': 'bad', 'title': 'مدرک نامرتبط', 'text': 'این مدرک مرتبط نیست.'},
    {'id': 'good', 'title': 'مدرک مرتبط', 'text': 'این مدرک ادعا را رد می‌کند.'},
  ],
});

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _open(WidgetTester tester, Progress progress, ValueNotifier<String> result) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(),
    home: Builder(builder: (context) => Scaffold(body: Column(children: [
      TextButton(onPressed: () async {
        final answer = await Navigator.of(context).push<AccuseResult>(MaterialPageRoute(
          builder: (_) => AccuseScreen(caseData: _case, progress: progress, marks: const {}),
        ));
        result.value = answer?.result ?? '';
      }, child: const Text('باز کردن')),
      ValueListenableBuilder<String>(valueListenable: result, builder: (_, value, __) => Text('نتیجه: $value')),
    ]))),
  ));
  await tester.tap(find.text('باز کردن'));
  await _pump(tester);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'player': 'p1', 'secret': 's1', 'token': 't1',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400,
    });
    await Api.i.init();
    Api.i.online = true;
  });

  testWidgets('an inconclusive accusation keeps the suspect selectable and can be corrected', (tester) async {
    final sent = <Map<String, dynamic>>[];
    Api.i.httpClient = MockClient((request) async {
      if (request.url.path == '/v1/me') return _json({'player_id': 'p1', 'coins': 100});
      final body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
      sent.add(body);
      if (body['evidence'] == 'good') return _json({'result': 'solved', 'coins': 100, 'stars': 2});
      return _json({
        'result': 'inconclusive', 'attempts_left': 2, 'coins': 100,
        'progress': {'attempts': 1, 'attempts_left': 2, 'wrong_tries': [
          {'s': 'a', 'e': 'bad', 'm': null, 'r': 'inconclusive'},
        ]},
      });
    });
    final result = ValueNotifier<String>('');
    await _open(tester, Progress({'attempts_left': 3}), result);
    await tester.tap(find.text('مظنون a'));
    await tester.pump();
    await tester.tap(find.text('ادامه'));
    await _pump(tester);
    await tester.tap(find.text('مدرک نامرتبط'));
    await tester.pump();
    await tester.tap(find.text('متهم می‌کنم!'));
    await _pump(tester);
    expect(find.textContaining('این اتهام اثبات نشد'), findsOneWidget);
    expect(find.textContaining('این آدم بی‌گناهه'), findsNothing);
    await tester.tap(find.text('مظنون a'));
    await tester.pump();
    await tester.tap(find.text('ادامه'));
    await _pump(tester);
    expect(find.text('کدوم مدرک دروغش رو ثابت می‌کنه؟'), findsOneWidget);
    await tester.tap(find.text('مدرک مرتبط'));
    await tester.pump();
    await tester.tap(find.text('متهم می‌کنم!'));
    await _pump(tester);
    expect(sent.map((b) => b['suspect']), ['a', 'a']);
    expect(result.value, 'solved');
    await tester.pumpWidget(const SizedBox());
    result.dispose();
  });

  for (final kind in ['hasty', 'inconclusive']) {
    testWidgets('reopening a persisted $kind accusation does not exclude its suspect', (tester) async {
      final result = ValueNotifier<String>('');
      final progress = Progress({
        'attempts': 1, 'attempts_left': 2,
        'wrong_tries': [{'s': 'a', 'e': 'bad', 'm': null, 'r': kind}],
      });
      await _open(tester, progress, result);
      await tester.tap(find.text('مظنون a'));
    await tester.pump();
      await tester.tap(find.text('ادامه'));
      await _pump(tester);
      expect(find.text('کدوم مدرک دروغش رو ثابت می‌کنه؟'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      result.dispose();
    });
  }
}
