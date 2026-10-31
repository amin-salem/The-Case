import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/screens/main_shell.dart';
import 'home_fixtures.dart';

Future<void> settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('a lost weekend case shows «این بار نشد» and the second-chance button, not «ورود به پرونده»', (t) async {
    await seedHome(weekend: 'lost');
    await pumpApp(t);
    MainShell.tab.value = MainShell.weekend;
    await settle(t);
    expect(find.text('این بار نشد'), findsWidgets);
    expect(find.byKey(const ValueKey('weekend-second-chance')), findsOneWidget);
    expect(find.text('فرصت دوباره · ۲۵۰ سکه'), findsOneWidget);
    expect(find.text('ورود به پرونده'), findsNothing);
    expect(find.byKey(const ValueKey('weekend-second-chance-note')), findsOneWidget);
    expect(find.text('فرصت دوباره حساب جدول هفته نمی‌شه.'), findsOneWidget);
  });

  testWidgets('the button asks for the quoted price first; «نه» leaves everything as it was', (t) async {
    await seedHome(weekend: 'lost');
    await pumpApp(t);
    MainShell.tab.value = MainShell.weekend;
    await settle(t);
    await t.tap(find.byKey(const ValueKey('weekend-second-chance')));
    await settle(t);
    expect(find.text('دوباره باز کن · ۲۵۰ سکه'), findsOneWidget);
    await t.tap(find.text('نه'));
    await settle(t);
    expect(find.byKey(const ValueKey('weekend-second-chance')), findsOneWidget);
  });

  testWidgets('an open weekend case still says «ورود به پرونده»', (t) async {
    await seedHome(weekend: 'open');
    await pumpApp(t);
    MainShell.tab.value = MainShell.weekend;
    await settle(t);
    expect(find.text('ورود به پرونده'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekend-second-chance')), findsNothing);
    expect(find.byKey(const ValueKey('weekend-second-chance-note')), findsNothing);
  });
}
