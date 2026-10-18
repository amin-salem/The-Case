import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/screens/weekend_screen.dart';

void main() {
  test('default opening: next Thursday 09:00 Tehran', () {
    // Tue 13 Oct 2026 15:30 Tehran = 12:00 UTC -> Thu 15 Oct 09:00 Tehran = 05:30 UTC
    expect(nextWeekendOpening(DateTime.utc(2026, 10, 13, 12, 0)).toUtc(), DateTime.utc(2026, 10, 15, 5, 30));
    // Thu 15 Oct 10:00 Tehran (already open) -> the Thursday after
    expect(nextWeekendOpening(DateTime.utc(2026, 10, 15, 6, 30)).toUtc(), DateTime.utc(2026, 10, 22, 5, 30));
    // Thu 15 Oct 08:00 Tehran -> same day
    expect(nextWeekendOpening(DateTime.utc(2026, 10, 15, 4, 30)).toUtc(), DateTime.utc(2026, 10, 15, 5, 30));
  });

  test('fallback follows the server schedule (weekday Monday=0 -> Dart +1, hour)', () {
    // server says Wednesday (2) at 21: Dart weekday 3. Tue 13 Oct 12:00 UTC -> Wed 14 Oct 17:30 UTC
    expect(nextWeekendOpening(DateTime.utc(2026, 10, 13, 12, 0), 3, 21).toUtc(), DateTime.utc(2026, 10, 14, 17, 30));
    // Thursday (3) at 9 Tehran = 05:30 UTC
    expect(nextWeekendOpening(DateTime.utc(2026, 10, 13, 12, 0), 4, 9).toUtc(), DateTime.utc(2026, 10, 15, 5, 30));
  });
}
