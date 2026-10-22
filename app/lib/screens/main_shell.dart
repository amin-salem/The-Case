import 'package:flutter/material.dart';

import '../services/sound.dart';
import '../theme.dart';
import '../services/whats_new.dart';
import '../services/api.dart';
import 'account_sheets.dart';
import 'archive_screen.dart';
import 'account_screen.dart';
import 'guide_screen.dart';
import 'home_screen.dart';
import 'invite_step_screen.dart';
import 'leaderboard_screen.dart';
import 'story_screen.dart';
import 'weekend_screen.dart';

/// The app's main frame: five tabs at the bottom (home, archive, weekend, leaderboard, profile).
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
    if (i == MainShell.weekend) WhatsNew.i.tagOpened('weekend_tab');
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

  Widget _page(int i) => switch (i) {
        MainShell.home => const HomeScreen(),
        MainShell.weekend => WeekendScreen(key: ValueKey('wk${_visits[i]}')),
        MainShell.archive => const ArchiveScreen(embedded: true), // keeps its filters; reloads when the tab opens
        MainShell.leaderboard => LeaderboardScreen(key: ValueKey('lb${_visits[i]}')),
        _ => AccountScreen(key: ValueKey('me${_visits[i]}')),
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MainShell.tab,
      builder: (context, current, _) => PopScope(
        // back on another tab goes home first; back on home leaves the app
        canPop: current == MainShell.home,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) MainShell.tab.value = MainShell.home;
        },
        child: Scaffold(
          body: IndexedStack(index: current, children: [for (int i = 0; i < MainShell.count; i++) _seen.contains(i) ? _page(i) : const SizedBox.shrink()]),
          bottomNavigationBar: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.2, // five labels share 360 dp: a huge system font must not break the bar
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
                selectedIndex: current,
                onDestinationSelected: (i) {
                  Sfx.i.play('tap', volume: 0.4);
                  MainShell.tab.value = i;
                },
                destinations: [
                  const NavigationDestination(
                      icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'خانه'),
                  const NavigationDestination(
                      icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'بایگانی'),
                  NavigationDestination(
                      icon: ListenableBuilder(
                          listenable: Listenable.merge([WhatsNew.i, MainShell.weekendOpen]),
                          builder: (_, __) => MainShell.weekendOpen.value
                              ? Badge(
                                  key: const ValueKey('weekend-dot'),
                                  smallSize: 9,
                                  backgroundColor: K.stamp,
                                  child: const Icon(Icons.nightlight_outlined))
                              : Badge(
                                  isLabelVisible: WhatsNew.i.tagVisible('weekend_tab'),
                                  label: const Text('تازه'),
                                  backgroundColor: K.stamp,
                                  child: const Icon(Icons.nightlight_outlined))),
                      selectedIcon: const Icon(Icons.nightlight_round),
                      label: 'آخر هفته'),
                  const NavigationDestination(
                      icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events_rounded), label: 'برترها'),
                  NavigationDestination(
                      icon: ListenableBuilder(
                          listenable: Api.i,
                          builder: (_, __) => Badge(
                              isLabelVisible: !(Api.i.profile?.secured ?? true) && (Api.i.profile?.casesSolved ?? 0) >= 1,
                              backgroundColor: K.stamp,
                              smallSize: 9,
                              child: const Icon(Icons.person_outline_rounded))),
                      selectedIcon: const Icon(Icons.person_rounded),
                      label: 'پروفایل'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
