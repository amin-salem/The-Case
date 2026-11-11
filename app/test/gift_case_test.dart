import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/gift_case.dart';

CaseRow row(String id, {int? freeUntil, bool solved = false, bool failed = false}) => CaseRow({
      'id': id, 'number': 20, 'title': 'پرونده‌ی $id', 'difficulty': 3, 'unlock_cost': freeUntil == null ? 150 : 0,
      if (freeUntil != null) 'free_until': freeUntil, 'solved': solved, 'failed': failed,
    });

int at(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  final now = DateTime(2026, 11, 12, 12);

  test('the server field free_until becomes the end of the gift; an old server sends none', () {
    expect(row('a').freeUntil, isNull);
    expect(row('a', freeUntil: at(now.add(const Duration(hours: 5)))).freeUntil, now.add(const Duration(hours: 5)));
  });

  test('the gift is the first case that is free now and not opened, solved or lost', () {
    final rows = [
      row('old', freeUntil: at(now.subtract(const Duration(hours: 1)))), // the hours are over
      row('done', freeUntil: at(now.add(const Duration(hours: 5))), solved: true),
      row('lost', freeUntil: at(now.add(const Duration(hours: 5))), failed: true),
      row('plain'),
      row('gift', freeUntil: at(now.add(const Duration(hours: 5)))),
    ];
    expect(giftCase(rows, now)?.id, 'gift');
    expect(giftCase([row('plain')], now), isNull);
    expect(giftCase(const [], now), isNull);
  });

  test('the time left is said in hours and minutes, never negative or empty', () {
    expect(giftLeftText(const Duration(hours: 31, minutes: 20)), '۳۱ ساعت دیگه');
    expect(giftLeftText(const Duration(hours: 5, minutes: 20)), '۵ ساعت و ۲۰ دقیقه دیگه');
    expect(giftLeftText(const Duration(hours: 5)), '۵ ساعت دیگه');
    expect(giftLeftText(const Duration(minutes: 45)), '۴۵ دقیقه دیگه');
    expect(giftLeftText(const Duration(seconds: 20)), 'کمتر از یک دقیقه دیگه');
    expect(giftLeftText(const Duration(minutes: -3)), 'کمتر از یک دقیقه دیگه');
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('the card shows the case, the free line, opens and closes at text scale $scale', (tester) async {
      var opened = 0, closed = 0;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale), size: const Size(360, 800)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GiftCaseCard(
                row: row('c020', freeUntil: at(DateTime.now().add(const Duration(hours: 30)))),
                onOpen: () => opened++,
                onClose: () => closed++,
              ),
            ),
          ),
        ),
      ));
      expect(find.text('پرونده‌ی هدیه‌ی تو'), findsOneWidget);
      expect(find.text('پرونده‌ی c020'), findsOneWidget);
      expect(find.textContaining('رایگان برای تو'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('gift-open')));
      await tester.tap(find.byKey(const ValueKey('gift-close')));
      expect(opened, 1);
      expect(closed, 1);
    });
  }
}
