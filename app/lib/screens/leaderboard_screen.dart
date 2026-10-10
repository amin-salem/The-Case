import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/character.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: K.night,
          title: Text('کارآگاه‌های برتر', style: tDisplay(20)),
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
            child: TabBarView(children: [_Board('daily'), _Board('weekly'), _Board('all')]),
          ),
        ),
      ),
    );
  }
}

class _Board extends StatefulWidget {
  const _Board(this.period);
  final String period;

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> with AutomaticKeepAliveClientMixin {
  late Future<Leaderboard> _f = Api.i.leaderboard(widget.period);

  @override
  bool get wantKeepAlive => true;

  String _value(LeaderRow r) {
    if (widget.period != 'daily') return '${fa(r.value)} ستاره';
    final m = r.value ~/ 60, s = r.value % 60;
    return '${fa(m)}:${fa(s).padLeft(2, '۰')}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<Leaderboard>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: K.brass));
        }
        if (snap.hasError) {
          final e = snap.error!;
          final msg = !Api.i.online && Api.isNetworkFail(e) ? Api.needOnlineText : Api.friendly(e);
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(msg, textAlign: TextAlign.center, style: tBody(15)),
              const SizedBox(height: 10),
              StampButton(label: 'دوباره', onTap: () => setState(() => _f = Api.i.leaderboard(widget.period))),
              ]),
            ),
          );
        }
        final lb = snap.data!;
        final podium = lb.top.where((r) => r.rank <= 3).toList();
        final rest = lb.top.where((r) => r.rank > 3).toList();
        LeaderRow? me = lb.me;
        for (final r in lb.top) {
          if (r.me) me = r;
        }
        return Column(children: [
          Expanded(
            child: lb.top.isEmpty
                ? Center(child: Text('هنوز کسی حل نکرده. اولین نفر باش!', textAlign: TextAlign.center, style: tBody(15)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    children: [
                      if (widget.period == 'daily')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${lb.title} · بیشترین ستاره و کمترین زمان',
                              textAlign: TextAlign.center, style: tBody(12.5, color: K.textSoft)),
                        ),
                      if (podium.isNotEmpty) _podium(podium),
                      const SizedBox(height: 12),
                      for (final r in rest) _row(r),
                    ],
                  ),
          ),
          if (me != null && me.rank > 0) _pinned(me),
        ]);
      },
    );
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
              color: K.night3,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 3),
              boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.35), blurRadius: first ? 18 : 10)],
            ),
            child: DetectiveFace(r.avatar, size: face),
          ),
          const SizedBox(height: 6),
          Text(r.me ? 'تو' : r.nickname,
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: tBody(13.5, w: FontWeight.w900)),
          if (widget.period == 'daily') Stars(count: r.stars, size: 13),
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
  Widget _pinned(LeaderRow me) {
    final inTop = me.rank >= 1 && me.rank <= 10;
    final line = inTop ? 'جزو ۱۰ نفر اولی! 🏆' : '${fa(me.rank - 10)} رتبه مونده تا ۱۰ نفر اول';
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
        DetectiveFace(r.avatar, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title ?? (r.me ? '${r.nickname} (تو)' : r.nickname),
                style: tBody(pinned ? 14 : 15, w: FontWeight.w900, color: pinned ? K.brass : K.text),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (r.rankTitle.isNotEmpty || pinned)
              Text(pinned ? r.nickname : r.rankTitle,
                  style: tBody(11.5, color: pinned ? K.textSoft : K.brass), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (widget.period == 'daily') ...[Stars(count: r.stars, size: 16), const SizedBox(width: 8)],
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
