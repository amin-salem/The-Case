import 'package:flutter/material.dart';
import '../widgets/state_view.dart';
import 'main_shell.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/avatar_frame.dart';
import '../widgets/engagement.dart' show faDuration;
import '../widgets/id_card.dart' show LeagueLook;
import '../widgets/streak_flame.dart';
import '../widgets/player_card_overlay.dart';
import '../services/board_text.dart';

const _bg = Color(0xFF0E0F11);
const _panel = Color(0xFF17181B);
const _line = Color(0x0DFFFFFF);
const _gold = Color(0xFFF4CF73);

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  static const _labels = ['پرونده‌ی امروز', 'این هفته', 'همیشه'];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(children: [
          // a soft brass glow at the top, like the design
          const PositionedDirectional(
            top: -140,
            start: 0,
            end: 0,
            height: 360,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: Alignment(0, -1), radius: .9, colors: [Color(0x29E0A526), Color(0x00E0A526)]),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(children: [
              Builder(builder: (context) {
                final c = DefaultTabController.of(context);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(children: [
                    SizedBox(
                      height: 44,
                      child: Row(children: [
                        Expanded(child: Text('برترها', style: tBody(26, w: FontWeight.w900, color: K.text).copyWith(height: 1.2))),
                        // the long explanation lives behind this «i» (one tap opens, one tap closes)
                        IconButton(
                          key: const ValueKey('lb-info'),
                          tooltip: 'این جدول چطور کار می‌کنه؟',
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                          style: IconButton.styleFrom(backgroundColor: const Color(0x0AFFFFFF), side: const BorderSide(color: Color(0x14FFFFFF))),
                          icon: const Icon(Icons.info_outline_rounded, color: Color(0xFFB9B5AA), size: 20),
                          onPressed: () => showBoardInfo(context, c.index, leagues: _knownLeagues),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),
                    AnimatedBuilder(
                      animation: c.animation!,
                      builder: (_, __) => Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
                        child: Row(children: [
                          for (var i = 0; i < 3; i++)
                            Expanded(
                              child: GestureDetector(
                                key: ValueKey('lb-tab-$i'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => c.animateTo(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: c.animation!.value.round() == i
                                        ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_gold, K.brass])
                                        : null,
                                    boxShadow: c.animation!.value.round() == i ? const [BoxShadow(color: Color(0x40E0A526), blurRadius: 14, offset: Offset(0, 4))] : null,
                                  ),
                                  child: Text(_labels[i],
                                      maxLines: 1,
                                      style: tBody(13.5, w: FontWeight.w900, color: c.animation!.value.round() == i ? const Color(0xFF17120A) : const Color(0xFFB9B5AA))),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ),
                  ]),
                );
              }),
              const Expanded(child: TabBarView(children: [LeaderboardBoard('daily'), LeaderboardBoard('weekly'), LeaderboardBoard('all')])),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The leagues of the last weekly board we loaded (so the «i» in the app bar can list their rank ranges too).
List<LeagueInfo> _knownLeagues = const [];

/// The weekly prizes (server: weekboard.LEAGUE_PRIZES) and the minimum of solved cases for one.
const _kPrizeText = 'اول ۶۰ سکه، دوم ۴۰ سکه، سوم ۲۵ سکه';

/// The full explanation of the boards, in a bottom sheet (opens from the «i» next to the title, closes in one tap).
/// [tab] 0 = today's case, 1 = this week, 2 = all time; the sheet shows that tab's part first.
Future<void> showBoardInfo(BuildContext context, int tab, {List<LeagueInfo> leagues = const []}) {
  final daily = _infoBlock('پرونده‌ی امروز', 'کارآگاه‌هایی که پرونده‌ی امروز رو همون روز حل کردن. ترتیب: پلاک بیشتر بالاتره؛ اگه پلاک‌ها برابر بود، زمان کمتر بالاتره (زیر هر نام می‌بینی)؛ اگه زمان هم برابر بود، اونی که زودتر حل کرده. برای جایگاه جدول باید پرونده رو واقعاً بررسی کرده باشی (بازجویی و مدارک)؛ پلاک و جایزه‌ات در هر حال مال خودته.');
  final all = _infoBlock('همیشه', 'جمع همه‌ی پلاک‌هایی که هر کارآگاه از اول تا حالا گرفته.');
  final weekly = <Widget>[
    _infoBlock('این هفته', 'فقط پرونده‌های همین هفته حساب می‌شن. بایگانی پلاک می‌ده، ولی توی جدول هفتگی نیست.'),
    _infoBlock('ساعت هفته', 'هفته جمعه‌ها ساعت ۲۱ بسته می‌شه، همون لحظه که پرونده‌ی اولِ هفته‌ی بعد باز می‌شه.'),
    _infoBlock('هفته‌ی منصفانه', 'هر پرونده مال هفته‌ای‌ه که منتشر شده. بعد از بسته شدن هفته، حل کردنش دیگه توی جدول هفتگی حساب نمی‌شه.'),
    _infoBlock('لیگ‌ها',
        'هر کارآگاه توی یکی از هشت لیگ بازی می‌کنه: از تازه‌کار تا اسطوره. لیگ هر کس با رتبه‌اش اولِ هفته معلوم می‌شه و تا آخر هفته عوض نمی‌شه؛ '
        'اگه وسط هفته رتبه بگیری، هفته‌ی بعد به لیگ بالاتر می‌ری. رتبه‌ای که کنار اسمت می‌بینی همیشه رتبه‌ی فعلی توئه، مثل پروفایل.'),
    for (final l in leagues)
      if (l.fromRank.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('لیگ ${l.name}: از «${l.fromRank}» تا «${l.toRank}»', style: tBody(12.5, color: K.textSoft)),
        ),
    _infoBlock('جایزه‌ها', 'به ۳ کارآگاه اولِ هر لیگ جایزه می‌رسه: $_kPrizeText. برای جایزه باید دست‌کم ۲ پرونده‌ی همین هفته رو حل کرده باشی.'),
    _infoBlock('ترتیب جدول هفته', 'اول پلاک، بعد تعداد شب‌ها، بعد شب‌های سر وقت، آخرش سرعت. یعنی ۱۰ پلاک توی ۴ شب از ۸ پلاک توی ۵ شب بالاتره؛ سرعت فقط وقتی حساب می‌شه که بقیه‌چیز برابر باشه.'),
    _infoBlock('اگه امتیازها برابر شد', 'اول پلاک بیشتر، بعد شب‌های بیشتر، بعد شب‌های بیشتری که همون شب حل کردی، بعد زمان کمتر، و بعد حسابِ قدیمی‌تر بالاتره.'),
  ];
  final order = tab == 1 ? [...weekly, daily, all] : tab == 2 ? [all, daily, ...weekly] : [daily, all, ...weekly];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: K.night2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: SingleChildScrollView(
          key: const ValueKey('lb-info-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('این جدول چطور کار می‌کنه؟', style: tDisplay(18))),
              IconButton(key: const ValueKey('lb-info-close'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.of(ctx).pop()),
            ]),
            const SizedBox(height: 6),
            ...order,
            const SizedBox(height: 8),
            StampButton(label: 'فهمیدم', onTap: () => Navigator.of(ctx).pop()),
          ]),
        ),
      ),
    ),
  );
}

Widget _infoBlock(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: tBody(14, color: K.brass, w: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(body, style: tBody(13.5, color: K.text)),
      ]),
    );

class LeaderboardBoard extends StatefulWidget {
  const LeaderboardBoard(this.period, {super.key});
  final String period;

  @override
  State<LeaderboardBoard> createState() => _BoardState();
}

class _BoardState extends State<LeaderboardBoard> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  int? _picked; // weekly: the league chosen with the switch (null = my own)
  bool _streak = false; // «همیشه»: the streak board instead of the plaques board
  final List<LeaderRow> _extra = []; // rows of the next pages («بیشتر نشون بده»)
  int? _nextOffset; // null = no more pages
  bool _loadingMore = false;
  String get _period => widget.period == 'all' && _streak ? 'streak' : widget.period;
  Leaderboard? _lb; // the last board we got: the header and the league switch stay on screen while a new one loads
  Object? _error;
  bool _loading = true;
  int _serial = 0; // only the newest request may change the screen

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(first: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && MainShell.tab.value == MainShell.leaderboard && !_loading) {
      _load();
    }
  }

  Future<void> _load({bool first = false}) async {
    final mine = ++_serial;
    if (!first) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final lb = _streak && widget.period == 'all' ? await Api.i.streakBoard() : await Api.i.leaderboard(widget.period, league: _picked);
      if (!mounted || mine != _serial) return;
      if (widget.period == 'weekly' && lb.leagueInfos.isNotEmpty) _knownLeagues = lb.leagueInfos;
      setState(() {
        _lb = lb;
        _extra.clear();
        _nextOffset = lb.nextOffset;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || mine != _serial) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _pick(int? league) {
    _picked = league;
    _load();
  }

  void _setStreak(bool on) {
    if (_streak == on) return;
    _streak = on;
    _load();
  }

  /// The next page of the same board (the server bounds every page and says where the next one starts).
  Future<void> _loadMore() async {
    final off = _nextOffset;
    if (off == null || _loadingMore) return;
    final mine = _serial;
    setState(() => _loadingMore = true);
    try {
      final lb = _streak && widget.period == 'all' ? await Api.i.streakBoard(offset: off) : await Api.i.leaderboard(widget.period, league: _picked, offset: off);
      if (!mounted || mine != _serial) return;
      final seen = {for (final r in [...?_lb?.top, ..._extra]) r.rank};
      setState(() {
        _extra.addAll(lb.top.where((r) => !seen.contains(r.rank)));
        _nextOffset = lb.nextOffset;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false); // the button stays: one more tap tries again
    }
  }

  @override
  bool get wantKeepAlive => true;

  String _value(LeaderRow r) => boardValue(_period, r.value);

  void _openSheet(LeaderRow r) {
    if (r.pid.isEmpty) return; // an old server sends no id: nothing to open
    showPlayerCard(context, r);
  }

  Widget _errorView(Object e) => StateView.forError(e, key: const ValueKey('lb-state'), onRetry: () => _load());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lb = _lb;
    if (lb == null) {
      if (_error != null) return _errorView(_error!);
      return const Center(child: CircularProgressIndicator(color: K.brass));
    }
    final weekly = widget.period == 'weekly';
    final all = [...lb.top, ..._extra];
    final podium = all.where((r) => r.rank >= 1 && r.rank <= 3).toList();
    final rest = all.where((r) => r.rank > 3).toList();
    LeaderRow? me = lb.me;
    for (final r in all) {
      if (r.me) me = r;
    }
    final selected = _picked ?? lb.myLeague;
    final selName = selected != null && selected >= 0 && selected < lb.leagues.length ? lb.leagues[selected] : '';
    final body = <Widget>[
      if (widget.period == 'daily') ..._dailyHeader(lb),
      if (widget.period == 'all') ..._allHeader(lb),
      if (weekly) ..._weeklyHeader(lb, selected),
      if (_loading)
        const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator(color: K.brass)))
      else if (_error != null)
        SizedBox(height: 400, child: _errorView(_error!))
      else if (all.isEmpty)
        StateView.empty(
          key: const ValueKey('lb-empty'),
          icon: Icons.emoji_events_outlined,
          title: 'جدول هنوز خالیه',
          body: weekly && selName.isNotEmpty
              ? 'هنوز هیچ کارآگاهی توی لیگ $selName پرونده‌ی این هفته رو حل نکرده. اولیش تو باش!'
              : 'هنوز کسی حل نکرده. اولین کارآگاه باش!',
          primaryLabel: 'برو سراغ پرونده‌ی امشب',
          onPrimary: () => MainShell.tab.value = MainShell.home,
        )
      else ...[
        if (podium.isNotEmpty) _podium(podium, prizes: weekly),
        if (rest.isNotEmpty)
          Container(
            decoration: BoxDecoration(color: const Color(0xFF15161A), borderRadius: BorderRadius.circular(20), border: Border.all(color: _line)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [for (final r in rest) _row(r)]),
          ),
        if (_nextOffset != null)
          OutlinedButton(
            key: const ValueKey('lb-more'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _loadingMore ? null : _loadMore,
            child: _loadingMore
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: K.brass))
                : const Text('بیشتر نشون بده'),
          ),
      ],
    ];
    final showMe = me != null && me.rank > 0 && !_loading;
    return Stack(children: [
      RefreshIndicator(
        onRefresh: () => _load(),
        color: K.brass,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 2, 16, showMe ? 112 : 24),
          itemCount: body.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (_, i) => body[i],
        ),
      ),
      if (showMe)
        PositionedDirectional(
          start: 12,
          end: 12,
          bottom: 14,
          child: SafeArea(top: false, child: _pinned(me, lb, leagues: weekly && lb.leagues.isNotEmpty)),
        ),
    ]);
  }

  /// Daily board: one card with the case's name and two small chips (how many solved, the middle time).
  List<Widget> _dailyHeader(Leaderboard lb) {
    final d = lb.daily;
    final title = lb.title.replaceFirst(RegExp(r'^پرونده‌ی امروز:\s*'), '');
    // Minimal: a small flat card, the case name and one quiet line (no pills, no big gradient box).
    Widget stat(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: _gold),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: tBody(12.5, w: FontWeight.w800, color: K.textSoft))),
        ]);
    return [
      Container(
        key: const ValueKey('daily-stats'),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(17, w: FontWeight.w900, color: K.text).copyWith(height: 1.4)),
          if (d != null && d.solved > 0)
            Wrap(key: const ValueKey('daily-stats-line'), spacing: 14, runSpacing: 2, children: [
              stat(Icons.groups_rounded, '${fa(d.solved)} کارآگاه'),
              if (d.mean != null) stat(Icons.timer_outlined, 'میانگین ${boardTime(d.mean!)}')
              else if (d.median != null) stat(Icons.timer_outlined, 'میانه ${boardTime(d.median!)}'),
            ]),
        ]),
      ),
    ];
  }

  /// «همیشه»: the plaques board or the streak board (live streaks only), as a small pill switch.
  List<Widget> _allHeader(Leaderboard lb) => [
        Center(
          child: Container(
            width: 230,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(99), border: Border.all(color: _line)),
            child: Row(children: [
              for (final m in [(false, 'پلاک‌ها', 'mode-stars'), (true, 'زنجیره', 'mode-streak')])
                Expanded(
                  child: GestureDetector(
                    key: ValueKey(m.$3),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _setStreak(m.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: _streak == m.$1 ? K.brass : Colors.transparent),
                      child: Text(m.$2, style: tBody(13, w: FontWeight.w900, color: _streak == m.$1 ? const Color(0xFF17120A) : const Color(0xFFB9B5AA))),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        if (_streak && lb.myBest > 0)
          Center(child: Text('رکورد خودت: ${fa(lb.myBest)} شب', key: const ValueKey('streak-sub'), style: tBody(12.5, color: K.textSoft))),
      ];

  String _weekLeft(Duration d) => d.inHours >= 24 ? '${fa(d.inDays)} روز و ${fa(d.inHours % 24)} ساعت' : faDuration(d.inSeconds);

  /// The weekly board: the eight league shields in one row. The chosen one is large and lit, the ones the player has
  /// reached are in colour, the ones ahead are grey. Only the chosen league's name is written.
  List<Widget> _weeklyHeader(Leaderboard lb, int? selected) {
    final end = lb.weekEndsAt;
    final left = end?.difference(DateTime.now());
    return [
      if (lb.leagues.isNotEmpty) ...[
        SizedBox(
          height: 74,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [for (int i = 0; i < lb.leagues.length; i++) Expanded(child: _leagueShield(i, lb, selected))],
          ),
        ),
        if (selected != null && selected >= 0 && selected < lb.leagues.length)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Center(child: Text('لیگ ${lb.leagues[selected]}', key: const ValueKey('league-name'), style: tBody(15, w: FontWeight.w900))),
          ),
      ],
      if (left != null && !left.isNegative)
        Center(
          child: Container(
            key: const ValueKey('week-left'),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(99), border: Border.all(color: _line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.timer_outlined, size: 15, color: K.brass),
              const SizedBox(width: 7),
              Text('${_weekLeft(left)} تا پایان هفته', style: tBody(12.5, w: FontWeight.w800, color: const Color(0xFFCFCABE))),
            ]),
          ),
        ),
    ];
  }

  Widget _leagueShield(int i, Leaderboard lb, int? selected) {
    final on = selected == i;
    final look = LeagueLook.of(i);
    final reached = i <= (lb.myLeague ?? 0);
    final size = on ? 54.0 : 30.0;
    Widget img = Image.asset(look.shield, width: size, height: size, fit: BoxFit.contain);
    if (!reached && !on) {
      img = Opacity(opacity: 0.45, child: ColorFiltered(colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation), child: img));
    } else if (on) {
      img = DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: look.glow.withValues(alpha: 0.55), blurRadius: 18)]),
        child: img,
      );
    }
    return GestureDetector(
      key: ValueKey('league-$i'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _pick(i == lb.myLeague ? null : i),
      child: Semantics(
        selected: on,
        label: lb.leagues[i],
        child: SizedBox(
          width: double.infinity,
          height: 56 + (on ? 14 : 0),
          child: Stack(alignment: Alignment.bottomCenter, children: [
            if (on) SizedBox.shrink(key: ValueKey('league-on-$i')),
            Padding(padding: const EdgeInsets.only(bottom: 10), child: img),
            if (lb.myLeague == i)
              Container(key: ValueKey('league-me-$i'), width: 6, height: 6, decoration: const BoxDecoration(color: K.brass, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }

  static const _silver = Color(0xFFC9CED8);
  static const _bronze = Color(0xFFCD8B52);
  static const _prizes = {1: 60, 2: 40, 3: 25};

  Color _medal(int rank) => switch (rank) { 1 => K.brass, 2 => _silver, 3 => _bronze, _ => K.night3 };

  /// Daily board: plaques first, and under them his solve time (the tie-breaker made visible: equal plaques, less time = higher).
  /// An old server sends no time (0): then only the plaques show.
  Widget _dailyEnd(LeaderRow r, {double size = 16, Color? color}) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        _shields(r.stars, size),
        if (r.value > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(boardTime(r.value), key: ValueKey('time-${r.rank}'), maxLines: 1, style: tBody(11.5, w: FontWeight.w800, color: color ?? const Color(0xFF9C998F))),
          ),
      ]);

  Widget _shields(int count, double size) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < 3; i++)
          Icon(Icons.shield_rounded, size: size, color: i < count ? K.brass : const Color(0xFF3A3B3F)),
      ]);

  /// The top three on the stage: 2 – 1 – 3, the first one raised and crowned; weekly shows the prize on each step.
  Widget _podium(List<LeaderRow> top, {bool prizes = false}) {
    LeaderRow? at(int rank) {
      for (final r in top) {
        if (r.rank == rank) return r;
      }
      return null;
    }

    Widget place(int rank) {
      final r = at(rank);
      if (r == null) return const Expanded(child: SizedBox());
      final first = rank == 1;
      final ring = _medal(rank);
      final face = first ? 104.0 : 82.0;
      return Expanded(
        child: InkWell(
          key: ValueKey('podium-$rank'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openSheet(r),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (first) const CustomPaint(size: Size(34, 24), painter: _CrownPainter()),
            SizedBox(
              width: face,
              height: face,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.4), blurRadius: first ? 30 : 18)]),
                  child: SizedBox(width: face * 0.8, height: face * 0.8),
                ),
                AvatarWithFrame(avatar: r.avatarId, frame: r.avatarFrame, size: face, animate: true),
                Positioned(
                  bottom: -6,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: ring, border: Border.all(color: _bg, width: 2)),
                    child: Text(fa(rank), style: tBody(13, w: FontWeight.w900, color: const Color(0xFF17120A)).copyWith(height: 1.1)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(r.me ? 'تو' : r.nickname, maxLines: 1, textAlign: TextAlign.center, style: tBody(13.5, w: FontWeight.w900, color: K.text)),
            ),
            if (r.weekend && _period == 'weekly') Padding(padding: const EdgeInsets.only(top: 3), child: _weekendTag(podium: rank)),
            SizedBox(
              height: _period == 'daily' ? 40 : 22,
              child: Center(
                child: _period == 'daily'
                    ? FittedBox(fit: BoxFit.scaleDown, child: _dailyEnd(r, size: 15, color: ring))
                    : Text(_value(r), maxLines: 1, style: tBody(12.5, color: ring, w: FontWeight.w900)),
              ),
            ),
            Container(
              height: switch (rank) { 1 => 54.0, 2 => 40.0, _ => 30.0 },
              margin: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 9),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14), bottom: Radius.circular(4)),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [ring.withValues(alpha: 0.28), const Color(0x3317181B)]),
                border: Border(top: BorderSide(color: ring)),
              ),
              child: prizes
                  ? Container(
                      key: ValueKey('prize-$rank'),
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 9),
                      decoration: BoxDecoration(color: const Color(0x800A0A0C), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0x59F4CF73))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.monetization_on_rounded, size: 13, color: K.brass),
                        const SizedBox(width: 4),
                        Text(fa(_prizes[rank]!), style: tBody(11.5, w: FontWeight.w900, color: _gold).copyWith(height: 1.1)),
                      ]),
                    )
                  : null,
            ),
          ]),
        ),
      );
    }

    // children run right to left: 2 on the right, 1 in the middle, 3 on the left
    return Stack(children: [
      Positioned.fill(
        top: -24,
        child: IgnorePointer(
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black, Colors.black, Colors.transparent], stops: [0, .55, 1]).createShader(r),
            blendMode: BlendMode.dstIn,
            child: Image.asset('assets/banners/podium_stage.webp', fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [place(2), place(1), place(3)]),
      ),
    ]);
  }

  /// The player's own row: a floating bar at the bottom with his place, how far the next place is and a thin bar.
  Widget _pinned(LeaderRow me, Leaderboard lb, {bool leagues = false}) {
    final n = leagues ? 3 : 10;
    final inTop = me.rank >= 1 && me.rank <= n;
    final gap = lb.gap;
    final line = gapLine(gap) ?? (inTop ? 'جزو ${fa(n)} کارآگاه اول${leagues ? ' لیگ' : ''}! 🏆' : '${fa(me.rank - n)} رتبه مونده تا ${fa(n)} کارآگاه اول${leagues ? ' لیگ' : ''}');
    // how close he is to the place above: my score against the score of that place
    double progress = inTop && gap == null ? 1 : 0;
    if (gap != null && gap.diff > 0) {
      final mine = me.value.toDouble();
      final target = gap.unit == 'seconds' ? (mine - gap.diff) : (mine + gap.diff);
      progress = target <= 0 || mine <= 0 ? 0 : (gap.unit == 'seconds' ? target / mine : mine / target).clamp(0.0, 1.0);
    }
    return Container(
      key: const ValueKey('lb-me'),
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xEB221C11),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: K.brass.withValues(alpha: 0.38)),
        boxShadow: const [BoxShadow(color: Color(0x8C000000), blurRadius: 40, offset: Offset(0, 18))],
      ),
      child: Row(children: [
        SizedBox(width: 34, child: Text(fa(me.rank), textAlign: TextAlign.center, maxLines: 1, style: tBody(22, w: FontWeight.w900, color: _gold))),
        const SizedBox(width: 12),
        AvatarWithFrame(avatar: me.avatarId, frame: me.avatarFrame, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Text('تو', style: tBody(14.5, w: FontWeight.w900, color: K.text)),
              const SizedBox(width: 8),
              Expanded(child: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: tBody(12, w: FontWeight.w800, color: const Color(0xFFE7DCC0)))),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: const Color(0x1AFFFFFF), color: K.brass),
            ),
          ]),
        ),
      ]),
    );
  }

  /// «آخر هفته»: solved this week's weekend case (one small brass outline, no icon, no more words).
  Widget _weekendTag({int? podium}) => Container(
        key: ValueKey(podium == null ? 'weekend-tag' : 'weekend-tag-$podium'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: K.brass.withValues(alpha: 0.7))),
        child: Text('آخر هفته', maxLines: 1, style: tBody(10.5, w: FontWeight.w900, color: K.brass)),
      );

  Widget _row(LeaderRow r) {
    final daily = _period == 'daily';
    final content = Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: r.me ? const Color(0x1AE0A526) : null, border: const Border(bottom: BorderSide(color: Color(0x0BFFFFFF)))),
      child: Row(children: [
        SizedBox(width: 24, child: Text(fa(r.rank), textAlign: TextAlign.center, maxLines: 1, style: tBody(14, w: FontWeight.w900, color: const Color(0xFF8E8B82)))),
        const SizedBox(width: 12),
        AvatarWithFrame(avatar: r.avatarId, frame: r.avatarFrame, size: 46),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // a long name gets smaller instead of ending in «…»
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(r.me ? '${r.nickname} (تو)' : r.nickname, maxLines: 1, style: tBody(14, w: FontWeight.w800, color: K.text)),
                ),
              ),
              if (r.streak >= 2) ...[const SizedBox(width: 6), StreakFlame(r.streak, size: 12)],
            ]),
            if (r.rankTitle.isNotEmpty || r.weekend)
              Row(children: [
                if (r.rankTitle.isNotEmpty)
                  Flexible(child: Text(r.rankTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11.5, w: FontWeight.w700, color: const Color(0xFFA59C83)))),
                if (r.weekend) ...[
                  if (r.rankTitle.isNotEmpty) const SizedBox(width: 6),
                  _weekendTag(),
                ],
              ]),
          ]),
        ),
        if (daily) _dailyEnd(r) else Text(_value(r), style: tBody(14, color: K.brass, w: FontWeight.w900)),
      ]),
    );
    if (r.pid.isEmpty) return content;
    // the avatar and the whole row open his card (a 64 px tall target)
    return InkWell(key: ValueKey('row-${r.rank}'), onTap: () => _openSheet(r), child: content);
  }
}

/// A small brass crown over the first place.
class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.95)
      ..lineTo(0, h * 0.25)
      ..lineTo(w * 0.3, h * 0.55)
      ..lineTo(w * 0.5, 0)
      ..lineTo(w * 0.7, h * 0.55)
      ..lineTo(w, h * 0.25)
      ..lineTo(w * 0.92, h * 0.95)
      ..close();
    c.drawPath(path, Paint()..color = K.brass);
    c.drawRect(Rect.fromLTWH(w * 0.08, h * 0.8, w * 0.84, h * 0.15), Paint()..color = const Color(0xFF9C7420));
    final dot = Paint()..color = K.stamp;
    c.drawCircle(Offset(w * 0.5, h * 0.6), h * 0.1, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
