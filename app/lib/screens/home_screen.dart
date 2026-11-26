import 'account_sheets.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/progress.dart';
import '../services/api.dart';
import '../services/app_update.dart';
import '../services/billing.dart';
import '../services/home_rules.dart';
import '../widgets/kikoja_card.dart';
import '../services/reminders.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/crime_tape.dart';
import '../widgets/engagement.dart';
import '../widgets/gift_case.dart';
import '../widgets/missions_card.dart';
import '../widgets/notifications_card.dart';
import '../widgets/name_sheet.dart';
import '../services/name_ideas.dart';
import '../widgets/state_view.dart';
import '../widgets/store_rating_card.dart';
import '../widgets/update_card.dart';
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
  Object? _failure; // the exception behind _error (the state view picks offline or error from it)
  bool _loading = false;
  Timer? _tick;
  DateTime _lastReload = DateTime.now();
  bool _wasOnline = Api.i.online;
  int _account = Api.i.account;
  bool _calendarShown = false;
  bool _calendarDone = false;

  @override
  void initState() {
    super.initState();
    Api.i.addListener(_onApi);
    AppUpdate.i.addListener(_onUpdate);
    AppUpdate.i.load();
    MainShell.tab.addListener(_onTab);
    WhatsNew.i.homeAction.addListener(_onWhatsNewJump);
    Reminders.i.onResume = _onResume;
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
    _calendarDone = true;
    if (mounted) await Reminders.i.askOnce();
    _maybeShowUpdate();
  }

  /// The «نسخه‌ی تازه آماده‌ست» modal: once per launch, only when the home page is the visible route (never over a case
  /// screen or another dialog), never with the forced-update page (bannerVisible is false then).
  void _maybeShowUpdate() {
    if (!mounted || !AppUpdate.i.modalDue || !_calendarDone) return;
    if (MainShell.tab.value != MainShell.home || ModalRoute.of(context)?.isCurrent != true) return;
    showUpdateModal(context);
  }

  /// «ممنون که آپدیت کردی»: shown once when the server has just paid the update coins.
  void _onUpdate() {
    if (!mounted) return;
    final n = AppUpdate.i.takeThanks();
    if (n > 0) {
      toast(context, 'ممنون که آپدیت کردی · ${fa(n)} سکه به حسابت اضافه شد');
    }
    _maybeShowUpdate();
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
    _maybeShowUpdate();
  }

  /// Back in the foreground (also after the phone's settings screen): fresh cases and a fresh reminder plan.
  Future<void> _onResume() async {
    final now = DateTime.now();
    if (now.difference(_lastReload).inMinutes >= 2) {
      _lastReload = now;
      await _load();
    } else {
      await Reminders.i.replanLast();
    }
  }

  @override
  void dispose() {
    if (Reminders.i.onResume == _onResume) Reminders.i.onResume = null;
    Api.i.removeListener(_onApi);
    AppUpdate.i.removeListener(_onUpdate);
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
          _failure = null;
        });
        // the dot on the weekend tab: a weekend case is open and not yet finished
        MainShell.weekendOpen.value = c.weekly != null && !c.weekly!.solved && !c.weekly!.failed;
        MainShell.noteArchiveCount(c.archive.length); // the dot on the archive tab: cases the player has not seen yet
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
      if (mounted) {
        setState(() {
          _error = Api.friendly(e);
          _failure = e;
        });
      }
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
                  const UpdateChip(),
                  const NamePromptCard(),
                  const StoreRatingCard(),
                  const NotificationsOffCard(),
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
    final intro = cs.intro;
    return [
      if (intro != null && !intro.solved && !intro.failed) ...[_introCard(intro), const SizedBox(height: 10)],
      if (!finished) ...[
        FadeSlideIn(child: _hero(c)),
        const SizedBox(height: 10),
        _giftCard(cs),
        const KikojaHomeCard(),
      ] else ...[
        // tonight is done: the daily puzzle moves up, the result stays as a short strip below it
        _giftCard(cs),
        const KikojaHomeCard(),
        if (c.solved) _solvedCard(c, cs) else _lostCard(c, cs),
        const SizedBox(height: 10),
      ],
      // only what asks something of the player now (a streak at risk, an account worth securing) ...
      _streakRow(cs),
      _secureRow(),
      if (_missions != null) ...[
        const SizedBox(height: 10),
        _missionsCompact(_missions!),
      ],
    ];
  }

  /// The free first case: one calm card above tonight's hero, gone once it is solved. Nothing else to read.
  Widget _introCard(CaseRow r) {
    return InkWell(
      key: const ValueKey('home-intro'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => openCaseRow(context, r),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: K.brass.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: K.brass, width: 1.5),
        ),
        child: Row(children: [
          const Icon(Icons.auto_awesome_rounded, color: K.brass, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('پرونده‌ی اول · رایگان', style: tBody(12.5, color: K.brass, w: FontWeight.w900).copyWith(height: 1.4)),
              Text(r.title, style: tBody(15, w: FontWeight.w900).copyWith(height: 1.4)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: K.brass, size: 26),
        ]),
      ),
    );
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
            key: const ValueKey('home_name'),
            onTap: () => showNameSheet(context),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(name.isEmpty ? 'سلام' : 'سلام، $name',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(14, w: FontWeight.w900)),
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit_rounded, size: 14, color: NameIdeas.isDefault(name) ? K.brass : K.textSoft),
                ],
              ]),
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

  /// Nothing to show yet. With no internet and nothing saved, explain the one-time need; it retries by itself when the
  /// connection returns. Never a raw error code.
  Widget _errorBox() {
    final f = _failure;
    if (f == null ? !Api.i.online : Api.failKind(f) == FailKind.offline) {
      return StateView.offline(
        key: const ValueKey('home-state'),
        onRetry: _refresh,
        body: 'برای گرفتن اولین پرونده باید یه بار به اینترنت وصل بشی. بعدش پرونده‌هایی که باز کردی بدون اینترنت هم خونده می‌شن؛ سکه و پیشرفتت هم سر جاشه.',
      );
    }
    return StateView.forError(f ?? StateError('cases'), key: const ValueKey('home-state'), onRetry: _refresh);
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
    return GestureDetector(
      key: const ValueKey('home-hero'),
      onTap: () => _open(c),
      child: Container(
        height: 262,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: K.brass.withValues(alpha: 0.4)),
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Stack(fit: StackFit.expand, children: [
            AnimatedScene(scene: c.scene, height: double.infinity),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x0017181A), Color(0xBF17181A), K.night],
                  stops: [0.3, 0.64, 1],
                ),
              ),
            ),
            const Positioned(right: 14, top: 14, child: _NewBadge()),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('امشب · رایگان', style: tBody(12, color: K.brass, w: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(c.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tDisplay(25).copyWith(height: 1.2)),
                const SizedBox(height: 6),
                DifficultyBar(c.difficulty, compact: true),
                const SizedBox(height: 12),
                StampButton(label: 'شروع تحقیقات', icon: Icons.search_rounded, height: 48, onTap: () => _open(c)),
              ]),
            ),
          ]),
        ),
      ),
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

  /// The streak row, only when it asks something of the player: the streak is at risk (tonight is not solved yet and the
  /// streak is 3 nights or more), the next step is one night away, or a broken streak can be repaired.
  Widget _streakRow(CasesList cs) {
    final p = Api.i.profile;
    if (p == null) return const SizedBox.shrink();
    final offer = p.streakRepair;
    final showOffer = offer != null && !Api.i.repairOfferClosed(offer);
    final t = cs.today;
    final next = nextStreakMilestone(p.streak, Api.i.streakMilestones);
    final due = HomeRules.streakDue(
        streak: p.streak,
        tonightOpen: t != null && !t.solved && !t.failed,
        nightsToNext: next == null ? null : next - p.streak,
        repairOffer: showOffer);
    if (!due) return const SizedBox.shrink();
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

  static final Set<String> _giftHidden = {}; // closed with the ✕ in this launch: «case id:player id»

  /// A promo case that is free for this new detective right now: one card under tonight's case, with the time left.
  /// Gone once he opens, solves or loses it, when the hours end, or when he closes it.
  Widget _giftCard(CasesList cs) {
    final c = giftCase(cs.archive, DateTime.now());
    final key = '${c?.id}:${Api.i.playerId}';
    if (c == null || _giftHidden.contains(key)) return const SizedBox.shrink();
    return GiftCaseCard(
      row: c,
      onClose: () => setState(() => _giftHidden.add(key)),
      onOpen: () async {
        await openCaseRow(context, c);
        if (mounted) _load();
      },
    );
  }

  /// An account worth securing: after the 3rd solved case, or after a purchase. The ✕ closes it for 7 days.
  Widget _secureRow() {
    final p = Api.i.profile;
    if (p == null) return const SizedBox.shrink();
    final due = HomeRules.secureDue(
        secured: p.secured,
        casesSolved: p.casesSolved,
        bought: Api.i.hasBought || p.noAds || p.vip,
        closedAt: Api.i.secureRowClosedAt,
        now: DateTime.now());
    if (!due) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        key: const ValueKey('home-secure'),
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: K.brass, width: 1.5)),
          child: Row(children: [
            Expanded(
              child: InkWell(
                key: const ValueKey('secure-open'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => openAccountSheet(context, showSecureSheet),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                  child: Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(color: K.night3, shape: BoxShape.circle),
                      child: const Icon(Icons.shield_rounded, color: K.brass, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('حسابت هنوز امن نیست', style: tBody(15, w: FontWeight.w900)),
                        Text('با شماره‌ات امنش کن و ${fa(Api.i.secureReward)} سکه بگیر',
                            style: tBody(12.5, color: K.textSoft).copyWith(height: 1.6)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('secure-close'),
              tooltip: 'بستن',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => Api.i.closeSecureRow(),
              icon: const Icon(Icons.close_rounded, color: K.textSoft, size: 20),
            ),
          ]),
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
