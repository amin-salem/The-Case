import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_poolakey/flutter_poolakey.dart';

import 'api.dart';

/// Which store this build is for. `bazaar` (the default) pays through Cafe Bazaar; `test` is for development
/// only (no money, the dev server accepts "test-" tokens). Set with --dart-define=STORE=...
/// (Myket billing was switched off on 12 Oct 2026: Bazaar is the only store for now.)
const String kStore = String.fromEnvironment('STORE', defaultValue: 'bazaar');

/// The store's name as players read it in the shop texts.
String get kStoreName => 'کافه‌بازار';

/// The RSA public key from the Cafe Bazaar developer panel (--dart-define=BAZAAR_RSA_KEY=...).
const String kBazaarRsa = String.fromEnvironment('BAZAAR_RSA_KEY');

const List<String> kProductIds = ['coins_small', 'coins_medium', 'coins_large', 'starter_pack', 'vip_monthly'];
const Set<String> _consumable = {'coins_small', 'coins_medium', 'coins_large', 'vip_monthly'};

enum BuyResult { granted, cancelled, pending, unavailable, failed }

/// In-app purchases. The phone never decides anything: every purchase token goes to our server,
/// which checks it with Cafe Bazaar and only then adds coins. Consumables are consumed in Bazaar after that.
class Billing extends ChangeNotifier {
  Billing._();
  static final Billing i = Billing._();

  bool _ready = false;
  bool _busy = false;
  final Map<String, String> _prices = {};
  final List<PurchaseInfo> _unfinished = [];

  bool get testStore => kStore == 'test';

  /// True when purchases can be made (Cafe Bazaar is installed and the key is set, or the test store).
  bool get available => testStore || _ready;

  /// The price Bazaar shows for a product (its own currency text), if known.
  String? price(String productId) => _prices[productId];

  Future<void> init() async {
    if (testStore || kBazaarRsa.isEmpty) return;
    try {
      final done = Completer<bool>();
      await FlutterPoolakey.connect(
        kBazaarRsa,
        onSucceed: () {
          if (!done.isCompleted) done.complete(true);
        },
        onFailed: () {
          if (!done.isCompleted) done.complete(false);
        },
        onDisconnected: () {
          _ready = false;
          notifyListeners();
        },
      );
      _ready = await done.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (_ready) await _loadInventory();
    } catch (e) {
      debugPrint('billing init: $e');
      _ready = false;
    }
    notifyListeners();
  }

  Future<void> _loadInventory() async {
    try {
      final details = await FlutterPoolakey.getInAppSkuDetails(kProductIds);
      _prices
        ..clear()
        ..addAll({for (final d in details) d.sku: d.price});
    } catch (e) {
      debugPrint('billing sku details: $e');
    }
    try {
      final owned = await FlutterPoolakey.getAllPurchasedProducts();
      _unfinished
        ..clear()
        ..addAll(owned);
    } catch (e) {
      debugPrint('billing inventory: $e');
    }
  }

  /// Purchases paid in Bazaar but not yet credited (the app closed, no internet...): credit them now.
  /// Safe to call often; the server never credits the same token twice.
  Future<int> recover() async {
    if (!_ready || _busy || !Api.i.online) return 0;
    _busy = true;
    var added = 0;
    try {
      await _loadInventory();
      for (final p in List<PurchaseInfo>.of(_unfinished)) {
        try {
          final (status, coins) = await Api.i.verifyPurchase(p.productId, p.purchaseToken, store: 'bazaar');
          if (status == 'granted' || status == 'already_granted') {
            added += coins;
            if (_consumable.contains(p.productId)) await FlutterPoolakey.consume(p.purchaseToken);
            _unfinished.remove(p);
          }
        } catch (e) {
          debugPrint('billing recover ${p.productId}: $e');
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
    final PurchaseInfo p;
    try {
      p = await FlutterPoolakey.purchase(productId, payload: Api.i.playerId ?? '');
    } catch (e) {
      final text = '$e'.toLowerCase();
      debugPrint('billing launch: $e');
      if (text.contains('cancel')) return (BuyResult.cancelled, 0);
      if (text.contains('owned')) {
        final added = await recover();
        return (BuyResult.granted, added);
      }
      return (BuyResult.failed, 0);
    }
    try {
      final (status, added) = await Api.i.verifyPurchase(productId, p.purchaseToken, store: 'bazaar');
      if (status != 'granted' && status != 'already_granted') return (BuyResult.failed, 0);
      if (_consumable.contains(productId)) {
        try {
          await FlutterPoolakey.consume(p.purchaseToken);
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
      final (status, added) = await Api.i.verifyPurchase(productId, token, store: 'bazaar');
      return (status == 'granted' ? BuyResult.granted : BuyResult.failed, added);
    } catch (e) {
      debugPrint('billing test: $e');
      return (BuyResult.failed, 0);
    }
  }
}
