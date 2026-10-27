import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// «نسخه‌ی تازه توی کافه بازار»: reads `latest_version` / `min_version` / `update_url` from the server config
/// (the admin panel sets them; defaults 1 / 1 mean nothing shows). It FAILS OPEN: no config, an offline start, a
/// missing or unreadable number all mean "no banner, no block". Never hurts a player.
class AppUpdate extends ChangeNotifier {
  AppUpdate._();
  static final AppUpdate i = AppUpdate._();

  /// The running build; tests replace it.
  static int build = kAppBuild;
  static DateTime Function() now = DateTime.now;

  /// After ✕ the banner stays hidden this long (per `latest_version`: a newer release shows it again).
  static const closedDays = 3;
  static const _kClosedAt = 'update_closed_at';
  static const _kClosedFor = 'update_closed_for';

  SharedPreferences? _prefs;

  /// Ints may come as strings; anything unreadable is 0 (= "not set").
  static int readInt(Object? v) {
    if (v is num && v.isFinite) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? 0;
    return 0;
  }

  int get latestVersion => readInt(Api.i.config['latest_version']);
  int get minVersion => readInt(Api.i.config['min_version']);

  /// Where the button goes: the server's `update_url` when it is a web link, else the Bazaar page.
  String get url {
    final u = Api.i.config['update_url'];
    if (u is String) {
      final p = Uri.tryParse(u.trim());
      if (p != null && (p.scheme == 'https' || p.scheme == 'http') && p.host.isNotEmpty) return u.trim();
    }
    return kShareLinkPlaceholder;
  }

  /// This build is older than the server's `min_version`: the full-screen page.
  bool get mustUpdate => minVersion > 0 && build < minVersion;

  /// This build is older than `latest_version` (and not blocked): the dismissible card.
  bool get bannerVisible {
    final latest = latestVersion;
    if (latest <= 0 || build >= latest || mustUpdate) return false;
    final p = _prefs;
    if (p == null) return true;
    final closedFor = p.getInt(_kClosedFor) ?? 0;
    final closedAt = p.getInt(_kClosedAt) ?? 0;
    if (closedFor != latest) return true;
    return now().millisecondsSinceEpoch - closedAt > const Duration(days: closedDays).inMilliseconds;
  }

  @visibleForTesting
  void resetForTest() => _prefs = null;

  Future<void> load() async {
    if (_prefs != null) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> closeBanner() async {
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      await p.setInt(_kClosedFor, latestVersion);
      await p.setInt(_kClosedAt, now().millisecondsSinceEpoch);
    } catch (_) {}
    notifyListeners();
  }

  /// Opens the store page. Returns false when the phone could not open it.
  Future<bool> open() async {
    try {
      return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
