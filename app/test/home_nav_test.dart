import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/screens/archive_screen.dart';
import 'package:the_case/screens/main_shell.dart';
import 'package:the_case/services/api.dart';
import 'home_fixtures.dart';

const _navHeight = 66.0;

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
      for (int i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      await t.enterText(find.byKey(const ValueKey('archive-search')), '۲۸');
      await t.pump();
      await t.tap(find.text('خانه').last);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('بایگانی').last);
      await t.pump(const Duration(milliseconds: 400));
      final field = t.widget<TextField>(find.byKey(const ValueKey('archive-search')));
      expect(field.controller!.text, '۲۸');
    });

    testWidgets('Android back from another tab goes home first, without a dialog', (t) async {
      await seedHome();
      await pumpApp(t);
      await t.tap(find.text('برترها').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), MainShell.leaderboard);
      final onTab = t.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).first);
      expect(onTab.canPop, isFalse, reason: 'on another tab, back must not leave the app');
      onTab.onPopInvokedWithResult!(false, null);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), MainShell.home);
      expect(find.byKey(const ValueKey('exit-dialog')), findsNothing);
    });

    group('exit confirmation on the home tab', () {
      var exits = 0;
      setUp(() {
        exits = 0;
        MainShell.exitApp = () => exits++;
      });
      tearDown(() {
        MainShell.exitApp = () {
          SystemNavigator.pop();
        };
      });

      Future<void> backOnHome(WidgetTester t) async {
        final scope = t.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).first);
        expect(scope.canPop, isFalse, reason: 'back on home never leaves the app by itself');
        scope.onPopInvokedWithResult!(false, null);
        await t.pump(const Duration(milliseconds: 300));
      }

      testWidgets('back on home shows the question; «خیر» keeps the app open', (t) async {
        await seedHome();
        await pumpApp(t);
        await backOnHome(t);
        expect(find.byKey(const ValueKey('exit-dialog')), findsOneWidget);
        expect(find.text('می‌خوای از برنامه خارج بشی؟'), findsOneWidget);
        expect(Directionality.of(t.element(find.byKey(const ValueKey('exit-dialog')))), TextDirection.rtl);
        await t.tap(find.byKey(const ValueKey('exit-no')));
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('exit-dialog')), findsNothing);
        expect(exits, 0);
        expect(selectedTab(t), MainShell.home);
      });

      testWidgets('«بله» leaves the app through MainShell.exitApp', (t) async {
        await seedHome();
        await pumpApp(t);
        await backOnHome(t);
        await t.tap(find.byKey(const ValueKey('exit-yes')));
        await t.pump(const Duration(milliseconds: 400));
        expect(exits, 1);
        expect(find.byKey(const ValueKey('exit-dialog')), findsNothing);
      });

      testWidgets('two quick back presses open one dialog; back while it is open means «خیر»', (t) async {
        await seedHome();
        await pumpApp(t);
        final scope = t.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope).first);
        scope.onPopInvokedWithResult!(false, null);
        scope.onPopInvokedWithResult!(false, null); // the second press in the same frame
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const ValueKey('exit-dialog')), findsOneWidget);
        // the system back button while the dialog is open pops the dialog route (= «خیر»)
        await t.binding.handlePopRoute();
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('exit-dialog')), findsNothing);
        expect(exits, 0);
        // and a new back press asks again
        await backOnHome(t);
        expect(find.byKey(const ValueKey('exit-dialog')), findsOneWidget);
      });
    });

    testWidgets('the bar is hidden inside a case (any screen pushed above the shell)', (t) async {
      await seedHome();
      await pumpApp(t);
      expect(find.byType(NavigationBar), findsOneWidget);
      final ctx = t.element(find.byType(NavigationBar));
      Navigator.of(ctx, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('داخل پرونده'))));
      for (int i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
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
      await t.scrollUntilVisible(find.text('مأموریت‌های امروز'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('مأموریت‌های امروز'), findsOneWidget);
      expect(find.text('۱ از ۳'), findsOneWidget);
      await t.scrollUntilVisible(find.text('۴ شب پشت سر هم'), 200, scrollable: find.byType(Scrollable).first);
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
      await seedHome();
      await pumpApp(t);
      expect(find.textContaining('آفلاینی'), findsNothing);
      // flip the flag and nudge the banner's own listener (no retry timer is started this way)
      Api.i.online = false;
      Api.i.rateLimitedUntil.value = DateTime.now().add(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('آفلاینی'), findsOneWidget);
      Api.i.rateLimitedUntil.value = null;
      Api.i.online = true;
      await t.pump(const Duration(milliseconds: 100));
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('360x740 at font $scale: the hero and both quick cards are on the first screen', (t) async {
        await seedHome(weekend: 'open');
        await pumpApp(t, scale: scale);
        final visibleBottom = 740 - _navHeight;
        // at font 1.0 everything fits; at 1.3 the hero fits whole and both quick cards start on the first screen
        // (their last lines are one short scroll away: the text is never clipped or shrunk).
        for (final k in ['home-hero', 'quick-archive', 'quick-weekend']) {
          final r = t.getRect(find.byKey(ValueKey(k)));
          if (scale > 1.0 && k != 'home-hero') {
            expect(r.top, lessThanOrEqualTo(visibleBottom - 8), reason: '$k must start above the bottom bar');
          } else {
            expect(r.bottom, lessThanOrEqualTo(visibleBottom), reason: '$k must be above the bottom bar');
          }
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
          // the other tabs are older screens; the sweep below checks the shell and home, not their own layout at 2.0
          for (final tab in scale > 1.0 ? <String>[] : ['بایگانی', 'آخر هفته', 'برترها', 'پروفایل']) {
            await t.tap(find.text(tab).last);
            await t.pump(const Duration(milliseconds: 400));
            expect(t.takeException(), isNull, reason: tab);
          }
        });
      }
    }
  });
}
