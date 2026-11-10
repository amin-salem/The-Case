import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/services/shop_value.dart';

void main() {
  test('cases: whole archive cases a coin amount opens', () {
    expect(ShopValue.cases(400), 2);
    expect(ShopValue.cases(1300), 8);
    expect(ShopValue.cases(3600), 24);
    expect(ShopValue.cases(149), 0); // less than one case: no line is shown
    expect(ShopValue.cases(0), 0);
    expect(ShopValue.cases(-5), 0);
  });

  test('bestValueId: the highest coins per toman gets the badge, from real prices', () {
    expect(
        ShopValue.bestValueId({
          'coins_small': (coins: 400, toman: 49000),
          'coins_medium': (coins: 1300, toman: 129000),
          'coins_large': (coins: 3600, toman: 299000),
        }),
        'coins_large');
    // the bag order does not decide: the numbers do
    expect(
        ShopValue.bestValueId({
          'coins_small': (coins: 900, toman: 49000),
          'coins_medium': (coins: 1300, toman: 129000),
          'coins_large': (coins: 1500, toman: 299000),
        }),
        'coins_small');
  });

  test('bestValueId: no claim when a price is unknown or two bags tie', () {
    expect(
        ShopValue.bestValueId({
          'coins_small': (coins: 400, toman: 49000),
          'coins_medium': (coins: 1300, toman: null),
          'coins_large': (coins: 3600, toman: 299000),
        }),
        isNull);
    expect(
        ShopValue.bestValueId({
          'coins_small': (coins: 0, toman: 49000),
          'coins_medium': (coins: 1300, toman: 129000),
        }),
        isNull);
    expect(
        ShopValue.bestValueId({
          'coins_small': (coins: 100, toman: 10000),
          'coins_medium': (coins: 200, toman: 20000),
        }),
        isNull);
  });

  test('vipBreakEven: the month where VIP beats buying archive cases with coins', () {
    // best rate 3600 coins / 299000 toman: a case (150 coins) costs 12 458 toman; VIP 149 000 -> 11 cases cost 137 000, 12 cost 149 500
    final n = ShopValue.vipBreakEven(149000, 3600 / 299000);
    expect(n, 12);
    // really cheaper at n, not at n-1
    final perCase = 150 / (3600 / 299000);
    expect(n! * perCase > 149000, isTrue);
    expect((n - 1) * perCase > 149000, isFalse);
  });

  test('vipBreakEven: hidden when it cannot be computed honestly', () {
    expect(ShopValue.vipBreakEven(null, 0.01), isNull);
    expect(ShopValue.vipBreakEven(149000, null), isNull);
    expect(ShopValue.vipBreakEven(0, 0.01), isNull);
    expect(ShopValue.vipBreakEven(149000, 0), isNull);
    expect(ShopValue.vipBreakEven(149000, 0.00001), isNull); // absurd rate: no number shown
  });
}
