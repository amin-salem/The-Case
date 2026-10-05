import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';
import 'services/api.dart';
import 'services/reminders.dart';
import 'services/sound.dart';
import 'theme.dart';
import 'widgets/fx.dart';
import 'widgets/scene.dart';
import 'widgets/typewriter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
  await Api.i.init();
  await Sfx.i.init();
  await Reminders.i.init();
  runApp(const TheCaseApp());
}

class TheCaseApp extends StatefulWidget {
  const TheCaseApp({super.key});

  @override
  State<TheCaseApp> createState() => _TheCaseAppState();
}

class _TheCaseAppState extends State<TheCaseApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // the ambience stops when the app goes to the background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Sfx.i.resumeAll();
      // back from the background: if we were offline, try the server again right away
      if (Api.i.ready && !Api.i.online) unawaited(Api.i.reconnect());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      Sfx.i.pauseAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پرونده',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const StartScreen(),
    );
  }
}

/// Connects to the server, then opens the home screen. Without internet it
/// still opens: the home screen works from what is saved on the phone.
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final started = Api.i.connect();
    if (Api.i.hasCache) {
      // a slow network must not hold the door: the saved data is enough to start
      await Future.any<void>([started, Future<void>.delayed(const Duration(seconds: 5))]);
    } else {
      await started;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => const HomeScreen(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: AnimatedScene(scene: 'villa_rain', height: double.infinity, dim: 0.4)),
        const Positioned.fill(child: Torchlight(child: SizedBox.expand())),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FadeSlideIn(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/icon/logo.png', width: 120, height: 120, filterQuality: FilterQuality.medium),
                  ),
                ),
                const SizedBox(height: 18),
                StampIn(delay: const Duration(milliseconds: 350), child: const StampMark('پرونده', size: 54)),
                const SizedBox(height: 14),
                Text('هر شب ساعت ۹، یه جنایت تازه', textAlign: TextAlign.center, style: tBody(15, color: K.textSoft)),
                const SizedBox(height: 32),
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: K.brass)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
