import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/services/app_update.dart';
import 'package:the_case/widgets/update_card.dart';

Widget _host(Widget child) => MaterialApp(
      builder: (context, c) => Directionality(textDirection: TextDirection.rtl, child: c!),
      home: Scaffold(body: ListView(children: [child])),
    );

void main() {
  var clock = DateTime(2026, 10, 30, 12);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 10, 30, 12);
    AppUpdate.now = () => clock;
    AppUpdate.build = 78;
    Api.i.config = const {};
    AppUpdate.i.resetForTest();
  });
  tearDown(() {
    AppUpdate.build = kAppBuild;
    Api.i.config = const {};
  });

  test('fails open: no config, defaults, junk values -> nothing shows', () {
    expect(AppUpdate.i.bannerVisible, isFalse);
    expect(AppUpdate.i.mustUpdate, isFalse);
    Api.i.config = {'min_version': 1, 'latest_version': 1};
    expect(AppUpdate.i.bannerVisible, isFalse);
    expect(AppUpdate.i.mustUpdate, isFalse);
    Api.i.config = {'min_version': 'abc', 'latest_version': null};
    expect(AppUpdate.i.bannerVisible, isFalse);
    expect(AppUpdate.i.mustUpdate, isFalse);
    Api.i.config = {'min_version': [], 'latest_version': {}};
    expect(AppUpdate.i.mustUpdate, isFalse);
  });

  test('ints may come as strings; same build or newer shows nothing', () {
    Api.i.config = {'latest_version': '79', 'min_version': '1'};
    expect(AppUpdate.i.latestVersion, 79);
    expect(AppUpdate.i.bannerVisible, isTrue);
    AppUpdate.build = 79;
    expect(AppUpdate.i.bannerVisible, isFalse);
    AppUpdate.build = 90;
    expect(AppUpdate.i.bannerVisible, isFalse);
  });

  test('min_version blocks and replaces the banner; url falls back to the Bazaar page', () {
    Api.i.config = {'latest_version': 80, 'min_version': 79, 'update_url': 'javascript:alert(1)'};
    expect(AppUpdate.i.mustUpdate, isTrue);
    expect(AppUpdate.i.bannerVisible, isFalse);
    expect(AppUpdate.i.url, kShareLinkPlaceholder);
    Api.i.config = {'update_url': 'https://cafebazaar.ir/app/x'};
    expect(AppUpdate.i.url, 'https://cafebazaar.ir/app/x');
  });

  testWidgets('below latest: card with the Persian text and the button', (t) async {
    Api.i.config = {'latest_version': 79};
    await t.pumpWidget(_host(const UpdateCard()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_card')), findsOneWidget);
    expect(find.textContaining('نسخه‌ی تازه‌ی پرونده توی کافه بازار منتشر شده'), findsOneWidget);
    expect(find.text('باز کردن کافه بازار'), findsOneWidget);
  });

  testWidgets('up to date or no config: no card', (t) async {
    await t.pumpWidget(_host(const UpdateCard()));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_card')), findsNothing);
    Api.i.config = {'latest_version': 78};
    await t.pumpWidget(_host(const UpdateCard(key: ValueKey('again'))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_card')), findsNothing);
  });

  testWidgets('closing hides it for 3 days, then it returns; a newer latest_version shows it at once', (t) async {
    Api.i.config = {'latest_version': 79};
    await t.pumpWidget(_host(const UpdateCard()));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('update_close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_card')), findsNothing);
    clock = clock.add(const Duration(days: 2));
    expect(AppUpdate.i.bannerVisible, isFalse);
    clock = clock.add(const Duration(days: 2));
    expect(AppUpdate.i.bannerVisible, isTrue);
    clock = DateTime(2026, 10, 30, 13);
    expect(AppUpdate.i.bannerVisible, isFalse);
    Api.i.config = {'latest_version': 80};
    expect(AppUpdate.i.bannerVisible, isTrue);
  });

  testWidgets('below min_version: the full page with one button', (t) async {
    Api.i.config = {'min_version': 79};
    expect(AppUpdate.i.mustUpdate, isTrue);
    await t.pumpWidget(const MaterialApp(home: UpdateRequiredScreen()));
    await t.pumpAndSettle();
    expect(find.text('برای ادامه باید برنامه رو از کافه بازار آپدیت کنی'), findsOneWidget);
    expect(find.text('باز کردن کافه بازار'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(IconButton), findsNothing);
  });
}
