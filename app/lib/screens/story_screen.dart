import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/coming_soon.dart';

DateTime? _time(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

/// The story tab. Until story mode opens it shows the season banner and a countdown.
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  bool _reached = false;

  Future<void> _done() async {
    setState(() => _reached = true);
    await Api.i.refreshConfig();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = Api.i.upcomingStory;
    // the planned start (Mon 12 Oct 00:00 Tehran) if the server doesn't say
    final at = _time(s['opens_at']) ?? DateTime.utc(2026, 10, 11, 20, 30).toLocal();
    final open = _reached || s['open'] == true || !at.isAfter(DateTime.now());
    final season = (s['season'] as num?)?.toInt() ?? 1;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          Text('داستان', style: tDisplay(26)),
          Text('پرونده‌های سرگرد ناصری · یه مسیر بی‌پایان', style: tBody(13, color: K.textSoft)),
          const SizedBox(height: 14),
          SectionBanner(
            background: Image.asset('assets/banners/story_s01.webp', fit: BoxFit.cover),
            chip: open ? 'فصل ${fa(season)} · شروع شد' : 'فصل ${fa(season)} · به‌زودی',
            title: (s['title'] as String?) ?? 'کبریت سوخته',
            subtitle: s['tagline'] as String?,
            countdownLabel: open ? null : 'تا شروع داستان',
            at: open ? null : at,
            onCountdownDone: _done,
            button: open
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: K.ok.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                    child: Text('داستان شروع شد! نسخه‌ی جدید برنامه رو نصب کن تا وارد اولین پرونده بشی.',
                        style: tBody(13.5, w: FontWeight.w700)),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          _partner(),
          const SizedBox(height: 14),
          const InfoCard(title: 'چطوری کار می‌کنه؟', lines: [
            (Icons.route_rounded, 'هر فصل ده پرونده داره و پشت همه‌شون یه راز بزرگه که توی پرونده‌ی آخر معلوم می‌شه.'),
            (Icons.lock_open_rounded, 'سه پرونده‌ی اول رایگانه و از همون اول بازه.'),
            (Icons.gavel_rounded, 'بعدش هر پرونده با یه «حکم بازرسی» باز می‌شه، یا ۱۲ ساعت بعد خودبه‌خود.'),
            (Icons.verified_rounded, 'حکم رو با حل پرونده‌ی هر شب، مأموریت‌های روزانه، زنجیره و پرونده‌ی آخر هفته می‌گیری.'),
            (Icons.all_inclusive_rounded, 'فصل که تموم بشه، فصل بعدی شروع می‌شه. داستان تموم نمی‌شه.'),
          ]),
        ]),
      ),
    );
  }

  Widget _partner() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: K.brass, width: 2)),
            child: ClipOval(child: Image.asset(portraitAsset('m_mid_officer'), fit: BoxFit.cover)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('سرگرد ناصری', style: tBody(15, w: FontWeight.w900, color: K.brass)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(12)),
                child: Text(
                    '«سلام همکار. سه ساله دنبال کسی‌ام که سر هر صحنه یه کبریت سوخته جا می‌ذاره. '
                    'تنهایی بهش نرسیدم؛ شاید با تو برسم. فقط زیاد حرف نزن، مدارک رو بخون.»',
                    style: tBody(13.5, color: K.ink)),
              ),
            ]),
          ),
        ]),
      );
}
