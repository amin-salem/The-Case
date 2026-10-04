import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/fx.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import 'leaderboard_screen.dart';

/// The big moment: stamp, stars, reward, explanation, share.
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
    Future<void>.delayed(const Duration(milliseconds: 300), () => Sfx.i.play('stamp', volume: 0.9));
    Future<void>.delayed(const Duration(milliseconds: 900), () => Sfx.i.play(solved ? 'win' : 'lose'));
  }

  String get _shareText {
    final stars = '★' * result.stars + '☆' * (3 - result.stars);
    return solved
        ? '🕵️ پرونده‌ی شماره‌ی ${fa(caseData.number)} «${caseData.title}» رو حل کردم! $stars\n'
            'تو می‌تونی؟ «پرونده» رو از کافه‌بازار بگیر.'
        : '🕵️ پرونده‌ی شماره‌ی ${fa(caseData.number)} «${caseData.title}» من رو شکست داد! تو می‌تونی حلش کنی؟';
  }

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
              const SizedBox(height: 10),
              FadeSlideIn(
                delay: const Duration(milliseconds: 1000),
                child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8, children: [
                  _pillW(Icons.monetization_on_rounded,
                      AnimatedCount(value: result.reward, prefix: 'پاداش ', suffix: ' سکه', style: tBody(14, w: FontWeight.w900)), K.brass),
                  _pill(Icons.local_fire_department_rounded, '${fa(result.streak)} روز پشت سر هم', K.stamp),
                  if (result.rank != null) _pill(Icons.emoji_events_rounded, 'رتبه‌ی ${fa(result.rank!)} امروز', K.ok),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            FadeSlideIn(
              delay: const Duration(milliseconds: 1200),
              child: Paper(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    if (culprit != null)
                      Container(
                        decoration: BoxDecoration(color: K.paperDark, borderRadius: BorderRadius.circular(12)),
                        child: AnimatedSuspect(avatar: culprit.avatar, size: 80, mood: Mood.sad),
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
                  Text(result.explanation ?? '', style: tBody(15.5, color: K.ink)),
                  if (result.proof.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('مدرک کلیدی: ${result.proof.map((id) => caseData.evidenceById(id)?.title ?? id).join('، ')}',
                        style: tBody(13, color: K.inkSoft, w: FontWeight.w700)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 18),
            StampButton(
              label: 'برای دوستات بفرست',
              icon: Icons.share_rounded,
              color: K.ok,
              onTap: () => SharePlus.instance.share(ShareParams(text: _shareText)),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: GhostButton(
                  label: 'جدول امروز',
                  icon: Icons.emoji_events_rounded,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: GhostButton(label: 'برگشت به پرونده', onTap: () => Navigator.pop(context))),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pill(IconData icon, String text, Color color) => _pillW(icon, Text(text, style: tBody(14, w: FontWeight.w900)), color);

  Widget _pillW(IconData icon, Widget label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(99), border: Border.all(color: color)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          label,
        ]),
      );
}
