import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/rate_card.dart';

void main() {
  test('case rows carry the rating numbers, and an old server without them gives zeros', () {
    final r = CaseRow({'id': 'c004', 'rating_avg': 4.25, 'rating_count': 12, 'comment_count': 3, 'my_rating': 5});
    expect(r.ratingAvg, 4.25);
    expect(r.ratingCount, 12);
    expect(r.commentCount, 3);
    expect(r.myRating, 5);
    final old = CaseRow({'id': 'c001'});
    expect(old.ratingAvg, 0);
    expect(old.ratingCount, 0);
    expect(old.commentCount, 0);
    expect(old.myRating, 0);
    expect(CaseRow({'id': 'c002', 'rating_avg': 4}).ratingAvg, 4.0); // a whole number from the server
  });

  test('the invite status parses; missing fields fall back to the rules (3 days, 20 friends)', () {
    final s = ReferralStatus({
      'referred': false,
      'can_redeem': true,
      'new_player_reward': 100,
      'inviter_reward': 150,
      'need_days': 3,
      'invited': 2,
      'invited_paid': 1,
      'best_days': 2,
    });
    expect(s.canRedeem, isTrue);
    expect(s.referred, isFalse);
    expect(s.newPlayerReward, 100);
    expect(s.inviterReward, 150);
    expect(s.invited, 2);
    expect(s.invitedPaid, 1);
    expect(s.bestDays, 2);
    expect(s.maxPaid, 20);
    final empty = ReferralStatus({});
    expect(empty.needDays, 3);
    expect(empty.canRedeem, isFalse);
    expect(empty.myDays, 0);
  });

  test('ratings are shown with one Persian decimal', () {
    expect(faRating(4.2), '۴٫۲');
    expect(faRating(5), '۵٫۰');
    expect(faRating(3.96), '۴٫۰');
  });

  testWidgets('the rating chip is empty until someone rated, then shows average, count and comments', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RatingChip(avg: 4.5, count: 0))));
    expect(find.byType(Icon), findsNothing);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RatingChip(avg: 4.5, count: 12, comments: 3))));
    expect(find.text('۴٫۵'), findsOneWidget);
    expect(find.textContaining('۱۲'), findsOneWidget);
    expect(find.text('۳'), findsOneWidget);
  });
}
