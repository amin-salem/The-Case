import 'account_sheets.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/progress.dart';
import '../services/api.dart';
import '../services/billing.dart';
import '../widgets/category.dart';
import '../services/reminders.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/crime_tape.dart';
import '../widgets/engagement.dart';
import '../widgets/missions_card.dart';
import '../widgets/offline.dart';
import '../widgets/profile_bell.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import '../widgets/whats_new_ui.dart';
import '../data/whats_new.dart';
import '../services/whats_new.dart';
import 'archive_screen.dart';
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
    WhatsNew.i.homeAction.addListener(_onWhatsNewJump);
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
    if (switched) {
      setState(() => _cases = null);
      MainShell.weekendOpen.value = false;
    }
    if (cameBack || switched) {
      _load();
      _showCalendar();
    }
  }

  @override
  void dispose() {
    Api.i.removeListener(_onApi);
    MainShell.tab.removeListener(_onTab);
    WhatsNew.i.homeAction.removeListener(_onWhatsNewJump);
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
        // the dot on the weekend tab: a weekend case is open and not yet finished
        MainShell.weekendOpen.value = c.weekly != null && !c.weekly!.solved && !c.weekly!.failed;
      }
      unawaited(_loadExtras());
      unawaited(_maybeOfferRepair());
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

  bool _repairShown = false;

  /// A streak that broke in the last 24 h: the server may offer a paid repair. Shown ONCE per break (a tap anywhere
  /// closes it for good) and it never blocks tonight's case.
  Future<void> _maybeOfferRepair() async {
    final offer = Api.i.profile?.streakRepair;
    if (_repairShown || offer == null || Api.i.repairOfferClosed(offer)) return;
    _repairShown = true;
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    await showStreakRepairOffer(context, offer);
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

  /// The «ادامه» button of the missions card: take the player to where the mission can be done.
  void _goMission(MissionRow m) {
    switch (missionTarget(m.id)) {
      case MissionTarget.tonight:
        final c = _cases?.today;
        if (c != null) {
          _open(c);
        } else {
          _openMissions();
        }
      case MissionTarget.weekend:
        MainShell.tab.value = MainShell.weekend;
      case MissionTarget.archive:
        _openArchive();
      case MissionTarget.sheet:
        _openMissions();
    }
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

  /// A «برو به …» jump from «چی تازه شده؟» that ends on the home screen.
  void _onWhatsNewJump() {
    final t = WhatsNew.i.homeAction.value;
    if (t == null || !mounted) return;
    WhatsNew.i.homeAction.value = null;
    switch (t) {
      case WhatsNewTarget.missions:
        _openMissions();
      case WhatsNewTarget.archive:
        _openArchive();
      default:
        final c = _cases?.today;
        if (c != null) _open(c);
    }
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

  /// The archive is a tab now.
  void _openArchive() => MainShell.tab.value = MainShell.archive;

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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                children: [
                  _topBar(),
                  const SizedBox(height: 10),
                  const WhatsNewBanner(),
                  const OfflineBanner(margin: EdgeInsets.only(bottom: 10)),
                  if (_error != null && _cases == null) _errorBox(),
                  if (_cases == null && _error == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                  if (_cases != null) ..._content(_cases!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Before tonight's case is solved: the hero and the two quick cards come first. After it is solved (or lost):
  /// a short result card and a clear invitation to the archive.
  List<Widget> _content(CasesList cs) {
    final c = cs.today;
    final finished = c != null && (c.solved || c.failed);
    return [
      if (!finished) FadeSlideIn(child: _hero(c)) else if (c.solved) _solvedCard(c, cs) else _lostCard(c, cs),
      const SizedBox(height: 10),
      if (finished) ...[
        _archiveInvite(cs),
        _weekendRow(),
      ] else
        _quickCards(cs),
      if (_missions != null) ...[const SizedBox(height: 10), _missionsCompact(_missions!)],
      const SizedBox(height: 10),
      _streakRow(),
      _secureRow(),
      _newsSection(),
    ];
  }

  // ---------------------------------------------------------------- top bar

  Widget _topBar() {
    final p = Api.i.profile;
    final name = p?.nickname ?? '';
    // a crowded row on a small phone: a very large system font is capped here so nothing overflows
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Row(children: [
        const ProfileBell(), // the avatar, the bell and the unread count (opens the messages)
        const SizedBox(width: 6),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => MainShell.tab.value = MainShell.profile,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name.isEmpty ? 'سلام' : 'سلام، $name',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900)),
              Text(p?.rankTitle ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11.5, color: K.brass, w: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        CoinChip(coins: Api.i.coins, onTap: _openShop),
      ]),
    );
  }

  void _openShop() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopScreen()));

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

  // ---------------------------------------------------------------- tonight's case

  /// The one big card: tonight's case (not solved yet). Compact: the quick cards must fit below it on a small phone.
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
    return _heroFrame(
      key: const ValueKey('home-hero'),
      onTap: () => _open(c),
      art: AnimatedScene(scene: c.scene, height: double.infinity),
      badge: const _NewBadge(),
      children: [
        Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
            child: Text('پرونده‌ی امشب · رایگان', style: tBody(11.5, color: K.ink, w: FontWeight.w900)),
          ),
          Text('شماره‌ی ${fa(c.number)}', style: tBody(11.5, color: K.textSoft, w: FontWeight.w700)),
          CategoryBadge(c.category),
        ]),
        const SizedBox(height: 4),
        Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tDisplay(22).copyWith(height: 1.3)),
        Text('${c.location} · ${fa(c.solvers)} کارآگاه حلش کردن',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(12.5, color: K.textSoft).copyWith(height: 1.5)),
        const SizedBox(height: 4),
        Row(children: [
          DifficultyBar(c.difficulty, compact: true),
          const SizedBox(width: 6),
          Flexible(
            child: Text(kDifficultyLabels[clampDifficulty(c.difficulty) - 1],
                maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11.5, color: K.textSoft)),
          ),
        ]),
        const SizedBox(height: 10),
        StampButton(label: 'شروع تحقیقات', icon: Icons.search_rounded, height: 50, onTap: () => _open(c)),
      ],
    );
  }

  Widget _heroFrame({Key? key, required VoidCallback? onTap, required Widget art, Widget? badge, required List<Widget> children}) {
    return GestureDetector(
      key: key,
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
              height: 80,
              child: Stack(fit: StackFit.expand, children: [
                art,
                const Positioned(left: 0, right: 0, bottom: 0, child: CrimeTape(height: 16)),
                if (badge != null) Positioned(right: 12, top: 10, child: badge),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ]),
        ),
      ),
    );
  }

  /// Tonight is solved: a short summary and the way to the result.
  Widget _solvedCard(CaseRow c, CasesList cs) {
    return Container(
      key: const ValueKey('home-solved'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: K.brass, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.check_circle_rounded, color: K.brass, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text('پرونده‌ی امشب حل شد', style: tDisplay(19, color: K.brass))),
          Plaques(count: c.stars, size: 22),
        ]),
        const SizedBox(height: 4),
        Text('«${c.title}» · شماره‌ی ${fa(c.number)}',
            maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(13, color: K.textSoft)),
        const SizedBox(height: 6),
        _nextLine(),
        const SizedBox(height: 10),
        StampButton(
            label: c.myRating == 0 ? 'مرور نتیجه و امتیاز دادن' : 'مرور نتیجه',
            icon: Icons.fact_check_rounded,
            color: K.night3,
            height: 48,
            onTap: () => _open(c)),
      ]),
    );
  }

  /// Tonight is lost: the case stays closed and the answer hidden; a second chance costs the real reopen price.
  Widget _lostCard(CaseRow c, CasesList cs) {
    return Container(
      key: const ValueKey('home-lost'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: K.stamp, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.lock_rounded, color: K.stamp, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('پرونده‌ی امشب بسته شد', style: tDisplay(19, color: K.stamp))),
        ]),
        const SizedBox(height: 4),
        Text(
          c.locked
              ? 'این بار نشد. با ${fa(c.unlockCost)} سکه (دو برابر قیمت بایگانی) یه فرصت دوباره می‌گیری؛ جواب تا وقتی بازش نکنی پنهون می‌مونه.'
              : 'این بار نشد؛ پرونده رو دوباره ببین.',
          style: tBody(13, color: K.textSoft).copyWith(height: 1.6),
        ),
        const SizedBox(height: 6),
        _nextLine(),
        const SizedBox(height: 10),
        StampButton(
            label: c.locked ? 'فرصت دوباره · ${fa(c.unlockCost)} سکه' : 'دیدن پرونده',
            icon: c.locked ? Icons.lock_open_rounded : Icons.visibility_rounded,
            color: K.night3,
            height: 48,
            onTap: () => _open(c)),
      ]),
    );
  }

  int _unsolved(CasesList cs) => cs.archive.where((r) => !r.solved).length;

  /// After tonight's case: the way to the archive, with the real number of old cases still waiting.
  Widget _archiveInvite(CasesList cs) {
    if (cs.archive.isEmpty) return const SizedBox.shrink();
    final n = _unsolved(cs);
    return Container(
      key: const ValueKey('archive-invite'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: K.brass.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.inventory_2_rounded, color: K.brass, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('یک پرونده‌ی دیگر؟', style: tDisplay(18)),
              Text(n > 0 ? '${fa(n)} پرونده‌ی بایگانی منتظرته' : 'همه‌ی پرونده‌های بایگانی رو حل کردی',
                  style: tBody(12.5, color: K.textSoft)),
            ]),
          ),
        ]),
        if (n > 0) ...[
          const SizedBox(height: 10),
          StampButton(
              label: 'برو به بایگانی',
              icon: Icons.inventory_2_outlined,
              height: 48,
              onTap: () => MainShell.tab.value = MainShell.archive),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- the two quick cards

  /// Archive and weekend case side by side (stacked on a very large font).
  Widget _quickCards(CasesList cs) {
    final a = _archiveCard(cs), w = _weekendCard(cs);
    final big = MediaQuery.textScalerOf(context).scale(10) > 15;
    if (big) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 10), w]);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: a),
        const SizedBox(width: 10),
        Expanded(child: w),
      ]),
    );
  }

  Widget _quickCard({Key? key, required IconData icon, required String title, required String line, Color lineColor = K.textSoft,
      Widget? badge, required VoidCallback onTap}) {
    return Material(
      key: key,
      color: K.night2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: K.night3)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Icon(icon, color: K.brass, size: 22),
              if (badge != null) ...[const SizedBox(width: 6), badge],
            ]),
            const SizedBox(height: 4),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900).copyWith(height: 1.4)),
            Text(line,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tBody(12, color: lineColor, w: FontWeight.w700).copyWith(height: 1.5)),
          ]),
        ),
      ),
    );
  }

  Widget _archiveCard(CasesList cs) {
    final n = _unsolved(cs);
    return _quickCard(
      key: const ValueKey('quick-archive'),
      icon: Icons.inventory_2_outlined,
      title: 'بایگانی پرونده‌ها',
      line: cs.archive.isEmpty
          ? 'هنوز پرونده‌ی قدیمی نیست'
          : n > 0
              ? '${fa(n)} پرونده منتظرته'
              : 'همه‌ی پرونده‌ها رو حل کردی',
      lineColor: n > 0 ? K.brass : K.textSoft,
      onTap: () => MainShell.tab.value = MainShell.archive,
    );
  }

  Widget _weekendCard(CasesList cs) {
    final (line, color) = _weekendState(cs);
    return _quickCard(
      key: const ValueKey('quick-weekend'),
      icon: Icons.nightlight_round,
      title: 'پرونده‌ی آخر هفته',
      line: line,
      lineColor: color,
      badge: const NewTag('weekend_tab'),
      onTap: () => MainShell.tab.value = MainShell.weekend,
    );
  }

  String _longLeft(Duration d) =>
      d.inHours >= 24 ? '${fa(d.inDays)} روز و ${fa(d.inHours % 24)} ساعت' : faClock(d);

  /// The real state of the weekend case: open (with its chapters), solved, lost, or closed with the opening time.
  (String, Color) _weekendState(CasesList cs) {
    final w = cs.weekly;
    final now = DateTime.now();
    if (w != null) {
      if (w.solved) return ('حلش کردی!', K.brass);
      if (w.failed) return ('این بار نشد', K.stamp);
      final next = cs.weeklyNextChapterAt;
      if (cs.weeklyFormat == 3 && next != null && next.isAfter(now)) {
        return ('باز است · فصل دوم: ${_longLeft(next.difference(now))} دیگه', K.brass);
      }
      final left = cs.weeklyClosesAt?.difference(now);
      if (left == null || left.isNegative) return ('باز است', K.brass);
      return ('باز است · ${_longLeft(left)} مونده', K.brass);
    }
    final at = Api.i.upcomingWeekend['opens_at'];
    if (at is num) {
      final d = DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000).difference(now);
      if (!d.isNegative) return ('بسته · ${_longLeft(d)} دیگه باز می‌شه', K.textSoft);
    }
    return ('بسته · به‌زودی', K.textSoft);
  }

  // ---------------------------------------------------------------- missions, streak, news

  /// Compact missions: done x of 3, a progress bar, the next mission and one button.
  Widget _missionsCompact(MissionsDay d) {
    final total = d.missions.length;
    MissionRow? next;
    for (final m in d.missions) {
      if (!m.done) {
        next = m;
        break;
      }
    }
    final ready = d.allDone && !d.claimed;
    return Container(
      key: const ValueKey('home-missions'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: K.kraft.withValues(alpha: 0.55)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openMissions,
          child: Row(children: [
            const Icon(Icons.assignment_turned_in_rounded, color: K.brass, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('مأموریت‌های امروز', style: tBody(14, w: FontWeight.w900))),
            Text('${fa(d.done)} از ${fa(total)}', style: tBody(13, color: K.brass, w: FontWeight.w900)),
          ]),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              key: const ValueKey('missions-bar'),
              value: total == 0 ? 0 : d.done / total,
              minHeight: 6,
              backgroundColor: K.night3,
              color: d.allDone ? K.ok : K.brass),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: Text(
              d.claimed
                  ? 'صندوقچه‌ی امروز باز شد'
                  : ready
                      ? 'همه‌ی مأموریت‌ها انجام شد؛ صندوقچه‌ات آماده‌ست'
                      : (next?.title ?? ''),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tBody(12.5, color: d.claimed ? K.ok : K.textSoft).copyWith(height: 1.5),
            ),
          ),
          if (!d.claimed)
            SizedBox(
              height: 48,
              child: TextButton(
                key: ValueKey(ready ? 'missions-claim' : 'missions-go'),
                onPressed: ready || next == null ? _openMissions : () => _goMission(next!),
                child: Text(ready ? 'باز کردن' : 'ادامه', style: tBody(14, color: K.brass, w: FontWeight.w900)),
              ),
            ),
        ]),
      ]),
    );
  }

  /// The streak: nights in a row, nights to the next milestone, and the repair offer when the server makes one.
  Widget _streakRow() {
    final p = Api.i.profile;
    if (p == null) return const SizedBox.shrink();
    final offer = p.streakRepair;
    final showOffer = offer != null && !Api.i.repairOfferClosed(offer);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: const ValueKey('home-streak'),
        decoration: BoxDecoration(
          color: K.night2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: K.stamp.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _openStreak,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                const Icon(Icons.local_fire_department_rounded, color: K.stamp, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(p.streak > 0 ? '${fa(p.streak)} شب پشت سر هم' : 'زنجیره‌ی شبانه',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900).copyWith(height: 1.4)),
                    Text(p.streak > 0 ? nextMilestoneLine(p.streak, Api.i.streakMilestones) : 'امشب پرونده رو حل کن تا زنجیره شروع بشه',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.textSoft).copyWith(height: 1.5)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: K.textSoft),
              ]),
            ),
          ),
          if (showOffer)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 4, 6),
              child: Row(children: [
                Expanded(
                  child: StampButton(
                    key: const ValueKey('streak-repair'),
                    label: 'ترمیم زنجیره · ${fa(offer.price)} سکه',
                    icon: Icons.local_fire_department_rounded,
                    height: 46,
                    onTap: () async {
                      await Api.i.closeRepairOffer(offer);
                      if (mounted) await repairStreak(context, offer);
                    },
                  ),
                ),
                IconButton(
                  key: const ValueKey('streak-repair-close'),
                  tooltip: 'بستن',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => Api.i.closeRepairOffer(offer),
                  icon: const Icon(Icons.close_rounded, color: K.textSoft, size: 20),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  bool _newsOpen = false;

  /// «تازه‌ها»: collapsed by default. What's new, the story, the invite, the leaderboard and the shop are one tap away.
  Widget _newsSection() {
    Widget row(IconData icon, String title, VoidCallback onTap, {String? sub, Widget? trailing}) => InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              Icon(icon, color: K.brass, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: tBody(13.5, w: FontWeight.w700).copyWith(height: 1.5)),
                  if (sub != null) Text(sub, style: tBody(11.5, color: K.textSoft).copyWith(height: 1.4)),
                ]),
              ),
              if (trailing != null) trailing,
              const Icon(Icons.chevron_right_rounded, color: K.textSoft, size: 20),
            ]),
          ),
        );
    return Container(
      key: const ValueKey('home-news'),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: K.night2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: K.night3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            key: const ValueKey('news-toggle'),
            onTap: () => setState(() => _newsOpen = !_newsOpen),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: K.brass, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('تازه‌ها', style: tBody(14, w: FontWeight.w900))),
                Icon(_newsOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: K.textSoft),
              ]),
            ),
          ),
          if (_newsOpen) ...[
            row(Icons.auto_awesome_rounded, 'چی تازه شده؟', () => showWhatsNewSheet(context, all: true)),
            row(Icons.menu_book_rounded, 'داستان', () => MainShell.openStory(context), sub: 'پرونده‌های سرگرد ناصری'),
            row(Icons.group_add_rounded, 'دعوت دوستان', () => MainShell.tab.value = MainShell.profile,
                sub: 'کد دعوتت توی پروفایله'),
            row(Icons.emoji_events_rounded, 'جدول برترها', () => MainShell.tab.value = MainShell.leaderboard),
            row(Icons.storefront_rounded, 'فروشگاه', _openShop),
          ],
        ]),
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
              const Icon(Icons.chevron_right_rounded, color: K.textSoft),
            ]),
          ),
        ),
      ),
    );
  }

  /// The weekend case as a one-line row (shown after tonight's case is finished).
  Widget _weekendRow() {
    final cs = _cases!;
    final w = cs.weekly;
    final t = Api.i.upcomingWeekend['title'];
    final title = w != null ? 'آخر هفته: ${w.title}' : (t is String && t.isNotEmpty ? 'آخر هفته: $t' : 'آخر هفته');
    final (sub, color) = _weekendState(cs);
    return _line(
      icon: Icons.nightlight_round,
      title: title,
      sub: sub,
      subColor: color,
      trailing: const NewTag('weekend_tab'),
      onTap: () => MainShell.tab.value = MainShell.weekend,
    );
  }

  /// Guests who solved something: one line asking to secure the account.
  Widget _secureRow() {
    final p = Api.i.profile;
    if (p == null || p.secured) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openAccountSheet(context, showSecureSheet),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: K.brass, width: 1.5)),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(color: K.night3, shape: BoxShape.circle),
                child: const Icon(Icons.shield_rounded, color: K.brass, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('حسابت هنوز امن نیست', style: tBody(15.5, w: FontWeight.w900)),
                  Text('با شماره‌ات امنش کن و ${fa(Api.i.secureReward)} سکه بگیر',
                      style: tBody(12.5, color: K.textSoft).copyWith(height: 1.6)),
                ]),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left_rounded, color: K.brass),
            ]),
          ),
        ),
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
