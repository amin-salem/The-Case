import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:myket_iap/myket_iap.dart';
import 'package:myket_iap/util/constants.dart';
import 'package:myket_iap/util/iab_result.dart';
import 'package:myket_iap/util/inventory.dart';
import 'package:myket_iap/util/purchase.dart';

import 'api.dart';

/// Which store this build is for. `myket` (the default) pays through Myket; `test` is for development
/// only (no money, the dev server accepts "test-" tokens). Set with --dart-define=STORE=...
const String kStore = String.fromEnvironment('STORE', defaultValue: 'myket');

/// The store's name as players read it in the shop texts (follows the STORE build setting).
String get kStoreName => kStore == 'bazaar' ? 'کافه‌بازار' : 'مایکت';

/// The RSA public key from the Myket developer panel (--dart-define=MYKET_RSA_KEY=...).
const String kMyketRsa = String.fromEnvironment('MYKET_RSA_KEY');

const List<String> kProductIds = ['coins_small', 'coins_medium', 'coins_large', 'starter_pack', 'vip_monthly'];
const Set<String> _consumable = {'coins_small', 'coins_medium', 'coins_large', 'vip_monthly'};

enum BuyResult { granted, cancelled, pending, unavailable, failed }

/// In-app purchases. The phone never decides anything: every purchase token goes to our server,
/// which checks it with Myket and only then adds coins. Consumables are consumed in Myket after that.
class Billing extends ChangeNotifier {
  Billing._();
  static final Billing i = Billing._();

  bool _ready = false;
  bool _busy = false;
  final Map<String, String> _prices = {};
  final List<Purchase> _unfinished = [];

  bool get testStore => kStore == 'test';

  /// True when purchases can be made (Myket is installed and the key is set, or the test store).
  bool get available => testStore || _ready;

  /// The price Myket shows for a product (its own currency text), if known.
  String? price(String productId) => _prices[productId];

  Future<void> init() async {
    if (testStore || kMyketRsa.isEmpty) return;
    try {
      final r = await MyketIAP.init(rsaKey: kMyketRsa, enableDebugLogging: kDebugMode);
      _ready = r?.isSuccess() ?? false;
      if (_ready) await _loadInventory();
    } catch (e) {
      debugPrint('billing init: $e');
      _ready = false;
    }
    notifyListeners();
  }

  Future<void> _loadInventory() async {
    try {
      final m = await MyketIAP.queryInventory(querySkuDetails: true, skus: kProductIds);
      final res = m[MyketIAP.RESULT] as IabResult?;
      final inv = m[MyketIAP.INVENTORY] as Inventory?;
      if (res == null || res.isFailure() || inv == null) return;
      _prices
        ..clear()
        ..addAll({for (final e in inv.mSkuMap.entries) e.key: e.value.mPrice});
      _unfinished
        ..clear()
        ..addAll(inv.mPurchaseMap.values);
    } catch (e) {
      debugPrint('billing inventory: $e');
    }
  }

  /// Purchases paid in Myket but not yet credited (the app closed, no internet...): credit them now.
  /// Safe to call often; the server never credits the same token twice.
  Future<int> recover() async {
    if (!_ready || _busy || !Api.i.online) return 0;
    _busy = true;
    var added = 0;
    try {
      await _loadInventory();
      for (final p in List<Purchase>.of(_unfinished)) {
        try {
          final (status, coins) = await Api.i.verifyPurchase(p.mSku, p.mToken);
          if (status == 'granted' || status == 'already_granted') {
            added += coins;
            if (_consumable.contains(p.mSku)) await MyketIAP.consume(purchase: p);
            _unfinished.remove(p);
          }
        } catch (e) {
          debugPrint('billing recover ${p.mSku}: $e');
        }
      }
    } finally {
      _busy = false;
    }
    if (added > 0) notifyListeners();
    return added;
  }

  /// Buys a product. Returns what happened and how many coins were added.
  Future<(BuyResult, int)> buy(String productId) async {
    if (testStore) return _buyTest(productId);
    if (!_ready) return (BuyResult.unavailable, 0);
    final Map<dynamic, dynamic> m;
    try {
      m = await MyketIAP.launchPurchaseFlow(sku: productId, payload: Api.i.playerId);
    } catch (e) {
      debugPrint('billing launch: $e');
      return (BuyResult.failed, 0);
    }
    final res = m[MyketIAP.RESULT] as IabResult?;
    final p = m[MyketIAP.PURCHASE] as Purchase?;
    if (res == null || res.isFailure() || p == null) {
      final code = res?.mResponse;
      if (code == Constants.BILLING_RESPONSE_RESULT_USER_CANCELED || code == Constants.IABHELPER_USER_CANCELLED) {
        return (BuyResult.cancelled, 0);
      }
      if (code == Constants.BILLING_RESPONSE_RESULT_ITEM_ALREADY_OWNED) {
        final added = await recover();
        return (BuyResult.granted, added);
      }
      return (BuyResult.failed, 0);
    }
    try {
      final (status, added) = await Api.i.verifyPurchase(productId, p.mToken);
      if (status != 'granted' && status != 'already_granted') return (BuyResult.failed, 0);
      if (_consumable.contains(productId)) {
        try {
          await MyketIAP.consume(purchase: p);
        } catch (e) {
          debugPrint('billing consume: $e'); // recover() consumes it later; the server won't credit twice
        }
      }
      return (BuyResult.granted, added);
    } catch (e) {
      // paid, but the server couldn't be reached: it stays unconsumed and recover() credits it later
      debugPrint('billing verify: $e');
      _unfinished.add(p);
      return (BuyResult.pending, 0);
    }
  }

  Future<(BuyResult, int)> _buyTest(String productId) async {
    try {
      final token = 'test-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
      final (status, added) = await Api.i.verifyPurchase(productId, token);
      return (status == 'granted' ? BuyResult.granted : BuyResult.failed, added);
    } catch (e) {
      debugPrint('billing test: $e');
      return (BuyResult.failed, 0);
    }
  }
}
