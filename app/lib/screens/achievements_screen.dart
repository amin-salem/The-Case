import 'package:flutter/material.dart';

import '../models/progress.dart';
import '../services/api.dart';
import '../theme.dart';
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

/// Every achievement, grouped, with progress toward the ones not earned yet.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  AchievementsList? _list;
  String? _error;

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
                if (l != null) ...[
                  _header(l),
                  for (final g in kAchievementGroups.entries) ..._group(g.key, g.value, l.items.where((a) => a.group == g.key).toList()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AchievementsList l) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF2B2414), K.night2]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: K.brass.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          const Icon(Icons.military_tech_rounded, color: K.brass, size: 44),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${fa(l.earned)} از ${fa(l.total)} دستاورد', style: tDisplay(19)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: l.total == 0 ? 0 : l.earned / l.total, minHeight: 7, backgroundColor: K.night3, color: K.brass),
              ),
              const SizedBox(height: 4),
              Text('هر دستاورد سکه و امتیاز تجربه جایزه داره.', style: tBody(12, color: K.textSoft)),
            ]),
          ),
        ]),
      );

  List<Widget> _group(String key, (IconData, String) g, List<AchievementRow> items) {
    if (items.isEmpty) return const [];
    final done = items.where((a) => a.earned).length;
    return [
      const SizedBox(height: 18),
      Row(children: [
        Icon(g.$1, color: K.brass, size: 20),
        const SizedBox(width: 6),
        Expanded(child: Text(g.$2, style: tDisplay(17))),
        Text('${fa(done)}/${fa(items.length)}', style: tBody(13, color: K.textSoft, w: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      for (int i = 0; i < items.length; i++)
        FadeSlideIn(delay: Duration(milliseconds: 40 * i), child: _tile(items[i], g.$1)),
    ];
  }

  Widget _tile(AchievementRow a, IconData icon) {
    final frac = a.target == 0 ? 0.0 : (a.progress / a.target).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: a.earned ? const Color(0xFF2B2414) : K.night2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: a.earned ? K.brass : K.night3),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: a.earned ? K.brass : K.night3,
          ),
          child: Icon(a.earned ? icon : Icons.lock_outline_rounded, color: a.earned ? K.ink : K.textSoft, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(a.title, style: tBody(15, w: FontWeight.w900, color: a.earned ? K.brass : K.text)),
            Text(a.desc, style: tBody(12.5, color: K.textSoft)),
            if (!a.earned && a.target > 1) ...[
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: frac, minHeight: 5, backgroundColor: K.night3, color: K.kraft),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${fa(a.progress)}/${fa(a.target)}', style: tBody(11.5, color: K.textSoft)),
              ]),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (a.coins > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(fa(a.coins), style: tBody(13, w: FontWeight.w900, color: a.earned ? K.textSoft : K.brass)),
              const SizedBox(width: 3),
              const CoinIcon(size: 15),
            ]),
          if (a.xp > 0) Text('+${fa(a.xp)} امتیاز', style: tBody(11, color: K.textSoft)),
          if (a.earned) const Icon(Icons.check_circle_rounded, color: K.ok, size: 18),
        ]),
      ]),
    );
  }
}
