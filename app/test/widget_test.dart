import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/theme.dart';

void main() {
  test('Persian digits', () {
    expect(fa(1234), '۱٬۲۳۴');
    expect(faClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '۰۱:۰۲:۰۳');
  });
}
