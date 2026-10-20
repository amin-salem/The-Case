import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/avatars.dart';
import '../models/progress.dart';
import '../models/story.dart';
import 'case_clock.dart';
import 'claim_note_store.dart';
import 'reminders.dart';

/// Server address (Liara). Another server for testing:
///   flutter run --dart-define=API_URL=http://192.168.1.5:8000
/// A build can point at one server with --dart-define=API_URL=…; otherwise the app uses
/// https://gaamly.ir (the list is kept so another address can be added later; a saved index is clamped).
const String kApiUrl = String.fromEnvironment('API_URL', defaultValue: '');
const List<String> kApiUrls = kApiUrl == '' ? ['https://gaamly.ir'] : [kApiUrl];
const int kAppBuild = int.fromEnvironment('APP_BUILD', defaultValue: 1);

class ApiException implements Exception {
  ApiException(this.status, this.detail);
  final int status;
  final Object? detail;

  /// The machine-readable reason ("not_enough_coins", "locked", ...).
  String get code => detail is Map ? '${(detail as Map)['error']}' : '$detail';

  /// Seconds the server asked us to wait (HTTP 429), 0 when unknown.
  int get retryAfter => detail is Map ? ((detail as Map)['retry_after'] as num?)?.toInt() ?? 0 : 0;
  bool get rateLimited => status == 429;

  /// The server's own friendly sentence for a refused registration (too many accounts on this phone / network today).
  String? get registerLimitMessage {
    final d = detail;
    if (d is Map && d['policy'] != null && '${d['policy']}'.startsWith('register') && d['message'] is String) {
      return d['message'] as String;
    }
    return null;
  }
  int get need => detail is Map ? ((detail as Map)['need'] as int? ?? (detail as Map)['cost'] as int? ?? 0) : 0;

  @override
  String toString() => 'ApiException($status, $detail)';
}

/// Why a call failed, as far as the player is concerned.
enum FailKind {
  /// no internet on the phone
  offline,

  /// the server is down, slow, restarting, or something in between answers instead of it
  server,

  /// the server said no for a game reason ("not_enough_coins", ...)
  business,

  /// anything else (a bug)
  other,
}

/// Everything that talks to the game server. Coins, cases and solutions live
/// on the server; the last answers are kept on the phone so the game still
/// opens (and opened cases can be read) without internet.
class Api extends ChangeNotifier {
  Api._();
  static final Api i = Api._();

  late SharedPreferences _p;
  int _baseIx = 0;

  /// The server address in use right now.
  String get apiBase => kApiUrls[_baseIx];
  http.Client _http = http.Client();
  String? _playerId, _secret, _token;
  int _tokenExp = 0;

  Map<String, dynamic> config = const {};
  Profile? profile;
  Map<String, dynamic> _profileJson = const {};
  int inboxCount = 0;

  /// Unread items in the messages hub: one shared number for every bell (updated with the profile).
  final ValueNotifier<int> unread = ValueNotifier(0);

  /// The last connection problem, already in friendly Persian ('' when fine).
  String lastError = '';
  bool ready = false;

  /// Set when the server said «too many requests» (429): until when to wait. The banner counts down to it.
  final ValueNotifier<DateTime?> rateLimitedUntil = ValueNotifier(null);

  /// Waits between retries of a rate-limited GET (tests replace it so nothing really sleeps).
  @visibleForTesting
  Future<void> Function(Duration) sleep = (d) => Future<void>.delayed(d);

  /// How long to wait before retry number [attempt] (0 = first retry) of a rate-limited GET: exponential
  /// (the server's Retry-After, doubling each time) plus up to half a second of jitter, never more than 10 s.
  static Duration backoffDelay(int attempt, int retryAfter, [Random? rng]) {
    final base = (retryAfter < 1 ? 1 : retryAfter) * 1000 * (1 << attempt);
    final jitter = (rng ?? Random()).nextInt(500);
    return Duration(milliseconds: (base + jitter).clamp(0, 10000).toInt());
  }

  /// False while the server can't be reached. Screens rebuild when it changes.
  bool online = true;

  /// Grows each time this phone switches to another account, so screens can reload.
  int account = 0;

  bool _configFromServer = false;
  bool _reconnecting = false;
  Timer? _retry;

  int get coins => profile?.coins ?? 0;

  /// What the last action earned (a finished mission, a new rank, achievements); the app shows banners.
  final ValueNotifier<Gains?> gains = ValueNotifier(null);

  void _emitGains(Object? j) {
    if (j is! Map) return;
    final g = Gains(j.cast<String, dynamic>());
    if (!g.isEmpty) gains.value = g;
    if (g.xp > 0 || g.warrants > 0 || g.achievements.isNotEmpty) unawaited(_refreshProfileQuietly()); // new XP / rank / coins
  }

  /// The detective ranks (XP needed, title), from the server's config.
  List<(int, String)> get ranks {
    final list = _economy['ranks'];
    if (list is! List || list.isEmpty) return const [(0, 'کارآگاه تازه‌کار')];
    return [for (final r in list) if (r is Map) ((r['xp'] as num?)?.toInt() ?? 0, '${r['title']}')];
  }

  /// Something from an earlier session is on the phone.
  bool get hasCache => profile != null || _p.containsKey(_kCases);

  @visibleForTesting
  set httpClient(http.Client c) => _http = c;

  // ---------------------------------------------------------------- friendly texts

  static const offlineText = 'به اینترنت وصل نیستی';
  static const serverDownText = 'الان به سرور دسترسی نداریم، چند دقیقه دیگه دوباره امتحان کن';
  static const genericText = 'یه مشکلی پیش اومد، دوباره امتحان کن';
  static String rateLimitedText(int seconds) => seconds > 0
      ? 'کمی صبر کن؛ ${_faDigits('$seconds')} ثانیه‌ی دیگه دوباره امتحان کن'
      : 'خیلی سریع پیش رفتی، کمی صبر کن و دوباره امتحان کن';

  static String _faDigits(String s) =>
      s.replaceAllMapped(RegExp(r'[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[m[0]!.codeUnitAt(0) - 48]);

  static const needOnlineText = 'برای این کار باید به اینترنت وصل باشی';
  static const offlineBannerText = 'آفلاینی؛ بعضی کارها به اینترنت نیاز داره';
  static const notSavedText = 'این پرونده هنوز روی گوشیت ذخیره نشده. برای باز کردنش یه بار به اینترنت وصل شو.';

  static FailKind failKind(Object e) {
    if (e is ApiException) return e.status >= 500 ? FailKind.server : FailKind.business;
    if (e is TimeoutException || e is FormatException) return FailKind.server;
    final t = e.toString();
    if (t.contains('HandshakeException') || t.contains('TlsException') || t.contains('CertificateException')) {
      return FailKind.server;
    }
    if (e is http.ClientException ||
        t.contains('SocketException') ||
        t.contains('Failed host lookup') ||
        t.contains('Connection refused') ||
        t.contains('Network is unreachable')) {
      return FailKind.offline;
    }
    return FailKind.other;
  }

  /// The server could not be reached (as opposed to "it answered no").
  static bool isNetworkFail(Object e) {
    final k = failKind(e);
    return k == FailKind.offline || k == FailKind.server;
  }

  /// A short Persian message for the player. Technical details only go to the debug log.
  static String friendly(Object e) {
    debugPrint('Api error: $e');
    if (e is ApiException && e.rateLimited) return e.registerLimitMessage ?? rateLimitedText(e.retryAfter);
    return switch (failKind(e)) {
      FailKind.offline => offlineText,
      FailKind.server => serverDownText,
      FailKind.business => errorText((e as ApiException).code),
      FailKind.other => genericText,
    };
  }

  // ---------------------------------------------------------------- start

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    try {
      _baseIx = (_p.getInt('api_base') ?? 0).clamp(0, kApiUrls.length - 1);
    } catch (_) {}
    _playerId = _p.getString('player');
    await ClaimNoteStore(_p).migrateLegacy(_playerId);
    _secret = _p.getString('secret');
    _token = _p.getString('token');
    _tokenExp = _p.getInt('token_exp') ?? 0;
    final cfg = _readCache(_kConfig);
    if (cfg is Map) config = Map<String, dynamic>.from(cfg);
    final me = _readCache(_kMe);
    if (me is Map) {
      _profileJson = Map<String, dynamic>.from(me);
      profile = Profile(_profileJson);
      unread.value = profile!.unread;
    }
  }

  /// Connects (register / login) and loads profile + config. Never throws:
  /// without internet the app goes on with what is saved on the phone.
  /// Set when the server refused to make a new account (too many accounts on this phone or network today):
  /// the offline banner shows this friendly sentence instead of the «no internet» text.
  String? registerBlocked;

  Future<void> connect() async {
    try {
      await _loadConfig();
      await _connectRest();
      lastError = '';
      registerBlocked = null;
    } catch (e) {
      lastError = friendly(e);
      registerBlocked = e is ApiException ? e.registerLimitMessage : null;
    }
    ready = true;
    notifyListeners();
  }

  /// Quietly tries the server again (used every ~20 s while offline, on app resume
  /// and by the retry buttons). Returns whether the server answered.
  Future<bool> reconnect() async {
    if (_reconnecting) return online;
    _reconnecting = true;
    try {
      if (!_configFromServer) await _loadConfig();
      await _connectRest();
      lastError = '';
      registerBlocked = null;
    } catch (e) {
      lastError = friendly(e);
      registerBlocked = e is ApiException ? e.registerLimitMessage : null;
    } finally {
      _reconnecting = false;
    }
    notifyListeners();
    return online;
  }

  /// What the weekend and story tabs show before they open (from /v1/config).
  Map<String, dynamic> _upcoming(String k) {
    final u = config['upcoming'];
    return u is Map && u[k] is Map ? (u[k] as Map).cast<String, dynamic>() : const {};
  }

  /// What the phone should announce in the next days (from /v1/config `notify`): each night's case,
  /// the weekend case and its chapters, the story opening. Bad entries are skipped.
  List<Map<String, dynamic>> get notifyPlan {
    final n = config['notify'];
    if (n is! List) return const [];
    return [
      for (final e in n)
        if (e is Map && e['at'] is num && e['head'] is String) Map<String, dynamic>.from(e)
    ];
  }

  Map<String, dynamic> get upcomingWeekend => _upcoming('weekend');
  Map<String, dynamic> get upcomingStory => _upcoming('story');

  /// Fetches the config again (e.g. when a countdown ends). Keeps the old one without internet.
  Future<void> refreshConfig() async {
    try {
      await _loadConfig();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadConfig() async {
    final j = await _call('GET', '/v1/config', auth: false);
    if (j is! Map) throw const FormatException('config is not an object');
    config = Map<String, dynamic>.from(j);
    _configFromServer = true;
    await _writeCache(_kConfig, config);
  }

  Future<void> _connectRest() async {
    await _ensureLogin();
    await refreshProfile();
    unawaited(refreshInbox());
    unawaited(_reportClient());
  }

  bool _clientReported = false;

  /// Tells the server which app version this is (once per app start; it shows in the admin panel). Failure is fine.
  Future<void> _reportClient() async {
    if (_clientReported) return;
    _clientReported = true;
    try {
      final info = await PackageInfo.fromPlatform();
      await _call('POST', '/v1/me/client', body: {
        'app_version': info.version,
        'build': int.tryParse(info.buildNumber) ?? kAppBuild,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('report client: $e');
    }
  }

  /// For the About card in Settings: does the server answer, and which version is it.
  Future<({bool ok, String version})> serverStatus() async {
    try {
      final r = await _sendAny('GET', '/health', const {}, null);
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (r.statusCode == 200 && j is Map) return (ok: true, version: '${j['version'] ?? ''}');
    } catch (_) {}
    return (ok: false, version: '');
  }


  void _wentOffline(Object e) {
    debugPrint('Api: server not reachable: $e');
    _retry ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (!online) unawaited(reconnect());
    });
    if (online) {
      online = false;
      notifyListeners();
    }
  }

  void _cameOnline() {
    _retry?.cancel();
    _retry = null;
    if (!online) {
      online = true;
      notifyListeners();
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

  Future<void>? _loginRun;

  /// One login at a time: a reconnect and a screen reload must not register two accounts.
  Future<void> _ensureLogin() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_token != null && _tokenExp - now > 3600) return;
    final run = _loginRun ??= _login().whenComplete(() => _loginRun = null);
    await run;
  }

  Future<void> _login() async {
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
      // Only the server's own "this secret is wrong" answer drops the saved account
      // (it moved to another phone). No internet / server trouble never does.
      if (e.status != 401 || e.code != 'wrong_login') rethrow;
      _playerId = _secret = null;
      return _login();
    }
  }

  String? get playerId => _playerId;

  bool get adsEnabled => config['ads_enabled'] == true;
  String get privacyUrl => config['privacy_url'] is String ? config['privacy_url'] as String : '$apiBase/privacy';
  String get termsUrl => config['terms_url'] is String ? config['terms_url'] as String : '$apiBase/terms';

  /// Contact links from the server config; null when the server does not send one (the row is hidden).
  String? get supportUrl => _nonEmpty(config['support_url']);
  String? get supportEmail => _nonEmpty(config['support_email']);
  static String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  /// Deletes this account on the server for good; the next connect starts a fresh guest account.
  /// Returns an error text, or null when done.
  Future<String?> deleteAccount() async {
    try {
      await _call('POST', '/v1/me/delete');
    } on ApiException catch (e) {
      return errorText(e.code);
    } catch (e) {
      return friendly(e);
    }
    await ClaimNoteStore(_p).removeAccount(_playerId);
    for (final k in const ['player', 'secret', 'token', 'token_exp']) {
      await _p.remove(k);
    }
    _playerId = _secret = _token = null;
    _tokenExp = 0;
    await _clearCache();
    profile = null;
    account++;
    notifyListeners();
    return null;
  }

  Future<void> _storeLogin(Map<String, dynamic> j) async {
    await ClaimNoteStore(_p).migrateLegacy(_playerId);
    final newId = j['player_id'] as String;
    final switched = _p.getString('player') != null && _p.getString('player') != newId;
    _clientReported = false; // the new account reports the app again
    _playerId = newId;
    _secret = j['secret'] as String;
    _token = j['token'] as String;
    _tokenExp = j['expires_at'] as int;
    await _p.setString('player', _playerId!);
    await _p.setString('secret', _secret!);
    await _p.setString('token', _token!);
    await _p.setInt('token_exp', _tokenExp);
    if (switched) {
      await _clearCache();
      account++;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- cache

  static const _kConfig = 'c_config';
  static const _kMe = 'c_me';
  static const _kCases = 'c_cases';
  static const _kRiddles = 'c_riddles';
  static const _kMissions = 'c_missions';
  static const _kAchievements = 'c_achievements';
  static const _kFeed = 'c_feed';
  static const _kCasePrefix = 'c_case_';
  static const _kNotesPrefix = 'notes_';
  static const _kStoryStatePrefix = 'c_story_state_';
  static const _kStoryBoard = 'c_story_board';

  Object? _readCache(String key) {
    final s = _p.getString(key);
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (e) {
      debugPrint('cache $key: $e');
      return null;
    }
  }

  Future<void> _writeCache(String key, Object? json) async {
    try {
      await _p.setString(key, jsonEncode(json));
    } catch (e) {
      debugPrint('cache $key: $e');
    }
  }

  /// Another account's data must not show up after a login on this phone.
  Future<void> _clearCache() async {
    for (final k in _p.getKeys().toList()) {
      if (k == _kMe || k == _kCases || k == _kRiddles || k == _kMissions || k == _kAchievements || k == _kFeed || k.startsWith(_kCasePrefix) || k.startsWith(_kNotesPrefix) || k.startsWith(_kStoryStatePrefix) || k == _kStoryBoard) {
        await _p.remove(k);
      }
    }
  }

  /// GET that saves the answer; without a server, the saved answer comes back instead.
  Future<Map<String, dynamic>> _cachedGet(String path, String key) async {
    try {
      final j = await _call('GET', path);
      if (j is! Map) throw const FormatException('answer is not an object');
      final m = Map<String, dynamic>.from(j);
      await _writeCache(key, m);
      return m;
    } catch (e) {
      // no internet, server trouble or «too many requests»: show what is saved on the phone
      if (!isNetworkFail(e) && !(e is ApiException && e.rateLimited)) rethrow;
      final saved = _readCache(key);
      if (saved is Map) return Map<String, dynamic>.from(saved);
      rethrow;
    }
  }

  /// Keeps the saved copy of a case in step with what the server just said
  /// (bought hints, wrong accusations), so it reads the same offline.
  Future<void> _saveProgress(String caseId, Object? progress) async {
    if (progress is! Map) return;
    final saved = _readCache('$_kCasePrefix$caseId');
    if (saved is! Map) return;
    await _writeCache('$_kCasePrefix$caseId', {...Map<String, dynamic>.from(saved), 'progress': progress});
  }

  /// The player's own marks on a case (suspicious / innocent, pinned evidence). Only on the phone.
  Map<String, dynamic> loadNotes(String caseId) {
    return ClaimNoteStore(_p).load(_playerId, caseId);
  }

  Future<void> saveNotes(String caseId, Map<String, dynamic> notes, {String? owner}) async {
    final target = owner ?? _playerId;
    if (target == null || target != _playerId) throw StateError('note_account_changed');
    await ClaimNoteStore(_p).save(target, caseId, notes);
  }

  /// One-time flags kept on the phone (e.g. the first-case tutorial was shown).
  bool flag(String key) {
    try {
      return _p.getBool('flag_$key') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setFlag(String key, [bool on = true]) async {
    try {
      await _p.setBool('flag_$key', on);
    } catch (_) {}
  }

  /// A number kept on the phone (e.g. when a gentle nudge was last dismissed). Only a convenience.
  int intPref(String key) {
    try {
      return _p.getInt('pref_$key') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> setIntPref(String key, int v) async {
    try {
      await _p.setInt('pref_$key', v);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- http

  Future<http.Response> _send(String method, Uri uri, Map<String, String> headers, String? data) {
    const t = Duration(seconds: 15);
    switch (method) {
      case 'GET':
        return _http.get(uri, headers: headers).timeout(t);
      case 'PATCH':
        return _http.patch(uri, headers: headers, body: data).timeout(t);
      default:
        return _http.post(uri, headers: headers, body: data).timeout(t);
    }
  }

  /// Tries the address that worked last, then the others (today there is only one). A request that timed out is not
  /// sent again (the server may have done it already); one that could not connect is.
  Future<http.Response> _sendAny(String method, String path, Map<String, String> headers, String? data) async {
    Object? first;
    StackTrace? stack;
    for (var n = 0; n < kApiUrls.length; n++) {
      final ix = (_baseIx + n) % kApiUrls.length;
      try {
        final r = await _send(method, Uri.parse('${kApiUrls[ix]}$path'), headers, data);
        if (ix != _baseIx) {
          _baseIx = ix;
          try {
            await _p.setInt('api_base', ix);
          } catch (_) {}
        }
        return r;
      } catch (e, st) {
        first ??= e;
        stack ??= st;
        if (e is TimeoutException) break;
      }
    }
    _wentOffline(first!);
    Error.throwWithStackTrace(first, stack!);
  }

  Future<Object?> _call(String method, String path,
      {Object? body, bool auth = true, bool retried = false, int attempt = 0}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      await _ensureLogin();
      headers['Authorization'] = 'Bearer $_token';
    }
    final data = body == null ? null : jsonEncode(body);
    final r = await _sendAny(method, path, headers, data);
    Object? decoded;
    try {
      final text = utf8.decode(r.bodyBytes);
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException catch (e) {
      if (r.statusCode < 400) {
        // a page that isn't ours (Wi-Fi login page, filter page): treat it as no server
        _wentOffline(e);
        rethrow;
      }
      decoded = null;
    }
    if (r.statusCode >= 500) {
      final err = ApiException(r.statusCode, decoded is Map ? decoded['detail'] : decoded);
      _wentOffline(err);
      throw err;
    }
    _cameOnline();
    if (r.statusCode == 429) {
      final fromHeader = int.tryParse(r.headers['retry-after'] ?? '') ?? 0;
      final err = ApiException(
          429, decoded is Map ? decoded : {'error': 'rate_limited', 'retry_after': fromHeader});
      final wait = err.retryAfter > 0 ? err.retryAfter : fromHeader;
      rateLimitedUntil.value = DateTime.now().add(Duration(seconds: wait < 1 ? 1 : wait));
      // Only a GET (safe to repeat), only a short wait, at most twice, with growing pauses: never a tight loop.
      if (method == 'GET' && attempt < 2 && wait <= 8) {
        await sleep(backoffDelay(attempt, wait));
        return _call(method, path, body: body, auth: auth, retried: retried, attempt: attempt + 1);
      }
      throw err;
    }
    if (r.statusCode == 401 && auth && !retried) {
      _token = null;
      _tokenExp = 0;
      return _call(method, path, body: body, auth: auth, retried: true);
    }
    if (r.statusCode >= 400) throw ApiException(r.statusCode, decoded is Map ? decoded['detail'] : decoded);
    return decoded;
  }

  // ---------------------------------------------------------------- profile

  /// [fromMe]: the answer of GET /v1/me, the only one that knows the bell number (other answers say 0).
  void _setProfile(Map<String, dynamic> j, {bool fromMe = false}) {
    if (fromMe) {
      final n = j['unread'];
      if (n is int && unread.value != n) unread.value = n;
    } else {
      j = Map<String, dynamic>.of(j)..['unread'] = unread.value;
    }
    _profileJson = j;
    profile = Profile(j);
    // the daily login reward is shown once; the saved copy must not show it again
    unawaited(_writeCache(_kMe, Map<String, dynamic>.of(j)..remove('login_reward')));
    notifyListeners();
  }

  void _setCoins(int coins) {
    if (profile == null) return;
    _setProfile(Map<String, dynamic>.of(_profileJson)
      ..['coins'] = coins
      ..remove('login_reward'));
  }

  Future<Profile?> refreshProfile() async {
    final j = await _call('GET', '/v1/me') as Map;
    _setProfile(Map<String, dynamic>.from(j), fromMe: true);
    _emitGains(j['gains']);
    return profile;
  }

  /// After something already went through on the server: a failed refresh is not an error.
  Future<void> _refreshProfileQuietly() async {
    try {
      await refreshProfile();
    } catch (e) {
      debugPrint('refresh profile: $e');
    }
  }

  Future<void> updateProfile({String? nickname, int? avatar, String? avatarId, String? avatarFrame}) async {
    final j = await _call('PATCH', '/v1/me', body: {
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
      if (avatarId != null) 'avatar_id': avatarId,
      if (avatarFrame != null) 'avatar_frame': avatarFrame,
    }) as Map;
    _setProfile(Map<String, dynamic>.from(j));
  }

  Future<int> adReward() async {
    final j = await _call('POST', '/v1/wallet/ad-reward') as Map;
    _setCoins(j['coins'] as int);
    return j['added'] as int;
  }

  // ---------------------------------------------------------------- cases

  /// The case list; offline, the last saved list.
  Future<CasesList> cases() async => CasesList(await _cachedGet('/v1/cases', _kCases));

  /// Returns (case, progress, isToday). Offline, a case opened before comes from the phone.
  Future<(CaseData, Progress, bool)> openCase(String id) async {
    final j = await _cachedGet('/v1/cases/$id', '$_kCasePrefix$id');
    return (CaseData((j['case'] as Map).cast<String, dynamic>()),
        Progress((j['progress'] as Map).cast<String, dynamic>()), j['today'] == true);
  }

  Future<void> unlockCase(String id, {int? expectedCost}) async {
    await _call('POST', '/v1/cases/$id/unlock', body: expectedCost == null ? null : {'expected_cost': expectedCost});
    await _refreshProfileQuietly();
  }

  // ---------------------------------------------------------------- story

  /// The career map (needs the server: it depends on the clock and the player's warrants).
  Future<StoryMap> story() async => StoryMap((await _call('GET', '/v1/story') as Map).cast<String, dynamic>());

  /// The scene the player is in (offline: the last saved one).
  Future<ChapterState> chapterState(String chapterId) async =>
      ChapterState(await _cachedGet('/v1/story/chapter/$chapterId/state', '$_kStoryStatePrefix$chapterId'));

  /// Picks an option. Needs the server (ApiException locked / wrong_scene ...). Saves the new state.
  Future<ChapterState> chooseOption(String chapterId, String scene, String option) async {
    final j = await _call('POST', '/v1/story/chapter/$chapterId/choose', body: {'scene': scene, 'option': option}) as Map;
    final m = Map<String, dynamic>.from(j);
    await _writeCache('$_kStoryStatePrefix$chapterId', m);
    return ChapterState(m);
  }

  /// The season case board (offline: the last saved one).
  Future<SeasonBoard> storyBoard() async => SeasonBoard(await _cachedGet('/v1/story/board', _kStoryBoard));

  /// Opens a chapter that is ready, or a waiting one with a warrant. Throws ApiException (wait / no_warrant ...).
  Future<StoryMap> openStoryChapter(int chapter, {bool warrant = false}) async {
    final j = await _call('POST', '/v1/story/$chapter/open', body: {'warrant': warrant}) as Map;
    await _refreshProfileQuietly();
    return StoryMap(j.cast<String, dynamic>());
  }

  /// Pays coins to skip the wait. Throws ApiException (not_enough_coins ...).
  Future<StoryMap> skipStoryWait(int chapter) async {
    final j = await _call('POST', '/v1/story/$chapter/skip') as Map;
    await _refreshProfileQuietly();
    return StoryMap(j.cast<String, dynamic>());
  }

  /// Returns (hint text, progress).
  Future<(String, Progress)> buyHint(String id) async {
    final j = (await _call('POST', '/v1/cases/$id/hint') as Map).cast<String, dynamic>();
    _setCoins(j['coins'] as int);
    _emitGains(j['gains']);
    await _saveProgress(id, j['progress']);
    return (j['hint'] as String, Progress((j['progress'] as Map).cast<String, dynamic>()));
  }

  Future<AccuseResult> accuse(String caseId, String suspectId, String evidenceId, {String? motive}) async {
    final j = (await _call('POST', '/v1/cases/$caseId/accuse', body: {
      'suspect': suspectId,
      if (evidenceId.isNotEmpty) 'evidence': evidenceId,
      if (motive != null) 'motive': motive,
      'extra_seconds': CaseClock.i.take(caseId),
    }) as Map)
        .cast<String, dynamic>();
    final r = AccuseResult(j);
    _emitGains(j['gains']);
    await _saveProgress(caseId, j['progress']);
    if (r.result == 'solved') {
      await _refreshProfileQuietly();
    } else {
      _setCoins(r.coins);
    }
    return r;
  }

  /// Weekend case: shows one evidence card to one suspect; returns what the suspect says.
  Future<({String text, Progress? progress})> showEvidence(String caseId, String suspectId, String evidenceId) async {
    final j = (await _call('POST', '/v1/cases/$caseId/show', body: {'suspect': suspectId, 'evidence': evidenceId}) as Map)
        .cast<String, dynamic>();
    await _saveProgress(caseId, j['progress']);
    return (
      text: (j['text'] as String?) ?? '',
      progress: j['progress'] is Map ? Progress((j['progress'] as Map).cast<String, dynamic>()) : null,
    );
  }

  /// Weekend format 3, night 1: answers «کی دروغ می‌گه؟» (one try). Returns the new progress (with the reveal) and the reward.
  Future<({bool ok, int reward, Progress? progress})> answerLiar(String caseId, String suspectId) async {
    final j = (await _call('POST', '/v1/cases/$caseId/liar', body: {'suspect': suspectId}) as Map).cast<String, dynamic>();
    await _saveProgress(caseId, j['progress']);
    final reward = (j['reward'] as num?)?.toInt() ?? 0;
    if (reward > 0) _setCoins((j['coins'] as num?)?.toInt() ?? coins);
    return (
      ok: j['ok'] == true,
      reward: reward,
      progress: j['progress'] is Map ? Progress((j['progress'] as Map).cast<String, dynamic>()) : null,
    );
  }

  /// Reports how long the case screen was open. Quiet: returns false when it didn't reach the server.
  Future<bool> tickCase(String caseId, int seconds) async {
    if (!online) return false;
    try {
      await _call('POST', '/v1/cases/$caseId/tick', body: {'seconds': seconds});
      return true;
    } on ApiException {
      return true; // the server answered (e.g. the case is finished): nothing to retry
    } catch (e) {
      return false;
    }
  }

  /// What everyone else guessed (only after the player finished the case).
  Future<Map<String, dynamic>> caseComments(String id, {int before = 0}) async =>
      ((await _call('GET', '/v1/cases/$id/comments${before > 0 ? '?before=$before' : ''}')) as Map).cast<String, dynamic>();

  Future<void> sendComment(String id, String body, {int rating = 0, int? parentId}) async {
    await _call('POST', '/v1/cases/$id/comments',
        body: {'body': body, 'rating': rating, if (parentId != null) 'parent_id': parentId});
  }

  Future<CaseStats> caseStats(String id) async =>
      CaseStats((await _call('GET', '/v1/cases/$id/stats') as Map).cast<String, dynamic>());

  /// Buys one streak insurance with coins. Throws ApiException (not_enough_coins / max_freezes).
  Future<void> buyStreakFreeze() async {
    final j = await _call('POST', '/v1/wallet/streak-freeze') as Map;
    _setProfile(Map<String, dynamic>.from(j));
  }

  Map<String, dynamic> get _economy =>
      config['economy'] is Map ? (config['economy'] as Map).cast<String, dynamic>() : const {};
  int get weeklyReward => _economy['weekly_reward'] as int? ?? 300;
  int get weeklyEarlyBonus => _economy['weekly_early_bonus'] as int? ?? 80;
  int get weekendLiarReward => _economy['weekend_liar_reward'] as int? ?? 10;
  int get weekendArchiveCost => _economy['weekend_archive_cost'] as int? ?? 250;
  int get freezeCost => _economy['freeze_cost'] as int? ?? 150;
  int get maxFreezes => _economy['max_freezes'] as int? ?? 2;
  int get secureReward => (_economy['secure_reward'] as num?)?.toInt() ?? 100;
  int get inviteReward => (_economy['invite_reward'] as num?)?.toInt() ?? 150;
  int get inviteNewPlayer => (_economy['invite_new_player'] as num?)?.toInt() ?? 100;
  List<int> get loginCalendar =>
      [for (final v in (_economy['login_calendar'] as List? ?? const [20, 30, 40, 50, 60, 80])) (v as num).toInt()];
  List<int> get streakBadges => [for (final v in (_economy['streak_badges'] as List? ?? const [7, 30, 100])) (v as num).toInt()];
  String get shareUrl => config['share_url'] is String
      ? config['share_url'] as String
      : (config['update_url'] is String ? config['update_url'] as String : 'https://cafebazaar.ir/app/ir.gammly.parvandeh');

  Future<Leaderboard> leaderboard(String period, {int? league}) async =>
      Leaderboard((await _call('GET', '/v1/leaderboard?period=$period${league != null ? '&league=$league' : ''}') as Map)
          .cast<String, dynamic>());

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
  Future<(String, int)> verifyPurchase(String productId, String token, {String store = 'bazaar'}) async {
    final j = (await _call('POST', '/v1/purchases/verify',
            body: {'product_id': productId, 'purchase_token': token, 'store': store}) as Map)
        .cast<String, dynamic>();
    await _refreshProfileQuietly();
    return ('${j['status']}', j['added'] as int? ?? 0);
  }

  // ---------------------------------------------------------------- account

  /// Phone-secured accounts (SMS code). Each returns an error text, or null when it worked.
  Future<String?> phoneSend(String phone) async {
    try {
      await _call('POST', '/v1/auth/phone/send', body: {'phone': phone});
      return null;
    } catch (e) {
      return friendly(e);
    }
  }

  /// Returns (reward coins, error text).
  Future<(int, String?)> phoneVerify(String phone, String code) async {
    try {
      final j = (await _call('POST', '/v1/auth/phone/verify', body: {'phone': phone, 'code': code}) as Map)
          .cast<String, dynamic>();
      _setProfile(Map<String, dynamic>.from(j['profile'] as Map));
      return (j['reward'] as int? ?? 0, null);
    } catch (e) {
      return (0, friendly(e));
    }
  }

  Future<String?> phoneLoginSend(String phone) async {
    try {
      await _call('POST', '/v1/auth/phone/login/send', auth: false, body: {'phone': phone, 'device_id': _deviceId()});
      return null;
    } catch (e) {
      return friendly(e);
    }
  }

  Future<String?> phoneLogin(String phone, String code) =>
      _loginWith('/v1/auth/phone/login', {'phone': phone, 'code': code});

  Future<String?> loginWithEmail(String email, String password) =>
      _loginWith('/v1/auth/login/email', {'email': email, 'password': password});

  Future<String?> useTransferCode(String code) => _loginWith('/v1/auth/transfer', {'code': code.trim()});

  Future<String?> _loginWith(String path, Map<String, dynamic> body) async {
    try {
      final j = await _call('POST', path, auth: false, body: {...body, 'device_id': _deviceId()}) as Map;
      await _storeLogin(j.cast<String, dynamic>());
    } catch (e) {
      return friendly(e);
    }
    await _refreshProfileQuietly();
    return null;
  }

  /// Returns (code, error text).
  Future<(String?, String?)> makeTransferCode() async {
    try {
      final j = await _call('POST', '/v1/auth/transfer-code') as Map;
      return ('${j['code']}', null);
    } catch (e) {
      return (null, friendly(e));
    }
  }

  /// Returns (coins received, error text).
  Future<(int, String?)> redeemInvite(String code) async {
    try {
      final j = await _call('POST', '/v1/referrals/redeem', body: {'code': code.trim()}) as Map;
      await _refreshProfileQuietly();
      final grants = (j['grants'] as List?) ?? const [];
      return (grants.isEmpty ? 0 : ((grants.first as Map)['amount'] as int? ?? 0), null);
    } catch (e) {
      return (0, friendly(e));
    }
  }

  /// The invite card: can a code still be entered, my progress, the friends' progress. Null when it cannot be read.
  Future<ReferralStatus?> referralStatus() async {
    try {
      return ReferralStatus((await _call('GET', '/v1/referrals/status') as Map).cast<String, dynamic>());
    } catch (e) {
      debugPrint('referral status: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- quick riddles

  /// Today's quick riddles; offline, the last saved set.
  Future<RiddleDay> riddles() async => RiddleDay(await _cachedGet('/v1/riddles', _kRiddles));

  Future<RiddleItem> unlockRiddle(String id) async {
    final j = (await _call('POST', '/v1/riddles/$id/unlock') as Map).cast<String, dynamic>();
    _setCoins(j['coins'] as int);
    _emitGains(j['gains']);
    return RiddleItem((j['item'] as Map).cast<String, dynamic>());
  }

  /// choice -1 = the timer ran out.
  Future<RiddleResult> answerRiddle(String id, int choice, int seconds) async {
    final j = (await _call('POST', '/v1/riddles/$id/answer', body: {'choice': choice, 'seconds': seconds}) as Map)
        .cast<String, dynamic>();
    final r = RiddleResult(j);
    _setCoins(r.coins);
    _emitGains(j['gains']);
    return r;
  }

  // ---------------------------------------------------------------- avatars and frames

  /// Every avatar and frame with what the player owns (goals reached are unlocked by this call).
  Future<AvatarCatalog> avatarCatalog() async {
    final j = (await _call('GET', '/v1/avatars') as Map).cast<String, dynamic>();
    _setCoins(j['coins'] as int);
    _emitGains(j['gains']);
    return AvatarCatalog(j);
  }

  /// Buys a shop avatar or frame (once, forever) and returns the new catalog.
  Future<AvatarCatalog> buyAvatarItem(String id) async {
    final j = (await _call('POST', '/v1/avatars/$id/buy') as Map).cast<String, dynamic>();
    _setCoins(j['coins'] as int);
    return AvatarCatalog(j);
  }

  // ---------------------------------------------------------------- achievements

  /// Every achievement with progress; offline, the last saved list.
  Future<AchievementsList> achievements() async => AchievementsList(await _cachedGet('/v1/achievements', _kAchievements));

  // ---------------------------------------------------------------- daily missions

  /// Today's missions; offline, the last saved ones.
  Future<MissionsDay> missions() async => MissionsDay(await _cachedGet('/v1/missions', _kMissions));

  /// Opens today's chest. Returns (missions, coins added).
  Future<(MissionsDay, int)> claimChest() async {
    final j = (await _call('POST', '/v1/missions/claim') as Map).cast<String, dynamic>();
    final m = (j['missions'] as Map).cast<String, dynamic>();
    await _writeCache(_kMissions, m);
    _setCoins(m['coins'] as int);
    _emitGains(j['gains']);
    return (MissionsDay(m), j['reward'] as int? ?? 0);
  }

  /// Tells the server a suspect's interrogation was opened (for the "interrogate everyone" mission).
  /// Quiet: offline or failing, nothing happens.
  Future<void> markSeen(String caseId, String suspectId) async {
    if (!online) return;
    try {
      final j = await _call('POST', '/v1/cases/$caseId/seen', body: {'suspect': suspectId});
      if (j is Map) _emitGains(j['gains']);
    } catch (e) {
      debugPrint('seen: $e');
    }
  }

  // ---------------------------------------------------------------- inbox

  Future<List<InboxGift>> inbox() async {
    final list = await _call('GET', '/v1/inbox') as List;
    final gifts = [for (final g in list) InboxGift((g as Map).cast<String, dynamic>())];
    inboxCount = gifts.length;
    for (final g in gifts) {
      if (g.title.startsWith('جایزه‌ی هفته')) {
        unawaited(Reminders.i.prizeNotice(g.id, g.title, g.message));
      }
    }
    notifyListeners();
    return gifts;
  }

  Future<void> refreshInbox() async {
    try {
      await inbox();
    } catch (e) {
      debugPrint('inbox: $e');
    }
  }

  Future<int> claim(InboxGift g) => claimGift(g.id, g.coins);

  /// Claims a gift by its inbox id («p12» / «b3»); the server pays once. Returns the coins it was worth.
  Future<int> claimGift(String id, int coins) async {
    final j = await _call('POST', '/v1/inbox/$id/claim') as Map;
    inboxCount = max(0, inboxCount - 1);
    _setCoins(j['coins'] as int);
    return coins;
  }

  // ---------------------------------------------------------------- messages hub

  /// The merged feed; offline, the last saved one.
  Future<Feed> feed() async {
    final f = Feed(await _cachedGet('/v1/feed', _kFeed));
    if (online) _setUnread(f.unread);
    return f;
  }

  /// Marks everything read (the server keeps one timestamp). Quiet: offline or failing, nothing happens.
  Future<void> feedSeen() async {
    if (!online) return;
    try {
      final j = await _call('POST', '/v1/feed/seen');
      if (j is Map) {
        final m = Map<String, dynamic>.from(j);
        await _writeCache(_kFeed, m);
      }
      _setUnread(0);
    } catch (e) {
      debugPrint('feed seen: $e');
    }
  }

  /// The bell number; also kept in the saved profile so a later coin update does not bring the old number back.
  void _setUnread(int n) {
    _profileJson = Map<String, dynamic>.of(_profileJson)..['unread'] = n;
    if (unread.value != n) unread.value = n;
  }

  // ---------------------------------------------------------------- errors

  static String errorText(String code) => switch (code) {
        'not_enough_coins' => 'سکه‌ات کافی نیست',
        'not_owned' => 'این چهره یا قاب هنوز مال تو نیست',
        'already_owned' => 'این رو قبلاً داری',
        'finish_case_first' => 'اول پرونده رو تموم کن، بعد نظر بده',
        'already_commented' => 'تو قبلاً برای این پرونده نظر دادی',
        'comment_too_short' => 'نظرت خیلی کوتاهه',
        'comment_too_long' => 'نظرت خیلی بلنده',
        'no_links' => 'توی نظر لینک یا آیدی نذار',
        'rating_needed' => 'اول امتیاز بده',
        'too_many_replies' => 'پاسخ‌های زیادی فرستادی؛ بعد از تأیید مدیر ادامه بده',
        'comments_off' => 'نظرها فعلاً بسته‌ست',
        'locked' => 'این پرونده قفله',
        'case_finished' => 'این پرونده تموم شده',
        'wait_last_chapter' => 'مدرک اصلی توی فصل آخره؛ بعد از باز شدنش می‌تونی متهم کنی',
        'no_shows_left' => 'مدرک نمایشی نمونده؛ با باز شدن فصل بعدی چند تای دیگه می‌رسه',
        'no_evidence' => 'این مدرک هنوز باز نشده',
        'how_needed' => 'بگو چرا و چطور',
        'wait' => 'این پرونده هنوز بازنشده؛ صبر کن، حکم بازرسی بده یا با سکه ردش کن',
        'no_warrant' => 'حکم بازرسی نداری',
        'wrong_order' => 'اول پرونده‌ی قبلی رو تموم کن',
        'chapter_locked' => 'این پرونده هنوز برات باز نشده',
        'story_not_open' => 'داستان هنوز شروع نشده',
        'wrong_scene' => 'این صحنه عوض شده؛ دوباره باز کن',
        'no_option' => 'این انتخاب وجود نداره',
        'too_many_choices' => 'تعداد انتخاب‌ها از حد گذشته',
        'no_chapter' => 'این پرونده هنوز نوشته نشده',
        'no_more_hints' => 'سرنخ دیگه‌ای نمونده',
        'bad_phone' => 'شماره‌ی موبایل درست نیست (مثل ۰۹۱۲۳۴۵۶۷۸۹)',
        'phone_taken' => 'این شماره قبلاً به یه حساب دیگه وصل شده؛ با «ورود با شماره» وارد شو',
        'phone_already_set' => 'حساب تو قبلاً با شماره امن شده',
        'code_expired' => 'کد منقضی شده؛ یه کد تازه بگیر',
        'sms_unavailable' => 'الان نمی‌تونیم پیامک بفرستیم؛ کمی بعد دوباره امتحان کن',
        'sms_failed' => 'پیامک نرسید؛ کمی بعد دوباره امتحان کن',
        'email_closed' => 'امن کردن با ایمیل بسته شده؛ از شماره‌ی موبایل استفاده کن',
        'bad_email' => 'ایمیل درست نیست',
        'bad_password' => 'رمز باید حداقل ۶ حرف باشه',
        'email_taken' => 'این ایمیل قبلاً برای یه حساب دیگه ثبت شده',
        'email_cant_change' => 'ایمیل این حساب رو نمی‌شه عوض کرد',
        'wrong_login' => 'ایمیل یا رمز اشتباهه',
        'bad_code' => 'کد اشتباهه یا تاریخش گذشته',
        'already_redeemed' => 'قبلاً کد دعوت وارد کردی',
        'only_for_new_players' => 'کد دعوت فقط برای بازیکن‌های تازه است',
        'same_device' => 'کد دعوت باید از گوشی یه کارآگاه دیگه باشه',
        'ad_limit' => 'امروز سهم تبلیغت تموم شد، فردا دوباره بیا',
        'bad_nickname' => 'این اسم قابل قبول نیست',
        'banned' => 'این حساب مسدود شده',
        'rate_limited' => 'خیلی سریع پیش رفتی، کمی صبر کن و دوباره امتحان کن',
        'too_many_requests' => 'خیلی سریع امتحان کردی، کمی صبر کن',
        'max_freezes' => 'بیشتر از این نمی‌شه بیمه نگه داشت',
        'finish_first' => 'اول پرونده رو تموم کن',
        'no_case' => 'هنوز پرونده‌ای باز نشده',
        'already_answered' => 'به این معما قبلاً جواب دادی',
        'missions_not_done' => 'اول هر سه مأموریت امروز رو انجام بده',
        'already_claimed' => 'صندوقچه‌ی امروز رو باز کردی',
        'no_suspect' => genericText,
        'not_today' => 'این معما مال امروز نیست؛ صفحه رو تازه کن',
        _ => genericText,
      };
}

