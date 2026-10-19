import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_poolakey/flutter_poolakey.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/services/billing.dart';

/// A fake Poolakey: each connect attempt follows the next entry of [script].
class FakeGateway implements BazaarGateway {
  FakeGateway(this.script);

  /// 'ok' = connection succeeds, 'hang' = no answer at all, anything else = connection fails with that text.
  final List<String> script;
  Object? purchaseError; // thrown on every purchase
  final List<Object> purchaseErrorsOnce = []; // thrown one per call, first
  final List<PurchaseInfo> owned = [];
  int connects = 0;
  int purchases = 0;
  final List<String> consumed = [];
  bool connected = false;

  @override
  Future<void> connect(String key,
      {required VoidCallback onSucceed, required void Function(String reason) onFailed, required VoidCallback onDisconnected}) async {
    final step = script[connects < script.length ? connects : script.length - 1];
    connects++;
    if (step == 'ok') {
      connected = true;
      scheduleMicrotask(onSucceed);
    } else if (step != 'hang') {
      scheduleMicrotask(() => onFailed(step));
    }
  }

  @override
  Future<bool> isConnected() async => connected;
  @override
  Future<List<SkuDetails>> skuDetails(List<String> ids) async => [SkuDetails('coins_small', 'inapp', '۵۰ هزار تومان', 't', 'd')];
  @override
  Future<List<PurchaseInfo>> purchased() async => List.of(owned);
  @override
  Future<PurchaseInfo> purchase(String productId, String payload) async {
    purchases++;
    if (purchaseErrorsOnce.isNotEmpty) throw purchaseErrorsOnce.removeAt(0);
    if (purchaseError != null) throw purchaseError!;
    return _info(productId, 'tok-$purchases');
  }

  @override
  Future<bool> consume(String token) async {
    consumed.add(token);
    return true;
  }
}

PurchaseInfo _info(String product, String token) =>
    PurchaseInfo('o', token, 'p', 'pkg', PurchaseState.PURCHASED, 1, product, '{}', 'sig');

void main() {
  final verified = <String>[];
  Future<(String, int)> verify(String productId, String token) async {
    verified.add(token);
    return ('granted', 100);
  }

  Billing make(FakeGateway g, {String key = 'k'}) =>
      Billing.forTest(gateway: g, rsaKey: key, verify: verify, connectTimeout: const Duration(milliseconds: 50), attempts: 3);

  setUp(verified.clear);

  test('first connect fails (timeout), buy() reconnects with retries and succeeds', () async {
    final g = FakeGateway(['hang', 'ok']);
    final b = make(g);
    await b.init(); // startup: 2 tries -> second works
    expect(b.available, isTrue);

    final g2 = FakeGateway(['hang', 'hang', 'ok']);
    final b2 = make(g2);
    await b2.ensureConnected(tries: 1); // a failed startup connect
    expect(b2.available, isFalse);
    expect(b2.problem, BillingProblem.timeout);
    final (result, coins) = await b2.buy('coins_small'); // lazy retry inside buy
    expect(result, BuyResult.granted);
    expect(coins, 100);
    expect(g2.consumed, ['tok-1']);
    expect(b2.available, isTrue);
  });

  test('Bazaar not installed: unavailable, tells why, no pointless retries', () async {
    final g = FakeGateway(['ir.cafebazaar.poolakey.exception.BazaarNotFoundException']);
    final b = make(g);
    final (result, _) = await b.buy('coins_small');
    expect(result, BuyResult.unavailable);
    expect(b.problem, BillingProblem.notInstalled);
    expect(g.connects, 1);
    expect(billingProblemText(b.problem), contains('پیدا نشد'));
  });

  test('Bazaar too old is told apart from not installed and from a timeout', () async {
    expect(classifyConnectFailure('IAPNotSupportedException'), BillingProblem.tooOld);
    expect(classifyConnectFailure('BazaarNotFoundException'), BillingProblem.notInstalled);
    expect(classifyConnectFailure('java.util.concurrent.TimeoutException'), BillingProblem.timeout);
    expect(classifyConnectFailure('something else'), BillingProblem.other);
  });

  test('missing RSA key is reported as such and never connects', () async {
    final g = FakeGateway(['ok']);
    final b = make(g, key: '');
    final (result, _) = await b.buy('coins_small');
    expect(result, BuyResult.unavailable);
    expect(b.problem, BillingProblem.noKey);
    expect(g.connects, 0);
  });

  test('user cancels: nothing credited', () async {
    final g = FakeGateway(['ok'])..purchaseError = PlatformException(code: 'PURCHASE_CANCELLED', message: 'canceled');
    final b = make(g);
    final (result, coins) = await b.buy('coins_small');
    expect(result, BuyResult.cancelled);
    expect(coins, 0);
    expect(verified, isEmpty);
  });

  test('already owned: the owned purchase is credited through recover()', () async {
    final g = FakeGateway(['ok'])
      ..purchaseError = PlatformException(code: 'FAILED_TO_BEGIN_FLOW', message: 'ItemAlreadyOwned');
    final b = make(g);
    await b.ensureConnected();
    g.owned.add(_info('coins_small', 'owned-1'));
    final (result, coins) = await b.buy('coins_small');
    expect(result, BuyResult.granted);
    expect(coins, 100);
    expect(verified, ['owned-1']);
    expect(g.consumed, ['owned-1']);
  });

  test('binding dropped right before the purchase: reconnects once and buys', () async {
    final g = FakeGateway(['ok', 'ok']);
    final b = make(g);
    await b.ensureConnected();
    g.purchaseErrorsOnce.add(PlatformException(code: 'PURCHASE_FAILED', message: 'In order to purchasing, connect to Poolakey!'));
    final (result, coins) = await b.buy('coins_small');
    expect(result, BuyResult.granted);
    expect(coins, 100);
    expect(g.connects, 2);
    expect(g.purchases, 2);
  });
}
