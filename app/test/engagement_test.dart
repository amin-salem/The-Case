import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
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
}
