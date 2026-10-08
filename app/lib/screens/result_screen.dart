import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/engagement.dart';
import '../widgets/fx.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import 'leaderboard_screen.dart';

/// The big moment: stamp, stars, one row of rewards, the culprit, what others thought, share.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.caseData, required this.result});
  final CaseData caseData;
  final AccuseResult result;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  CaseData get caseData => widget.caseData;
  AccuseResult get result => widget.result;
  bool get solved => result.result == 'solved';

  @override
  void initState() {
    super.initState();
    // stamp, then the verdict music
    Sfx.i.duck();
    Future<void>.delayed(const Duration(milliseconds: 200), () => Sfx.i.play('stamp', volume: 0.8));
    Future<void>.delayed(const Duration(milliseconds: 700), () => Sfx.i.play(solved ? 'win' : 'lose'));
    Future<void>.delayed(const Duration(milliseconds: 4500), Sfx.i.unduck);
    if (result.badge != null) {
      Future<void>.delayed(const Duration(milliseconds: 2600), () => Sfx.i.play('clue', volume: 0.7));
    }
  }

  bool _more = false; // the full explanation

  @override
  Widget build(BuildContext context) {
    final culprit = result.culprit == null ? null : caseData.suspect(result.culprit!);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: AnimatedScene(scene: caseData.scene, height: double.infinity, dim: 0.7)),
        if (solved) const Positioned.fill(child: Confetti()),
        SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(18, 24, 18, 24), children: [
            Center(
              child: StampIn(
                delay: const Duration(milliseconds: 250),
                child: StampMark(solved ? 'حل شد' : 'پرونده رو باختی', size: 40, color: solved ? K.brass : K.stamp),
              ),
            ),
            const SizedBox(height: 18),
            if (solved) ...[
              Center(child: StampIn(delay: const Duration(milliseconds: 700), child: Stars(count: result.stars, size: 44))),
              const SizedBox(height: 12),
              FadeSlideIn(delay: const Duration(milliseconds: 1000), child: _rewards()),
              if (result.badge != null) ...[
                const SizedBox(height: 10),
                BadgeBanner(badge: result.badge!),
              ],
            ] else
              Center(
                child: Text('این بار مقصر از دستت در رفت. فردا شب یه پرونده‌ی تازه منتظرته.',
                    textAlign: TextAlign.center, style: tBody(14, color: K.text.withValues(alpha: 0.85))),
              ),
            const SizedBox(height: 18),
            FadeSlideIn(
              delay: const Duration(milliseconds: 1200),
              child: Paper(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (culprit != null)
                      Container(
                        decoration: BoxDecoration(color: K.paperDark, borderRadius: BorderRadius.circular(12)),
                        child: AnimatedSuspect(avatar: culprit.avatar, size: 72, mood: Mood.sad),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('مقصر', style: tBody(12, color: K.inkSoft)),
                        Text(culprit?.name ?? '', style: tDisplay(22, color: K.stamp)),
                        Text(culprit?.role ?? '', style: tBody(13, color: K.inkSoft)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    alignment: Alignment.topCenter,
                    child: Text(result.explanation ?? '',
                        maxLines: _more ? null : 3,
                        overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
                        style: tBody(15, color: K.ink)),
                  ),
                  if (_more && result.proof.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('مدرک کلیدی: ${result.proof.map((id) => caseData.evidenceById(id)?.title ?? id).join('، ')}',
                        style: tBody(13, color: K.inkSoft, w: FontWeight.w700)),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => setState(() => _more = !_more),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4), foregroundColor: K.stamp),
                      child: Text(_more ? 'بستن توضیح ▴' : 'ادامه‌ی توضیح ▾', style: tBody(13.5, color: K.stamp, w: FontWeight.w900)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            GuessStatsCard(caseData: caseData),
            const SizedBox(height: 18),
            FadeSlideIn(
              delay: const Duration(milliseconds: 1500),
              child: StampButton(
                label: solved ? 'پز بده' : 'به دوستات بگو',
                icon: Icons.share_rounded,
                onTap: () => SharePlus.instance.share(ShareParams(text: shortShareText(caseData, result))),
              ),
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: 'برگشت به خانه',
              icon: Icons.home_rounded,
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
          ]),
        ),
      ]),
    );
  }

  /// One small row: coins, nights in a row, today's rank (tap: the leaderboard).
  Widget _rewards() {
    Widget item(IconData icon, Color color, Widget label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 4),
          label,
        ]);
    final style = tBody(13.5, w: FontWeight.w900);
    final items = <Widget>[
      item(Icons.monetization_on_rounded, K.brass, AnimatedCount(value: result.reward, prefix: '+', suffix: ' سکه', style: style)),
      item(Icons.local_fire_department_rounded, K.stamp, Text('${fa(result.streak)} شب', style: style)),
      if (result.rank != null)
        GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
          child: item(Icons.emoji_events_rounded, K.brass, Text('رتبه‌ی ${fa(result.rank!)}', style: style)),
        ),
    ];
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: K.brass.withValues(alpha: 0.4)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 12), color: K.textSoft.withValues(alpha: 0.4)),
              items[i],
            ],
          ]),
        ),
      ),
      if (result.freezesUsed > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.shield_rounded, size: 16, color: K.brass),
            const SizedBox(width: 4),
            Flexible(child: Text('بیمه زنجیره‌ات رو نجات داد', style: tBody(12.5, color: K.textSoft, w: FontWeight.w700))),
          ]),
        ),
    ]);
  }
}
