import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sound.dart';
import '../theme.dart';
import '../services/whats_new.dart';
import '../services/api.dart';
import '../services/app_update.dart';
import '../widgets/update_card.dart';
import 'account_sheets.dart';
import 'archive_screen.dart';
import 'account_screen.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'invite_step_screen.dart';
import 'leaderboard_screen.dart';
import 'story_screen.dart';
import 'weekend_screen.dart';

/// The app's main frame: four items in the bottom bar (the desk, archive, leaderboard, my card); the weekend page opens from the home card.
/// The story opens from the «تازه‌ها» section of the home screen (a normal route, see [openStory]).
/// Quick riddles (riddles_screen.dart) are hidden for now. The shop opens from the coin chip.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Any screen can switch tabs: `MainShell.tab.value = MainShell.weekend;`
  static final ValueNotifier<int> tab = ValueNotifier(0);
  static const home = 0, archive = 1, weekend = 2, leaderboard = 3, profile = 4;
  static const count = 5;

  /// True while a weekend case is open and not yet solved or lost (the home screen sets it): a small dot on the tab.
  static final ValueNotifier<bool> weekendOpen = ValueNotifier(false);

  /// The «آخر هفته» tab was opened and counted in this app launch (at most one `weekend_tab_open` event per launch).
  static bool _weekendTabLogged = false;

  @visibleForTesting
  static void resetWeekendTabLog() => _weekendTabLogged = false;

  /// How the app is left after «بله» in the exit dialog. Tests replace it (a real [SystemNavigator.pop] ends the test).
  static void Function() exitApp = () {
    SystemNavigator.pop();
  };

  /// Story mode is not a tab any more: it opens as a normal screen (from «تازه‌ها» on the home screen).
  static Future<void> openStory(BuildContext context) async {
    Sfx.i.ambient('music_story', volume: Sfx.musicVolume);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
        appBar: AppBar(toolbarHeight: 44, backgroundColor: K.night, title: Text('داستان', style: tDisplay(18))),
        body: const StoryScreen())));
    Sfx.i.ambient('amb_home', volume: Sfx.homeVolume);
  }

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // a tab other than home is rebuilt each time it is opened, so it shows fresh data
  final List<int> _visits = List.filled(MainShell.count, 0);
  final Set<int> _seen = {MainShell.home}; // tabs are built the first time they are opened
  bool _exitDialogOpen = false; // two quick back presses must never stack two dialogs

  @override
  void initState() {
    super.initState();
    MainShell.tab.value = MainShell.home;
    MainShell.tab.addListener(_onTab);
    Api.i.addListener(_checkGate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkGate();
      if ((Api.i.profile?.casesSolved ?? 0) > 0) {
        Api.i.setFlag('intro_done');
        return;
      }
      _firstRun();
    });
  }

  /// First run: the guide, then the optional "friend's invite code" step (both shown once).
  Future<void> _firstRun() async {
    await GuideScreen.maybeShowFirstRun(context);
    if (mounted) await InviteStepScreen.maybeShow(context);
  }

  @override
  void dispose() {
    MainShell.tab.removeListener(_onTab);
    Api.i.removeListener(_checkGate);
    super.dispose();
  }

  /// Email-secured accounts must link a phone number (full screen, no way out until it is done).
  void _checkGate() {
    if (!mounted || !(Api.i.profile?.needsPhone ?? false) || !Api.i.online) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (Api.i.profile?.needsPhone ?? false)) showPhoneGate(context);
    });
  }

  void _onTab() {
    if (!mounted) return;
    final i = MainShell.tab.value;
    if (i == MainShell.weekend) {
      WhatsNew.i.tagOpened('weekend_tab');
      // one event per app launch (the admin panel compares weekdays with Thursday-Saturday); no personal data
      if (!MainShell._weekendTabLogged) {
        MainShell._weekendTabLogged = true;
        Api.i.track('weekend_tab_open');
      }
    }
    setState(() {
      _visits[i]++;
      _seen.add(i);
    });
    // each main tab has its own music; the beds cross-fade
    if (i == MainShell.home) {
      Sfx.i.ambient('amb_home', volume: Sfx.homeVolume);
    } else if (i == MainShell.weekend) {
      Sfx.i.ambient('music_weekend', volume: Sfx.musicVolume);
    } else {
      Sfx.i.ambient('amb_home', volume: Sfx.homeVolume);
    }
  }

  /// Android back on the home tab: ask before leaving. «خیر» (or back again while it is open) just closes the dialog.
  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('exit-dialog'),
        backgroundColor: K.paper,
        scrollable: true, // long texts on a small phone / large font
        content: Text('می‌خوای از برنامه خارج بشی؟', style: tDisplay(18, color: K.ink)),
        actions: [
          TextButton(
              key: const ValueKey('exit-no'),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('خیر', style: tBody(15, color: K.inkSoft))),
          FilledButton(
            key: const ValueKey('exit-yes'),
            style: FilledButton.styleFrom(backgroundColor: K.stamp),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('بله', style: tBody(15, color: Colors.white, w: FontWeight.w700)),
          ),
        ],
      ),
    );
    _exitDialogOpen = false;
    if (leave == true) MainShell.exitApp();
  }

  /// The tab behind each bar item (the weekend page, tab 2, has no item).
  static const _tabs = [MainShell.home, MainShell.archive, MainShell.leaderboard, MainShell.profile];
  static int _navOf(int tab) => tab == MainShell.weekend ? 0 : _tabs.indexOf(tab).clamp(0, 3);

  Widget _page(int i) => switch (i) {
        MainShell.home => const HomeScreen(),
        MainShell.weekend => WeekendScreen(key: ValueKey('wk${_visits[i]}')),
        MainShell.archive => const ArchiveScreen(embedded: true), // keeps its filters; reloads when the tab opens
        MainShell.leaderboard => LeaderboardScreen(key: ValueKey('lb${_visits[i]}')),
        _ => AccountScreen(key: ValueKey('me${_visits[i]}')),
      };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Api.i,
        // older than the server's min_version: only the update page (fails open without a config)
        builder: (context, _) => AppUpdate.i.mustUpdate ? const UpdateRequiredScreen() : _shell(context),
      );

  Widget _shell(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MainShell.tab,
      builder: (context, current, _) => PopScope(
        // back on another tab goes home first; back on home asks «می‌خوای از برنامه خارج بشی؟» (never leaves at once)
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (current != MainShell.home) {
            MainShell.tab.value = MainShell.home;
          } else {
            _confirmExit();
          }
        },
        child: Scaffold(
          body: IndexedStack(index: current, children: [for (int i = 0; i < MainShell.count; i++) _seen.contains(i) ? _page(i) : const SizedBox.shrink()]),
          bottomNavigationBar: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2, // four labels share 360 dp: a huge system font must not break the bar
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: K.night2,
                indicatorColor: K.stamp.withValues(alpha: 0.22),
                labelTextStyle: WidgetStateProperty.resolveWith((s) => tBody(11.5,
                    w: FontWeight.w700, color: s.contains(WidgetState.selected) ? K.text : K.textSoft)),
                iconTheme: WidgetStateProperty.resolveWith(
                    (s) => IconThemeData(color: s.contains(WidgetState.selected) ? K.brass : K.textSoft, size: 24)),
              ),
              child: NavigationBar(
                height: 66,
                // the weekend page is not in the bar (it opens from the home card): the bar keeps «میز کار» lit there
                selectedIndex: _navOf(current),
                onDestinationSelected: (i) {
                  Sfx.i.play('tap', volume: 0.4);
                  MainShell.tab.value = _tabs[i];
                },
                destinations: [
                  NavigationDestination(
                      icon: ListenableBuilder(
                          listenable: Listenable.merge([WhatsNew.i, MainShell.weekendOpen]),
                          builder: (_, __) => Badge(
                              key: MainShell.weekendOpen.value ? const ValueKey('weekend-dot') : null,
                              smallSize: 9,
                              isLabelVisible: MainShell.weekendOpen.value,
                              backgroundColor: K.stamp,
                              child: const Icon(Icons.home_outlined))),
                      selectedIcon: const Icon(Icons.home_rounded),
                      label: 'میز کار'),
                  const NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'بایگانی'),
                  const NavigationDestination(
                      icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events_rounded), label: 'برترها'),
                  NavigationDestination(
                      icon: ListenableBuilder(
                          listenable: Api.i,
                          builder: (_, __) => Badge(
                              isLabelVisible: !(Api.i.profile?.secured ?? true) && (Api.i.profile?.casesSolved ?? 0) >= 1,
                              backgroundColor: K.stamp,
                              smallSize: 9,
                              child: const Icon(Icons.badge_outlined))),
                      selectedIcon: const Icon(Icons.badge_rounded),
                      label: 'کارت من'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
