import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/result_screen.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/rate_card.dart';

final _case = CaseData({'id': 'prompt-case', 'title': 'پروندهٔ آزمون', 'scene': 'office',
  'suspects': [{'id': 'a', 'name': 'مظنون', 'avatar': <String, dynamic>{}}],
  'evidence': [{'id': 'e', 'title': 'مدرک', 'text': 'متن مدرک'}]});
final _result = AccuseResult({'result': 'solved', 'culprit': 'a', 'stars': 3, 'reward': 30,
  'explanation': List.filled(12, 'این توضیح پرونده است و کارآگاه باید فرصت خواندنش را داشته باشد.').join(' ')});
http.Response _json(Object data) => http.Response.bytes(utf8.encode(jsonEncode(data)), 200,
  headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _pump(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
  await t.pump();
}

Future<void> _open(WidgetTester t) async {
  await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Builder(builder: (context) => Scaffold(
    body: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ResultScreen(caseData: _case, result: _result))), child: const Text('باز کردن نتیجه'))))));
  await t.tap(find.text('باز کردن نتیجه'));
  await _pump(t);
  await t.pump(const Duration(seconds: 5)); // finish the existing sound/entrance timers
}

Future<void> _read(WidgetTester t) async {
  final expand = find.text('ادامه‌ی توضیح');
  await t.scrollUntilVisible(expand, 250, scrollable: find.byType(Scrollable).first);
  await t.tap(expand);
  await _pump(t);
  final done = find.byKey(const ValueKey('finished-reading'));
  await t.scrollUntilVisible(done, 300, scrollable: find.byType(Scrollable).first);
  await t.tap(done);
  await _pump(t);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'player': 'p1', 'secret': 's1', 'token': 't1',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
    await Api.i.init();
    Api.i.online = true;
    Api.i.profile = Profile({'player_id': 'p1', 'secured': false, 'coins': 100});
    Api.i.httpClient = MockClient((r) async => _json(r.url.path.endsWith('/comments')
      ? {'has_mine': false, 'can_write': true, 'items': [], 'count': 0}
      : <String, dynamic>{}));
  });

  testWidgets('reading for any elapsed time opens no automatic prompt and home stays available', (t) async {
    await _open(t);
    await t.pump(const Duration(minutes: 2));
    expect(find.byType(RateSheet), findsNothing);
    expect(find.textContaining('اولین پرونده‌ات رو حل کردی!'), findsNothing);
    expect(Api.i.flag('rate_sheet_prompt-case'), isFalse);
    final home = find.text('برگشت به خانه');
    await t.scrollUntilVisible(home, 400, scrollable: find.byType(Scrollable).first);
    await t.tap(home);
    await _pump(t);
    expect(find.text('باز کردن نتیجه'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('explicit finish serializes eligible secure then rate; both dismiss and do not repeat', (t) async {
    await _open(t);
    await _read(t);
    expect(find.textContaining('اولین پرونده‌ات رو حل کردی!'), findsOneWidget);
    expect(find.byType(RateSheet), findsNothing);
    await t.tap(find.text('بعداً').last);
    await _pump(t);
    expect(find.textContaining('اولین پرونده‌ات رو حل کردی!'), findsNothing);
    expect(find.byType(RateSheet), findsOneWidget);
    await t.tap(find.descendant(of: find.byType(RateSheet), matching: find.byTooltip('بستن')));
    await _pump(t);
    expect(find.byType(RateSheet), findsNothing);
    expect(Api.i.flag('rate_sheet_prompt-case'), isTrue);
    await t.pump(const Duration(seconds: 30));
    expect(find.byType(RateSheet), findsNothing);
    await t.pumpWidget(const SizedBox());
    await _open(t);
    await _read(t);
    expect(find.byType(RateSheet), findsNothing);
    expect(find.textContaining('اولین پرونده‌ات رو حل کردی!'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('secured accounts skip securing and an inline skip suppresses the automatic rating', (t) async {
    Api.i.profile = Profile({'player_id': 'p1', 'secured': true});
    await Api.i.setFlag('rate_skip_prompt-case', true);
    await _open(t);
    await _read(t);
    expect(find.byType(RateSheet), findsNothing);
    expect(find.textContaining('حسابت رو امن کن'), findsNothing);
    expect(Api.i.flag('rate_sheet_prompt-case'), isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('leaving while rating eligibility is in flight cancels the pending sheet', (t) async {
    Api.i.profile = Profile({'player_id': 'p1', 'secured': true});
    var calls = 0;
    final pending = Completer<http.Response>();
    Api.i.httpClient = MockClient((r) async {
      if (r.url.path.endsWith('/comments') && ++calls > 1) return pending.future;
      return _json({'has_mine': false, 'can_write': true, 'items': [], 'count': 0});
    });
    await _open(t);
    await _read(t);
    final context = t.element(find.byType(ResultScreen));
    Navigator.of(context).popUntil((r) => r.isFirst);
    await _pump(t);
    pending.complete(_json({'has_mine': false, 'can_write': true}));
    await _pump(t);
    expect(find.byType(RateSheet), findsNothing);
    expect(find.text('باز کردن نتیجه'), findsOneWidget);
    expect(Api.i.flag('rate_sheet_prompt-case'), isFalse);
    await t.pumpWidget(const SizedBox());
  });
}
