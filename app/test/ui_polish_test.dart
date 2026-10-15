import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/theme.dart';

Future<void> _pump(WidgetTester t, Widget w) => t.pumpWidget(MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: Center(child: w))),
    ));

void main() {
  testWidgets('coin chip reads right to left: «+», the number, then the coin', (t) async {
    await _pump(t, CoinChip(coins: 660, onTap: () {}));
    await t.pump(const Duration(seconds: 2));
    final plus = t.getCenter(find.byIcon(Icons.add_circle_rounded)).dx;
    final coin = t.getCenter(find.byType(CoinIcon)).dx;
    final number = t.getCenter(find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('۶۶۰') || (w is Text && (w.data ?? '').contains('660')))).dx;
    expect(plus > number, isTrue, reason: '«+» is the rightmost');
    expect(number > coin, isTrue, reason: 'the number sits between «+» and the coin');
  });

  testWidgets('coin chip without a «+» is number first, then the coin (right to left)', (t) async {
    await _pump(t, const CoinChip(coins: 935));
    await t.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.add_circle_rounded), findsNothing);
    final coin = t.getCenter(find.byType(CoinIcon)).dx;
    final number = t.getCenter(find.byWidgetPredicate((w) => w is Text && ((w.data ?? '').contains('۹۳۵') || (w.data ?? '').contains('935')))).dx;
    expect(number > coin, isTrue);
  });

  testWidgets('GhostButton can show the shared coin instead of a material icon', (t) async {
    await _pump(t, GhostButton(label: 'رد شدن با سکه', leading: const CoinIcon(size: 18), onTap: () {}));
    expect(find.byType(CoinIcon), findsOneWidget);
    expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
  });
}
