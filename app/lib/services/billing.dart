import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
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

/// Why the connection to Cafe Bazaar is not there (the shop shows a different text for each).
enum BillingProblem { none, notInstalled, tooOld, timeout, noKey, other }

/// The Persian text for a problem (null for none). Used by the shop and by tests.
String? billingProblemText(BillingProblem p) {
  switch (p) {
    case BillingProblem.none:
      return null;
    case BillingProblem.notInstalled:
      return 'اپ $kStoreName روی گوشی پیدا نشد. اول نصبش کن، بعد دوباره امتحان کن.';
    case BillingProblem.tooOld:
      return 'نسخه‌ی اپ $kStoreName قدیمیه. به‌روزش کن و دوباره امتحان کن.';
    case BillingProblem.timeout:
      return 'اتصال به $kStoreName جواب نداد. یه بار اپ $kStoreName رو باز کن و دوباره امتحان کن.';
    case BillingProblem.noKey:
      return 'خرید توی این نسخه فعال نیست. نسخه‌ی تازه‌ی بازی رو نصب کن.';
    case BillingProblem.other:
      return 'اتصال به $kStoreName برقرار نشد. دوباره امتحان کن.';
  }
}

/// Sorts a Poolakey connection-failure text (an exception name) into a [BillingProblem].
@visibleForTesting
BillingProblem classifyConnectFailure(String reason) {
  final t = reason.toLowerCase();
  if (t.contains('notfound') || t.contains('not found') || t.contains('notinstalled') || t.contains('not installed')) {
    return BillingProblem.notInstalled;
  }
  if (t.contains('notsupported') || t.contains('not supported') || t.contains('update') || t.contains('outdated')) {
    return BillingProblem.tooOld;
  }
  if (t.contains('timeout') || t.contains('timed out')) return BillingProblem.timeout;
  return BillingProblem.other;
}

/// What [Billing] needs from Poolakey. A thin layer so tests can use a fake instead of the phone's Bazaar.
abstract class BazaarGateway {
  Future<void> connect(String key,
      {required VoidCallback onSucceed, required void Function(String reason) onFailed, required VoidCallback onDisconnected});
  Future<bool> isConnected();
  Future<List<SkuDetails>> skuDetails(List<String> ids);
  Future<List<PurchaseInfo>> purchased();
  Future<PurchaseInfo> purchase(String productId, String payload);
  Future<bool> consume(String token);
}

class PoolakeyGateway implements BazaarGateway {
  @override
  Future<void> connect(String key,
      {required VoidCallback onSucceed, required void Function(String reason) onFailed, required VoidCallback onDisconnected}) {
    return FlutterPoolakey.connect(key, onSucceed: onSucceed, onFailed: onFailed, onDisconnected: onDisconnected);
  }

  @override
  Future<bool> isConnected() => FlutterPoolakey.isConnected();
  @override
  Future<List<SkuDetails>> skuDetails(List<String> ids) => FlutterPoolakey.getInAppSkuDetails(ids);
  @override
  Future<List<PurchaseInfo>> purchased() => FlutterPoolakey.getAllPurchasedProducts();
  @override
  Future<PurchaseInfo> purchase(String productId, String payload) => FlutterPoolakey.purchase(productId, payload: payload);
  @override
  Future<bool> consume(String token) => FlutterPoolakey.consume(token);
}

/// In-app purchases. The phone never decides anything: every purchase token goes to our server,
/// which checks it with Cafe Bazaar and only then adds coins. Consumables are consumed in Bazaar after that.
///
/// The connection to the Bazaar app is lazy and retried (13-18 Oct 2026, after Bazaar rejected version 55): it is
/// opened at startup in the background, again when the player buys, on app resume and after a disconnect. A failed
/// first connect never leaves the shop dead.
class Billing extends ChangeNotifier {
  Billing._()
      : _gateway = PoolakeyGateway(),
        _rsaKey = kBazaarRsa,
        _testStore = kStore == 'test',
        _verify = _apiVerify,
        _isOnline = _apiOnline,
        _playerId = _apiPlayer;

  /// For tests: everything the phone and the server provide is replaced.
  @visibleForTesting
  Billing.forTest({
    required BazaarGateway gateway,
    String rsaKey = 'test-key',
    bool testStore = false,
    required Future<(String, int)> Function(String productId, String token) verify,
    bool Function()? isOnline,
    this.connectTimeout = const Duration(milliseconds: 200),
    this.retryDelay = Duration.zero,
    this.attempts = 3,
  })  : _gateway = gateway,
        _rsaKey = rsaKey,
        _testStore = testStore,
        _verify = verify,
        _isOnline = isOnline ?? (() => true),
        _playerId = (() => 'player');

  static final Billing i = Billing._();

  static Future<(String, int)> _apiVerify(String productId, String token) =>
      Api.i.verifyPurchase(productId, token, store: 'bazaar');
  static bool _apiOnline() => Api.i.online;
  static String? _apiPlayer() => Api.i.playerId;

  final BazaarGateway _gateway;
  final String _rsaKey;
  final bool _testStore;
  final Future<(String, int)> Function(String, String) _verify;
  final bool Function() _isOnline;
  final String? Function() _playerId;

  /// How long one connection attempt may take (slow Xiaomi/MIUI phones bind to Bazaar slowly) and how many.
  Duration connectTimeout = const Duration(seconds: 18);
  Duration retryDelay = const Duration(seconds: 1);
  int attempts = 3;

  bool _ready = false;
  bool _busy = false;
  bool _connecting = false;
  BillingProblem _problem = BillingProblem.none;
  Future<BillingProblem>? _connectFuture;
  final Map<String, String> _prices = {};
  final List<PurchaseInfo> _unfinished = [];

  bool get testStore => _testStore;

  /// True when purchases can be made right now (Bazaar is connected, or the test store).
  bool get available => testStore || _ready;

  /// True while a (re)connection to Bazaar is running; the shop shows «در حال اتصال به کافه‌بازار…».
  bool get connecting => _connecting;

  /// Why the last connection failed (none when connected).
  BillingProblem get problem => _problem;

  /// The price Bazaar shows for a product (its own currency text), if known.
  String? price(String productId) => _prices[productId];

  /// Startup: connect in the background (never throws, never blocks the game).
  Future<void> init() async {
    if (testStore) return;
    await ensureConnected(tries: 2);
  }

  /// The app came back to the foreground: if Bazaar is not connected, try once more quietly.
  Future<void> onResume() async {
    if (testStore || _connecting || _busy) return;
    if (_ready && !await _alive()) {
      _ready = false;
      notifyListeners();
    }
    if (!_ready) await ensureConnected(tries: 1);
  }

  Future<bool> _alive() async {
    try {
      return await _gateway.isConnected();
    } catch (_) {
      return false;
    }
  }

  /// Connects to the Bazaar app (shares one running attempt between callers). Retries on timeouts and unknown
  /// errors; gives up at once when Bazaar is missing/too old or the key is not set. Returns the problem (none = ok).
  Future<BillingProblem> ensureConnected({int? tries}) {
    if (testStore) return Future.value(BillingProblem.none);
    if (_ready) return Future.value(BillingProblem.none);
    return _connectFuture ??= _connectLoop(tries ?? attempts).whenComplete(() {
      _connectFuture = null;
      _connecting = false;
      notifyListeners();
    });
  }

  Future<BillingProblem> _connectLoop(int tries) async {
    if (_rsaKey.isEmpty) {
      _problem = BillingProblem.noKey;
      debugPrint('billing: BAZAAR_RSA_KEY is empty in this build');
      return _problem;
    }
    _connecting = true;
    notifyListeners();
    var problem = BillingProblem.other;
    for (var n = 1; n <= tries; n++) {
      problem = await _connectOnce();
      debugPrint('billing: connect attempt $n/$tries -> ${problem.name}');
      if (problem == BillingProblem.none) break;
      if (problem == BillingProblem.notInstalled || problem == BillingProblem.tooOld) break; // retrying can't help
      if (n < tries) await Future<void>.delayed(retryDelay * n);
    }
    _problem = problem;
    if (problem == BillingProblem.none) {
      _ready = true;
      _connecting = false;
      notifyListeners();
      await _loadInventory();
    } else {
      _ready = false;
    }
    return problem;
  }

  Future<BillingProblem> _connectOnce() async {
    final done = Completer<BillingProblem>();
    try {
      // Not awaited on its own: the answer comes through the callbacks (or the timeout below).
      unawaited(_gateway
          .connect(
            _rsaKey,
            onSucceed: () {
              if (!done.isCompleted) done.complete(BillingProblem.none);
            },
            onFailed: (reason) {
              debugPrint('billing: connection failed: $reason');
              if (!done.isCompleted) done.complete(classifyConnectFailure(reason));
            },
            onDisconnected: _onDisconnected,
          )
          .catchError((Object e) {
        debugPrint('billing: connect error: $e');
        if (!done.isCompleted) done.complete(classifyConnectFailure('$e'));
      }));
      return await done.future.timeout(connectTimeout, onTimeout: () => BillingProblem.timeout);
    } catch (e) {
      debugPrint('billing connect: $e');
      return BillingProblem.other;
    }
  }

  void _onDisconnected() {
    if (!_ready) return;
    _ready = false;
    notifyListeners();
    // Bazaar's process was stopped or the system dropped the binding: reconnect quietly
    unawaited(Future<void>.delayed(const Duration(seconds: 2)).then((_) => ensureConnected(tries: 1)));
  }

  Future<void> _loadInventory() async {
    try {
      final details = await _gateway.skuDetails(kProductIds);
      _prices
        ..clear()
        ..addAll({for (final d in details) d.sku: d.price});
    } catch (e) {
      debugPrint('billing sku details: $e');
    }
    try {
      final owned = await _gateway.purchased();
      _unfinished
        ..clear()
        ..addAll(owned);
    } catch (e) {
      debugPrint('billing inventory: $e');
    }
    notifyListeners();
  }

  /// Purchases paid in Bazaar but not yet credited (the app closed, no internet...): credit them now.
  /// Safe to call often; the server never credits the same token twice.
  Future<int> recover() async {
    if (!_ready || _busy || !_isOnline()) return 0;
    _busy = true;
    var added = 0;
    try {
      await _loadInventory();
      for (final p in List<PurchaseInfo>.of(_unfinished)) {
        try {
          final (status, coins) = await _verify(p.productId, p.purchaseToken);
          if (status == 'granted' || status == 'already_granted') {
            added += coins;
            if (_consumable.contains(p.productId)) await _gateway.consume(p.purchaseToken);
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

  /// Buys a product. Returns what happened and how many coins were added. When Bazaar is not connected yet it
  /// connects first (with retries); [problem] says why when the result is [BuyResult.unavailable].
  Future<(BuyResult, int)> buy(String productId) async {
    if (testStore) return _buyTest(productId);
    if (!_ready) {
      final problem = await ensureConnected();
      if (problem != BillingProblem.none || !_ready) return (BuyResult.unavailable, 0);
    }
    PurchaseInfo? p;
    for (var round = 0; round < 2 && p == null; round++) {
      try {
        p = await _gateway.purchase(productId, _playerId() ?? '');
      } catch (e) {
        final text = '$e'.toLowerCase();
        debugPrint('billing launch: $e');
        final code = e is PlatformException ? e.code : '';
        if (code == 'PURCHASE_CANCELLED' || text.contains('cancel')) return (BuyResult.cancelled, 0);
        if (text.contains('owned') || text.contains('already')) {
          final added = await recover();
          return (BuyResult.granted, added);
        }
        // the binding dropped between the connect and the purchase (or no screen was in front): reconnect once
        final notConnected = text.contains('connect to poolakey') || text.contains('not connected') || code == 'NO_ACTIVITY';
        if (round == 0 && notConnected) {
          _ready = false;
          final problem = await ensureConnected(tries: 2);
          if (problem != BillingProblem.none || !_ready) return (BuyResult.unavailable, 0);
          continue;
        }
        return (BuyResult.failed, 0);
      }
    }
    final bought = p!;
    try {
      final (status, added) = await _verify(productId, bought.purchaseToken);
      if (status != 'granted' && status != 'already_granted') return (BuyResult.failed, 0);
      if (_consumable.contains(productId)) {
        try {
          await _gateway.consume(bought.purchaseToken);
        } catch (e) {
          debugPrint('billing consume: $e'); // recover() consumes it later; the server won't credit twice
        }
      }
      return (BuyResult.granted, added);
    } catch (e) {
      // paid, but the server couldn't be reached: it stays unconsumed and recover() credits it later
      debugPrint('billing verify: $e');
      _unfinished.add(bought);
      return (BuyResult.pending, 0);
    }
  }

  Future<(BuyResult, int)> _buyTest(String productId) async {
    try {
      final token = 'test-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
      final (status, added) = await _verify(productId, token);
      return (status == 'granted' ? BuyResult.granted : BuyResult.failed, added);
    } catch (e) {
      debugPrint('billing test: $e');
      return (BuyResult.failed, 0);
    }
  }
}
