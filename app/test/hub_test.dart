import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/models/progress.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/badge_cell.dart';
import 'package:the_case/widgets/cast_strip.dart';
import 'package:the_case/widgets/missions_card.dart';
import 'package:the_case/widgets/profile_bell.dart';

Map<String, dynamic> _m(String id, String title, int progress, int target, bool done) =>
    {'id': id, 'title': title, 'target': target, 'progress': progress, 'done': done};

MissionsDay _day(List<Map<String, dynamic>> missions, {bool allDone = false, bool claimed = false, int streak = 0}) => MissionsDay({
      'day': '2026-10-13',
      'missions': missions,
      'all_done': allDone,
      'claimed': claimed,
      'chest_coins': 120,
      'chest_streak': streak,
      'next_at': DateTime(2026, 10, 14).millisecondsSinceEpoch ~/ 1000,
    });

Future<void> _pump(WidgetTester t, MissionsDay d, {List<String>? went}) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HomeMissionsCard(
          day: d,
          now: () => DateTime(2026, 10, 13, 22),
          onChanged: (_) {},
          onGo: (m) => went?.add(m.id),
          onOpenSheet: () {},
        ),
      ),
    ),
  ));
  await t.pump();
}

void main() {
  group('feed parsing', () {
    test('items, kinds, claimable gifts and the unread number', () {
      final f = Feed({
        'unread': 2,
        'items': [
          {'id': 'p1', 'kind': 'gift', 'title': 'هدیه', 'body': 'x', 'at': 1760000000, 'unread': true, 'gift_id': 'p1', 'reward': 50},
          {'id': 'c001', 'kind': 'case', 'title': 'پرونده باز شد', 'at': 1759990000, 'unread': false},
          {'id': 'bad'},
        ],
      });
      expect(f.unread, 2);
      expect(f.items.length, 3);
      expect(f.items[0].claimable, isTrue);
      expect(f.items[0].reward, 50);
      expect(f.items[1].isGift, isFalse);
      expect(f.items[1].claimable, isFalse);
      expect(f.items[1].giftId, isNull);
      expect(f.items[2].kind, 'system'); // unknown/missing values never crash
      expect(Feed({}).items, isEmpty);
    });

    test('a profile carries the unread number; old profiles say zero', () {
      expect(Profile({'unread': 7}).unread, 7);
      expect(Profile({}).unread, 0);
    });
  });

  group('bell label', () {
    test('Persian digits and a 99+ cap', () {
      expect(unreadLabel(3), '۳');
      expect(unreadLabel(99), '۹۹');
      expect(unreadLabel(100), '99+');
    });
  });

  group('missions card', () {
    testWidgets('none done: the button continues the first unfinished mission', (t) async {
      final went = <String>[];
      await _pump(t, _day([_m('daily_case', 'پرونده‌ی امشب رو حل کن', 0, 1, false), _m('talk3', 'با ۳ مظنون حرف بزن', 0, 3, false), _m('hint_use', 'یک سرنخ بخر', 0, 1, false)]), went: went);
      expect(find.text('۰/۳'), findsWidgets);
      expect(find.text('ادامه: پرونده‌ی امشب رو حل کن'), findsOneWidget);
      expect(find.byKey(const ValueKey('missions-claim')), findsNothing);
      await t.tap(find.byKey(const ValueKey('missions-go')));
      expect(went, ['daily_case']);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('partial: done mission is struck through with a check, the button names the next one', (t) async {
      await _pump(t, _day([_m('daily_case', 'پرونده‌ی امشب رو حل کن', 1, 1, true), _m('talk3', 'با ۳ مظنون حرف بزن', 1, 3, false), _m('hint_use', 'یک سرنخ بخر', 0, 1, false)], streak: 3));
      expect(find.text('۱/۳'), findsWidgets);
      expect(find.byKey(const ValueKey('mission-done-daily_case')), findsOneWidget);
      expect(find.byKey(const ValueKey('mission-open-talk3')), findsOneWidget);
      expect(find.text('ادامه: با ۳ مظنون حرف بزن'), findsOneWidget);
      expect(find.text('۳ روز پیاپی صندوقچه رو باز کردی'), findsOneWidget);
      final done = t.widget<Text>(find.text('پرونده‌ی امشب رو حل کن'));
      expect(done.style!.decoration, TextDecoration.lineThrough);
      expect(done.style!.color, K.textSoft);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('all done and not claimed: the green claim button', (t) async {
      await _pump(t, _day([_m('a', 'یک', 1, 1, true), _m('b', 'دو', 3, 3, true), _m('c', 'سه', 1, 1, true)], allDone: true));
      expect(find.byKey(const ValueKey('missions-claim')), findsOneWidget);
      expect(find.byKey(const ValueKey('missions-go')), findsNothing);
      expect(find.text('باز کردن صندوقچه · ۱۲۰ سکه'), findsOneWidget);
      expect(find.text('۳/۳'), findsWidgets);
      await t.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('claimed: the card says the chest was opened', (t) async {
      await _pump(t, _day([_m('a', 'یک', 1, 1, true), _m('b', 'دو', 3, 3, true), _m('c', 'سه', 1, 1, true)], allDone: true, claimed: true));
      expect(find.text('صندوقچه‌ی امروز باز شد'), findsOneWidget);
      expect(find.byKey(const ValueKey('missions-claim')), findsNothing);
      expect(find.byKey(const ValueKey('missions-go')), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
    });

    test('each mission type knows where it lives', () {
      expect(missionTarget('daily_case'), MissionTarget.tonight);
      expect(missionTarget('weekend_talk'), MissionTarget.weekend);
      expect(missionTarget('archive_open'), MissionTarget.archive);
      expect(missionTarget('riddle_play3'), MissionTarget.sheet);
      expect(missionTarget('something_new'), MissionTarget.sheet);
    });
  });

  group('badge cell', () {
    AchievementRow row(bool earned) => AchievementRow({
          'id': 'cases_50',
          'title': 'بایگانی زنده',
          'desc': '۵۰ پرونده حل کن',
          'group': 'cases',
          'target': 50,
          'progress': earned ? 50 : 48,
          'earned': earned,
          'coins': 400,
        });

    testWidgets('earned: gold ring, light title, brass subtitle', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: BadgeCell(badge: row(true), icon: Icons.star))));
      expect(find.byKey(const ValueKey('badge-earned-cases_50')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-locked-cases_50')), findsNothing);
      expect(t.widget<Text>(find.text('بایگانی زنده')).style!.color, K.text);
      expect(t.widget<Text>(find.text('۴۰۰ سکه')).style!.color, K.brass);
      final box = t.widget<Container>(find.byKey(const ValueKey('badge-earned-cases_50'))).decoration! as BoxDecoration;
      expect((box.gradient! as LinearGradient).colors, [kBadgeGold, K.kraft, K.kraftDark]);
    });

    testWidgets('locked: grey title and the progress under the name', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: BadgeCell(badge: row(false), icon: Icons.star))));
      expect(find.byKey(const ValueKey('badge-locked-cases_50')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge-earned-cases_50')), findsNothing);
      expect(t.widget<Text>(find.text('بایگانی زنده')).style!.color, kBadgeLockedText);
      expect(t.widget<Text>(find.text('۴۸ از ۵۰')).style!.color, kBadgeLockedText);
      expect(find.text('۴۰۰ سکه'), findsNothing);
    });
  });

  group('suspects named in a text', () {
    final all = [
      for (final n in ['علی‌اصغر فرجی', 'علی مرادی', 'دکتر ماندانا شریفی', 'کاوه ملکی'])
        Suspect({'id': n, 'name': n, 'role': 'x', 'age': 30})
    ];

    test('first names without titles', () {
      expect(suspectFirstName('دکتر ماندانا شریفی'), 'ماندانا');
      expect(suspectFirstName('مهندس آرمان'), 'آرمان');
      expect(suspectFirstName('کاوه ملکی'), 'کاوه');
    });

    test('whole words only, possessive ZWNJ allowed', () {
      expect(suspectsNamedIn('کاوه‌ی بیچاره دیر رسید', all).map((s) => s.name), ['کاوه ملکی']);
      expect(suspectsNamedIn('ماندانا گفت نه', all).map((s) => s.name), ['دکتر ماندانا شریفی']);
      expect(suspectsNamedIn('علی‌اصغر آخر شب رفت', all).map((s) => s.name), ['علی‌اصغر فرجی']);
      expect(suspectsNamedIn('علیرضا کسی نیست', all), isEmpty);
      expect(suspectsNamedIn('', all), isEmpty);
    });

    test('a suspect without an intro (old cached case) parses with an empty one', () {
      expect(Suspect({'id': 's1', 'name': 'ا ب'}).intro, '');
      expect(Suspect({'id': 's1', 'intro': 'یک خط'}).intro, 'یک خط');
    });
  });
}
