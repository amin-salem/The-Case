import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/cast_strip.dart';

Suspect _s(String id, String name) => Suspect({'id': id, 'name': name, 'role': 'x', 'age': 30});

void main() {
  final all = [_s('s1', 'جمشید حکیمی'), _s('s2', 'مینا قاسمی'), _s('s3', 'بهمن عبدی'), _s('s4', 'نادر وکیلی')];
  List<String> ids(String t) => [for (final s in suspectsNamedIn(t, all)) s.id];

  test('a surname alone names the suspect', () {
    expect(ids('عبدی صبح ساعت ۹ آمد، حکیمی پول را گرفت'), ['s1', 's3']);
  });
  test('first name and full name still work', () {
    expect(ids('مینا آمد'), ['s2']);
    expect(ids('نادر وکیلی رفت'), ['s4']);
  });
  test('a surname inside a longer word does not count', () {
    expect(ids('قاسمیه و عبدیان آمدند'), isEmpty);
  });
  test('a shared surname or a surname equal to another first name is ignored', () {
    final fam = [_s('s1', 'علی رضایی'), _s('s2', 'مریم رضایی'), _s('s3', 'رضا کریمی'), _s('s4', 'سارا رضا')];
    expect([for (final s in suspectsNamedIn('رضایی آمد', fam)) s.id], isEmpty);
    expect([for (final s in suspectsNamedIn('رضا آمد', fam)) s.id], ['s3']);
  });
}
