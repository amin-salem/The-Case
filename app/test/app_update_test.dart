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

  Widget scaled(Widget child, double scale) => MaterialApp(
        builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: TextDirection.rtl, child: c!)),
        home: child,
      );

  Widget opener() => Builder(
      builder: (context) => Scaffold(
            body: Column(children: [
              TextButton(key: const ValueKey('open_modal'), onPressed: () => showUpdateModal(context), child: const Text('x')),
              const UpdateChip(),
            ]),
          ));

  test('bonusCoins: from the config, bounded 0..300, 0 when absent (old server)', () {
    expect(AppUpdate.i.bonusCoins, 0);
    Api.i.config = {'update_bonus_coins': 50};
    expect(AppUpdate.i.bonusCoins, 50);
    Api.i.config = {'update_bonus_coins': 9999};
    expect(AppUpdate.i.bonusCoins, 300);
    Api.i.config = {'update_bonus_coins': -4};
    expect(AppUpdate.i.bonusCoins, 0);
    Api.i.config = {'update_bonus_coins': 'x'};
    expect(AppUpdate.i.bonusCoins, 0);
  });

  testWidgets('modal: title, reward line, big button; the reward line is hidden when there are no coins', (t) async {
    Api.i.config = {'latest_version': 79, 'update_bonus_coins': 50};
    await t.pumpWidget(scaled(opener(), 1));
    await AppUpdate.i.load();
    await t.tap(find.byKey(const ValueKey('open_modal')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_modal')), findsOneWidget);
    expect(find.text('نسخه‌ی تازه آماده‌ست'), findsOneWidget);
    expect(find.text('۵۰ سکه هدیه‌ی آپدیت'), findsOneWidget);
    expect(find.text('آپدیت در کافه بازار'), findsOneWidget);
    expect(find.text('بعداً یادآوری کن'), findsOneWidget);
    expect(t.getSize(find.byKey(const ValueKey('update_close'))).shortestSide, greaterThanOrEqualTo(44));
    await t.tap(find.byKey(const ValueKey('update_later')));
    await t.pumpAndSettle();
    Api.i.config = {'latest_version': 79, 'update_bonus_coins': 0};
    await t.tap(find.byKey(const ValueKey('open_modal')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_reward')), findsNothing);
  });

  testWidgets('modal fits at text scale 1.3 and 2.0 on a small phone', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    for (final scale in [1.3, 2.0]) {
      Api.i.config = {'latest_version': 79, 'update_bonus_coins': 50};
      await t.pumpWidget(scaled(opener(), scale));
      await AppUpdate.i.load();
      await t.tap(find.byKey(const ValueKey('open_modal')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'scale $scale');
      expect(find.text('آپدیت در کافه بازار'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('update_close')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'scale $scale chip');
    }
  });

  testWidgets('the button opens the store and closes the modal; each exit hides it and shows the chip', (t) async {
    Api.i.config = {'latest_version': 79, 'update_bonus_coins': 50};
    final opened = <Uri>[];
    AppUpdate.launcher = (u) async {
      opened.add(u);
      return true;
    };
    addTearDown(() => AppUpdate.launcher = (u) async => false);
    await t.pumpWidget(scaled(opener(), 1));
    await AppUpdate.i.load();
    expect(find.byKey(const ValueKey('update_chip')), findsNothing, reason: 'modal not closed yet: no chip');
    await t.tap(find.byKey(const ValueKey('open_modal')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('update_open')));
    await t.pumpAndSettle();
    expect(opened, isNotEmpty);
    expect(find.byKey(const ValueKey('update_modal')), findsNothing);
    expect(find.text('نسخه‌ی تازه هست · ۵۰ سکه هدیه'), findsOneWidget);
    expect(AppUpdate.i.bannerVisible, isFalse);
    // the chip opens it again, and ✕ closes it
    await t.tap(find.byKey(const ValueKey('update_chip')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_modal')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('update_close')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('update_modal')), findsNothing);
  });

  test('modalDue: once per launch, not when closed, never with the forced-update page, never when up to date', () async {
    Api.i.config = {'latest_version': 79};
    expect(AppUpdate.i.modalDue, isFalse, reason: 'preferences not read yet: the 3-day closing is unknown');
    await AppUpdate.i.load();
    expect(AppUpdate.i.modalDue, isTrue);
    AppUpdate.i.markModalShown();
    expect(AppUpdate.i.modalDue, isFalse);
    AppUpdate.i.resetForTest();
    await AppUpdate.i.load();
    Api.i.config = {'latest_version': 80, 'min_version': 79};
    expect(AppUpdate.i.modalDue, isFalse);
    expect(AppUpdate.i.chipVisible, isFalse);
    Api.i.config = {'latest_version': 78};
    expect(AppUpdate.i.modalDue, isFalse);
    expect(AppUpdate.i.chipVisible, isFalse);
    Api.i.config = {'latest_version': 79};
    await AppUpdate.i.closeBanner();
    expect(AppUpdate.i.modalDue, isFalse);
    expect(AppUpdate.i.chipVisible, isTrue);
    clock = clock.add(const Duration(days: 4));
    expect(AppUpdate.i.modalDue, isTrue);
    expect(AppUpdate.i.chipVisible, isFalse);
  });

  test('thank-you is taken once', () {
    AppUpdate.i.thank(0);
    expect(AppUpdate.i.takeThanks(), 0);
    AppUpdate.i.thank(50);
    expect(AppUpdate.i.takeThanks(), 50);
    expect(AppUpdate.i.takeThanks(), 0);
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
