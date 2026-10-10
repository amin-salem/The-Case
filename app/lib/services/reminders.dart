import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../theme.dart' show fa;

/// Local reminders, scheduled on the phone itself (no Firebase, which is unreliable in Iran):
/// - 21:00 every night: "tonight's case is open"
/// - 22:30 on nights the player hasn't solved yet: "your streak is in danger"
/// Times come from the server's next_case_at, so the phone's time zone doesn't matter.
class Reminders extends ChangeNotifier {
  Reminders._();
  static final Reminders i = Reminders._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  SharedPreferences? _prefs;
  bool _ready = false;

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
    } catch (e) {
      debugPrint('reminders init: $e');
    }
  }

  /// Asks for the Android 13+ notification permission, once.
  Future<void> askOnce() async {
    if (!_ready || (_prefs?.getBool('reminders_asked') ?? false)) return;
    await _prefs?.setBool('reminders_asked', true);
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('reminders permission: $e');
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
      await askOnce();
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
        await _at(500 + extra, when(e), e['head'] as String, (e['body'] as String?) ?? '');
        extra++;
      }
      // Saturday 10:00 (Tehran = UTC+3:30): last week's ranking prizes are in the inbox
      var sat = DateTime.now().toUtc();
      sat = DateTime.utc(sat.year, sat.month, sat.day, 6, 30);
      while (sat.weekday != DateTime.saturday || !sat.isAfter(DateTime.now().toUtc())) {
        sat = sat.add(const Duration(days: 1));
      }
      for (int w = 0; w < 4; w++) {
        await _at(400 + w, sat.add(Duration(days: 7 * w)), 'نتیجه‌ی هفته اعلام شد 🏆',
            'جدول برترهای هفته بسته شد. شاید جایزه گرفته باشی؛ صندوق هدیه‌ها رو ببین!');
      }
      final sr = (_prefs?.getString('story_ready') ?? '').split('|');
      if (sr.length >= 2) {
        final ms = int.tryParse(sr[0]);
        if (ms != null) await _at(600, DateTime.fromMillisecondsSinceEpoch(ms), 'فصل بعدی داستان آماده‌ست 🔥', 'ناصری منتظره: «${sr.sublist(1).join('|')}» رو باز کن.');
      }
      // tonight's case opened one day before the next one; remind 90 minutes after it opens
      final tonight = nextCaseAt.subtract(const Duration(days: 1));
      if (streak > 0 && !tonightSolved) {
        await _at(200, tonight.add(const Duration(minutes: 90)), 'زنجیره‌ات در خطره! 🔥',
            tonightTitle == null || tonightTitle.isEmpty
                ? 'زنجیره‌ی ${fa(streak)} شبه‌ات منتظر پرونده‌ی امشبه. نذار بشکنه!'
                : 'زنجیره‌ی ${fa(streak)} شبه‌ات منتظر «$tonightTitle» ـه. نذار بشکنه!');
      }
      // later nights: if the app isn't opened (= the case isn't solved), these still go off
      for (int d = 1; d < 4 && streak > 0; d++) {
        final t = tonight.add(Duration(days: d));
        final e = nightlyAt(t);
        final late = e?['late'] as String?;
        await _at(200 + d, t.add(const Duration(minutes: 90)), 'پرونده‌ی امشب رو حل نکردی 🔥',
            late ?? 'زنجیره‌ات رو از دست نده؛ هنوز وقت داری.');
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
