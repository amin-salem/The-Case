import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'billing.dart' show kStore;

/// «از بازی راضی بودی؟ به ما امتیاز بده»: one polite card on the HOME screen after a 3-star solve (Amin, 28 Oct 2026;
/// ratings lift the app in Bazaar search and installs). Fair-play rules, all kept here:
/// - never during a case, never blocks anything, offers no reward;
/// - only after the player solved at least [minSolved] cases and just earned 3 stars;
/// - at most once every [gapDays] days (✕ / «بعداً» counts as shown), never again once the button was tapped;
/// - only for the Cafe Bazaar build. Storage failing means nothing shows (fails closed for a nag, open for the game).
class StoreRating extends ChangeNotifier {
  StoreRating._();
  static final StoreRating i = StoreRating._();

  static const minSolved = 3;
  static const gapDays = 30;
  static const _kReady = 'rating_ready';
  static const _kShownAt = 'rating_shown_at';
  static const _kTapped = 'rating_tapped';

  /// Tests replace these.
  static DateTime Function() now = DateTime.now;
  static Future<bool> Function(Uri) launcher = (u) => launchUrl(u, mode: LaunchMode.externalApplication);
  static String store = kStore;

  static const bazaarPage = 'bazaar://details?id=ir.gammly.parvandeh';
  static const webPage = 'https://cafebazaar.ir/app/ir.gammly.parvandeh';

  SharedPreferences? _p;
  bool _ready = false;
  bool _tapped = false;
  int _shownAt = 0;

  Future<void> load() async {
    if (_p != null) return;
    try {
      final p = await SharedPreferences.getInstance();
      _ready = p.getBool(_kReady) ?? false;
      _tapped = p.getBool(_kTapped) ?? false;
      _shownAt = p.getInt(_kShownAt) ?? 0;
      _p = p;
      notifyListeners();
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTest() {
    _p = null;
    _ready = false;
    _tapped = false;
    _shownAt = 0;
  }

  /// Called after a solve. Only a 3-star solve by a player with enough solved cases arms the card.
  Future<void> noteSolve({required int stars, required int solved}) async {
    if (stars < 3 || solved < minSolved || store != 'bazaar') return;
    await load();
    if (_p == null || _tapped) return;
    _ready = true;
    try {
      await _p!.setBool(_kReady, true);
    } catch (_) {}
    notifyListeners();
  }

  /// The home screen asks this; false whenever anything is unknown.
  bool get visible {
    if (_p == null || !_ready || _tapped || store != 'bazaar') return false;
    final solved = Api.i.profile?.casesSolved ?? 0;
    if (solved < minSolved) return false;
    return now().millisecondsSinceEpoch - _shownAt > const Duration(days: gapDays).inMilliseconds;
  }

  /// ✕ or «بعداً»: hide it for [gapDays] days.
  Future<void> later() async {
    _ready = false;
    _shownAt = now().millisecondsSinceEpoch;
    try {
      await _p?.setBool(_kReady, false);
      await _p?.setInt(_kShownAt, _shownAt);
    } catch (_) {}
    notifyListeners();
  }

  /// The button: opens Bazaar's page of the app (the review box is there), then the web page; never shown again.
  Future<bool> rate() async {
    _tapped = true;
    _ready = false;
    try {
      await _p?.setBool(_kTapped, true);
      await _p?.setBool(_kReady, false);
    } catch (_) {}
    notifyListeners();
    for (final u in [Uri.parse(bazaarPage), Uri.parse(webPage)]) {
      try {
        if (await launcher(u)) return true;
      } catch (_) {}
    }
    return false;
  }
}
