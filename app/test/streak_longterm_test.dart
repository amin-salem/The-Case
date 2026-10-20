import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/engagement.dart';
import 'package:the_case/widgets/streak_flame.dart';

const _ladder = [3, 7, 14, 30, 60, 100, 200, 365];

void main() {
  test('the next step of the ladder and the «x شب مونده» line', () {
    expect(nextStreakMilestone(0, _ladder), 3);
    expect(nextStreakMilestone(3, _ladder), 7);
    expect(nextStreakMilestone(30, _ladder), 60);
    expect(nextStreakMilestone(365, _ladder), isNull);
    expect(nextMilestoneLine(48, _ladder), '۱۲ شب مونده تا «قاب «شعله»»');
    expect(nextMilestoneLine(0, _ladder), '۳ شب مونده تا «سه شب پیاپی»');
    expect(nextMilestoneLine(365, _ladder), contains('همه‌ی پله‌ها'));
    // an unsorted ladder from the server still finds the smallest bigger step
    expect(nextStreakMilestone(10, const [30, 7, 14]), 14);
    for (final m in _ladder) {
      expect(kMilestoneNames.containsKey(m), isTrue, reason: 'name for $m');
    }
  });

  test('profile: the repair offer is optional (an old server sends none)', () {
    final old = Profile({'player_id': 'p', 'nickname': 'ن', 'streak': 5});
    expect(old.streakRepair, isNull);
    final p = Profile({
      'player_id': 'p',
      'nickname': 'ن',
      'streak': 12,
      'streak_repair': {'key': '2026-10-18', 'streak': 12, 'price': 260},
    });
    expect(p.streakRepair!.price, 260);
    expect(p.streakRepair!.streak, 12);
    expect(p.streakRepair!.key, '2026-10-18');
  });

  test('leaderboard rows: the flame comes from `streak`, old servers give none', () {
    expect(LeaderRow({'rank': 1, 'nickname': 'الف'}).streak, 0);
    expect(LeaderRow({'rank': 1, 'nickname': 'الف', 'streak': 33}).streak, 33);
  });

  test('accuse result: a milestone is optional', () {
    expect(AccuseResult({'result': 'solved'}).streakMilestone, isNull);
    final r = AccuseResult({'result': 'solved', 'streak': 60, 'streak_milestone': 60});
    expect(r.streakMilestone, 60);
    expect(r.badge, isNull);
  });

  testWidgets('the flame shows from two nights and is empty before', (tester) async {
    Future<void> show(int n) => tester.pumpWidget(Directionality(
          textDirection: TextDirection.rtl,
          child: Center(child: StreakFlame(n)),
        ));
    await show(0);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    await show(1);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
    await show(12);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.text('۱۲'), findsOneWidget);
    expect(streakFlameColor(400) != streakFlameColor(5), isTrue);
  });
}
