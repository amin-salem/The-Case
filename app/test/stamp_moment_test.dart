import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/screens/settings_screen.dart';
import 'package:the_case/services/haptics.dart';
import 'package:the_case/services/sound.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/typewriter.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
      theme: buildTheme(),
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
        child: Directionality(textDirection: TextDirection.rtl, child: c!),
      ),
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stamp animation', () {
    testWidgets('animations on: the stamp starts invisible and lands after its delay', (t) async {
      await t.pumpWidget(_app(const Center(child: StampIn(delay: Duration(milliseconds: 100), drop: true, child: Text('مهر')))));
      final opacity = t.widget<Opacity>(find.descendant(of: find.byType(StampIn), matching: find.byType(Opacity)));
      expect(opacity.opacity, 0);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 500));
      final landed = t.widget<Opacity>(find.descendant(of: find.byType(StampIn), matching: find.byType(Opacity)));
      expect(landed.opacity, 1);
    });

    testWidgets('reduced motion: the stamp is simply there, no animation widgets, nothing scheduled', (t) async {
      await t.pumpWidget(_app(const Center(child: StampIn(delay: Duration(seconds: 1), drop: true, child: Text('مهر'))), disableAnimations: true));
      expect(find.text('مهر'), findsOneWidget);
      expect(find.descendant(of: find.byType(StampIn), matching: find.byType(Opacity)), findsNothing);
      expect(find.descendant(of: find.byType(StampIn), matching: find.byType(Transform)), findsNothing);
      await t.pump(const Duration(seconds: 2)); // the delay passes: still the same, no error
      expect(find.text('مهر'), findsOneWidget);
    });
  });

  group('haptics switch', () {
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('default is on and the stamp and a button press vibrate', () async {
      SharedPreferences.setMockInitialValues({});
      await Haptics.i.init();
      expect(Haptics.i.on, isTrue);
      Haptics.i.stamp();
      Haptics.i.light();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, hasLength(2));
    });

    test('off: nothing vibrates, for the stamp and for buttons', () async {
      SharedPreferences.setMockInitialValues({Haptics.prefKey: false});
      await Haptics.i.init();
      expect(Haptics.i.on, isFalse);
      Haptics.i.stamp();
      Haptics.i.light();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(calls, isEmpty);
    });

    test('the choice is saved and read back after a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await Haptics.i.init();
      await Haptics.i.setOn(false);
      expect((await SharedPreferences.getInstance()).getBool(Haptics.prefKey), isFalse);
      await Haptics.i.init(); // a new launch
      expect(Haptics.i.on, isFalse);
      await Haptics.i.setOn(true);
      await Haptics.i.init();
      expect(Haptics.i.on, isTrue);
    });
  });

  group('settings toggles «صدا» and «لرزش»', () {
    Widget rows() => ListenableBuilder(
          listenable: Listenable.merge([Sfx.i, Haptics.i]),
          builder: (_, __) => Column(children: feedbackToggleRows()),
        );

    testWidgets('both are on by default, are separate, and are saved', (t) async {
      SharedPreferences.setMockInitialValues({});
      await Haptics.i.init();
      await t.pumpWidget(_app(rows()));
      expect(find.text('صدا'), findsOneWidget);
      expect(find.text('لرزش'), findsOneWidget);
      expect(t.widget<Switch>(find.descendant(of: find.byKey(const ValueKey('setting-sound')), matching: find.byType(Switch))).value, isTrue);
      expect(t.widget<Switch>(find.descendant(of: find.byKey(const ValueKey('setting-haptics')), matching: find.byType(Switch))).value, isTrue);

      // vibration off: sound stays on
      await t.tap(find.byKey(const ValueKey('setting-haptics')));
      await t.pump();
      expect(Haptics.i.on, isFalse);
      expect(Sfx.i.muted, isFalse);
      expect((await SharedPreferences.getInstance()).getBool(Haptics.prefKey), isFalse);

      // sound off: vibration state is untouched
      await t.tap(find.byKey(const ValueKey('setting-sound')));
      await t.pump();
      expect(Sfx.i.muted, isTrue);
      expect(Haptics.i.on, isFalse);
      expect((await SharedPreferences.getInstance()).getBool('muted'), isTrue);

      // back on
      await t.tap(find.byKey(const ValueKey('setting-haptics')));
      await t.tap(find.byKey(const ValueKey('setting-sound')));
      await t.pump();
      expect(Haptics.i.on, isTrue);
      expect(Sfx.i.muted, isFalse);
    });
  });
}
