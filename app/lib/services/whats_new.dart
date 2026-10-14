import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/whats_new.dart';

/// State behind «چی تازه شده؟»: which release the player has seen, and the red «تازه» tags.
/// Everything is in shared prefs; [now] can be replaced in tests.
class WhatsNew extends ChangeNotifier {
  WhatsNew._();
  static final WhatsNew i = WhatsNew._();

  static DateTime Function() now = DateTime.now;
  static const tagDays = 7;

  List<WhatsNewRelease> releases = kWhatsNew;
  SharedPreferences? _p;
  int _seen = 0;
  bool _snoozed = false; // «بعداً یادم بنداز»: hidden until the next app start
  final Map<String, DateTime> _tagFirst = {};
  final Set<String> _tagOpened = {};

  /// Call once at start, BEFORE Api.init (a phone with no saved player is a fresh install: nothing is "new" to it).
  Future<void> init({List<WhatsNewRelease>? list}) async {
    if (list != null) releases = list;
    _p = await SharedPreferences.getInstance();
    _snoozed = false;
    _tagFirst.clear();
    _tagOpened.clear();
    final latest = latestId;
    final fresh = !_p!.containsKey('player');
    if (!_p!.containsKey('wn_seen')) {
      _seen = fresh ? latest : 0;
      await _p!.setInt('wn_seen', _seen);
    } else {
      _seen = _p!.getInt('wn_seen') ?? 0;
    }
    for (final r in releases) {
      for (final it in r.items) {
        for (final t in it.tags) {
          if (_p!.getBool('wn_open_$t') ?? false) _tagOpened.add(t);
          final s = _p!.getString('wn_first_$t');
          if (s != null) {
            final d = DateTime.tryParse(s);
            if (d != null) _tagFirst[t] = d;
          } else if (!fresh && r.id > _seen) {
            _tagFirst[t] = now();
            await _p!.setString('wn_first_$t', now().toIso8601String());
          }
        }
      }
    }
    notifyListeners();
  }

  int get latestId => releases.isEmpty ? 0 : releases.first.id;

  /// The banner shows while the newest release has not been seen.
  bool get pending => !_snoozed && releases.isNotEmpty && _seen < latestId;

  WhatsNewRelease? get latest => releases.isEmpty ? null : releases.first;

  /// The latest releases for Settings, newest first.
  List<WhatsNewRelease> recent([int n = 5]) => releases.take(n).toList();

  /// Closing the banner or opening the list.
  Future<void> markSeen() async {
    _seen = latestId;
    await _p?.setInt('wn_seen', _seen);
    notifyListeners();
  }

  /// «بعداً یادم بنداز»: seen for now, but the banner returns at the next start.
  Future<void> remindLater(int before) async {
    _seen = before;
    _snoozed = true;
    await _p?.setInt('wn_seen', _seen);
    notifyListeners();
  }

  /// A red «تازه» tag is visible until its place is opened or [tagDays] days after it was first seen.
  bool tagVisible(String id) {
    if (_tagOpened.contains(id)) return false;
    final first = _tagFirst[id];
    if (first == null) return false;
    return now().difference(first) < const Duration(days: tagDays);
  }

  Future<void> tagOpened(String id) async {
    if (_tagOpened.contains(id) || !_tagFirst.containsKey(id)) return;
    _tagOpened.add(id);
    await _p?.setBool('wn_open_$id', true);
    notifyListeners();
  }

  /// A jump that needs the home screen (case, comments, missions): the home screen listens and clears it.
  final ValueNotifier<WhatsNewTarget?> homeAction = ValueNotifier(null);
}
