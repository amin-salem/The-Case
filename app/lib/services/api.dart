import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Server address (Liara). Another server for testing:
///   flutter run --dart-define=API_URL=http://192.168.1.5:8000
const String kApiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://thecase.liara.run');
const int kAppBuild = int.fromEnvironment('APP_BUILD', defaultValue: 1);

class ApiException implements Exception {
  ApiException(this.status, this.detail);
  final int status;
  final Object? detail;

  /// The machine-readable reason ("not_enough_coins", "locked", ...).
  String get code => detail is Map ? '${(detail as Map)['error']}' : '$detail';
  int get need => detail is Map ? ((detail as Map)['need'] as int? ?? (detail as Map)['cost'] as int? ?? 0) : 0;

  @override
  String toString() => 'ApiException($status, $detail)';
}

/// Everything that talks to the game server. The game is online: coins,
/// cases and solutions live on the server.
class Api extends ChangeNotifier {
  Api._();
  static final Api i = Api._();

  late SharedPreferences _p;
  final http.Client _http = http.Client();
  String? _playerId, _secret, _token;
  int _tokenExp = 0;

  Map<String, dynamic> config = const {};
  Profile? profile;
  int inboxCount = 0;
  String lastError = '';
  bool ready = false;

  int get coins => profile?.coins ?? 0;

  // ---------------------------------------------------------------- start

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _playerId = _p.getString('player');
    _secret = _p.getString('secret');
    _token = _p.getString('token');
    _tokenExp = _p.getInt('token_exp') ?? 0;
  }

  /// Connects (register / login) and loads profile + config. Returns an error text or null.
  Future<String?> connect() async {
    try {
      config = (await _call('GET', '/v1/config', auth: false) as Map).cast<String, dynamic>();
      await _ensureLogin();
      await refreshProfile();
      ready = true;
      lastError = '';
      unawaited(refreshInbox());
      notifyListeners();
      return null;
    } catch (e) {
      lastError = describe(e);
      notifyListeners();
      return lastError;
    }
  }

  String _deviceId() {
    var id = _p.getString('device');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _p.setString('device', id);
    }
    return id;
  }

  Future<void> _ensureLogin() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_token != null && _tokenExp - now > 3600) return;
    if (_playerId == null || _secret == null) {
      final j = await _call('POST', '/v1/auth/register',
          auth: false, body: {'device_id': _deviceId(), 'app_version': kAppBuild}) as Map;
      await _storeLogin(j.cast<String, dynamic>());
      return;
    }
    try {
      final j = await _call('POST', '/v1/auth/login',
          auth: false, body: {'player_id': _playerId, 'secret': _secret, 'app_version': kAppBuild}) as Map;
      _token = j['token'] as String;
      _tokenExp = j['expires_at'] as int;
      await _p.setString('token', _token!);
      await _p.setInt('token_exp', _tokenExp);
    } on ApiException catch (e) {
      if (e.status != 401) rethrow;
      // the account moved to another phone: start fresh here
      _playerId = _secret = null;
      return _ensureLogin();
    }
  }

  Future<void> _storeLogin(Map<String, dynamic> j) async {
    _playerId = j['player_id'] as String;
    _secret = j['secret'] as String;
    _token = j['token'] as String;
    _tokenExp = j['expires_at'] as int;
    await _p.setString('player', _playerId!);
    await _p.setString('secret', _secret!);
    await _p.setString('token', _token!);
    await _p.setInt('token_exp', _tokenExp);
  }

  // ---------------------------------------------------------------- http

  static String describe(Object e) {
    final t = e.toString();
    if (e is ApiException) return 'server error ${e.status}: ${e.detail}';
    if (t.contains('Failed host lookup') || t.contains('SocketException')) {
      return 'no internet / server not found ($kApiUrl)';
    }
    if (t.contains('TimeoutException')) return 'server did not answer in time';
    if (t.contains('HandshakeException')) return 'HTTPS/SSL problem';
    if (e is FormatException) return 'server sent a non-JSON answer (it may be restarting)';
    return t.length > 140 ? t.substring(0, 140) : t;
  }

  Future<Object?> _call(String method, String path, {Object? body, bool auth = true, bool retried = false}) async {
    final uri = Uri.parse('$kApiUrl$path');
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      await _ensureLogin();
      headers['Authorization'] = 'Bearer $_token';
    }
    final data = body == null ? null : jsonEncode(body);
    const t = Duration(seconds: 15);
    final http.Response r;
    switch (method) {
      case 'GET':
        r = await _http.get(uri, headers: headers).timeout(t);
      case 'PATCH':
        r = await _http.patch(uri, headers: headers, body: data).timeout(t);
      default:
        r = await _http.post(uri, headers: headers, body: data).timeout(t);
    }
    final text = utf8.decode(r.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (r.statusCode == 401 && auth && !retried) {
      _token = null;
      _tokenExp = 0;
      return _call(method, path, body: body, auth: auth, retried: true);
    }
    if (r.statusCode >= 400) throw ApiException(r.statusCode, decoded is Map ? decoded['detail'] : decoded);
    return decoded;
  }

  void _setCoins(int coins) {
    final p = profile;
    if (p == null) return;
    profile = Profile({
      'player_id': p.playerId, 'nickname': p.nickname, 'avatar': p.avatar, 'invite_code': p.inviteCode,
      'referred': p.referred, 'email': p.email, 'secured': p.secured, 'coins': coins, 'no_ads': p.noAds,
      'vip_until': p.vipUntil, 'streak': p.streak, 'best_streak': p.bestStreak, 'cases_solved': p.casesSolved,
      'stars_total': p.starsTotal, 'login_day': p.loginDay, 'streak_freezes': p.streakFreezes,
    });
    notifyListeners();
  }

  // ---------------------------------------------------------------- profile

  Future<Profile?> refreshProfile() async {
    final j = await _call('GET', '/v1/me') as Map;
    profile = Profile(j.cast<String, dynamic>());
    notifyListeners();
    return profile;
  }

  Future<void> updateProfile({String? nickname, int? avatar}) async {
    final j = await _call('PATCH', '/v1/me', body: {
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
    }) as Map;
    profile = Profile(j.cast<String, dynamic>());
    notifyListeners();
  }

  Future<int> adReward() async {
    final j = await _call('POST', '/v1/wallet/ad-reward') as Map;
    _setCoins(j['coins'] as int);
    return j['added'] as int;
  }

  // ---------------------------------------------------------------- cases

  Future<CasesList> cases() async => CasesList((await _call('GET', '/v1/cases') as Map).cast<String, dynamic>());

  /// Returns (case, progress, isToday).
  Future<(CaseData, Progress, bool)> openCase(String id) async {
    final j = (await _call('GET', '/v1/cases/$id') as Map).cast<String, dynamic>();
    return (CaseData((j['case'] as Map).cast<String, dynamic>()),
        Progress((j['progress'] as Map).cast<String, dynamic>()), j['today'] == true);
  }

  Future<void> unlockCase(String id) async {
    await _call('POST', '/v1/cases/$id/unlock');
    await refreshProfile();
  }

  /// Returns (hint text, progress).
  Future<(String, Progress)> buyHint(String id) async {
    final j = (await _call('POST', '/v1/cases/$id/hint') as Map).cast<String, dynamic>();
    _setCoins(j['coins'] as int);
    return (j['hint'] as String, Progress((j['progress'] as Map).cast<String, dynamic>()));
  }

  Future<AccuseResult> accuse(String caseId, String suspectId, String evidenceId) async {
    final j = (await _call('POST', '/v1/cases/$caseId/accuse', body: {'suspect': suspectId, 'evidence': evidenceId})
            as Map)
        .cast<String, dynamic>();
    final r = AccuseResult(j);
    if (r.result == 'solved') {
      await refreshProfile();
    } else {
      _setCoins(r.coins);
    }
    return r;
  }

  /// What everyone else guessed (only after the player finished the case).
  Future<CaseStats> caseStats(String id) async =>
      CaseStats((await _call('GET', '/v1/cases/$id/stats') as Map).cast<String, dynamic>());

  /// Buys one streak insurance with coins. Throws ApiException (not_enough_coins / max_freezes).
  Future<void> buyStreakFreeze() async {
    final j = await _call('POST', '/v1/wallet/streak-freeze') as Map;
    profile = Profile(j.cast<String, dynamic>());
    notifyListeners();
  }

  Map<String, dynamic> get _economy =>
      config['economy'] is Map ? (config['economy'] as Map).cast<String, dynamic>() : const {};
  int get freezeCost => _economy['freeze_cost'] as int? ?? 150;
  int get maxFreezes => _economy['max_freezes'] as int? ?? 2;
  List<int> get loginCalendar =>
      [for (final v in (_economy['login_calendar'] as List? ?? const [20, 30, 40, 50, 60, 80])) (v as num).toInt()];
  List<int> get streakBadges => [for (final v in (_economy['streak_badges'] as List? ?? const [7, 30, 100])) (v as num).toInt()];
  String get shareUrl => config['share_url'] is String
      ? config['share_url'] as String
      : (config['update_url'] is String ? config['update_url'] as String : 'https://cafebazaar.ir/app/ir.aminsalem.the_case');

  Future<Leaderboard> leaderboard(String period) async =>
      Leaderboard((await _call('GET', '/v1/leaderboard?period=$period') as Map).cast<String, dynamic>());

  // ---------------------------------------------------------------- shop

  String price(String productId) {
    final p = config['prices'];
    return p is Map && p[productId] is String ? p[productId] as String : '';
  }

  int productCoins(String productId) {
    final e = config['economy'];
    if (e is Map && e['products'] is Map && (e['products'] as Map)[productId] is Map) {
      return ((e['products'] as Map)[productId] as Map)['coins'] as int? ?? 0;
    }
    return 0;
  }

  /// Returns (status, coins added).
  Future<(String, int)> verifyPurchase(String productId, String token) async {
    final j = (await _call('POST', '/v1/purchases/verify', body: {'product_id': productId, 'purchase_token': token})
            as Map)
        .cast<String, dynamic>();
    await refreshProfile();
    return ('${j['status']}', j['added'] as int? ?? 0);
  }

  // ---------------------------------------------------------------- account

  /// Returns (reward coins, error text).
  Future<(int, String?)> secureWithEmail(String email, String password) async {
    try {
      final j = (await _call('POST', '/v1/auth/email', body: {'email': email, 'password': password}) as Map)
          .cast<String, dynamic>();
      profile = Profile((j['profile'] as Map).cast<String, dynamic>());
      notifyListeners();
      return (j['reward'] as int? ?? 0, null);
    } on ApiException catch (e) {
      return (0, errorText(e.code));
    } catch (e) {
      return (0, 'اتصال به سرور برقرار نیست\n(${describe(e)})');
    }
  }

  Future<String?> loginWithEmail(String email, String password) =>
      _loginWith('/v1/auth/login/email', {'email': email, 'password': password});

  Future<String?> useTransferCode(String code) => _loginWith('/v1/auth/transfer', {'code': code.trim()});

  Future<String?> _loginWith(String path, Map<String, dynamic> body) async {
    try {
      final j = await _call('POST', path, auth: false, body: {...body, 'device_id': _deviceId()}) as Map;
      await _storeLogin(j.cast<String, dynamic>());
      await refreshProfile();
      return null;
    } on ApiException catch (e) {
      return errorText(e.code);
    } catch (e) {
      return 'اتصال به سرور برقرار نیست\n(${describe(e)})';
    }
  }

  Future<String?> makeTransferCode() async {
    try {
      final j = await _call('POST', '/v1/auth/transfer-code') as Map;
      return '${j['code']}';
    } catch (_) {
      return null;
    }
  }

  /// Returns (coins received, error text).
  Future<(int, String?)> redeemInvite(String code) async {
    try {
      final j = await _call('POST', '/v1/referrals/redeem', body: {'code': code.trim()}) as Map;
      await refreshProfile();
      final grants = (j['grants'] as List?) ?? const [];
      return (grants.isEmpty ? 0 : ((grants.first as Map)['amount'] as int? ?? 0), null);
    } on ApiException catch (e) {
      return (0, errorText(e.code));
    } catch (e) {
      return (0, 'اتصال به سرور برقرار نیست');
    }
  }

  // ---------------------------------------------------------------- inbox

  Future<List<InboxGift>> inbox() async {
    final list = await _call('GET', '/v1/inbox') as List;
    final gifts = [for (final g in list) InboxGift((g as Map).cast<String, dynamic>())];
    inboxCount = gifts.length;
    notifyListeners();
    return gifts;
  }

  Future<void> refreshInbox() async {
    try {
      await inbox();
    } catch (_) {}
  }

  Future<int> claim(InboxGift g) async {
    final j = await _call('POST', '/v1/inbox/${g.id}/claim') as Map;
    inboxCount = max(0, inboxCount - 1);
    _setCoins(j['coins'] as int);
    return g.coins;
  }

  // ---------------------------------------------------------------- errors

  static String errorText(String code) => switch (code) {
        'not_enough_coins' => 'سکه‌ات کافی نیست',
        'locked' => 'این پرونده قفله',
        'case_finished' => 'این پرونده تموم شده',
        'no_more_hints' => 'سرنخ دیگه‌ای نمونده',
        'bad_email' => 'ایمیل درست نیست',
        'bad_password' => 'رمز باید حداقل ۶ حرف باشه',
        'email_taken' => 'این ایمیل قبلاً برای یه حساب دیگه ثبت شده',
        'email_cant_change' => 'ایمیل این حساب رو نمی‌شه عوض کرد',
        'wrong_login' => 'ایمیل یا رمز اشتباهه',
        'bad_code' => 'کد اشتباهه یا تاریخش گذشته',
        'already_redeemed' => 'قبلاً کد دعوت وارد کردی',
        'only_for_new_players' => 'کد دعوت فقط برای بازیکن‌های تازه است',
        'same_device' => 'نمی‌شه با گوشی خودت خودت رو دعوت کنی!',
        'ad_limit' => 'امروز سهم تبلیغت تموم شد، فردا دوباره بیا',
        'bad_nickname' => 'این اسم قابل قبول نیست',
        'banned' => 'این حساب مسدود شده',
        'too_many_requests' => 'خیلی سریع امتحان کردی، کمی صبر کن',
        'max_freezes' => 'بیشتر از این نمی‌شه بیمه نگه داشت',
        'finish_first' => 'اول پرونده رو تموم کن',
        _ => 'خطا، دوباره امتحان کن',
      };
}
