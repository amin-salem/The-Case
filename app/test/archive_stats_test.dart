import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/widgets/archive_stats.dart';

Widget _wrap(List<Widget> cards, {double scale = 1}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SizedBox(width: 360, child: Column(children: cards)),
          ),
        ),
      ),
    );

Widget _card(Widget stats, {String title = ''}) => Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        stats,
      ]),
    );

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('stats slot sits at the same x on every card, no overflow (360 dp, font x$scale)', (t) async {
      await t.pumpWidget(_wrap([
        _card(const ArchiveStatsSlot(avg: 4.8, count: 1200, comments: 345), title: 'عنوان خیلی خیلی خیلی طولانی برای آزمایش بریده شدن متن در کارت'),
        _card(const ArchiveStatsSlot(avg: 0, count: 0, comments: 0), title: 'بدون امتیاز'),
        _card(const ArchiveStatsSlot(avg: 3.0, count: 2, comments: 0)),
        _card(const ArchiveStatsSlot(avg: 0, count: 0, comments: 7)),
      ], scale: scale));
      expect(t.takeException(), isNull);
      final slots = find.byKey(const ValueKey('archive-stats'));
      expect(slots, findsNWidgets(4));
      final lefts = [for (var i = 0; i < 4; i++) t.getTopLeft(slots.at(i)).dx];
      final widths = [for (var i = 0; i < 4; i++) t.getSize(slots.at(i)).width];
      expect(lefts.toSet().length, 1, reason: 'left edges $lefts');
      expect(widths.toSet().length, 1, reason: 'widths $widths');
      // inner slots are fixed too
      final r = find.byKey(const ValueKey('archive-rating-slot'));
      final c = find.byKey(const ValueKey('archive-comments-slot'));
      expect({for (var i = 0; i < 4; i++) t.getTopLeft(r.at(i)).dx}.length, 1);
      expect({for (var i = 0; i < 4; i++) t.getTopLeft(c.at(i)).dx}.length, 1);
      // stats live on the physical left side of the card
      expect(lefts.first, lessThan(180));
    });
  }

  testWidgets('placeholders: no rating and no comments are muted, not empty', (t) async {
    await t.pumpWidget(_wrap([_card(const ArchiveStatsSlot(avg: 0, count: 0, comments: 0))]));
    expect(find.text('بدون امتیاز'), findsOneWidget);
    expect(find.text('۰'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
  });

  testWidgets('comments show even when nobody rated', (t) async {
    await t.pumpWidget(_wrap([_card(const ArchiveStatsSlot(avg: 0, count: 0, comments: 7))]));
    expect(find.text('۷'), findsOneWidget);
    expect(find.text('بدون امتیاز'), findsOneWidget);
  });
}
