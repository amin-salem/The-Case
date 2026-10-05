import 'package:flutter/material.dart';

import '../services/sound.dart';
import '../theme.dart';
import 'account_screen.dart';
import 'home_screen.dart';
import 'leaderboard_screen.dart';
import 'riddles_screen.dart';
import 'shop_screen.dart';

/// The app's main frame: five tabs at the bottom (home, daily, leaderboard, shop, profile).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  /// Any screen can switch tabs: `MainShell.tab.value = MainShell.daily;`
  static final ValueNotifier<int> tab = ValueNotifier(0);
  static const home = 0, daily = 1, leaderboard = 2, shop = 3, profile = 4;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // a tab other than home is rebuilt each time it is opened, so it shows fresh data
  final List<int> _visits = List.filled(5, 0);
  final Set<int> _seen = {MainShell.home}; // tabs are built the first time they are opened

  @override
  void initState() {
    super.initState();
    MainShell.tab.value = MainShell.home;
    MainShell.tab.addListener(_onTab);
  }

  @override
  void dispose() {
    MainShell.tab.removeListener(_onTab);
    super.dispose();
  }

  void _onTab() {
    if (!mounted) return;
    final i = MainShell.tab.value;
    setState(() {
      _visits[i]++;
      _seen.add(i);
    });
    if (i == MainShell.home) Sfx.i.ambient('amb_home', volume: 0.28);
  }

  Widget _page(int i) => switch (i) {
        MainShell.home => const HomeScreen(),
        MainShell.daily => RiddlesScreen(key: ValueKey('daily${_visits[i]}'), embedded: true),
        MainShell.leaderboard => LeaderboardScreen(key: ValueKey('lb${_visits[i]}')),
        MainShell.shop => ShopScreen(key: ValueKey('shop${_visits[i]}')),
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
          body: IndexedStack(index: current, children: [for (int i = 0; i < 5; i++) _seen.contains(i) ? _page(i) : const SizedBox.shrink()]),
          bottomNavigationBar: NavigationBarTheme(
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
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'خانه'),
                NavigationDestination(icon: Icon(Icons.bolt_outlined), selectedIcon: Icon(Icons.bolt_rounded), label: 'روزانه'),
                NavigationDestination(
                    icon: Icon(Icons.emoji_events_outlined), selectedIcon: Icon(Icons.emoji_events_rounded), label: 'برترها'),
                NavigationDestination(
                    icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'فروشگاه'),
                NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'پروفایل'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
