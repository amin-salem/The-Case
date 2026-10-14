import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/screens/weekend_screen.dart';

void main() {
  test('next Wednesday 21:00 Tehran', () {
    // Tue 13 Oct 2026 15:30 Tehran = 12:00 UTC -> Wed 14 Oct 21:00 Tehran = 17:30 UTC
    expect(nextWednesdayNine(DateTime.utc(2026, 10, 13, 12, 0)).toUtc(), DateTime.utc(2026, 10, 14, 17, 30));
    // Wed 14 Oct 22:00 Tehran -> the Wednesday after
    expect(nextWednesdayNine(DateTime.utc(2026, 10, 14, 18, 30)).toUtc(), DateTime.utc(2026, 10, 21, 17, 30));
    // Wed 14 Oct 08:00 Tehran -> same day
    expect(nextWednesdayNine(DateTime.utc(2026, 10, 14, 4, 30)).toUtc(), DateTime.utc(2026, 10, 14, 17, 30));
  });
}
