import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/category.dart';
import '../widgets/profile_bell.dart';
import '../widgets/coming_soon.dart';
import '../widgets/scene.dart';
import 'case_screen.dart';

DateTime? _time(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

/// The next weekend opening (the weekday and hour of the server's schedule; Thursday 09:00 Tehran by default,
/// Tehran is a fixed UTC+3:30). Only a fallback when the server doesn't say when the next one opens.
DateTime nextWeekendOpening([DateTime? now, int weekday = DateTime.thursday, int hour = 9]) {
  const offset = Duration(hours: 3, minutes: 30);
  final local = (now ?? DateTime.now()).toUtc().add(offset); // Tehran wall clock, kept in a UTC DateTime
  var day = DateTime.utc(local.year, local.month, local.day, hour);
  day = day.add(Duration(days: (weekday - day.weekday) % 7));
  if (!day.isAfter(local)) day = day.add(const Duration(days: 7));
  return day.subtract(offset).toLocal();
}

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

  /// «هر هفته پنجشنبه صبح ساعت ۹ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری.» comes from the server (content.weekend_schedule),
  /// so the app can never disagree with the clock; this literal is only for an old cached config.
  String _scheduleText(Map<String, dynamic> up) {
    final t = _schedule(up)['text'];
    return t is String && t.isNotEmpty ? t : 'هر هفته پنجشنبه صبح ساعت ۹ باز می‌شه و تا جمعه ساعت ۲۱ وقت داری.';
  }

  DateTime _fallbackOpening(Map<String, dynamic> up) {
    final s = _schedule(up);
    final wd = s['open_weekday'], h = s['open_hour'];
    // the server counts Monday = 0, Dart counts Monday = 1
    return nextWeekendOpening(null, wd is num ? wd.toInt() + 1 : DateTime.thursday, h is num ? h.toInt() : 9);
  }

  /// Format 3: «شب اول / شب دوم» side by side, the early-solve reward and the countdown to chapter 2.
  Widget _nightsCard() {
    final api = Api.i;
    final at = _cases?.weeklyNextChapterAt;
    final night2Open = at == null;
    Widget col(String title, IconData icon, List<String> lines, {bool active = false, Widget? extra}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: K.night2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? K.brass : K.night3, width: active ? 1.5 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, color: active ? K.brass : K.textSoft, size: 18),
                const SizedBox(width: 6),
                Text(title, style: tDisplay(16, color: active ? K.brass : K.text)),
              ]),
              const SizedBox(height: 8),
              for (final l in lines)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $l', style: tBody(12.5, color: K.textSoft))),
              if (extra != null) extra,
            ]),
          ),
        );
    return Column(key: const ValueKey('nights-card'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: K.brass.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: K.brass.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          const Icon(Icons.bolt_rounded, color: K.brass),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                night2Open
                    ? 'شب دوم باز شده؛ جایزه‌ی زودتر حل‌کردن تموم شد، ولی جایزه‌ی اصلی سر جاشه.'
                    : 'کامل حل کنی قبل از شب دوم: ${fa(api.weeklyEarlyBonus)} سکه‌ی اضافه + پلاک «شب اول».',
                style: tBody(13.5, w: FontWeight.w900)),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        col('شب اول', Icons.nightlight_round, [
          'مظنون‌ها و مدارک شب اول',
          '«کی دروغ می‌گه؟»: یک بار جواب بده، ${fa(api.weekendLiarReward)} سکه',
          'از همین شب می‌تونی متهم کنی',
        ], active: !night2Open),
        const SizedBox(width: 10),
        col('شب دوم', Icons.wb_twilight_rounded, [
          'یه مظنون تازه',
          'مدارک و حرف‌های جدید',
          night2Open ? 'باز شده' : 'تا باز شدنش:',
        ], active: night2Open, extra: night2Open || at == null ? null : BigCountdown(at: at, onDone: _opened)),
      ]),
    ]);
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
                  const SizedBox(height: 4),
                  const DifficultyBar(5, compact: true),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            if (weekly != null)
              SectionBanner(
                background: AnimatedScene(scene: weekly.scene, height: double.infinity, dim: 0.2),
                chip: weekly.solved ? 'حلش کردی!' : 'پرونده‌ی این هفته · بازه',
                title: weekly.title,
                subtitle: '${weekly.category.isEmpty ? '' : '${categoryName(weekly.category)} · '}دو فصل، هشت مظنون · جایزه‌ی ${fa(Api.i.weeklyReward)} سکه',
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
            if (weekly != null && _cases?.weeklyFormat == 3) ...[const SizedBox(height: 14), _nightsCard()],
            const SizedBox(height: 14),
            InfoCard(title: 'چطوری کار می‌کنه؟', lines: [
              (Icons.event_rounded, '${_scheduleText(up)} پرونده‌ی شبانه سر جاشه.'),
              (Icons.auto_stories_rounded, _cases?.weeklyFormat == 3
                  ? 'دو شب داره؛ شب دوم یه مظنون تازه و مدارک جدید می‌آره.'
                  : 'دو فصل داره؛ فصل دوم مدارک و حرف‌های تازه می‌آره.'),
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
