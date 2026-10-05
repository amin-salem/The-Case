import 'dart:async';

import 'package:flutter/material.dart';

import '../models/progress.dart';
import '../services/api.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/offline.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import 'dialogs.dart';

/// Today's quick riddles («معمای سریع»): one-minute mini mysteries, the same for everyone.
class RiddlesScreen extends StatefulWidget {
  const RiddlesScreen({super.key});

  @override
  State<RiddlesScreen> createState() => _RiddlesScreenState();
}

class _RiddlesScreenState extends State<RiddlesScreen> {
  RiddleDay? _day;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final d = _day;
      if (d != null && DateTime.now().isAfter(d.nextAt.add(const Duration(seconds: 2))) && Api.i.online) {
        _day = null; // a new day: a new set
        _load();
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.i.riddles();
      if (!mounted) return;
      setState(() {
        _day = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = Api.friendly(e));
    }
  }

  Future<void> _open(RiddleItem r) async {
    var item = r;
    if (r.locked) {
      if (!needOnline(context)) return;
      final cost = _day!.unlockCost;
      final ok = await confirm(context, 'معمای ${fa(r.slot)}', 'معماهای رایگان امروز تموم شد. این یکی رو با ${fa(cost)} سکه باز کن.', 'باز کن');
      if (!ok || !mounted) return;
      try {
        item = await Api.i.unlockRiddle(r.id);
      } on ApiException catch (e) {
        if (!mounted) return;
        if (e.code == 'not_enough_coins') {
          await showNeedCoins(context, cost);
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
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RiddlePlayScreen(item: item, day: _day!)));
    Sfx.i.ambient('amb_home', volume: 0.28);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _day;
    return Scaffold(
      body: GrainBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: K.stamp,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward_rounded, color: K.text)),
                  Expanded(child: Text('معمای سریع', style: tDisplay(24))),
                  ListenableBuilder(listenable: Api.i, builder: (_, __) => CoinChip(coins: Api.i.coins)),
                ]),
                const SizedBox(height: 4),
                Text(
                  d == null
                      ? 'هر روز چند معمای یک‌دقیقه‌ای، برای همه یکی.'
                      : 'هر روز ${fa(d.items.length)} معمای یک‌دقیقه‌ای، برای همه یکی. '
                          '${fa(d.items.where((r) => r.free).length)}تای اول رایگانه؛ هر جواب درست ${fa(d.reward)} سکه.',
                  style: tBody(13, color: K.textSoft),
                ),
                const SizedBox(height: 12),
                const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                if (d == null && _error == null)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: K.brass))),
                if (d == null && _error != null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Text(_error!, textAlign: TextAlign.center, style: tBody(14, color: K.textSoft)),
                      const SizedBox(height: 12),
                      GhostButton(label: 'دوباره', icon: Icons.refresh_rounded, onTap: _load),
                    ]),
                  ),
                if (d != null) ...[
                  _summary(d),
                  const SizedBox(height: 14),
                  for (int i = 0; i < d.items.length; i++)
                    FadeSlideIn(delay: Duration(milliseconds: 70 * i), child: _row(d, d.items[i])),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(RiddleDay d) {
    final left = d.nextAt.difference(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Icon(Icons.bolt_rounded, color: K.brass),
        const SizedBox(width: 6),
        Expanded(child: Text('امروز: ${fa(d.correct)} درست از ${fa(d.answered)} جواب', style: tBody(14, w: FontWeight.w700))),
        Text('معماهای تازه: ', style: tBody(12, color: K.textSoft)),
        Text(left.isNegative ? 'رسیده!' : faClock(left), style: tDisplay(16, color: K.brass)),
      ]),
    );
  }

  Widget _row(RiddleDay d, RiddleItem r) {
    final (IconData icon, Color color, String status) = r.answered
        ? (r.correct ? (Icons.check_circle_rounded, K.ok, 'درست!') : (Icons.cancel_rounded, K.stamp, 'اشتباه'))
        : r.locked
            ? (Icons.lock_rounded, K.textSoft, '${fa(d.unlockCost)} سکه')
            : (Icons.play_circle_fill_rounded, K.brass, r.free ? 'رایگان' : 'باز شده');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _open(r),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: K.night2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: (r.answered ? color : K.kraft).withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(10)),
              child: Text(fa(r.slot), style: tDisplay(20, color: K.brass)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.locked ? 'معمای قفل' : r.title, style: tDisplay(17)),
                Text(r.answered ? 'ببین چرا' : (r.locked ? 'با سکه باز می‌شه' : 'یک دقیقه وقت داری'),
                    style: tBody(12.5, color: K.textSoft)),
              ]),
            ),
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 4),
            Text(status, style: tBody(12.5, color: color, w: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// One riddle: the story, the clue card, three choices and a one-minute timer.
class RiddlePlayScreen extends StatefulWidget {
  const RiddlePlayScreen({super.key, required this.item, required this.day});
  final RiddleItem item;
  final RiddleDay day;

  @override
  State<RiddlePlayScreen> createState() => _RiddlePlayScreenState();
}

class _RiddlePlayScreenState extends State<RiddlePlayScreen> {
  /// When each riddle was first shown (this app session): leaving and coming back doesn't reset the clock.
  static final Map<String, DateTime> _started = {};

  late RiddleItem _item = widget.item;
  RiddleResult? _result;
  bool _sending = false;
  bool _warned = false;
  Timer? _tick;

  int get _limit => widget.day.seconds;
  int get _elapsed => DateTime.now().difference(_started[_item.id]!).inSeconds;
  int get _left => (_limit - _elapsed).clamp(0, _limit);

  @override
  void initState() {
    super.initState();
    Sfx.i.ambient('amb_${_item.scene}');
    Sfx.i.play('paper', volume: 0.5);
    if (!_item.answered) {
      _started.putIfAbsent(_item.id, DateTime.now);
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    }
  }

  void _onTick() {
    if (!mounted || _result != null || _item.answered) return;
    setState(() {});
    if (_left <= 10 && !_warned) {
      _warned = true;
      Sfx.i.play('heartbeat', volume: 0.6);
    }
    if (_left <= 0 && !_sending) _answer(-1);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _answer(int choice) async {
    if (_sending || _result != null) return;
    if (choice >= 0 && !needOnline(context)) return;
    setState(() => _sending = true);
    try {
      final r = await Api.i.answerRiddle(_item.id, choice, _elapsed.clamp(0, 3600));
      if (!mounted) return;
      _tick?.cancel();
      setState(() {
        _result = r;
        _item = r.item;
      });
      Sfx.i.play(r.correct ? 'win' : 'wrong', volume: 0.8);
    } catch (e) {
      if (choice < 0) _tick?.cancel(); // time ran out but the answer didn't reach the server: don't keep retrying
      if (mounted) toast(context, Api.friendly(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  RiddleItem? get _next {
    final rest = widget.day.items.where((r) => r.slot > _item.slot && !r.locked && !r.answered);
    return rest.isEmpty ? null : rest.first;
  }

  @override
  Widget build(BuildContext context) {
    final done = _item.answered;
    return Scaffold(
      body: GrainBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Row(children: [
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward_rounded, color: K.text)),
                Expanded(child: Text('معمای ${fa(_item.slot)}: ${_item.title}', style: tDisplay(19), overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AnimatedScene(scene: _item.scene, height: 130, dim: 0.25),
              ),
              const SizedBox(height: 12),
              if (!done) _timer(),
              if (done) _verdict(),
              const SizedBox(height: 12),
              Paper(child: Text(_item.text, style: tBody(15.5, color: K.ink).copyWith(height: 1.8))),
              const SizedBox(height: 12),
              _clue(),
              const SizedBox(height: 16),
              Text(done ? 'جواب‌ها' : 'کدوم درسته؟', style: tDisplay(18)),
              const SizedBox(height: 8),
              for (int i = 0; i < _item.choices.length; i++) _choice(i),
              if (done && _item.explain.isNotEmpty) ...[
                const SizedBox(height: 10),
                StampIn(
                  child: Paper(
                    color: K.paperDark,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('چرا؟', style: tDisplay(18, color: K.ink)),
                      const SizedBox(height: 4),
                      Text(_item.explain, style: tBody(14.5, color: K.ink).copyWith(height: 1.8)),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                if (_next != null)
                  StampButton(
                    label: 'معمای بعدی',
                    icon: Icons.chevron_left_rounded,
                    onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => RiddlePlayScreen(item: _next!, day: widget.day))),
                  )
                else
                  StampButton(label: 'برگشت', color: K.night3, onTap: () => Navigator.pop(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _timer() {
    final frac = _limit == 0 ? 0.0 : _left / _limit;
    final hurry = _left <= 10;
    return Row(children: [
      Icon(Icons.timer_rounded, color: hurry ? K.stamp : K.brass),
      const SizedBox(width: 8),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
              value: frac, minHeight: 10, backgroundColor: K.night3, color: hurry ? K.stamp : K.brass),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 52,
        child: Text(faClock(Duration(seconds: _left)), style: tDisplay(18, color: hurry ? K.stamp : K.text)),
      ),
    ]);
  }

  Widget _verdict() {
    final ok = _item.correct;
    final timedOut = _item.choice == -1;
    final reward = _result?.reward ?? 0;
    return Row(children: [
      StampMark(ok ? 'درست!' : (timedOut ? 'وقت تموم شد' : 'اشتباه'), color: ok ? K.ok : K.stamp, size: 22),
      const Spacer(),
      if (reward > 0)
        Row(children: [
          Text('+${fa(reward)}', style: tDisplay(20, color: K.brass)),
          const SizedBox(width: 4),
          const CoinIcon(size: 20),
        ]),
    ]);
  }

  Widget _clue() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: K.clue,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 5))],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.search_rounded, color: K.ink, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('سرنخ', style: tDisplay(16, color: K.ink)),
              Text(_item.clue, style: tBody(14.5, color: K.ink, w: FontWeight.w700).copyWith(height: 1.7)),
            ]),
          ),
        ]),
      );

  Widget _choice(int i) {
    final done = _item.answered;
    final right = done && _item.answer == i;
    final picked = _item.choice == i;
    final color = right ? K.ok : (done && picked ? K.stamp : K.night3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: done || _sending ? null : () => _answer(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: done ? color.withValues(alpha: right || picked ? 0.9 : 0.4) : K.night2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: done ? color : K.kraft.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(children: [
            Text(['الف', 'ب', 'ج'][i], style: tDisplay(17, color: K.brass)),
            const SizedBox(width: 12),
            Expanded(child: Text(_item.choices[i], style: tBody(15, w: FontWeight.w700))),
            if (right) const Icon(Icons.check_rounded, color: Colors.white),
            if (done && picked && !right) const Icon(Icons.close_rounded, color: Colors.white),
          ]),
        ),
      ),
    );
  }
}
