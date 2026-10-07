import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/screens/weekend_screen.dart';

void main() {
  test('next Thursday 21:00 Tehran', () {
    // Wed 7 Oct 2026 15:52 Tehran = 12:22 UTC -> Thu 8 Oct 21:00 Tehran = 17:30 UTC
    expect(nextThursdayNine(DateTime.utc(2026, 10, 7, 12, 22)).toUtc(), DateTime.utc(2026, 10, 8, 17, 30));
    // Thu 8 Oct 22:00 Tehran -> the Thursday after
    expect(nextThursdayNine(DateTime.utc(2026, 10, 8, 18, 30)).toUtc(), DateTime.utc(2026, 10, 15, 17, 30));
    // Thu 8 Oct 20:00 Tehran -> same day
    expect(nextThursdayNine(DateTime.utc(2026, 10, 8, 16, 30)).toUtc(), DateTime.utc(2026, 10, 8, 17, 30));
  });
}
