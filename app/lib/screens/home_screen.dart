import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import 'account_screen.dart';
import 'case_screen.dart';
import 'dialogs.dart';
import 'inbox_sheet.dart';
import 'leaderboard_screen.dart';
import 'shop_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CasesList? _cases;
  String? _error;
  Timer? _tick;
  DateTime _lastReload = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      final next = _cases?.nextCaseAt;
      final now = DateTime.now();
      if (next != null && now.isAfter(next.add(const Duration(seconds: 2))) &&
          now.difference(_lastReload).inSeconds >= 30) {
        _lastReload = now;
        _load();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = Api.i.profile?.loginReward ?? 0;
      if (r > 0 && mounted) toast(context, 'جایزه‌ی ورود امروز: ${fa(r)} سکه');
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await Api.i.cases();
      if (mounted) {
        setState(() {
          _cases = c;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = Api.describe(e));
    }
  }

  Future<void> _open(CaseRow row) async {
    if (row.locked) {
      final ok = await confirm(context, 'باز کردن پرونده‌ی قدیمی',
          'این پرونده مال روزهای قبله. با ${fa(row.unlockCost)} سکه بازش کن.', 'باز کن');
      if (!ok || !mounted) return;
      try {
        await Api.i.unlockCase(row.id);
      } on ApiException catch (e) {
        if (!mounted) return;
        if (e.code == 'not_enough_coins') {
          await showNeedCoins(context, row.unlockCost);
        } else {
          toast(context, Api.errorText(e.code));
        }
        return;
      } catch (e) {
        if (mounted) toast(context, 'اتصال به سرور برقرار نیست');
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaseScreen(caseId: row.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GrainBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Api.i,
            builder: (context, _) => RefreshIndicator(
              onRefresh: _load,
              color: K.stamp,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  _topBar(),
                  const SizedBox(height: 16),
                  if (_error != null && _cases == null) _errorBox(),
                  if (_cases == null && _error == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                  if (_cases != null) ...[
                    _todayCard(_cases!.today),
                    const SizedBox(height: 12),
                    _nextCase(),
                    _secureBanner(),
                    const SizedBox(height: 22),
                    if (_cases!.archive.isNotEmpty) ...[
                      Text('بایگانی پرونده‌ها', style: tDisplay(20)),
                      Text('پرونده‌های روزهای قبل؛ هنوز می‌شه حلشون کرد.', style: tBody(13, color: K.textSoft)),
                      const SizedBox(height: 10),
                      for (int i = 0; i < _cases!.archive.length; i++)
                        FadeSlideIn(delay: Duration(milliseconds: 60 * i), child: _archiveRow(_cases!.archive[i])),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final p = Api.i.profile;
    final det = kDetectives[(p?.avatar ?? 0) % kDetectives.length];
    return Row(children: [
      Flexible(
        child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: K.night3, shape: BoxShape.circle, border: Border.all(color: K.brass, width: 2)),
            child: ClipOval(child: CustomPaint(painter: CharacterPainter(det))),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p?.nickname ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900)),
              Row(children: [
                const Icon(Icons.local_fire_department_rounded, size: 16, color: K.stamp),
                Flexible(
                  child: Text(' ${fa(p?.streak ?? 0)} روز پشت سر هم',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.textSoft)),
                ),
              ]),
            ]),
          ),
        ]),
        ),
      ),
      const SizedBox(width: 4),
      _iconBtn(Icons.emoji_events_rounded, () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
      Stack(clipBehavior: Clip.none, children: [
        _iconBtn(Icons.mail_rounded, () => showInbox(context)),
        if (Api.i.inboxCount > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: K.stamp, shape: BoxShape.circle),
              child: Text(fa(Api.i.inboxCount), style: tBody(9, w: FontWeight.w900)),
            ),
          ),
      ]),
      const SizedBox(width: 4),
      CoinChip(coins: Api.i.coins, onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen()))),
    ]);
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) =>
      IconButton(onPressed: onTap, icon: Icon(icon, color: K.text), splashRadius: 22);

  Widget _errorBox() => Paper(
        child: Column(children: [
          Text('پرونده‌ها بارگذاری نشد', style: tDisplay(18, color: K.ink)),
          Text(_error ?? '', textDirection: TextDirection.ltr, style: tBody(11, color: K.inkSoft)),
          const SizedBox(height: 10),
          StampButton(label: 'دوباره', onTap: _load),
        ]),
      );

  Widget _todayCard(CaseRow? c) {
    if (c == null) {
      return Paper(child: Text('هنوز پرونده‌ای باز نشده. ساعت ۹ شب برگرد!', style: tBody(16, color: K.ink)));
    }
    return GestureDetector(
      onTap: () => _open(c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // kraft folder tab
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
          decoration: const BoxDecoration(color: K.kraft, borderRadius: BorderRadius.vertical(top: Radius.circular(10))),
          child: Text('پرونده‌ی امشب · شماره‌ی ${fa(c.number)}', style: tBody(12, color: K.ink, w: FontWeight.w900)),
        ),
        Container(
          decoration: BoxDecoration(
            color: K.kraft,
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
            boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 20, offset: Offset(0, 10))],
          ),
          padding: const EdgeInsets.all(8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(children: [
                AnimatedScene(scene: c.scene, height: 170),
                if (c.solved || c.failed)
                  Positioned(
                    left: 14,
                    top: 14,
                    child: StampMark(c.solved ? 'حل شد' : 'باخت', size: 26, color: c.solved ? K.brass : K.stamp),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, style: tDisplay(24, color: K.ink)),
                Text(c.location, style: tBody(13, color: K.ink.withValues(alpha: 0.75))),
                const SizedBox(height: 8),
                Row(children: [
                  Difficulty(c.difficulty, color: K.ink),
                  const SizedBox(width: 10),
                  const Icon(Icons.people_alt_rounded, size: 16, color: K.ink),
                  Text(' ${fa(c.solvers)} نفر حلش کردن', style: tBody(12, color: K.ink)),
                  const Spacer(),
                  if (c.solved) Stars(count: c.stars, size: 20),
                ]),
                const SizedBox(height: 10),
                StampButton(
                  label: c.solved || c.failed ? 'دیدن پرونده' : 'شروع تحقیقات',
                  icon: Icons.search_rounded,
                  color: c.solved || c.failed ? K.ink : K.stamp,
                  onTap: () => _open(c),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _nextCase() {
    final next = _cases!.nextCaseAt;
    final left = next.difference(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.schedule_rounded, color: K.brass),
        const SizedBox(width: 8),
        Expanded(child: Text('پرونده‌ی بعدی', style: tBody(14, w: FontWeight.w700))),
        Text(faClock(left), style: tDisplay(18, color: K.brass)),
      ]),
    );
  }

  Widget _secureBanner() {
    final p = Api.i.profile;
    if (p == null || p.secured || p.casesSolved < 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFF1F3A34), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: K.ok.withValues(alpha: 0.6))),
          child: Row(children: [
            const Icon(Icons.shield_rounded, color: K.ok),
            const SizedBox(width: 8),
            Expanded(child: Text('حسابت رو با ایمیل امن کن تا سکه‌ها و ستاره‌هات گم نشن · ۲۰۰ سکه هدیه',
                style: tBody(13, w: FontWeight.w700))),
          ]),
        ),
      ),
    );
  }

  Widget _archiveRow(CaseRow c) {
    return GestureDetector(
      onTap: () => _open(c),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: K.kraft.withValues(alpha: 0.25))),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 74, height: 56, child: AnimatedScene(scene: c.scene, height: 56)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('شماره‌ی ${fa(c.number)}', style: tBody(11, color: K.textSoft)),
              Text(c.title, style: tBody(16, w: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
              Difficulty(c.difficulty, color: K.kraft),
            ]),
          ),
          if (c.solved)
            Stars(count: c.stars, size: 18)
          else if (c.failed)
            Text('باخت', style: tBody(13, color: K.stamp, w: FontWeight.w900))
          else if (c.locked)
            Row(children: [
              const Icon(Icons.lock_rounded, size: 16, color: K.brass),
              const SizedBox(width: 4),
              Text(fa(c.unlockCost), style: tBody(14, color: K.brass, w: FontWeight.w900)),
            ])
          else
            const Icon(Icons.chevron_left_rounded, color: K.textSoft),
        ]),
      ),
    );
  }
}
