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
        return Column(children: [
          if (widget.period == 'daily')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('${lb.title}\nبیشترین ستاره و کمترین زمان', textAlign: TextAlign.center, style: tBody(13, color: K.textSoft)),
            ),
          Expanded(
            child: lb.top.isEmpty
                ? Center(child: Text('هنوز کسی حل نکرده. اولین نفر باش!', textAlign: TextAlign.center, style: tBody(15)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: lb.top.length,
                    itemBuilder: (_, i) => _row(lb.top[i]),
                  ),
          ),
          if (lb.me != null && !lb.top.any((r) => r.me)) Padding(padding: const EdgeInsets.all(16), child: _row(lb.me!)),
        ]);
      },
    );
  }

  Widget _row(LeaderRow r) {
    final medal = switch (r.rank) { 1 => K.brass, 2 => const Color(0xFFC9CED8), 3 => const Color(0xFFCD8B52), _ => K.night3 };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: r.me ? const Color(0xFF2E2416) : K.night2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: r.me ? K.brass : K.night3),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: medal, shape: BoxShape.circle),
          child: Text(fa(r.rank), style: tBody(13, color: r.rank <= 3 ? K.ink : K.text, w: FontWeight.w900)),
        ),
        const SizedBox(width: 10),
        DetectiveFace(r.avatar, size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(r.me ? '${r.nickname} (تو)' : r.nickname,
                style: tBody(15, w: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (r.rankTitle.isNotEmpty)
              Text(r.rankTitle, style: tBody(11.5, color: K.brass), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (widget.period == 'daily') ...[Stars(count: r.stars, size: 16), const SizedBox(width: 8)],
        Text(_value(r), style: tBody(14, color: K.brass, w: FontWeight.w900)),
      ]),
    );
  }
}
