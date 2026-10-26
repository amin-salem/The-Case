import 'package:flutter/material.dart';

import '../models/progress.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/medal.dart';
import '../widgets/offline.dart';
import '../widgets/typewriter.dart';

const Map<String, (IconData, String)> kAchievementGroups = {
  'cases': (Icons.folder_special_rounded, 'پرونده‌ها'),
  'skill': (Icons.psychology_rounded, 'مهارت'),
  'streak': (Icons.local_fire_department_rounded, 'شب‌های پیاپی'),
  'riddles': (Icons.bolt_rounded, 'معمای سریع'),
  'missions': (Icons.assignment_turned_in_rounded, 'مأموریت‌ها'),
  'account': (Icons.person_rounded, 'حساب'),
  'rank': (Icons.workspace_premium_rounded, 'درجه'),
};

/// The icon of one chain (by the chain id the server sends); a group icon when the chain is unknown.
const Map<String, IconData> _chainIcons = {
  'cases': Icons.folder_special_rounded,
  'stars': Icons.stars_rounded,
  'hint': Icons.psychology_rounded,
  'first': Icons.gps_fixed_rounded,
  'fast': Icons.bolt_rounded,
  'fast2': Icons.flash_on_rounded,
  'early': Icons.wb_twilight_rounded,
  'wknight': Icons.nightlight_round,
  'weekend': Icons.weekend_rounded,
  'top3': Icons.emoji_events_rounded,
  'album': Icons.photo_album_rounded,
  'streak': Icons.local_fire_department_rounded,
  'riddle': Icons.extension_rounded,
  'rfast': Icons.timer_rounded,
  'rday': Icons.check_circle_rounded,
  'chest': Icons.card_giftcard_rounded,
  'cstreak': Icons.event_available_rounded,
  'inter': Icons.record_voice_over_rounded,
  'arch': Icons.inventory_2_rounded,
  'invite': Icons.group_add_rounded,
  'login': Icons.calendar_month_rounded,
  'secure': Icons.verified_user_rounded,
  'rank': Icons.workspace_premium_rounded,
};

/// What each of the big ranks gives (shown on the «درجه‌ها» tab). Only things that exist.
const Map<String, String> _rankPerks = {
  'کارآگاه': 'قاب برنزی + نشان کارآگاهی',
  'بازرس': 'نشان بازرسی',
  'کارآگاه نخبه': 'لیگ «سرپرست» در جدول هفته + نشان نخبگان',
  'سربازرس': 'قاب نقره‌ای',
  'استاد معما': 'نشان استاد',
  'افسانه': 'قاب طلایی + نشان افسانه',
  'اسطوره‌ی کارآگاهی': 'بالاترین درجه + نشان اسطوره',
};

/// Achievements as chains of tiers, and the ladder of detective ranks. The server pays each tier on its own, once.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  AchievementsList? _list;
  String? _error;
  String _group = '';
  bool _ranks = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.i.achievements();
      if (!mounted) return;
      setState(() {
        _list = l;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = Api.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return Scaffold(
      appBar: AppBar(backgroundColor: K.night, title: Text('دستاوردها', style: tDisplay(20))),
      body: GrainBackground(
        child: SafeArea(
          top: false,
          child: RefreshIndicator(
            color: K.stamp,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                _tabs(),
                const SizedBox(height: 12),
                if (_ranks) ..._ladder(),
                if (!_ranks) ...[
                  if (l == null && _error == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                  if (l == null && _error != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        Text(_error!, textAlign: TextAlign.center, style: tBody(14, color: K.textSoft)),
                        const SizedBox(height: 12),
                        GhostButton(label: 'دوباره', icon: Icons.refresh_rounded, onTap: _load),
                      ]),
                    ),
                  if (l != null) ..._chainsView(l),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabs() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final t in [(false, 'دستاوردها'), (true, 'درجه‌ها')])
            Expanded(
              child: GestureDetector(
                key: ValueKey('ach-tab-${t.$1 ? 'ranks' : 'chains'}'),
                onTap: () => setState(() => _ranks = t.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _ranks == t.$1 ? K.brass : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                  child: Text(t.$2, style: tBody(14, w: FontWeight.w900, color: _ranks == t.$1 ? K.ink : K.textSoft)),
                ),
              ),
            ),
        ]),
      );

  // ------------------------------------------------------------------ the rank hero (shared by both tabs)

  Widget _hero({AchievementsList? l}) {
    final p = Api.i.profile;
    final ranks = Api.i.ranks;
    final r = p?.rank ?? 0;
    final next = p?.nextRankXp;
    final title = p?.rankTitle ?? ranks.first.$2;
    final nextTitle = p?.nextRankTitle;
    final chains = l?.chains ?? const <AchievementChain>[];
    final nearest = [for (final c in chains) if (c.next != null) c.remaining]..sort();
    return Container(
      key: const ValueKey('ach-hero'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF2B2414), K.night2]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.brass.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Medal(
              metal: metalFor(r, ranks.length),
              size: 76,
              child: Text(fa(r + 1), style: tDisplay(24, color: medalInk(metalFor(r, ranks.length))))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('درجه‌ی تو', style: tBody(12, color: K.textSoft)),
              Text(title, style: tDisplay(24, color: K.brass)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: p?.rankProgress ?? 0, minHeight: 8, backgroundColor: K.night3, color: K.brass),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Text('${fa(p?.xp ?? 0)} امتیاز', style: tBody(11.5, color: K.textSoft)),
                const Spacer(),
                Flexible(
                    child: Text(next == null ? 'بالاترین درجه' : '${fa(next - (p?.xp ?? 0))} تا «$nextTitle»',
                        overflow: TextOverflow.ellipsis, style: tBody(11.5, color: K.textSoft))),
              ]),
            ]),
          ),
        ]),
        if (l != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            _stat('${fa(l.earned)}', 'دستاورد گرفته‌ای'),
            const SizedBox(width: 8),
            _stat('${fa(l.total - l.earned)}', 'تا همه‌اش'),
            const SizedBox(width: 8),
            _stat(nearest.isEmpty ? '—' : fa(nearest.first), 'تا دستاورد بعدی'),
          ]),
        ],
      ]),
    );
  }

  Widget _stat(String v, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(v, style: tDisplay(20)),
            Text(label, textAlign: TextAlign.center, style: tBody(10.5, color: K.textSoft)),
          ]),
        ),
      );

  // ------------------------------------------------------------------ the chains

  List<Widget> _chainsView(AchievementsList l) {
    final chains = l.chains;
    final groups = [for (final g in kAchievementGroups.keys) if (chains.any((c) => c.group == g)) g];
    final shown = [for (final c in chains) if (_group.isEmpty || c.group == _group) c];
    return [
      _hero(l: l),
      const SizedBox(height: 12),
      SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          _chip('', 'همه'),
          for (final g in groups) _chip(g, kAchievementGroups[g]!.$2),
        ]),
      ),
      const SizedBox(height: 10),
      for (int i = 0; i < shown.length; i++) FadeSlideIn(delay: Duration(milliseconds: 30 * i), child: _chainCard(shown[i])),
    ];
  }

  Widget _chip(String key, String label) {
    final on = _group == key;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        key: ValueKey('ach-chip-$key'),
        onTap: () => setState(() => _group = key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: on ? K.brass : K.night2, borderRadius: BorderRadius.circular(18), border: Border.all(color: on ? K.brass : K.night3)),
          child: Text(label, style: tBody(13, w: FontWeight.w800, color: on ? K.ink : K.textSoft)),
        ),
      ),
    );
  }

  Widget _chainCard(AchievementChain c) {
    final n = c.next;
    final count = c.tiers.length;
    final metal = c.reached == 0 ? MedalMetal.locked : metalFor(c.reached - 1, count);
    final icon = _chainIcons[c.id] ?? kAchievementGroups[c.group]?.$1 ?? Icons.military_tech_rounded;
    return GestureDetector(
      key: ValueKey('ach-chain-${c.id}'),
      onTap: () => _tiersSheet(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.complete ? K.brass.withValues(alpha: 0.7) : K.night3),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Medal(metal: metal, size: 52, child: Icon(icon, size: 22, color: medalInk(metal))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(c.title, style: tDisplay(18))),
                  if (c.complete)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(8)),
                      child: Text('کامل شد', style: tBody(11, w: FontWeight.w900, color: K.ink)),
                    ),
                ]),
                Text(n == null ? 'همه‌ی پله‌ها را گرفتی' : 'بعدی: «${n.title}»', style: tBody(12.5, color: K.textSoft)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            for (int i = 0; i < count; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(end: i == count - 1 ? 0 : 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                        value: i < c.reached ? 1 : (i == c.reached ? c.stepFraction : 0),
                        minHeight: 6,
                        backgroundColor: K.night3,
                        color: K.brass),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('${fa(c.value)} ${c.unit}', style: tBody(12.5, color: K.textSoft))),
            if (n != null) Text('هدف: ${fa(n.target)}', style: tBody(12.5, w: FontWeight.w800, color: K.text)),
          ]),
          if (n != null && (n.coins > 0 || n.xp > 0))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Text('جایزه‌ی پله‌ی بعد:', style: tBody(11.5, color: K.textSoft)),
                const SizedBox(width: 6),
                if (n.coins > 0) ...[
                  Text(fa(n.coins), style: tBody(12, w: FontWeight.w900, color: K.brass)),
                  const SizedBox(width: 3),
                  const CoinIcon(size: 14),
                  const SizedBox(width: 8),
                ],
                if (n.xp > 0) Text('+${fa(n.xp)} امتیاز', style: tBody(12, color: K.textSoft)),
              ]),
            ),
        ]),
      ),
    );
  }

  void _tiersSheet(AchievementChain c) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.night2,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(padding: const EdgeInsets.all(18), shrinkWrap: true, children: [
            Text(c.title, style: tDisplay(21)),
            Text('${fa(c.reached)} از ${fa(c.tiers.length)} پله', style: tBody(12.5, color: K.textSoft)),
            const SizedBox(height: 10),
            for (final t in c.tiers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(children: [
                  Medal(
                      metal: t.earned ? metalFor(t.tier - 1, c.tiers.length) : MedalMetal.locked,
                      size: 38,
                      child: t.earned
                          ? Icon(Icons.check_rounded, size: 18, color: medalInk(metalFor(t.tier - 1, c.tiers.length)))
                          : Icon(Icons.lock_outline_rounded, size: 15, color: K.textSoft)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(t.title, style: tBody(14.5, w: FontWeight.w900, color: t.earned ? K.brass : K.text)),
                      Text(t.desc, style: tBody(12, color: K.textSoft)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (t.coins > 0)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(fa(t.coins), style: tBody(13, w: FontWeight.w900, color: t.earned ? K.textSoft : K.brass)),
                        const SizedBox(width: 3),
                        const CoinIcon(size: 14),
                      ]),
                    if (t.xp > 0) Text('+${fa(t.xp)} امتیاز', style: tBody(11, color: K.textSoft)),
                  ]),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ the ladder of ranks

  List<Widget> _ladder() {
    final ranks = Api.i.ranks;
    final p = Api.i.profile;
    final r = p?.rank ?? 0;
    return [
      _hero(),
      const SizedBox(height: 14),
      Text('${fa(ranks.length)} درجه', style: tDisplay(18)),
      Text('امتیاز تجربه از حل پرونده (با پلاک بیشتر، بیشتر)، صندوقچه‌ی مأموریت‌ها و دستاوردها می‌آد.',
          style: tBody(12.5, color: K.textSoft)),
      const SizedBox(height: 10),
      for (int i = 0; i < ranks.length; i++)
        Container(
          key: ValueKey('ach-rank-$i'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: i == r ? const Color(0xFF2B2414) : K.night2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: i == r ? K.brass : K.night3),
          ),
          child: Row(children: [
            Medal(
                metal: i > r ? MedalMetal.locked : metalFor(i, ranks.length),
                size: 42,
                child: Text(fa(i + 1), style: tDisplay(15, color: medalInk(i > r ? MedalMetal.locked : metalFor(i, ranks.length))))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(ranks[i].$2, style: tBody(15, w: FontWeight.w900, color: i == r ? K.brass : (i < r ? K.text : K.textSoft))),
                if (_rankPerks[ranks[i].$2] != null) Text(_rankPerks[ranks[i].$2]!, style: tBody(11.5, color: K.textSoft)),
              ]),
            ),
            const SizedBox(width: 8),
            if (i < r)
              const Icon(Icons.check_circle_rounded, color: K.ok, size: 20)
            else
              Text(i == r ? 'الان' : '${fa(ranks[i].$1)} امتیاز', style: tBody(12, w: FontWeight.w800, color: i == r ? K.ok : K.textSoft)),
          ]),
        ),
    ];
  }
}
