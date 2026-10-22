import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/widgets/engagement.dart';

void main() {
  final caseData = CaseData({
    'id': 'c027',
    'number': 27,
    'title': 'ساعت‌شمار موتور',
    'suspects': [
      {'id': 's1', 'name': 'ناصر صیادی'},
      {'id': 's3', 'name': 'کوروش بحری'},
    ],
    'evidence': [
      {'id': 'e1', 'title': 'ساعت‌شمار موتور ساعت ۱۸'},
    ],
  });

  test('time is shown as minutes:seconds in Persian digits', () {
    expect(faDuration(252), '۴:۱۲');
    expect(faDuration(5), '۰:۰۵');
    expect(faDuration(3725), '۱:۰۲:۰۵');
  });

  test('share card for a solved case: tries, stars, time, hints, streak; never the answer', () {
    final r = AccuseResult({
      'result': 'solved',
      'stars': 2,
      'streak': 12,
      'seconds': 252,
      'hints_used': 0,
      'culprit': 's3',
      'proof': ['e1'],
      'progress': {'attempts': 1, 'solved': true},
    });
    final lines = shareLines(caseData, r);
    expect(lines[0], contains('۲۷'));
    expect(lines.join('\n'), contains('🟥🟩'));
    expect(lines.join('\n'), contains('⭐⭐☆'));
    expect(lines.join('\n'), contains('۴:۱۲'));
    expect(lines.join('\n'), contains('بدون سرنخ'));
    expect(lines.join('\n'), contains('۱۲ شب'));
    final text = shareText(caseData, r);
    expect(text, isNot(contains('کوروش')));
    expect(text, isNot(contains('ساعت ۱۸')));
    expect(text, contains('https://'));
  });

  test('share card for a lost case', () {
    final r = AccuseResult({'result': 'failed', 'progress': {'attempts': 3, 'failed': true}});
    expect(shareLines(caseData, r).join('\n'), contains('🟥🟥🟥'));
  });

  test('spoiler-free share: plaques, cards, minutes and the link; never the culprit or a clue', () {
    final r = AccuseResult({
      'result': 'solved', 'stars': 3, 'seconds': 372, 'culprit': 's3', 'proof': ['e1'],
      'depth': {'evidence': 4},
    });
    final text = spoilerFreeShareText(caseData, r);
    expect(text, startsWith('پرونده‌ی ۲۷ «ساعت‌شمار موتور» 🕵️ ۳ پلاک · ۴ مدرک · ۶ دقیقه — تو هم امتحان کن: '));
    expect(text, endsWith(Api.i.shareUrl));
    expect(text, isNot(contains('کوروش')));
    expect(text, isNot(contains('s3')));
    expect(text.contains('\n'), isFalse);
    // an old server (no depth): the card just leaves the cards out
    final old = spoilerFreeShareText(caseData, AccuseResult({'result': 'solved', 'stars': 1, 'seconds': 20}));
    expect(old, contains('۱ پلاک · ۱ دقیقه'));
    expect(old, isNot(contains('مدرک')));
    final lost = spoilerFreeShareText(caseData, AccuseResult({'result': 'failed'}));
    expect(lost, contains('این بار نشد'));
    expect(lost, isNot(contains('پلاک')));
  });

  test('the share link has one home: the constant', () {
    expect(kShareLinkPlaceholder, startsWith('https://'));
  });
}
