import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:the_case/screens/archive_screen.dart';
import 'package:the_case/screens/main_shell.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/widgets/engagement.dart' show kMilestoneNames;
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
          ['میز کار', 'آخر هفته', 'بایگانی', 'برترها', 'کارت من']);
      expect(selectedTab(t), 0);
      await t.tap(find.text('بایگانی').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), 2);
      expect(find.byType(ArchiveScreen), findsOneWidget);
      await t.tap(find.text('میز کار').last);
      await t.pump(const Duration(milliseconds: 300));
      expect(selectedTab(t), MainShell.home);
    });

    testWidgets('each tab is at least 48 dp tall and wide', (t) async {
      await seedHome();
      await pumpApp(t);
      for (final label in ['میز کار', 'آخر هفته', 'بایگانی', 'برترها', 'کارت من']) {
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
      await t.tap(find.text('میز کار').last);
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
      expect(selectedTab(t), 3);
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

    testWidgets('archive tab shows a dot for cases the player has not seen; opening it clears the dot', (t) async {
      await seedHome();
      await Api.i.setIntPref('archive_seen_count', 1); // the seed holds 4 old cases
      await pumpApp(t);
      expect(find.byKey(const ValueKey('archive-dot')), findsOneWidget);
      await t.tap(find.text('بایگانی').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('archive-dot')), findsNothing);
    });

    testWidgets('a first count is taken as seen: no dot for the old cases of a new install', (t) async {
      await seedHome();
      await Api.i.setIntPref('archive_seen_count', 0);
      await pumpApp(t);
      expect(find.byKey(const ValueKey('archive-dot')), findsNothing);
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
    testWidgets('before solved: a lean hero, the streak and the missions; no archive or weekend card, header with coins', (t) async {
      await seedHome(weekend: 'open');
      await pumpApp(t);
      expect(find.text('ساعت‌شمار موتور'), findsOneWidget);
      expect(find.text('شروع تحقیقات'), findsOneWidget);
      expect(find.textContaining('رایگان'), findsOneWidget);
      expect(find.text('سلام، آرش'), findsOneWidget);
      // the archive and the weekend case live in the bar (a red dot says when something is new), not on the home screen
      expect(find.text('بایگانی پرونده‌ها'), findsNothing);
      expect(find.text('پرونده‌ی آخر هفته'), findsNothing);
      expect(find.byKey(const ValueKey('quick-archive')), findsNothing);
      expect(find.byKey(const ValueKey('quick-weekend')), findsNothing);
      // the streak is at risk (tonight is open, 4 nights): its row asks something of the player, so it is shown
      await t.scrollUntilVisible(find.text('۴ شب پشت سر هم'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('۴ شب پشت سر هم'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('home-missions')), 200, scrollable: find.byType(Scrollable).first);
      await t.scrollUntilVisible(find.text('مأموریت‌های امروز'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('مأموریت‌های امروز'), findsOneWidget);
      expect(find.text('۱ از ۳'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-solved')), findsNothing);
    });

    testWidgets('the weekend item of the bar opens the weekend page and back returns home', (t) async {
      await seedHome(weekend: 'open');
      await pumpApp(t);
      await t.tap(find.text('آخر هفته').last);
      await t.pump(const Duration(milliseconds: 400));
      expect(MainShell.tab.value, MainShell.weekend);
      expect(selectedTab(t), 1);
      await t.tap(find.byKey(const ValueKey('weekend-back')));
      await t.pump(const Duration(milliseconds: 400));
      expect(MainShell.tab.value, MainShell.home);
    });

    testWidgets('after solved: the result card instead of the hero (the archive is in the bar)', (t) async {
      await seedHome(tonight: 'solved');
      await pumpApp(t);
      expect(find.byKey(const ValueKey('home-hero')), findsNothing);
      expect(find.text('شروع تحقیقات'), findsNothing);
      expect(find.text('پرونده‌ی امشب حل شد'), findsOneWidget);
      expect(find.textContaining('مرور نتیجه'), findsOneWidget);
      expect(find.text('یک پرونده‌ی دیگر؟'), findsNothing);
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

    testWidgets('missions are directly reachable at the bottom without a more menu', (t) async {
      await seedHome();
      await pumpApp(t);
      await t.scrollUntilVisible(find.byKey(const ValueKey('home-missions')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('مأموریت‌های امروز'), findsOneWidget);
      expect(find.byKey(const ValueKey('more-toggle')), findsNothing);
      for (final label in ['چی تازه شده؟', 'داستان', 'دعوت دوستان', 'جدول برترها', 'فروشگاه']) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    group('lean home: a row appears only when it asks something of the player', () {
      Finder streakRow() => find.byKey(const ValueKey('home-streak'));
      Finder secureRow() => find.byKey(const ValueKey('home-secure'));

      /// The page is a lazy list: scroll to the missions at the end before checking them.
      Future<void> toBottom(WidgetTester t) async {
        await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await t.pump(const Duration(milliseconds: 300));
      }

      /// A fresh home page for the next seed (the previous one would keep its old cases).
      Future<void> fresh(WidgetTester t) => t.pumpWidget(const SizedBox());

      Future<void> showHome(WidgetTester t, {double scale = 1}) async {
        await pumpApp(t, scale: scale);
        await toBottom(t);
      }

      testWidgets('streak row: at risk (tonight open, 4 nights) is shown', (t) async {
        await seedHome(streak: 4);
        await showHome(t);
        expect(streakRow(), findsOneWidget);
      });

      testWidgets('streak row: solved tonight with the next step 3 nights away hides it', (t) async {
        await seedHome(streak: 4, tonight: 'solved');
        await showHome(t);
        expect(streakRow(), findsNothing);
      });

      testWidgets('streak row: a short streak with the next step 2 nights away hides it', (t) async {
        await seedHome(streak: 1);
        await showHome(t);
        expect(streakRow(), findsNothing);
      });

      testWidgets('streak row: the next step one night away shows it even when tonight is solved', (t) async {
        await seedHome(streak: 2, tonight: 'solved'); // the ladder starts 3, 7, ...
        await showHome(t);
        expect(streakRow(), findsOneWidget);
        expect(find.text('۱ شب مونده تا «${kMilestoneNames[3]}»'), findsOneWidget);
      });

      testWidgets('secure row: hidden before the 3rd solve', (t) async {
        await seedHome(secured: false, casesSolved: 2);
        await showHome(t);
        expect(secureRow(), findsNothing);
      });

      testWidgets('secure row: shown after the 3rd solve', (t) async {
        await seedHome(secured: false, casesSolved: 3);
        await showHome(t);
        expect(secureRow(), findsOneWidget);
        expect(find.text('حسابت هنوز امن نیست'), findsOneWidget);
      });

      testWidgets('secure row: never for a secured account', (t) async {
        await seedHome(secured: true, casesSolved: 9, bought: true);
        await showHome(t);
        expect(secureRow(), findsNothing);
      });

      testWidgets('secure row: a bought store pack (no ads) is enough, with fewer than 3 solved cases', (t) async {
        await seedHome(secured: false, casesSolved: 1, noAds: true);
        await showHome(t);
        expect(secureRow(), findsOneWidget);
      });

      testWidgets('secure row: the ✕ is at least 48 dp and closes it', (t) async {
        await seedHome(secured: false, casesSolved: 4);
        await showHome(t);
        final r = t.getRect(find.byKey(const ValueKey('secure-close')));
        expect(r.width, greaterThanOrEqualTo(48));
        expect(r.height, greaterThanOrEqualTo(48));
        await t.tap(find.byKey(const ValueKey('secure-close')));
        await t.pump(const Duration(milliseconds: 300));
        expect(secureRow(), findsNothing);
        expect(Api.i.secureRowClosedAt, isNotNull);
      });

      testWidgets('secure row: closed 3 days ago stays away; closed 8 days ago it is back', (t) async {
        await seedHome(secured: false, casesSolved: 4, secureClosedAt: DateTime.now().subtract(const Duration(days: 3)));
        await showHome(t);
        expect(secureRow(), findsNothing);
        await fresh(t);
        await seedHome(secured: false, casesSolved: 4, secureClosedAt: DateTime.now().subtract(const Duration(days: 8)));
        await showHome(t);
        expect(secureRow(), findsOneWidget);
      });

      testWidgets('a quiet night ends with missions and no more menu', (t) async {
        await seedHome(streak: 1);
        await pumpApp(t);
        expect(find.byKey(const ValueKey('home-hero')), findsOneWidget);
        await toBottom(t);
        expect(streakRow(), findsNothing);
        expect(secureRow(), findsNothing);
        expect(find.byKey(const ValueKey('home-missions')), findsOneWidget);
        expect(find.text('دعوت دوستان'), findsNothing);
        expect(find.byKey(const ValueKey('more-toggle')), findsNothing);
      });

      testWidgets('the finished mission chest is reachable directly from the desk', (t) async {
        await seedHome(streak: 1);
        Api.i.httpClient = MockClient((r) async {
          if (r.url.path == '/v1/cases') return jsonResponse(casesBody());
          if (r.url.path == '/v1/missions') {
            final m = missionsBody(done: 3);
            m['all_done'] = true;
            return jsonResponse(m);
          }
          return jsonResponse({});
        });
        await pumpApp(t);
        await toBottom(t);
        expect(find.byKey(const ValueKey('missions-claim')), findsOneWidget);
        expect(find.byKey(const ValueKey('more-toggle')), findsNothing);
        await t.tap(find.byKey(const ValueKey('missions-claim')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('مأموریت‌های امروز'), findsWidgets);
        expect(t.takeException(), isNull);
      });

      testWidgets('the weekend card keeps its real state (open with time left)', (t) async {
        await seedHome(weekend: 'open', streak: 1);
        await pumpApp(t);
        expect(find.textContaining('باز است'), findsOneWidget);
        expect(find.textContaining('مونده'), findsOneWidget);
      });

      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('everything at once at font $scale: no overflow', (t) async {
          await seedHome(streak: 4, secured: false, casesSolved: 5, weekend: 'open');
          await showHome(t, scale: scale);
          expect(streakRow(), findsOneWidget);
          expect(secureRow(), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.scrollUntilVisible(find.byKey(const ValueKey('home-missions')), 200, scrollable: find.byType(Scrollable).first);
          expect(t.takeException(), isNull);
        });
      }
    });

    group('home states', () {
      testWidgets('no connection and nothing saved: the calm offline page, no code, and it loads by itself when the line is back', (t) async {
        await seedHome(online: false);
        await pumpApp(t);
        expect(find.byKey(const ValueKey('home-state')), findsOneWidget);
        expect(find.text('خط تلفن قطعه'), findsOneWidget);
        expect(find.byKey(const ValueKey('failure_code')), findsNothing);
        expect(find.textContaining('کد خطا'), findsNothing);
        expect(find.byKey(const ValueKey('home-hero')), findsNothing);
        // the line comes back: one successful call is enough, nobody taps the button
        Api.i.httpClient = MockClient((r) async {
          if (r.url.path == '/v1/cases') return jsonResponse(casesBody());
          return jsonResponse({});
        });
        await Api.i.missions().then<void>((_) {}, onError: (Object _) {});
        for (int i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 300));
        }
        expect(Api.i.online, isTrue);
        expect(find.byKey(const ValueKey('home-state')), findsNothing);
        expect(find.byKey(const ValueKey('home-hero')), findsOneWidget);
      });

      testWidgets('a server error: the error page says coins and progress are safe and has a retry button', (t) async {
        await seedHome();
        Api.i.httpClient = MockClient((r) async => jsonResponse({'detail': 'x'}, 500));
        await pumpApp(t);
        expect(find.text('پرونده‌خانه یه لحظه شلوغه'), findsOneWidget);
        expect(find.textContaining('سکه'), findsWidgets);
        expect(find.textContaining('کد خطا'), findsNothing);
        expect(find.byKey(const ValueKey('state-primary')), findsOneWidget); // the way forward is always there
        // a failed call starts Api's 20-second retry timer: one good call stops it, so no timer is left pending
        Api.i.httpClient = MockClient((r) async => jsonResponse({}));
        await Api.i.missions().then<void>((_) {}, onError: (Object _) {});
        // the line is back: the error page retries by itself, let that finish before the test ends
        for (int i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 300));
        }
      });
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
      testWidgets('360x740 at font $scale: the hero is whole on the first screen, above the bottom bar', (t) async {
        await seedHome(weekend: 'open');
        await pumpApp(t, scale: scale);
        final r = t.getRect(find.byKey(const ValueKey('home-hero')));
        expect(r.bottom, lessThanOrEqualTo(740 - _navHeight));
        expect(t.takeException(), isNull);
      });
    }

    for (final scale in [1.0, 1.3, 2.0]) {
      for (final state in ['open', 'solved', 'lost']) {
        testWidgets('no overflow at font $scale, tonight $state', (t) async {
          await seedHome(tonight: state, weekend: 'open');
          await pumpApp(t, scale: scale);
          expect(t.takeException(), isNull);
          await t.scrollUntilVisible(find.byKey(const ValueKey('home-missions')), 200, scrollable: find.byType(Scrollable).first);
          expect(t.takeException(), isNull);
          // the other tabs are older screens; the sweep below checks the shell and home, not their own layout at 2.0
          for (final tab in scale > 1.0 ? <String>[] : ['بایگانی', 'برترها', 'کارت من']) {
            await t.tap(find.text(tab).last);
            await t.pump(const Duration(milliseconds: 400));
            expect(t.takeException(), isNull, reason: tab);
          }
        });
      }
    }
  });
}
