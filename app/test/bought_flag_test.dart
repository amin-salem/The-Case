import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the «has bought» flag is read per account from the phone', () async {
    SharedPreferences.setMockInitialValues({'player': 'p', 'bought_coins_p': true});
    await Api.i.init();
    expect(Api.i.hasBought, isTrue);
    SharedPreferences.setMockInitialValues({'player': 'q', 'bought_coins_p': true});
    await Api.i.init();
    expect(Api.i.hasBought, isFalse, reason: 'another account on the same phone has not bought');
    SharedPreferences.setMockInitialValues({'player': 'p'});
    await Api.i.init();
    expect(Api.i.hasBought, isFalse);
  });

  test('closing the securing row is remembered per account', () async {
    SharedPreferences.setMockInitialValues({'player': 'p'});
    await Api.i.init();
    expect(Api.i.secureRowClosedAt, isNull);
    final at = DateTime(2026, 11, 11, 20);
    await Api.i.closeSecureRow(at);
    expect(Api.i.secureRowClosedAt, at);
    SharedPreferences.setMockInitialValues({'player': 'q'});
    await Api.i.init();
    expect(Api.i.secureRowClosedAt, isNull);
  });
}
