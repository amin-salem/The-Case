import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/profile_bell.dart';
import '../widgets/coming_soon.dart';
import '../widgets/scene.dart';
import 'case_screen.dart';

DateTime? _time(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

/// The next weekend opening (the weekday and hour of the server's schedule; Wednesday 21:00 Tehran by default,
/// Tehran is a fixed UTC+3:30). Only a fallback when the server doesn't say when the next one opens.
DateTime nextWeekendOpening([DateTime? now, int weekday = DateTime.wednesday, int hour = 21]) {
  const offset = Duration(hours: 3, minutes: 30);
  final local = (now ?? DateTime.now()).toUtc().add(offset); // Tehran wall clock, kept in a UTC DateTime
  var day = DateTime.utc(local.year, local.month, local.day, hour);
  day = day.add(Duration(days: (weekday - day.weekday) % 7));
  if (!day.isAfter(local)) day = day.add(const Duration(days: 7));
  return day.subtract(offset).toLocal();
}

DateTime nextWednesdayNine([DateTime? now]) => nextWeekendOpening(now);

/// The weekend tab: this weekend's big case, or a countdown to the next one.
class WeekendScreen extends StatefulWidget {
  const WeekendScreen({super.key});

  @override
  State<WeekendScreen> createState() => _WeekendScreenState();
}

class _WeekendScreenState extends State<WeekendScreen> {
  CasesList? _cases;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await Api.i.cases();
      if (mounted) setState(() => _cases = c);
    } catch (_) {}
  }

  Future<void> _opened() async {
    await Api.i.refreshConfig();
    await _load();
  }

  void _play(CaseRow c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaseScreen(caseId: c.id)));
    _load();
  }

  /// The schedule the server sends with the weekend info (`schedule`), or the built-in default.
  Map<String, dynamic> _schedule(Map<String, dynamic> up) {
    final s = up['schedule'];
    return s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{};
  }

  /// «هر هفته چهارشنبه شب ساعت ۲۱ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری.» comes from the server (content.weekend_schedule),
  /// so the app can never disagree with the clock; this literal is only for an old cached config.
  String _scheduleText(Map<String, dynamic> up) {
    final t = _schedule(up)['text'];
    return t is String && t.isNotEmpty ? t : 'هر هفته چهارشنبه شب ساعت ۲۱ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری.';
  }

  DateTime _fallbackOpening(Map<String, dynamic> up) {
    final s = _schedule(up);
    final wd = s['open_weekday'], h = s['open_hour'];
    // the server counts Monday = 0, Dart counts Monday = 1
    return nextWeekendOpening(null, wd is num ? wd.toInt() + 1 : DateTime.wednesday, h is num ? h.toInt() : 21);
  }

  @override
  Widget build(BuildContext context) {
    final weekly = _cases?.weekly;
    final up = Api.i.upcomingWeekend;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _opened,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const ProfileBell(size: 40),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('آخر هفته', style: tDisplay(26)),
                  Text('یه پرونده‌ی بزرگ و خیلی سخت، هر هفته', style: tBody(13, color: K.textSoft)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            if (weekly != null)
              SectionBanner(
                background: AnimatedScene(scene: weekly.scene, height: double.infinity, dim: 0.2),
                chip: weekly.solved ? 'حلش کردی!' : 'پرونده‌ی این هفته · بازه',
                title: weekly.title,
                subtitle: 'دو فصل، هشت مظنون · جایزه‌ی ${fa(Api.i.weeklyReward)} سکه',
                countdownLabel: 'تا پایان پرونده',
                at: _cases?.weeklyClosesAt,
                onCountdownDone: _opened,
                onTap: () => _play(weekly),
                button: StampButton(
                    label: weekly.solved ? 'دیدن پرونده' : 'ورود به پرونده',
                    icon: Icons.search_rounded,
                    onTap: () => _play(weekly)),
              )
            else
              SectionBanner(
                background: up['scene'] is String
                    ? AnimatedScene(scene: up['scene'] as String, height: double.infinity, dim: 0.2)
                    : Image.asset('assets/banners/weekend.webp', fit: BoxFit.cover),
                chip: 'به‌زودی · خیلی سخت',
                title: (up['title'] as String?) ?? 'پرونده‌ی بعدی در راهه',
                subtitle: up['location'] as String?,
                countdownLabel: 'تا باز شدن پرونده',
                at: _time(up['opens_at']) ?? _fallbackOpening(up),
                onCountdownDone: _opened,
              ),
            const SizedBox(height: 14),
            InfoCard(title: 'چطوری کار می‌کنه؟', lines: [
              (Icons.event_rounded, '${_scheduleText(up)} پرونده‌ی شبانه سر جاشه.'),
              (Icons.auto_stories_rounded, 'دو فصل داره؛ فصل دوم، ۲۴ ساعت بعد، مدارک و حرف‌های تازه می‌آره.'),
              (Icons.fact_check_rounded, 'هر مدرک رو می‌تونی به یه مظنون نشون بدی و ببینی چی می‌گه. تعدادش محدوده.'),
              (Icons.gavel_rounded, 'از همون فصل اول می‌تونی متهم کنی: هم مقصر، هم «چرا و چطور». زودتر درست بگی، ${fa(Api.i.weeklyEarlyBonus)} سکه‌ی اضافه می‌گیری.'),
              (Icons.emoji_events_rounded, 'جایزه: تا ${fa(Api.i.weeklyReward)} سکه و کلی امتیاز رتبه. زنجیره‌ی شبانه‌ت هم دست نمی‌خوره.'),
            ]),
          ]),
        ),
      ),
    );
  }
}
