import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';

/// The rank's badge: more stripes for higher ranks.
class RankIcon extends StatelessWidget {
  const RankIcon({super.key, required this.rank, this.size = 30});
  final int rank;
  final double size;

  @override
  Widget build(BuildContext context) {
    final top = rank >= Api.i.ranks.length - 1;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: top ? K.brass : K.night3,
        border: Border.all(color: K.brass, width: 1.6),
      ),
      child: Icon(top ? Icons.auto_awesome_rounded : Icons.workspace_premium_rounded,
          size: size * 0.62, color: top ? K.ink : K.brass),
    );
  }
}

/// A slim line: rank title, XP to the next rank, and a progress bar.
class RankBar extends StatelessWidget {
  const RankBar({super.key, required this.profile, this.onTap});
  final Profile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final next = p.nextRankXp;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: K.brass.withValues(alpha: 0.25))),
        child: Row(children: [
          RankIcon(rank: p.rank, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(p.rankTitle, style: tBody(14, w: FontWeight.w900, color: K.brass))),
                Text(next == null ? '${fa(p.xp)} امتیاز تجربه' : '${fa(p.xp)} / ${fa(next)}',
                    style: tBody(11.5, color: K.textSoft)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: p.rankProgress),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 6, backgroundColor: K.night3, color: K.brass),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Every rank, the ones reached lit up, with what gives XP.
class RankLadder extends StatelessWidget {
  const RankLadder({super.key, required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final ranks = Api.i.ranks;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: K.kraft.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('درجه‌ی کارآگاهی', style: tDisplay(18)),
        const SizedBox(height: 2),
        Text('امتیاز تجربه از حل پرونده (بیشتر با ستاره‌ی بیشتر)، معمای سریع، صندوقچه‌ی مأموریت‌ها و دستاوردها می‌آد.',
            style: tBody(12.5, color: K.textSoft)),
        const SizedBox(height: 10),
        RankBar(profile: profile),
        const SizedBox(height: 10),
        for (int i = 0; i < ranks.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Opacity(opacity: i <= profile.rank ? 1 : 0.35, child: RankIcon(rank: i, size: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(ranks[i].$2,
                    style: tBody(13.5,
                        w: i == profile.rank ? FontWeight.w900 : FontWeight.w400,
                        color: i == profile.rank ? K.brass : (i < profile.rank ? K.text : K.textSoft))),
              ),
              Text(i <= profile.rank ? (i == profile.rank ? 'الان' : '✓') : '${fa(ranks[i].$1)} امتیاز',
                  style: tBody(12, color: i <= profile.rank ? K.ok : K.textSoft)),
            ]),
          ),
      ]),
    );
  }
}
