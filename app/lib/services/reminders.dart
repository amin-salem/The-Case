import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../theme.dart' show fa;

/// Local reminders, scheduled on the phone itself (no Firebase, which is unreliable in Iran):
/// - 21:00 every night: "tonight's case is open"
/// - 20:00, one hour before the next case, only if the open case is still unsolved and a streak is running: "your streak
///   is in danger" (Amin, 8 Nov 2026: 22:30 was 90 minutes after the case opened, far too early to mean anything).
///   At most one reminder a day besides the 21:00 one, so players do not switch notifications off.
/// Times come from the server's next_case_at, so the phone's time zone doesn't matter.
class Reminders extends ChangeNotifier with WidgetsBindingObserver {
  Reminders._();
  static final Reminders i = Reminders._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;
  bool _ready = false;
  static const _system = MethodChannel('ir.gammly.parvandeh/system');

  /// Whether Android lets the app show notifications at all (the system switch, separate from our own «یادآوری» switch).
  /// Stays true until a real check says otherwise, so nothing flashes on startup or on other platforms.
  bool systemOn = true;

  /// Set by the home screen: reload the cases and re-plan when the app returns to the foreground.
  Future<void> Function()? onResume;
  Map<String, dynamic>? _last;

  /// Reminders are wanted in the app but the phone blocks them: the home card and the settings line show.
  bool get blocked => _ready && enabled && !systemOn;

  static const _bannerDays = 7;
  bool get bannerVisible {
    if (!blocked) return false;
    final ms = _prefs?.getInt('notif_banner_closed') ?? 0;
    return DateTime.now().millisecondsSinceEpoch - ms > const Duration(days: _bannerDays).inMilliseconds;
  }

  Future<void> closeBanner() async {
    await _prefs?.setInt('notif_banner_closed', DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  bool get enabled => _prefs?.getBool('reminders_on') ?? true;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'nightly_case',
      'پرونده‌ی هر شب',
      channelDescription: 'یادآوری پرونده‌ی تازه‌ی ساعت ۹ شب و زنجیره‌ی روزهای پشت سر هم',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFC0392B),
    ),
  );

  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      tzdata.initializeTimeZones();
      try {
        // the white fingerprint-and-lens icon (copied into res/ by tools/patch_android.py)
        await _plugin.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_stat_case')),
        );
      } catch (_) {
        // a debug build made without patch_android.py has no ic_stat_case
        await _plugin.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        );
      }
      _ready = true;
      WidgetsBinding.instance.addObserver(this);
      await refreshSystem();
    } catch (e) {
      debugPrint('reminders init: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Reads the real system state (permission AND the app's notification switch in Android settings).
  Future<bool> refreshSystem() async {
    if (!_ready) return true;
    try {
      final on = await _android?.areNotificationsEnabled() ?? true;
      if (on != systemOn) {
        systemOn = on;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('reminders check: $e');
    }
    return systemOn;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_ready) return;
    () async {
      await refreshSystem();
      final reload = onResume;
      if (reload != null) {
        await reload();
      } else {
        await replanLast();
      }
    }();
  }

  /// Plans again with the last known facts (used when the app returns to the foreground without a fresh load).
  Future<void> replanLast() async {
    final l = _last;
    if (l == null) return;
    await plan(
        nextCaseAt: l['next'] as DateTime, tonightSolved: l['solved'] as bool, streak: l['streak'] as int,
        plan: (l['plan'] as List).cast<Map<String, dynamic>>(), tonightTitle: l['title'] as String?);
  }

  /// Asks for the Android 13+ notification permission, once (the first start of the home screen).
  Future<void> askOnce() async {
    if (!_ready) return;
    if (await refreshSystem()) return;
    if (_prefs?.getBool('reminders_asked') ?? false) return;
    await _prefs?.setBool('reminders_asked', true);
    try {
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('reminders permission: $e');
    }
    await refreshSystem();
  }

  /// Fixes switched-off notifications: asks again; when Android shows no dialog any more (denied twice, or switched off
  /// in the phone's settings) it opens the app's notification settings. Returns true when notifications are on.
  Future<bool> fix() async {
    if (!_ready) return true;
    if (await refreshSystem()) return true;
    final started = DateTime.now();
    try {
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('reminders permission: $e');
    }
    if (await refreshSystem()) {
      await replanLast();
      return true;
    }
    // a real dialog takes the player a moment to answer; an instant "no" means Android did not show it
    if (DateTime.now().difference(started) < const Duration(milliseconds: 900)) await openSystem('notifications');
    return false;
  }

  /// Opens a phone settings screen: "notifications", "battery" or "app". False when the phone has no such screen.
  Future<bool> openSystem(String what) async {
    try {
      return (await _system.invokeMethod<bool>('open', what)) ?? false;
    } catch (e) {
      debugPrint('reminders open settings: $e');
      return false;
    }
  }

  /// Shows one notification right now, so the player can see that his phone lets the app notify.
  Future<bool> test() async {
    if (!_ready) return false;
    try {
      await _plugin.show(
          id: 900, title: 'اعلان آزمایشی ✅', body: 'اعلان‌های پرونده روی گوشی تو کار می‌کنه.', notificationDetails: _details);
      return await refreshSystem();
    } catch (e) {
      debugPrint('reminders test: $e');
      return false;
    }
  }

  Future<void> setEnabled(bool on) async {
    await _prefs?.setBool('reminders_on', on);
    notifyListeners();
    if (!on && _ready) {
      try {
        await _plugin.cancelAll();
      } catch (_) {}
    } else if (on) {
      // the player asked for reminders: re-ask / open the phone's settings if they are blocked
      await fix();
      await replanLast();
    }
  }

  /// Plans the next week. Call it whenever the case list or the streak changes.
  /// [plan] is the server's list of what to announce (content-based texts); without it the texts are generic.
  Future<void> plan({
    required DateTime nextCaseAt,
    required bool tonightSolved,
    required int streak,
    List<Map<String, dynamic>> plan = const [],
    String? tonightTitle,
  }) async {
    if (!_ready) return;
    _last = {'next': nextCaseAt, 'solved': tonightSolved, 'streak': streak, 'plan': plan, 'title': tonightTitle};
    try {
      await _plugin.cancelAll();
      if (!enabled) return;
      DateTime when(Map<String, dynamic> e) => DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt() * 1000);
      Map<String, dynamic>? nightlyAt(DateTime t) {
        for (final e in plan) {
          if (e['kind'] == 'nightly' && when(e).difference(t).abs() < const Duration(hours: 1)) return e;
        }
        return null;
      }

      for (int d = 0; d < 7; d++) {
        final t = nextCaseAt.add(Duration(days: d));
        final e = nightlyAt(t);
        await _at(100 + d, t, (e?['head'] as String?) ?? 'پرونده‌ی امشب باز شد 🕵️',
            (e?['body'] as String?) ?? 'یه جنایت تازه منتظرته. ببین می‌تونی زودتر از بقیه حلش کنی؟');
      }
      // weekend case, its chapters and the story opening
      var extra = 0;
      for (final e in plan) {
        if (e['kind'] == 'nightly' || extra >= 8) continue;
        // a weekend case now opens on Wednesday 21:00 with the nightly case: keep the two notifications apart
        final w = e['kind'] == 'weekend' && nightlyAt(when(e)) != null ? when(e).add(const Duration(minutes: 2)) : when(e);
        await _at(500 + extra, w, e['head'] as String, (e['body'] as String?) ?? '');
        extra++;
      }
      // the week's result (prizes in the inbox) comes from the server's plan as kind "weekresult" (Friday 21:10 Tehran):
      // no day or week math on the phone
      await _huntAgain();
      final sr = (_prefs?.getString('story_ready') ?? '').split('|');
      if (sr.length >= 2) {
        final ms = int.tryParse(sr[0]);
        if (ms != null) await _at(600, DateTime.fromMillisecondsSinceEpoch(ms), 'فصل بعدی داستان آماده‌ست 🔥', 'ناصری منتظره: «${sr.sublist(1).join('|')}» رو باز کن.');
      }
      // The open case ("tonight's") stays solvable until the next one opens at nextCaseAt, and the streak only breaks
      // then. So the warning goes one hour before that moment, not right after the case opened. Only when it is still
      // unsolved and a streak runs. Later nights get no streak warning: a missed night already broke (or insured) it.
      if (streak > 0 && !tonightSolved) {
        await _at(200, nextCaseAt.subtract(const Duration(hours: 1)), 'زنجیره‌ات در خطره! 🔥',
            tonightTitle == null || tonightTitle.isEmpty
                ? 'زنجیره‌ی ${fa(streak)} شبه‌ات تا ساعت ۹ شب وقت داره. نذار بشکنه!'
                : 'زنجیره‌ی ${fa(streak)} شبه‌ات تا ساعت ۹ شب وقت داره؛ «$tonightTitle» رو حل کن و نذار بشکنه!');
      }
    } catch (e) {
      debugPrint('reminders plan: $e');
    }
  }

  /// A story chapter becomes ready (the 12-hour wait ends): call this when the chapter list says when.
  Future<void> storyReady(DateTime at, String chapterTitle) async {
    if (!_ready || !enabled) return;
    try {
      // kept on the phone too, because plan() clears everything and then puts it back
      await _prefs?.setString('story_ready', '${at.millisecondsSinceEpoch}|$chapterTitle');
      await _at(600, at, 'فصل بعدی داستان آماده‌ست 🔥', 'ناصری منتظره: «$chapterTitle» رو باز کن.');
    } catch (e) {
      debugPrint('reminders story: $e');
    }
  }

  /// «شکار سه‌روزه»: the coming drops, messages and departures (texts from the server, generic on purpose).
  /// Kept on the phone too, because plan() clears everything and then puts it back.
  Future<void> huntPlan(List<Map<String, dynamic>> events) async {
    if (!_ready) return;
    try {
      await _prefs?.setString('hunt_plan', jsonEncode(events.take(24).toList()));
      if (_last != null) {
        await replanLast(); // clears everything and puts it back, the hunt included
      } else if (enabled) {
        await _huntAgain();
      }
    } catch (e) {
      debugPrint('reminders hunt: $e');
    }
  }

  Future<void> _huntAgain() async {
    final raw = _prefs?.getString('hunt_plan');
    if (raw == null || raw.isEmpty) return;
    final list = jsonDecode(raw);
    if (list is! List) return;
    var n = 0;
    for (final e in list) {
      if (e is! Map || e['at'] is! num || n >= 24) continue;
      await _at(700 + n, DateTime.fromMillisecondsSinceEpoch((e['at'] as num).toInt() * 1000), '${e['head'] ?? ''}', '${e['body'] ?? ''}');
      n++;
    }
  }

  /// A weekly prize reached the inbox: tell the player right away (once per prize).
  Future<void> prizeNotice(String id, String title, String body) async {
    if (!_ready || !enabled) return;
    try {
      final seen = _prefs?.getStringList('prize_seen') ?? <String>[];
      if (seen.contains(id)) return;
      await _prefs?.setStringList('prize_seen', [...seen.take(30), id]);
      await _plugin.show(id: 300, title: title, body: body, notificationDetails: _details);
    } catch (e) {
      debugPrint('reminders prize: $e');
    }
  }

  Future<void> _at(int id, DateTime when, String title, String body) async {
    if (!when.isAfter(DateTime.now().add(const Duration(minutes: 1)))) return;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
  }
}
