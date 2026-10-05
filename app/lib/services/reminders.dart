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
  Future<void> plan({required DateTime nextCaseAt, required bool tonightSolved, required int streak}) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      if (!enabled) return;
      for (int d = 0; d < 7; d++) {
        await _at(100 + d, nextCaseAt.add(Duration(days: d)), 'پرونده‌ی امشب باز شد 🕵️',
            'یه جنایت تازه منتظرته. ببین می‌تونی زودتر از بقیه حلش کنی؟');
      }
      // tonight's case opened one day before the next one; remind 90 minutes after it opens
      final tonight = nextCaseAt.subtract(const Duration(days: 1));
      if (streak > 0 && !tonightSolved) {
        await _at(200, tonight.add(const Duration(minutes: 90)), 'زنجیره‌ات در خطره! 🔥',
            'زنجیره‌ی ${fa(streak)} شبه‌ات منتظر پرونده‌ی امشبه. نذار بشکنه!');
      }
      // later nights: if the app isn't opened (= the case isn't solved), these still go off
      for (int d = 1; d < 4 && streak > 0; d++) {
        await _at(200 + d, tonight.add(Duration(days: d, minutes: 90)), 'پرونده‌ی امشب رو حل نکردی 🔥',
            'زنجیره‌ات رو از دست نده؛ هنوز وقت داری.');
      }
    } catch (e) {
      debugPrint('reminders plan: $e');
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
