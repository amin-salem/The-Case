import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/coming_soon.dart';
import '../widgets/scene.dart';
import 'case_screen.dart';

DateTime? _time(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

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

  @override
  Widget build(BuildContext context) {
    final weekly = _cases?.weekly;
    final up = Api.i.upcomingWeekend;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _opened,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
            Text('آخر هفته', style: tDisplay(26)),
            Text('پرونده‌ی بزرگ و خیلی سخت هر پنجشنبه شب', style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 14),
            if (weekly != null)
              SectionBanner(
                background: AnimatedScene(scene: weekly.scene, height: double.infinity, dim: 0.2),
                chip: weekly.solved ? 'حلش کردی!' : 'پرونده‌ی این هفته · باز است',
                title: weekly.title,
                subtitle: 'سه فصل، هشت مظنون · جایزه‌ی ${fa(Api.i.weeklyReward)} سکه',
                countdownLabel: 'تا پایان',
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
                countdownLabel: 'باز می‌شه تا',
                at: _time(up['opens_at']) ?? _cases?.nextCaseAt,
                onCountdownDone: _opened,
              ),
            const SizedBox(height: 14),
            InfoCard(title: 'چطوری کار می‌کنه؟', lines: [
              (Icons.event_rounded, 'هر پنجشنبه ساعت ۹ شب باز می‌شه و تا آخر جمعه وقت داری.'),
              (Icons.auto_stories_rounded, 'سه فصل داره: هر چند ساعت، مدارک تازه‌ای رو می‌شه.'),
              (Icons.groups_rounded, 'هشت مظنون؛ باید هم مقصر رو پیدا کنی، هم انگیزه‌ی واقعیش رو.'),
              (Icons.emoji_events_rounded, 'جایزه: تا ${fa(Api.i.weeklyReward)} سکه و کلی امتیاز رتبه. زنجیره‌ی شبانه‌ت هم دست نمی‌خوره.'),
            ]),
          ]),
        ),
      ),
    );
  }
}
