import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/screens/weekend_tutorial.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';

int _calls = 0;

Widget _app(Widget home, {double scale = 1}) => MaterialApp(
      theme: buildTheme(),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: w!),
      ),
      home: home,
    );

/// A home with one button that opens a weekend case, like the weekend tab does.
Widget _home() => Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: TextButton(onPressed: () => openWeekendCase(ctx, 'w1'), child: const Text('open')),
        ),
      ),
    );

void _bigScreen(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> _tapKey(WidgetTester t, String key) async {
  await t.tap(find.byKey(ValueKey(key)));
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _tapText(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).last);
  await t.tap(find.text(text).last);
  await t.pump(const Duration(milliseconds: 400));
}

/// Plays the whole practice with real taps.
Future<void> _playThrough(WidgetTester t) async {
  await _tapKey(t, 'tut_ch2'); // step 1
  await _tapKey(t, 'tut_accuse'); // step 2
  await _tapText(t, 'کامران'); // open the real suspect sheet
  await _tapText(t, 'یک مدرک نشونش بده');
  await t.tap(find.widgetWithText(ListTile, 'دوربین راهرو'));
  await t.pump(const Duration(milliseconds: 600));
  expect(find.text('۲ از ۳'), findsOneWidget); // the counter goes down
  expect(find.textContaining('واکنش عادی'), findsWidgets);
  await _tapText(t, 'یک مدرک نشونش بده');
  await t.tap(find.widgetWithText(ListTile, 'گِل کنار در پشتی'));
  await t.pump(const Duration(milliseconds: 600));
  expect(find.text('۱ از ۳'), findsOneWidget);
  expect(find.textContaining('لو رفت'), findsWidgets);
  await _tapText(t, 'بستن');
  await t.pump(const Duration(milliseconds: 600));
  expect(find.textContaining('قدم ۵ از ۶'), findsOneWidget);
  await _tapKey(t, 'tut_accuse');
  expect(find.text('چه کسی؟'), findsOneWidget);
  await _tapKey(t, 'who_s1');
  await _tapKey(t, 'tut_confirm'); // wrong culprit
  expect(find.text('اشتباه'), findsOneWidget);
  await _tapKey(t, 'who_s2');
  await _tapKey(t, 'tut_confirm');
  expect(find.text('چرا و چطور؟'), findsOneWidget);
  await _tapKey(t, 'why_m1');
  await _tapKey(t, 'tut_confirm'); // wrong why
  expect(find.text('چرا و چطور؟'), findsOneWidget);
  await _tapKey(t, 'why_m2');
  await _tapKey(t, 'tut_confirm');
  expect(find.text('پرونده حل شد!'), findsOneWidget);
  expect(find.text('بزن بریم'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _calls = 0;
    await Api.i.init();
    Api.i.httpClient = MockClient((r) async {
      _calls++;
      return http.Response('{}', 200);
    });
    weekendCaseBuilder = (id) => Scaffold(
          body: Builder(builder: (ctx) => TextButton(onPressed: () => Navigator.pop(ctx), child: Text('CASE $id'))),
        );
  });

  testWidgets('shows once on the first tap, then the case opens; never again after the flag', (t) async {
    _bigScreen(t);
    await t.pumpWidget(_app(_home()));
    expect(Api.i.flag(kWeekendTutorialFlag), isFalse);

    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('تمرین پرونده‌ی آخر هفته'), findsOneWidget);
    expect(find.text('CASE w1'), findsNothing);

    await _playThrough(t);
    await _tapText(t, 'بزن بریم');
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('CASE w1'), findsOneWidget); // continues into the case
    expect(Api.i.flag(kWeekendTutorialFlag), isTrue);

    await t.tap(find.text('CASE w1'));
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('تمرین پرونده‌ی آخر هفته'), findsNothing);
    expect(find.text('CASE w1'), findsOneWidget);
  });

  testWidgets('skip works at the first step, sets the flag and opens the case', (t) async {
    _bigScreen(t);
    await t.pumpWidget(_app(_home()));
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('رد کردن'), findsOneWidget);
    await t.tap(find.text('رد کردن'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('تمرین پرونده‌ی آخر هفته'), findsNothing);
    expect(find.text('CASE w1'), findsOneWidget);
    expect(Api.i.flag(kWeekendTutorialFlag), isTrue);
  });

  testWidgets('skip is also there inside the suspect sheet', (t) async {
    _bigScreen(t);
    await t.pumpWidget(_app(const WeekendTutorial()));
    await _tapKey(t, 'tut_ch2');
    await _tapKey(t, 'tut_accuse');
    await _tapText(t, 'کامران');
    expect(find.text('رد کردن'), findsNWidgets(2)); // the screen's and the sheet's
    await t.tap(find.text('رد کردن').last);
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(WeekendTutorial), findsNothing);
  });

  testWidgets('replay from the help button, even after the flag', (t) async {
    _bigScreen(t);
    await Api.i.setFlag(kWeekendTutorialFlag);
    await t.pumpWidget(_app(const Scaffold(body: Center(child: WeekendHelpButton()))));
    await t.tap(find.text('راهنما'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('تمرین پرونده‌ی آخر هفته'), findsOneWidget);
    await t.tap(find.text('رد کردن'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('تمرین پرونده‌ی آخر هفته'), findsNothing);
  });

  testWidgets('the practice never calls the server and the accuse flow reaches the finish', (t) async {
    _bigScreen(t);
    await t.pumpWidget(_app(const WeekendTutorial()));
    await _playThrough(t);
    expect(_calls, 0);
  });

  testWidgets('small phone and big text: the first step does not overflow', (t) async {
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const WeekendTutorial(), scale: 1.3));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(find.text('رد کردن'), findsOneWidget);
  });
}
