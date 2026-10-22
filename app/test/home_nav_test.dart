import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/screens/archive_screen.dart';
import 'package:the_case/screens/main_shell.dart';
import 'home_fixtures.dart';

const _navHeight = 66.0;

Future<void> systemBack(WidgetTester t) async {
  final message = const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute'));
  await t.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation', message, (_) {});
}

int selectedTab(WidgetTester t) => t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  group('bottom navigation', () {
    testWidgets('five tabs in order; the active one is selected; switching works', (t) async {
      await seedHome();
      await pumpApp(t);
      final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 5);
      expect([for (final d in bar.destinations) (d as NavigationDestination).label],
          ['خانه', 'بایگانی', 'آخر هفته', 'برترها', 'پروفایل']);
      expect(selectedTab(t), MainShell.home);
      await t.tap(find.text('بایگانی').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), MainShell.archive);
      expect(find.byType(ArchiveScreen), findsOneWidget);
      await t.tap(find.text('خانه').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), MainShell.home);
    });

    testWidgets('each tab is at least 48 dp tall and wide', (t) async {
      await seedHome();
      await pumpApp(t);
      for (final label in ['خانه', 'بایگانی', 'آخر هفته', 'برترها', 'پروفایل']) {
        final r = t.getRect(find.ancestor(of: find.text(label).last, matching: find.byType(NavigationDestination)).first);
        expect(r.height, greaterThanOrEqualTo(48), reason: label);
        expect(r.width, greaterThanOrEqualTo(48), reason: label);
      }
    });

    testWidgets('a tab keeps its state when the player switches away and back', (t) async {
      await seedHome();
      await pumpApp(t);
      await t.tap(find.text('بایگانی').last);
      await t.pump(const Duration(milliseconds: 400));
      await t.enterText(find.byKey(const ValueKey('archive-search')), '۲۸');
      await t.pump();
      await t.tap(find.text('خانه').last);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('بایگانی').last);
      await t.pump(const Duration(milliseconds: 400));
      final field = t.widget<TextField>(find.byKey(const ValueKey('archive-search')));
      expect(field.controller!.text, '۲۸');
    });

    testWidgets('Android back from another tab goes home first; on home it leaves the app', (t) async {
      await seedHome();
      await pumpApp(t);
      await t.tap(find.text('برترها').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), MainShell.leaderboard);
      await systemBack(t);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), MainShell.home);
      final popScope = t.widget<PopScope>(find.byType(PopScope).first);
      expect(popScope.canPop, isTrue, reason: 'on home, back may leave the app');
    });

    testWidgets('the bar is hidden inside a case (any screen pushed above the shell)', (t) async {
      await seedHome();
      await pumpApp(t);
      expect(find.byType(NavigationBar), findsOneWidget);
      final ctx = t.element(find.byType(NavigationBar));
      Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('داخل پرونده'))));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('داخل پرونده'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('weekend tab shows a dot only while a weekend case is open and unsolved', (t) async {
      await seedHome(weekend: 'open');
      await pumpApp(t);
      expect(find.byKey(const ValueKey('weekend-dot')), findsOneWidget);
      await seedHome(weekend: 'solved');
      MainShell.weekendOpen.value = false;
      await pumpApp(t);
      expect(find.byKey(const ValueKey('weekend-dot')), findsNothing);
      await seedHome();
      await pumpApp(t);
      expect(find.byKey(const ValueKey('weekend-dot')), findsNothing);
    });
  });

  group('home', () {
    testWidgets('before solved: hero, real archive count and real weekend state, header with coins', (t) async {
      await seedHome(weekend: 'open');
      await pumpApp(t);
      expect(find.text('ساعت‌شمار موتور'), findsOneWidget);
      expect(find.text('شروع تحقیقات'), findsOneWidget);
      expect(find.textContaining('رایگان'), findsOneWidget);
      expect(find.text('سلام، آرش'), findsOneWidget);
      expect(find.text('بایگانی پرونده‌ها'), findsOneWidget);
      expect(find.text('۳ پرونده منتظرته'), findsOneWidget); // 4 old cases, 1 solved
      expect(find.text('پرونده‌ی آخر هفته'), findsOneWidget);
      expect(find.textContaining('باز است'), findsOneWidget);
      expect(find.text('مأموریت‌های امروز'), findsOneWidget);
      expect(find.text('۱ از ۳'), findsOneWidget);
      expect(find.text('۴ شب پشت سر هم'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-solved')), findsNothing);
    });

    testWidgets('weekend card with no open case says closed', (t) async {
      await seedHome();
      await pumpApp(t);
      expect(find.textContaining('بسته'), findsWidgets);
    });

    testWidgets('the archive card opens the archive tab', (t) async {
      await seedHome();
      await pumpApp(t);
      await t.tap(find.byKey(const ValueKey('quick-archive')));
      await t.pump(const Duration(milliseconds: 400));
      expect(selectedTab(t), MainShell.archive);
      expect(find.byType(ArchiveScreen), findsOneWidget);
    });

    testWidgets('the weekend card opens the weekend tab', (t) async {
      await seedHome(weekend: 'open');
      await pumpApp(t);
      await t.tap(find.byKey(const ValueKey('quick-weekend')));
      await t.pump(const Duration(milliseconds: 400));
      expect(selectedTab(t), MainShell.weekend);
    });

    testWidgets('after solved: result card and archive invitation instead of the hero', (t) async {
      await seedHome(tonight: 'solved');
      await pumpApp(t);
      expect(find.byKey(const ValueKey('home-hero')), findsNothing);
      expect(find.text('شروع تحقیقات'), findsNothing);
      expect(find.text('پرونده‌ی امشب حل شد'), findsOneWidget);
      expect(find.textContaining('مرور نتیجه'), findsOneWidget);
      expect(find.text('یک پرونده‌ی دیگر؟'), findsOneWidget);
      expect(find.text('۳ پرونده‌ی بایگانی منتظرته'), findsOneWidget);
      await t.tap(find.text('برو به بایگانی'));
      await t.pump(const Duration(milliseconds: 400));
      expect(selectedTab(t), MainShell.archive);
    });

    testWidgets('lost today: closed, second chance with the real reopen price, no answer', (t) async {
      await seedHome(tonight: 'lost');
      await pumpApp(t);
      expect(find.text('پرونده‌ی امشب بسته شد'), findsOneWidget);
      expect(find.textContaining('۳۰۰ سکه'), findsWidgets);
      expect(find.text('فرصت دوباره · ۳۰۰ سکه'), findsOneWidget);
      expect(find.text('شروع تحقیقات'), findsNothing);
      expect(find.byKey(const ValueKey('home-hero')), findsNothing);
    });

    testWidgets('the «تازه‌ها» section is collapsed and opens with the old entries', (t) async {
      await seedHome();
      await pumpApp(t);
      await t.scrollUntilVisible(find.byKey(const ValueKey('news-toggle')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('چی تازه شده؟'), findsNothing);
      await t.tap(find.byKey(const ValueKey('news-toggle')));
      await t.pump(const Duration(milliseconds: 300));
      for (final s in ['چی تازه شده؟', 'داستان', 'دعوت دوستان', 'جدول برترها', 'فروشگاه']) {
        expect(find.text(s), findsWidgets, reason: s);
      }
    });

    testWidgets('offline: the short strip says so', (t) async {
      await seedHome(online: false);
      await pumpApp(t);
      expect(find.textContaining('آفلاینی'), findsOneWidget);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('360x740 at font $scale: the hero and both quick cards are on the first screen', (t) async {
        await seedHome(weekend: 'open');
        await pumpApp(t, scale: scale);
        final visibleBottom = 740 - _navHeight;
        for (final k in ['home-hero', 'quick-archive', 'quick-weekend']) {
          final r = t.getRect(find.byKey(ValueKey(k)));
          expect(r.bottom, lessThanOrEqualTo(visibleBottom), reason: '$k must be above the bottom bar');
        }
        expect(t.takeException(), isNull);
      });
    }

    for (final scale in [1.0, 1.3, 2.0]) {
      for (final state in ['open', 'solved', 'lost']) {
        testWidgets('no overflow at font $scale, tonight $state', (t) async {
          await seedHome(tonight: state, weekend: 'open');
          await pumpApp(t, scale: scale);
          expect(t.takeException(), isNull);
          await t.scrollUntilVisible(find.byKey(const ValueKey('news-toggle')), 200, scrollable: find.byType(Scrollable).first);
          await t.tap(find.byKey(const ValueKey('news-toggle')));
          await t.pump(const Duration(milliseconds: 300));
          expect(t.takeException(), isNull);
          for (final tab in ['بایگانی', 'آخر هفته', 'برترها', 'پروفایل']) {
            await t.tap(find.text(tab).last);
            await t.pump(const Duration(milliseconds: 400));
            expect(t.takeException(), isNull, reason: tab);
          }
        });
      }
    }
  });
}
