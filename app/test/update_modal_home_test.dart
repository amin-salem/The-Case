import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/services/app_update.dart';
import 'home_fixtures.dart';

void main() {
  setUp(() {
    AppUpdate.build = 78;
    AppUpdate.i.resetForTest();
  });
  tearDown(() {
    AppUpdate.build = kAppBuild;
    Api.i.config = const {};
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('home: the update modal opens once, ✕ leaves the chip (text scale $scale)', (t) async {
      await seedHome();
      Api.i.config = {'latest_version': 79, 'update_bonus_coins': 50};
      await pumpApp(t, scale: scale);
      for (int i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const ValueKey('update_modal')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const ValueKey('update_close')));
      await t.pump(const Duration(milliseconds: 400));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('update_modal')), findsNothing);
      expect(find.byKey(const ValueKey('update_chip')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('home: no modal and no chip when up to date, or with the forced-update page', (t) async {
    await seedHome();
    Api.i.config = {'latest_version': 78};
    await pumpApp(t);
    expect(find.byKey(const ValueKey('update_modal')), findsNothing);
    expect(find.byKey(const ValueKey('update_chip')), findsNothing);
  });

  testWidgets('home: a closed modal (3 days) stays closed at the next launch', (t) async {
    await seedHome();
    SharedPreferences.setMockInitialValues({
      'player': 'p', 'secret': 's', 'token': 't',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400,
      'update_closed_for': 79, 'update_closed_at': DateTime.now().millisecondsSinceEpoch,
    });
    Api.i.config = {'latest_version': 79};
    await pumpApp(t);
    expect(find.byKey(const ValueKey('update_modal')), findsNothing);
    expect(find.byKey(const ValueKey('update_chip')), findsOneWidget);
  });
}
