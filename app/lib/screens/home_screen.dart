import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/progress.dart';
import '../services/api.dart';
import '../services/billing.dart';
import '../services/reminders.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/engagement.dart';
import '../widgets/fx.dart';
import '../widgets/missions_card.dart';
import '../widgets/offline.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import 'case_screen.dart';
import 'dialogs.dart';
import 'inbox_sheet.dart';
import 'main_shell.dart';
import 'shop_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CasesList? _cases;
  MissionsDay? _missions;
  String? _error;
  bool _loading = false;
  Timer? _tick;
  DateTime _lastReload = DateTime.now();
  bool _wasOnline = Api.i.online;
  int _account = Api.i.account;
  bool _calendarShown = false;

  @override
  void initState() {
    super.initState();
    Api.i.addListener(_onApi);
    MainShell.tab.addListener(_onTab);
    _load();
    Sfx.i.ambient('amb_home', volume: 0.28);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _welcome());
  }

  /// Today's login calendar, then (once) the permission for the nightly reminders.
  Future<void> _welcome() async {
    await _showCalendar();
    if (mounted) await Reminders.i.askOnce();
  }

  /// Today's login reward (once per visit; it may only arrive after coming back online).
  Future<void> _showCalendar() async {
    final p = Api.i.profile;
    if (_calendarShown || p == null || p.loginReward <= 0 || !mounted) return;
    _calendarShown = true;
    await showLoginCalendar(context, day: p.loginDay < 1 ? 1 : p.loginDay, reward: p.loginReward);
  }

  /// Back online, or another account on this phone: fetch fresh cases.
  void _onApi() {
    final api = Api.i;
    final cameBack = api.online && !_wasOnline;
    final switched = api.account != _account;
    _wasOnline = api.online;
    _account = api.account;
    if (!mounted) return;
    if (switched) setState(() => _cases = null);
    if (cameBack || switched) {
      _load();
      _showCalendar();
    }
  }

  @override
  void dispose() {
    Api.i.removeListener(_onApi);
    MainShell.tab.removeListener(_onTab);
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final c = await Api.i.cases();
      if (mounted) {
        setState(() {
          _cases = c;
          _error = null;
        });
      }
      unawaited(_loadExtras());
      await Reminders.i.plan(
          nextCaseAt: c.nextCaseAt, tonightSolved: c.today?.solved ?? false, streak: Api.i.profile?.streak ?? 0);
      // a purchase paid earlier but not credited yet (app closed, no internet) is credited now
      final recovered = await Billing.i.recover();
      if (recovered > 0 && mounted) toast(context, 'خریدت اضافه شد: ${fa(recovered)} سکه');
    } catch (e) {
      if (mounted) setState(() => _error = Api.friendly(e));
    } finally {
      _loading = false;
    }
  }

  /// The smaller daily things on the home page (missions); a failure just hides them.
  /// (Quick riddles are hidden for now.)
  Future<void> _loadExtras() async {
    try {
      final m = await Api.i.missions();
      if (mounted) setState(() => _missions = m);
    } catch (e) {
      debugPrint('missions: $e');
    }
  }

  void _openMissions() {
    var day = _missions;
    if (day == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.night,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, set) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: MissionsCard(
              day: day!,
              onChanged: (m) {
                set(() => day = m);
                if (mounted) setState(() => _missions = m);
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Coming back to the home tab: fresh cases and missions.
  void _onTab() {
    if (MainShell.tab.value == MainShell.home && mounted) _load();
  }

  /// Pull-to-refresh and the retry buttons: wake the connection first if it was down.
  Future<void> _refresh() async {
    if (!Api.i.online || Api.i.profile == null) await Api.i.reconnect();
    await _load();
  }

  Future<void> _open(CaseRow row) async {
    if (row.locked) {
      if (!needOnline(context)) return;
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
          toast(context, Api.friendly(e));
        }
        return;
      } catch (e) {
        if (mounted) toast(context, Api.friendly(e));
        return;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaseScreen(caseId: row.id)));
    Sfx.i.ambient('amb_home', volume: 0.28);
    _load(); // also refreshes the missions
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GrainBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Api.i,
            builder: (context, _) => RefreshIndicator(
              onRefresh: _refresh,
              color: K.stamp,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  _topBar(),
                  const SizedBox(height: 16),
                  const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                  if (_error != null && _cases == null) _errorBox(),
                  if (_cases == null && _error == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                  if (_cases != null) ...[
                    if (_cases!.weekly != null) ...[
                      _weeklyCard(_cases!.weekly!, _cases!.weeklyClosesAt),
                      const SizedBox(height: 14),
                    ],
                    _todayCard(_cases!.today),
                    const SizedBox(height: 12),
                    _nextCase(),
                    const SizedBox(height: 12),
                    if (_missions != null) ...[
                      _missionsRow(_missions!),
                    ],
                    if (Api.i.profile != null) ...[
                      const SizedBox(height: 10),
                      StreakCard(profile: Api.i.profile!),
                    ],
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
    // a crowded row on a small phone: a very large system font is capped here so nothing overflows
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Row(children: [
      Flexible(
        child: GestureDetector(
        onTap: () => MainShell.tab.value = MainShell.profile,
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: K.night3, shape: BoxShape.circle, border: Border.all(color: K.brass, width: 2)),
            child: DetectiveFace(p?.avatar ?? 0, size: 42),
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
      const SoundButton(),
      Stack(clipBehavior: Clip.none, children: [
        _iconBtn(Icons.mail_rounded, () {
          if (needOnline(context)) showInbox(context);
        }),
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
      CoinChip(
          coins: Api.i.coins,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen()))),
      ]),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) =>
      IconButton(onPressed: onTap, icon: Icon(icon, color: K.text), splashRadius: 22);

  /// Nothing to show yet. With no internet and nothing saved, explain the one-time need.
  Widget _errorBox() {
    final offline = !Api.i.online;
    return Paper(
      child: Column(children: [
        Icon(offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded, color: K.inkSoft, size: 36),
        const SizedBox(height: 6),
        Text(offline ? 'هنوز پرونده‌ای روی گوشیت نیست' : 'پرونده‌ها الان باز نشد',
            textAlign: TextAlign.center, style: tDisplay(18, color: K.ink)),
        const SizedBox(height: 4),
        Text(
          offline
              ? 'برای گرفتن اولین پرونده باید یه بار به اینترنت وصل بشی. بعدش پرونده‌هایی که باز کردی بدون اینترنت هم خونده می‌شن.'
              : (_error ?? Api.genericText),
          textAlign: TextAlign.center,
          style: tBody(14, color: K.inkSoft),
        ),
        const SizedBox(height: 12),
        StampButton(label: 'دوباره امتحان کن', icon: Icons.refresh_rounded, onTap: _refresh),
      ]),
    );
  }

  /// The weekend's big case: harder, in three chapters, open Thursday night to Saturday night.
  Widget _weeklyCard(CaseRow c, DateTime? closes) {
    final left = closes?.difference(DateTime.now());
    final status = c.solved
        ? 'حلش کردی!'
        : c.failed
            ? 'این بار نشد'
            : left == null || left.isNegative
                ? ''
                : 'تا پایان: ${faClock(left)}';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(c),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: K.brass, width: 1.5),
          boxShadow: [BoxShadow(color: K.brass.withValues(alpha: 0.18), blurRadius: 18)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(children: [
            AnimatedScene(scene: c.scene, height: 150, dim: 0.45),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
                    child: Text('پرونده‌ی آخر هفته · خیلی سخت', style: tBody(11.5, color: K.ink, w: FontWeight.w900)),
                  ),
                  const Spacer(),
                  Text(c.title, style: tDisplay(22)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Expanded(
                      child: Text('سه فصل، هشت مظنون · جایزه‌ی ${fa(Api.i.weeklyReward)} سکه',
                          style: tBody(12.5, color: K.text.withValues(alpha: 0.85))),
                    ),
                    Text(status, style: tBody(12.5, color: c.solved ? K.ok : K.brass, w: FontWeight.w900)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

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
                  )
                else
                  const Positioned(right: 12, top: 12, child: _NewBadge()),
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
                  Expanded(
                    child: Text(' ${fa(c.solvers)} نفر حلش کردن',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.ink)),
                  ),
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

  /// One line for today's missions; tapping it opens the full list.
  Widget _missionsRow(MissionsDay m) {
    final (String text, Color color) = m.claimed
        ? ('صندوقچه‌ی امروز باز شد', K.ok)
        : m.allDone
            ? ('صندوقچه آماده‌ست، بازش کن!', K.ok)
            : ('${fa(m.done)} از ${fa(m.missions.length)} انجام شد', K.brass);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _openMissions,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.assignment_turned_in_rounded, color: K.brass),
          const SizedBox(width: 8),
          Expanded(child: Text('مأموریت‌های امروز', style: tBody(14, w: FontWeight.w700))),
          Text(text, style: tBody(12.5, color: color, w: FontWeight.w700)),
          const Icon(Icons.chevron_left_rounded, color: K.brass),
        ]),
      ),
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
        // offline, the saved time may already be past: then the new case is waiting online
        Text(left.isNegative && !Api.i.online ? 'رسیده!' : faClock(left), style: tDisplay(18, color: K.brass)),
      ]),
    );
  }

  Widget _secureBanner() {
    final p = Api.i.profile;
    if (p == null || p.secured || p.casesSolved < 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => MainShell.tab.value = MainShell.profile,
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
            child: SizedBox(width: 74, height: 56, child: AnimatedScene(scene: c.scene, height: 56, animated: false)),
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

/// Pulsing "new" tag on tonight's case.
class _NewBadge extends StatefulWidget {
  const _NewBadge();

  @override
  State<_NewBadge> createState() => _NewBadgeState();
}

class _NewBadgeState extends State<_NewBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: K.stamp,
            borderRadius: BorderRadius.circular(99),
            boxShadow: [BoxShadow(color: K.stamp.withValues(alpha: 0.35 + 0.4 * _c.value), blurRadius: 6 + 12 * _c.value)],
          ),
          child: Text('جدید', style: tBody(12, w: FontWeight.w900)),
        ),
      );
}
