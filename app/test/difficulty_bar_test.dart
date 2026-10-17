import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/theme.dart';

Widget _wrap(Widget w, {TextDirection dir = TextDirection.rtl, double scale = 1}) => MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Center(child: w)),
        ),
      ),
    );

Color _segColor(WidgetTester t, int i) {
  final c = t.widget<Container>(find.byKey(ValueKey('diff-seg-$i')));
  return (c.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('5 segments, filled count and colour per level', (t) async {
    for (var l = 1; l <= 5; l++) {
      await t.pumpWidget(_wrap(DifficultyBar(l)));
      expect(find.byType(Container).evaluate().where((e) => (e.widget.key as ValueKey?)?.value.toString().startsWith('diff-seg') ?? false).length, 5);
      for (var i = 0; i < 5; i++) {
        if (i < l) {
          expect(_segColor(t, i), kDifficultyColors[l - 1], reason: 'level $l seg $i');
        } else {
          expect(_segColor(t, i), isNot(kDifficultyColors[l - 1]));
        }
      }
      expect(find.text(kDifficultyLabels[l - 1]), findsOneWidget);
    }
    expect(kDifficultyColors.toSet().length, 5);
  });

  testWidgets('level 1 is on the right and fills toward the left (even in an LTR parent)', (t) async {
    for (final dir in [TextDirection.rtl, TextDirection.ltr]) {
      await t.pumpWidget(_wrap(const DifficultyBar(2), dir: dir));
      final x = [for (var i = 0; i < 5; i++) t.getCenter(find.byKey(ValueKey('diff-seg-$i'))).dx];
      for (var i = 0; i < 4; i++) {
        expect(x[i] > x[i + 1], isTrue);
      }
    }
  });

  testWidgets('null and out of range are clamped to 1..5', (t) async {
    await t.pumpWidget(_wrap(const DifficultyBar(0)));
    expect(find.text('آسان'), findsOneWidget);
    await t.pumpWidget(_wrap(const DifficultyBar(9)));
    expect(find.text('خیلی سخت'), findsOneWidget);
    await t.pumpWidget(_wrap(const DifficultyBar(-3, compact: true)));
    expect(_segColor(t, 0), kDifficultyColors[0]);
    expect(clampDifficulty(null), 2);
    expect(clampDifficulty(7), 5);
  });

  testWidgets('semantics label in Persian digits', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_wrap(const DifficultyBar(4)));
    expect(find.bySemanticsLabel(RegExp('سختی ۴ از ۵')), findsOneWidget);
    h.dispose();
  });

  testWidgets('no overflow at 360 dp and large font scale; compact has a fixed size', (t) async {
    t.view.physicalSize = const Size(360, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(const Row(children: [Expanded(child: Text('x')), DifficultyBar(5), DifficultyBar(3, compact: true)]), scale: 2));
    expect(t.takeException(), isNull);
    final sizes = <Size>{};
    for (var l = 1; l <= 5; l++) {
      await t.pumpWidget(_wrap(DifficultyBar(l, compact: true)));
      sizes.add(t.getSize(find.byType(DifficultyBar)));
    }
    expect(sizes.length, 1);
  });
}
