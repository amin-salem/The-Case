import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../screens/dialogs.dart';
import '../services/api.dart';
import '../services/sound.dart';
import '../theme.dart';
import 'typewriter.dart';

// ------------------------------------------------------------------ share card

/// "۴:۱۲" (or "۱:۰۴:۱۲" past an hour) in Persian digits.
String faDuration(int seconds) {
  final d = Duration(seconds: seconds < 0 ? 0 : seconds);
  String two(int v) => fa(v).padLeft(2, '۰');
  final m = d.inMinutes % 60, s = d.inSeconds % 60;
  return d.inHours > 0 ? '${fa(d.inHours)}:${two(m)}:${two(s)}' : '${fa(d.inMinutes)}:${two(s)}';
}

/// Wordle-style result: how it went, with no spoilers (no culprit, no evidence).
List<String> shareLines(CaseData c, AccuseResult r) {
  final solved = r.result == 'solved';
  final wrong = r.progress?.attempts ?? (solved ? 0 : 3);
  final lines = <String>[
    '🕵️ «پرونده» · شماره‌ی ${fa(c.number)}',
    '«${c.title}»',
  ];
  if (solved) {
    lines.add('${'🟥' * wrong}🟩   ${'⭐' * r.stars}${'☆' * (3 - r.stars)}');
    lines.add('⏱ ${faDuration(r.seconds)} · ${r.hintsUsed == 0 ? '💡 بدون سرنخ' : '💡 ${fa(r.hintsUsed)} سرنخ'}');
    if (r.streak >= 2) lines.add('🔥 ${fa(r.streak)} شب پشت سر هم');
  } else {
    lines.add('${'🟥' * (wrong < 1 ? 3 : wrong)}  این پرونده من رو شکست داد!');
  }
  return lines;
}

String shareText(CaseData c, AccuseResult r) {
  final solved = r.result == 'solved';
  return [
    ...shareLines(c, r),
    '',
    solved ? 'هر شب ساعت ۹ یه جنایت تازه. تو هم می‌تونی حلش کنی؟' : 'تو می‌تونی حلش کنی؟ هر شب ساعت ۹ یه جنایت تازه.',
    Api.i.shareUrl,
  ].join('\n');
}

/// A preview of the share text on a paper card, with the share button.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key, required this.caseData, required this.result});
  final CaseData caseData;
  final AccuseResult result;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Paper(
        color: K.paperDark,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.ios_share_rounded, size: 18, color: K.inkSoft),
            const SizedBox(width: 6),
            Text('کارت نتیجه‌ات (بدون لو دادن جواب)', style: tBody(12.5, color: K.inkSoft, w: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          for (final line in shareLines(caseData, result)) Text(line, style: tBody(15.5, color: K.ink, w: FontWeight.w700)),
        ]),
      ),
      const SizedBox(height: 10),
      StampButton(
        label: 'برای دوستات بفرست',
        icon: Icons.share_rounded,
        color: K.ok,
        onTap: () => SharePlus.instance.share(ShareParams(text: shareText(caseData, result))),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ what others thought

/// Bars: who players accused first, and how many solved it. Only for finished cases.
class GuessStatsCard extends StatefulWidget {
  const GuessStatsCard({super.key, required this.caseData});
  final CaseData caseData;

  @override
  State<GuessStatsCard> createState() => _GuessStatsCardState();
}

class _GuessStatsCardState extends State<GuessStatsCard> {
  late final Future<CaseStats?> _stats = _load();

  Future<CaseStats?> _load() async {
    try {
      return await Api.i.caseStats(widget.caseData.id);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CaseStats?>(
      future: _stats,
      builder: (context, snap) {
        final s = snap.data;
        if (s == null || s.players < 1 || widget.caseData.suspects.isEmpty) return const SizedBox.shrink();
        final rows = [for (final x in widget.caseData.suspects) (x, s.suspects[x.id] ?? 0)]
          ..sort((a, b) => b.$2.compareTo(a.$2));
        final top = rows.first;
        final topRight = top.$1.id == s.culprit;
        return FadeSlideIn(
          child: Paper(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.groups_rounded, color: K.ink),
                const SizedBox(width: 8),
                Expanded(child: Text('بقیه چی فکر می‌کردن؟', style: tDisplay(18, color: K.ink))),
              ]),
              const SizedBox(height: 2),
              Text(
                top.$2 == 0
                    ? 'هنوز کسی کسی رو متهم نکرده.'
                    : '${fa(top.$2)}٪ اول به ${top.$1.name} شک کردن${topRight ? ' و درست زدن!' : '، ولی اشتباه بود!'}',
                style: tBody(14, color: K.inkSoft, w: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final r in rows) _bar(r.$1, r.$2, r.$1.id == s.culprit),
              const SizedBox(height: 6),
              Text(
                'از ${fa(s.players)} کارآگاه، ${fa(s.solvedPct)}٪ حلش کردن · ${fa(s.firstTryPct)}٪ با اولین حدس',
                style: tBody(13, color: K.inkSoft),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _bar(Suspect who, int pct, bool culprit) {
    final color = culprit ? K.stamp : K.inkSoft.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(
          width: 104,
          child: Row(children: [
            if (culprit) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.gavel_rounded, size: 15, color: K.stamp)),
            Flexible(
              child: Text(who.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13, color: K.ink, w: culprit ? FontWeight.w900 : FontWeight.w700)),
            ),
          ]),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct / 100),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 12, color: color, backgroundColor: K.paperDark),
            ),
          ),
        ),
        SizedBox(
          width: 46,
          child: Text('${fa(pct)}٪', textAlign: TextAlign.left, style: tBody(13, color: K.ink, w: FontWeight.w900)),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ login calendar

/// The 7-day login calendar, shown when today's login reward arrives.
Future<void> showLoginCalendar(BuildContext context, {required int day, required int reward}) {
  Sfx.i.play(day >= 7 ? 'win' : 'reveal', volume: 0.7);
  return showDialog<void>(context: context, builder: (_) => _CalendarDialog(day: day < 1 ? 1 : (day > 7 ? 7 : day), reward: reward));
}

class _CalendarDialog extends StatelessWidget {
  const _CalendarDialog({required this.day, required this.reward});
  final int day, reward;

  @override
  Widget build(BuildContext context) {
    final cal = Api.i.loginCalendar;
    return Dialog(
      backgroundColor: K.paper,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('جایزه‌ی ورود روزانه', textAlign: TextAlign.center, style: tDisplay(22, color: K.ink)),
          Text('هر روز بیای، جایزه بزرگ‌تر می‌شه. روز هفتم یه پاکت مهروموم‌شده! یه روز جا بمونی، از اول شروع می‌شه.',
              textAlign: TextAlign.center, style: tBody(13, color: K.inkSoft)),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [for (int d = 1; d <= 7; d++) _tile(d, d <= cal.length ? cal[d - 1] : null)],
          ),
          const SizedBox(height: 16),
          StampIn(
            delay: const Duration(milliseconds: 350),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const CoinIcon(size: 30),
              const SizedBox(width: 8),
              Text('+${fa(reward)} سکه', style: tDisplay(28, color: K.kraftDark)),
            ]),
          ),
          if (day >= 7)
            Text('پاکت مهروموم‌شده رو باز کردی!', textAlign: TextAlign.center, style: tBody(14, color: K.stamp, w: FontWeight.w900)),
          const SizedBox(height: 12),
          StampButton(label: 'بگیر', icon: Icons.check_rounded, onTap: () => Navigator.pop(context)),
        ]),
      ),
    );
  }

  Widget _tile(int d, int? coins) {
    final past = d < day, now = d == day;
    final tile = Container(
      width: 70,
      height: 84,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: now ? K.kraft : (past ? K.paperDark : Colors.white.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: now ? K.stamp : K.inkSoft.withValues(alpha: 0.25), width: now ? 2.5 : 1),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('روز ${fa(d)}', style: tBody(12, color: K.ink, w: FontWeight.w700)),
        if (past)
          const Icon(Icons.check_circle_rounded, color: K.ok, size: 26)
        else if (coins == null)
          Icon(now ? Icons.drafts_rounded : Icons.mail_rounded, color: K.stamp, size: 28)
        else
          const CoinIcon(size: 22),
        Text(coins == null ? (now ? fa(reward) : '؟') : fa(coins),
            style: tBody(13, color: past ? K.inkSoft : K.ink, w: FontWeight.w900)),
      ]),
    );
    return now ? StampIn(delay: const Duration(milliseconds: 150), child: tile) : tile;
  }
}

// ------------------------------------------------------------------ streak insurance & badges

const Map<int, String> kBadgeNames = {7: 'کارآگاه پیگیر', 30: 'کارآگاه خستگی‌ناپذیر', 100: 'افسانه‌ی شب'};

/// Asks, then buys one streak insurance with coins.
Future<void> buyStreakInsurance(BuildContext context) async {
  final api = Api.i;
  final ok = await confirm(
      context,
      'بیمه‌ی زنجیره',
      'اگه یه شب پرونده رو حل نکنی، یکی از بیمه‌ها خرج می‌شه و زنجیره‌ات نمی‌شکنه. '
          'قیمت: ${fa(api.freezeCost)} سکه. حداکثر ${fa(api.maxFreezes)} بیمه می‌تونی داشته باشی.',
      'بخر');
  if (!ok || !context.mounted) return;
  try {
    await api.buyStreakFreeze();
    Sfx.i.play('clue', volume: 0.7);
    if (context.mounted) toast(context, 'زنجیره‌ات بیمه شد 🛡');
  } on ApiException catch (e) {
    if (!context.mounted) return;
    if (e.code == 'not_enough_coins') {
      await showNeedCoins(context, e.need > 0 ? e.need : api.freezeCost);
    } else {
      toast(context, Api.errorText(e.code));
    }
  } catch (_) {
    if (context.mounted) toast(context, 'اتصال به سرور برقرار نیست');
  }
}

/// Home card: the streak, the insurance held, and the next badge.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final api = Api.i;
    final held = profile.streakFreezes, max = api.maxFreezes;
    final next = api.streakBadges.where((b) => b > profile.streak).fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: K.stamp.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.local_fire_department_rounded, color: K.stamp, size: 30),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fa(profile.streak)} شب پشت سر هم', style: tDisplay(18)),
              Text(
                next == null
                    ? 'همه‌ی نشان‌ها رو گرفتی!'
                    : '${fa(next - profile.streak)} شب دیگه تا نشان «${kBadgeNames[next] ?? '${fa(next)} شب'}»',
                style: tBody(12.5, color: K.textSoft),
              ),
            ]),
          ),
          for (int i = 0; i < max; i++)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(i < held ? Icons.shield_rounded : Icons.shield_outlined,
                  color: i < held ? K.ok : K.textSoft.withValues(alpha: 0.5), size: 26),
            ),
        ]),
        if (held < max) ...[
          const SizedBox(height: 10),
          StampButton(
            label: 'بیمه‌ی زنجیره · ${fa(api.freezeCost)} سکه',
            icon: Icons.shield_rounded,
            color: K.night3,
            height: 44,
            onTap: () => buyStreakInsurance(context),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('زنجیره‌ات بیمه‌ست: اگه یه شب جا بمونی، نمی‌شکنه.', style: tBody(12.5, color: K.ok)),
          ),
      ]),
    );
  }
}

/// The three streak badges; earned ones light up.
class StreakBadges extends StatelessWidget {
  const StreakBadges({super.key, required this.best});
  final int best;

  @override
  Widget build(BuildContext context) {
    final badges = Api.i.streakBadges;
    return Row(children: [
      for (final b in badges)
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: K.night2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: best >= b ? K.brass : Colors.transparent),
            ),
            child: Column(children: [
              Icon(Icons.military_tech_rounded, size: 34, color: best >= b ? K.brass : K.textSoft.withValues(alpha: 0.3)),
              Text(kBadgeNames[b] ?? '', textAlign: TextAlign.center, style: tBody(11.5, w: FontWeight.w900, color: best >= b ? K.text : K.textSoft)),
              Text('${fa(b)} شب پشت سر هم', textAlign: TextAlign.center, style: tBody(10.5, color: K.textSoft)),
            ]),
          ),
        ),
    ]);
  }
}

/// Shown on the result screen when a badge was just earned.
class BadgeBanner extends StatelessWidget {
  const BadgeBanner({super.key, required this.badge});
  final int badge;

  @override
  Widget build(BuildContext context) => StampIn(
        delay: const Duration(milliseconds: 1500),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2414),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: K.brass, width: 2),
          ),
          child: Row(children: [
            const Icon(Icons.military_tech_rounded, color: K.brass, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('نشان تازه: «${kBadgeNames[badge] ?? ''}»', style: tDisplay(17, color: K.brass)),
                Text('${fa(badge)} شب پشت سر هم پرونده حل کردی!', style: tBody(13, color: K.text)),
              ]),
            ),
          ]),
        ),
      );
}
