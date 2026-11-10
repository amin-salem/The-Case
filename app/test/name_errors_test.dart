import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/services/api.dart';

void main() {
  test('a taken name and a name that is not acceptable have different messages', () {
    final taken = Api.errorText('nickname_taken');
    final bad = Api.errorText('bad_nickname');
    expect(taken, isNot(bad));
    expect(taken, contains('کارآگاه دیگه'));
    expect(bad, isNot(contains('قبلاً')));
  });

  test('emoji, stickers and a wrong length each say what to do', () {
    expect(Api.errorText('nickname_chars'), contains('ایموجی'));
    expect(Api.errorText('nickname_length'), contains('۱۶'));
    for (final c in ['nickname_taken', 'nickname_chars', 'nickname_length', 'bad_nickname']) {
      expect(Api.errorText(c), isNot(Api.errorText('something_unknown')), reason: c);
    }
  });
}
