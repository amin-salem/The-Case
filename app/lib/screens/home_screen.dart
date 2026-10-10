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
import '../widgets/crime_tape.dart';
import '../widgets/engagement.dart';
import '../widgets/missions_card.dart';
import '../widgets/offline.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import 'archive_screen.dart';
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
    Sfx.i.ambient('amb_home', volume: Sfx.homeVolume);
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
          nextCaseAt: c.nextCaseAt, tonightSolved: c.today?.solved ?? false, streak: Api.i.profile?.streak ?? 0,
          plan: Api.i.notifyPlan, tonightTitle: c.today?.title);
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

  /// The streak chip: the streak, the insurance held and the next badge, in a small sheet.
  void _openStreak() {
    if (Api.i.profile == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: K.night,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: ListenableBuilder(
            listenable: Api.i,
            builder: (context, _) => Api.i.profile == null ? const SizedBox.shrink() : StreakCard(profile: Api.i.profile!),
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
    await openCaseRow(context, row);
    if (mounted) _load(); // also refreshes the missions
  }

  Future<void> _openArchive() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ArchiveScreen()));
    if (mounted) _load();
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
                  const SizedBox(height: 14),
                  const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                  if (_error != null && _cases == null) _errorBox(),
                  if (_cases == null && _error == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                  if (_cases != null) ...[
                    FadeSlideIn(child: _hero(_cases!.today)),
                    const SizedBox(height: 14),
                    if (_missions != null) _missionsRow(_missions!),
                    _weekendRow(),
                    _archiveRow(),
                    _secureRow(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- top bar

  Widget _topBar() {
    final p = Api.i.profile;
    // a crowded row on a small phone: a very large system font is capped here so nothing overflows
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(p?.nickname ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900)),
                  Text(p?.rankTitle ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11.5, color: K.brass, w: FontWeight.w700)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        _streakChip(p?.streak ?? 0),
        const SizedBox(width: 6),
        CoinChip(
            coins: Api.i.coins,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen()))),
        Stack(clipBehavior: Clip.none, children: [
          IconButton(
            onPressed: () {
              if (needOnline(context)) showInbox(context);
            },
            icon: const Icon(Icons.mail_rounded, color: K.text),
            visualDensity: VisualDensity.compact,
            tooltip: 'صندوق پیام',
          ),
          if (Api.i.inboxCount > 0)
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 3),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(99)),
                child: Text(fa(Api.i.inboxCount), style: tBody(9, w: FontWeight.w900).copyWith(height: 1.3)),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _streakChip(int streak) => GestureDetector(
        onTap: _openStreak,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: K.stamp.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: K.stamp.withValues(alpha: 0.7)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.local_fire_department_rounded, size: 18, color: K.stamp),
            const SizedBox(width: 3),
            Text(fa(streak), style: tBody(15, w: FontWeight.w900)),
          ]),
        ),
      );

  /// Nothing to show yet. With no internet and nothing saved, explain the one-time need.
  Widget _errorBox() {
    final offline = !Api.i.online;
    return Paper(
      child: Column(children: [
        Icon(offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded, color: K.inkSoft, size: 36),
        const SizedBox(height: 6),
        Text(offline ? 'هنوز پرونده‌ای روی گوشیت نیست' : 'پرونده‌ها بارگذاری نشد',
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

  // ---------------------------------------------------------------- tonight's case

  /// "Next case: 05:23:10"; offline, the saved time may already be past: then the new case is waiting online.
  Widget _nextLine() {
    final left = _cases!.nextCaseAt.difference(DateTime.now());
    return Row(children: [
      const Icon(Icons.schedule_rounded, size: 16, color: K.textSoft),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          left.isNegative && !Api.i.online ? 'پرونده‌ی بعدی: رسیده!' : 'پرونده‌ی بعدی: ${faClock(left)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tBody(12.5, color: K.textSoft, w: FontWeight.w700),
        ),
      ),
    ]);
  }

  /// The one big card: tonight's case.
  Widget _hero(CaseRow? c) {
    if (c == null) {
      return _heroFrame(
        onTap: null,
        art: Image.asset('assets/banners/weekend.webp', fit: BoxFit.cover),
        children: [
          Text('هنوز پرونده‌ای باز نشده', style: tDisplay(22)),
          const SizedBox(height: 2),
          Text('هر شب ساعت ۹ یه پرونده‌ی تازه باز می‌شه.', style: tBody(13.5, color: K.textSoft)),
          const SizedBox(height: 10),
          _nextLine(),
        ],
      );
    }
    final finished = c.solved || c.failed;
    return _heroFrame(
      onTap: () => _open(c),
      art: AnimatedScene(scene: c.scene, height: double.infinity),
      badge: finished
          ? StampMark(c.solved ? 'حل شد' : 'باخت', size: 22, color: c.solved ? K.brass : K.stamp)
          : const _NewBadge(),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
          child: Text('پرونده‌ی امشب · شماره‌ی ${fa(c.number)}', style: tBody(11.5, color: K.ink, w: FontWeight.w900)),
        ),
        const SizedBox(height: 8),
        Text(c.title, style: tDisplay(24)),
        const SizedBox(height: 2),
        Row(children: [
          const Icon(Icons.place_rounded, size: 15, color: K.brass),
          const SizedBox(width: 3),
          Expanded(
            child: Text('${c.location} · ${fa(c.solvers)} نفر حلش کردن',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(12.5, color: K.textSoft)),
          ),
        ]),
        const SizedBox(height: 12),
        if (!finished)
          StampButton(label: 'شروع تحقیقات', icon: Icons.search_rounded, onTap: () => _open(c))
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              if (c.solved) ...[Stars(count: c.stars, size: 20), const SizedBox(width: 8)],
              Expanded(
                child: Text(
                  c.solved ? 'امشب حلش کردی!' : 'این بار نشد؛ فردا شب جبران کن.',
                  style: tBody(14, w: FontWeight.w900, color: c.solved ? K.brass : K.stamp),
                ),
              ),
              Text('دیدن پرونده', style: tBody(12.5, color: K.textSoft, w: FontWeight.w700)),
              const Icon(Icons.chevron_left_rounded, color: K.textSoft, size: 20),
            ]),
          ),
        const SizedBox(height: 10),
        _nextLine(),
      ],
    );
  }

  Widget _heroFrame({required VoidCallback? onTap, required Widget art, Widget? badge, required List<Widget> children}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: K.brass, width: 1.5),
          boxShadow: [BoxShadow(color: K.brass.withValues(alpha: 0.14), blurRadius: 20)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 168,
              child: Stack(fit: StackFit.expand, children: [
                art,
                const Positioned(left: 0, right: 0, bottom: 0, child: CrimeTape(height: 16)),
                if (badge != null) Positioned(right: 12, top: 12, child: badge),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- one-line rows

  /// A one-line row: icon, title (and a short line under it), something small at the end, a chevron.
  Widget _line({required IconData icon, required String title, String? sub, Color subColor = K.textSoft, Widget? trailing,
      required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: K.night2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: K.night3)),
            child: Row(children: [
              Icon(icon, color: K.brass, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w700).copyWith(height: 1.5)),
                  if (sub != null)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tBody(12, color: subColor, w: FontWeight.w700).copyWith(height: 1.5)),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
              const Icon(Icons.chevron_left_rounded, color: K.textSoft),
            ]),
          ),
        ),
      ),
    );
  }

  /// Today's missions: one pill per mission, filled as far as it got.
  Widget _missionsRow(MissionsDay m) {
    return _line(
      icon: Icons.assignment_turned_in_rounded,
      title: 'مأموریت‌های امروز',
      onTap: _openMissions,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (m.allDone && !m.claimed) ...[
          const Icon(Icons.inventory_2_rounded, size: 18, color: K.brass),
          const SizedBox(width: 6),
        ],
        for (final x in m.missions)
          Container(
            width: 22,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(99)),
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: x.done ? 1.0 : (x.target <= 0 ? 0.0 : (x.progress / x.target).clamp(0.0, 1.0).toDouble()),
              child: Container(
                decoration: BoxDecoration(color: x.done ? K.ok : K.brass, borderRadius: BorderRadius.circular(99)),
              ),
            ),
          ),
      ]),
    );
  }

  /// The weekend case: open now (time left), or coming soon.
  Widget _weekendRow() {
    final w = _cases!.weekly;
    final String title;
    String sub;
    Color color = K.textSoft;
    if (w != null) {
      title = 'آخر هفته: ${w.title}';
      final left = _cases!.weeklyClosesAt?.difference(DateTime.now());
      (sub, color) = w.solved
          ? ('حلش کردی!', K.brass)
          : w.failed
              ? ('این بار نشد', K.stamp)
              : (left == null || left.isNegative
                      ? 'بازه'
                      : left.inHours >= 24
                          ? 'تا پایان: ${fa(left.inDays)} روز و ${fa(left.inHours % 24)} ساعت'
                          : 'تا پایان: ${faClock(left)}',
                  K.brass);
    } else {
      final t = Api.i.upcomingWeekend['title'];
      title = t is String && t.isNotEmpty ? 'آخر هفته: $t' : 'آخر هفته';
      sub = 'به‌زودی';
    }
    return _line(
      icon: Icons.nightlight_round,
      title: title,
      sub: sub,
      subColor: color,
      onTap: () => MainShell.tab.value = MainShell.weekend,
    );
  }

  Widget _archiveRow() {
    final a = _cases!.archive;
    if (a.isEmpty) return const SizedBox.shrink();
    final solved = a.where((r) => r.solved).length;
    return _line(
      icon: Icons.inventory_2_outlined,
      title: 'بایگانی پرونده‌ها',
      sub: '${fa(solved)} از ${fa(a.length)} پرونده رو حل کردی',
      onTap: _openArchive,
    );
  }

  /// Guests who solved something: one line asking to secure the account.
  Widget _secureRow() {
    final p = Api.i.profile;
    if (p == null || p.secured || p.casesSolved < 1) return const SizedBox.shrink();
    return _line(
      icon: Icons.shield_rounded,
      title: 'حسابت رو امن کن تا سکه‌هات گم نشن',
      sub: 'با ایمیل · ${fa(Api.i.secureReward)} سکه هدیه',
      subColor: K.brass,
      onTap: () => MainShell.tab.value = MainShell.profile,
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
