import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/widgets/id_card.dart';

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale), size: const Size(360, 800)),
          child: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: Center(child: child))),
        ),
      ),
    );

IdCardData _data({int league = 1, String code = ''}) => IdCardData(
      name: 'آرش',
      title: 'بازرس',
      avatarId: 'det_01',
      league: league,
      memberNo: 418,
      since: DateTime.utc(2026, 11, 1),
      solved: 41,
      stars: 90,
      bestStreak: 19,
      fastest: 221,
      inviteCode: code,
      recent: const [CardBadge(title: 'پرونده‌خوار', group: 'cases', metal: 1)],
    );

void main() {
  test('league of a rank follows the server ranges', () {
    expect([for (final r in [0, 1, 2, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 20]) leagueOfRank(r)], [0, 0, 1, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]);
  });

  test('Jalali dates and card texts', () {
    expect(toJalali(DateTime(2026, 3, 21)), [1405, 1, 1]);
    expect(toJalali(DateTime(2026, 11, 11)), [1405, 8, 20]);
    expect(fastestText(221), '۳:۴۱');
    expect(fastestText(0), '—');
    expect(memberNoText(418), '۰۰۴۱۸');
    expect(memberNoText(0), '—');
  });

  for (final scale in [1.0, 2.0]) {
    for (var league = 0; league < 8; league++) {
      testWidgets('card at font $scale, league $league: front and back build without overflow', (t) async {
        await t.pumpWidget(_app(IdCard(data: _data(league: league, code: 'AB12CD')), scale: scale));
        await t.pump(const Duration(milliseconds: 100));
        expect(find.text('آرش'), findsOneWidget);
        expect(find.text('بازرس'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('id-card')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 800));
        expect(find.text('۴۱'), findsOneWidget);
        expect(find.text('AB12CD'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets("someone else's card has no invite code or QR", (t) async {
    await t.pumpWidget(_app(IdCard(data: _data(code: ''), startOnBack: true)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('AB12CD'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
