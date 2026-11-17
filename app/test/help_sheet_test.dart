import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/widgets/help_sheet.dart';

HelpOption _o(String id, int price, {bool plaque = false, bool free = false, int stock = 0, bool locked = false, bool done = false}) =>
    HelpOption(id: id, icon: Icons.search_rounded, title: 'T-$id', what: 'W-$id', price: price, plaque: plaque, free: free, stock: stock, locked: locked, done: done);

Future<void> _open(WidgetTester t, List<HelpOption> opts, void Function(HelpOption?) got, {String? pre}) async {
  await t.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            key: const ValueKey('go'),
            onPressed: () async => got(await showHelpSheet(c, options: opts, hintsTaken: 1, coins: 100, preselect: pre)),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.byKey(const ValueKey('go')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sheet: rows, plaque tags, confirm returns the choice', (t) async {
    HelpOption? got;
    await _open(t, [_o('magnifier', 35), _o('hint1', 40), _o('hint2', 80, plaque: true)], (o) => got = o);
    expect(find.byKey(const ValueKey('help-opt-magnifier')), findsOneWidget);
    expect(find.text('پلاک کم نمی‌شود'), findsNWidgets(2));
    expect(find.text('−۱ پلاک'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('help-opt-hint1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('help-confirm')));
    await t.pumpAndSettle();
    expect(got?.id, 'hint1');
  });

  testWidgets('sheet: locked and done rows cannot be chosen; preselect works', (t) async {
    HelpOption? got;
    await _open(t, [_o('magnifier', 35, done: true), _o('hint2', 80, plaque: true, locked: true), _o('camera', 100)], (o) => got = o, pre: 'camera');
    await t.tap(find.byKey(const ValueKey('help-opt-hint2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('help-confirm')));
    await t.pumpAndSettle();
    expect(got?.id, 'camera');
  });

  testWidgets('ladder: three steps with taken/current/ahead', (t) async {
    await t.pumpWidget(const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: HintLadder(taken: 1)))));
    expect(find.byKey(const ValueKey('hint-step-0-taken')), findsOneWidget);
    expect(find.byKey(const ValueKey('hint-step-1-current')), findsOneWidget);
    expect(find.byKey(const ValueKey('hint-step-2-ahead')), findsOneWidget);
  });
}
