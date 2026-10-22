import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/profile_bell.dart';
import '../widgets/avatar_frame.dart';
import '../widgets/engagement.dart' show faDuration;
import '../widgets/streak_flame.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: K.night,
          leadingWidth: 64,
          leading: const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Center(child: ProfileBell(size: 34))),
          // the long explanation lives behind the «i» next to the title (one tap opens, one tap closes)
          title: Builder(
            builder: (context) => Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text('کارآگاه‌های برتر', style: tDisplay(20), overflow: TextOverflow.ellipsis)),
              IconButton(
                key: const ValueKey('lb-info'),
                tooltip: 'این جدول چطور کار می‌کنه؟',
                icon: const Icon(Icons.info_outline_rounded, color: K.brass),
                onPressed: () => showBoardInfo(context, DefaultTabController.of(context).index, leagues: _knownLeagues),
              ),
            ]),
          ),
          bottom: TabBar(
            indicatorColor: K.stamp,
            labelStyle: tBody(14, w: FontWeight.w900),
            labelColor: K.text,
            unselectedLabelColor: K.textSoft,
            tabs: const [Tab(text: 'پرونده‌ی امروز'), Tab(text: 'این هفته'), Tab(text: 'همیشه')],
          ),
        ),
        body: const GrainBackground(
          // SafeArea: the player's own row at the bottom stays above the phone's navigation bar
          child: SafeArea(
            top: false,
            child: TabBarView(children: [LeaderboardBoard('daily'), LeaderboardBoard('weekly'), LeaderboardBoard('all')]),
          ),
        ),
      ),
    );
  }
}

/// The leagues of the last weekly board we loaded (so the «i» in the app bar can list their rank ranges too).
List<LeagueInfo> _knownLeagues = const [];

/// The weekly prizes (server: weekboard.LEAGUE_PRIZES) and the minimum of solved cases for one.
const _kPrizeText = 'اول ۱۲۰ سکه، دوم ۸۰ سکه، سوم ۵۰ سکه';

/// The full explanation of the boards, in a bottom sheet (opens from the «i» next to the title, closes in one tap).
/// [tab] 0 = today's case, 1 = this week, 2 = all time; the sheet shows that tab's part first.
Future<void> showBoardInfo(BuildContext context, int tab, {List<LeagueInfo> leagues = const []}) {
  final daily = _infoBlock('پرونده‌ی امروز', 'کارآگاه‌هایی که پرونده‌ی امروز رو همون روز حل کردن؛ بیشترین پلاک و بعد کمترین زمان بالاتره. برای جایگاه جدول باید پرونده رو واقعاً بررسی کرده باشی (بازجویی و مدارک)؛ پلاک و جایزه‌ات در هر حال مال خودته.');
  final all = _infoBlock('همیشه', 'جمع همه‌ی پلاک‌هایی که هر کارآگاه از اول تا حالا گرفته.');
  final weekly = <Widget>[
    _infoBlock('این هفته', 'فقط پرونده‌های همین هفته حساب می‌شن. بایگانی پلاک می‌ده، ولی توی جدول هفتگی نیست.'),
    _infoBlock('ساعت هفته', 'هفته جمعه‌ها ساعت ۲۱ بسته می‌شه، همون لحظه که پرونده‌ی اولِ هفته‌ی بعد باز می‌شه.'),
    _infoBlock('هفته‌ی منصفانه', 'هر پرونده مال هفته‌ای‌ه که منتشر شده. بعد از بسته شدن هفته، حل کردنش دیگه توی جدول هفتگی حساب نمی‌شه.'),
    _infoBlock('لیگ‌ها',
        'هر کارآگاه توی یکی از چهار لیگ بازی می‌کنه: تازه‌کار، کارآگاه، بازرس و سرپرست. لیگ هر کس با رتبه‌اش اولِ هفته معلوم می‌شه و تا آخر هفته عوض نمی‌شه؛ '
        'اگه وسط هفته رتبه بگیری، هفته‌ی بعد به لیگ بالاتر می‌ری. رتبه‌ای که کنار اسمت می‌بینی همیشه رتبه‌ی فعلی توئه، مثل پروفایل.'),
    for (final l in leagues)
      if (l.fromRank.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('لیگ ${l.name}: از «${l.fromRank}» تا «${l.toRank}»', style: tBody(12.5, color: K.textSoft)),
        ),
    _infoBlock('جایزه‌ها', 'به ۳ کارآگاه اولِ هر لیگ جایزه می‌رسه: $_kPrizeText. برای جایزه باید دست‌کم ۲ پرونده‌ی همین هفته رو حل کرده باشی.'),
    _infoBlock('ترتیب جدول هفته', 'جدول هفته به پیوستگی جایزه می‌ده، نه به عجله: اول تعداد شب‌هایی که پرونده حل کردی، بعد شب‌هایی که همون شب حل کردی، بعد پلاک بیشتر. سرعت فقط وقتی حساب می‌شه که همه‌چیز برابر باشه.'),
    _infoBlock('اگه امتیازها برابر شد', 'اول شب‌های حل‌شده‌ی بیشتر، بعد شب‌های حل‌شده در همون شب، بعد پلاک بیشتر، بعد زمان کمتر، و بعد حسابِ قدیمی‌تر بالاتره.'),
    _infoBlock('قرعه‌ی شبانه', 'بین کارآگاه‌هایی که پرونده‌ی هر شب رو با ۳ پلاک و بررسی کامل حل کنن، فردا یک نفر قرعه‌کشی می‌شه و یک حکم بازرسی هدیه می‌گیره. سرعت توی قرعه نقشی نداره.'),
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

class _BoardState extends State<LeaderboardBoard> with AutomaticKeepAliveClientMixin {
  int? _picked; // weekly: the league chosen with the switch (null = my own)
  Leaderboard? _lb; // the last board we got: the header and the league switch stay on screen while a new one loads
  Object? _error;
  bool _loading = true;
  int _serial = 0; // only the newest request may change the screen

  @override
  void initState() {
    super.initState();
    _load(first: true);
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
      final lb = await Api.i.leaderboard(widget.period, league: _picked);
      if (!mounted || mine != _serial) return;
      if (widget.period == 'weekly' && lb.leagueInfos.isNotEmpty) _knownLeagues = lb.leagueInfos;
      setState(() {
        _lb = lb;
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

  @override
  bool get wantKeepAlive => true;

  String _value(LeaderRow r) {
    if (widget.period != 'daily') return '${fa(r.value)} پلاک';
    final m = r.value ~/ 60, s = r.value % 60;
    return '${fa(m)}:${fa(s).padLeft(2, '۰')}';
  }

  Widget _errorView(Object e) {
    final msg = !Api.i.online && Api.isNetworkFail(e) ? Api.needOnlineText : Api.friendly(e);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(msg, textAlign: TextAlign.center, style: tBody(15)),
          const SizedBox(height: 10),
          StampButton(label: 'دوباره', onTap: () => _load()),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lb = _lb;
    if (lb == null) {
      if (_error != null) return _errorView(_error!);
      return const Center(child: CircularProgressIndicator(color: K.brass));
    }
    final weekly = widget.period == 'weekly';
    final podium = lb.top.where((r) => r.rank <= 3).toList();
    final rest = lb.top.where((r) => r.rank > 3).toList();
    LeaderRow? me = lb.me;
    for (final r in lb.top) {
      if (r.me) me = r;
    }
    final selected = _picked ?? lb.myLeague;
    final selName = selected != null && selected >= 0 && selected < lb.leagues.length ? lb.leagues[selected] : '';
    // the header (one short line + the league switch) is ALWAYS built, whatever the chosen league holds
    final body = <Widget>[
      if (widget.period == 'daily')
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text('${lb.title} · بیشترین پلاک و کمترین زمان', textAlign: TextAlign.center, style: tBody(12.5, color: K.textSoft)),
        ),
      if (weekly) ..._weeklyHeader(lb, selected),
      if (_loading)
        const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator(color: K.brass)))
      else if (_error != null)
        SizedBox(height: 220, child: _errorView(_error!))
      else if (lb.top.isEmpty)
        Padding(
          key: const ValueKey('lb-empty'),
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Text(
              weekly && selName.isNotEmpty
                  ? 'هنوز هیچ کارآگاهی توی لیگ $selName پرونده‌ی این هفته رو حل نکرده. اولیش تو باش!'
                  : 'هنوز کسی حل نکرده. اولین کارآگاه باش!',
              textAlign: TextAlign.center,
              style: tBody(15)),
        )
      else ...[
        if (podium.isNotEmpty) _podium(podium),
        const SizedBox(height: 12),
        for (final r in rest) _row(r),
      ],
    ];
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), children: body)),
      if (me != null && me.rank > 0 && !_loading) _pinned(me, leagues: weekly && lb.leagues.isNotEmpty),
    ]);
  }

  String _weekLeft(Duration d) => d.inHours >= 24
      ? '${fa(d.inDays)} روز و ${fa(d.inHours % 24)} ساعت'
      : faDuration(d.inSeconds);

  /// The weekly board: ONE short line (what it is and when the week ends) and the league switch.
  /// The long explanation is behind the «i» in the app bar.
  List<Widget> _weeklyHeader(Leaderboard lb, int? selected) {
    final end = lb.weekEndsAt;
    final left = end?.difference(DateTime.now());
    final line = left != null && !left.isNegative
        ? 'پلاک‌های پرونده‌های همین هفته · ${_weekLeft(left)} دیگه بسته می‌شه'
        : 'پلاک‌های پرونده‌های همین هفته';
    return [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(child: Text(line, textAlign: TextAlign.center, style: tBody(12.5, color: K.brass, w: FontWeight.w700))),
        const SizedBox(width: 4),
        InkResponse(
          key: const ValueKey('lb-info-inline'),
          radius: 20,
          onTap: () => showBoardInfo(context, 1, leagues: lb.leagueInfos),
          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.info_outline_rounded, size: 17, color: K.textSoft)),
        ),
      ]),
      if (lb.leagues.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
          for (int i = 0; i < lb.leagues.length; i++)
            ChoiceChip(
              key: ValueKey('league-$i'),
              label: Text(lb.leagues[i] + (lb.myLeague == i ? ' (تو)' : ''), style: tBody(12.5, w: FontWeight.w900)),
              selected: selected == i,
              selectedColor: K.brass,
              backgroundColor: K.night2,
              onSelected: (_) => _pick(i == lb.myLeague ? null : i),
            ),
        ]),
      ],
      const SizedBox(height: 10),
    ];
  }

  static const _silver = Color(0xFFC9CED8);
  static const _bronze = Color(0xFFCD8B52);

  Color _medal(int rank) => switch (rank) { 1 => K.brass, 2 => _silver, 3 => _bronze, _ => K.night3 };

  /// The top three: 2 – 1 – 3, the first one raised with a crown.
  Widget _podium(List<LeaderRow> top) {
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
      final face = first ? 72.0 : 58.0;
      return Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (first) const CustomPaint(size: Size(34, 22), painter: _CrownPainter()),
          if (first) const SizedBox(height: 2),
          Container(
            width: face + 8,
            height: face + 8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.35), blurRadius: first ? 18 : 10)],
            ),
            child: AvatarWithFrame(avatar: r.avatarId, frame: r.avatarFrame, size: face + 8, animate: true),
          ),
          const SizedBox(height: 6),
          Text(r.me ? 'تو' : r.nickname,
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: tBody(13.5, w: FontWeight.w900)),
          if (widget.period == 'daily') Plaques(count: r.stars, size: 13),
          Text(_value(r), maxLines: 1, style: tBody(12.5, color: ring, w: FontWeight.w900)),
          const SizedBox(height: 4),
          Container(
            height: switch (rank) { 1 => 54.0, 2 => 40.0, _ => 30.0 },
            margin: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ring.withValues(alpha: 0.2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(top: BorderSide(color: ring, width: 2)),
            ),
            child: Text(fa(rank), style: tDisplay(first ? 24 : 19, color: ring)),
          ),
        ]),
      );
    }

    // children run right to left: 2 on the right, 1 in the middle, 3 on the left
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [place(2), place(1), place(3)]);
  }

  /// The player's own row, always at the bottom.
  Widget _pinned(LeaderRow me, {bool leagues = false}) {
    // weekly with leagues: the prizes go to the first 3 of each league
    final n = leagues ? 3 : 10;
    final inTop = me.rank >= 1 && me.rank <= n;
    final line = inTop ? 'جزو ${fa(n)} کارآگاه اول${leagues ? ' لیگ' : ''}! 🏆' : '${fa(me.rank - n)} رتبه مونده تا ${fa(n)} کارآگاه اول${leagues ? ' لیگ' : ''}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(color: K.night2, border: Border(top: BorderSide(color: K.night3))),
      child: _row(me, title: line),
    );
  }

  Widget _row(LeaderRow r, {String? title}) {
    final medal = _medal(r.rank);
    final pinned = title != null;
    return Container(
      margin: EdgeInsets.only(bottom: pinned ? 0 : 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: r.me ? const Color(0xFF2E2416) : K.night2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: r.me ? K.brass : K.night3),
      ),
      child: Row(children: [
        Container(
          constraints: const BoxConstraints(minWidth: 32),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: medal, borderRadius: BorderRadius.circular(99)),
          child: Text(fa(r.rank), style: tBody(13, color: r.rank <= 3 ? K.ink : K.text, w: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        AvatarWithFrame(avatar: r.avatarId, frame: r.avatarFrame, size: 44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Flexible(
                child: Text(title ?? (r.me ? '${r.nickname} (تو)' : r.nickname),
                    style: tBody(pinned ? 14 : 15, w: FontWeight.w900, color: pinned ? K.brass : K.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (!pinned && r.streak >= 2) ...[const SizedBox(width: 6), StreakFlame(r.streak, size: 13)],
            ]),
            if (r.rankTitle.isNotEmpty || pinned)
              Text(pinned ? [r.nickname, if (r.rankTitle.isNotEmpty) r.rankTitle, if (r.leagueName.isNotEmpty) 'لیگ ${r.leagueName}'].join(' · ') : r.rankTitle,
                  style: tBody(11.5, color: pinned ? K.textSoft : K.brass), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (widget.period == 'daily') ...[Plaques(count: r.stars, size: 16), const SizedBox(width: 8)],
        Text(_value(r), style: tBody(14, color: K.brass, w: FontWeight.w900)),
      ]),
    );
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
