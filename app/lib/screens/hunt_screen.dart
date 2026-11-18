import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/reminders.dart';
import '../theme.dart';
import '../widgets/character.dart';
import 'dialogs.dart';

/// «شکار سه‌روزه»: a special case played in real time over two days (server app/hunt.py, Amin 18 Nov 2026).
/// Eight suspects, one of them leaves town every few hours; evidence arrives on a schedule; the killer writes from the
/// victim's phone; one accusation. The server is the clock and the judge; this screen only shows and counts down.

// ---------------------------------------------------------------- time (Tehran is a fixed UTC+3:30, like the app)

DateTime _tehran(int epoch) =>
    DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true).add(const Duration(hours: 3, minutes: 30));
const List<String> _days = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
String _two(int v) => fa(v).padLeft(2, '۰');
String huntClock(int epoch) {
  final t = _tehran(epoch);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

String huntDay(int epoch) => _days[_tehran(epoch).weekday - 1];
String huntWhen(int epoch) => '${huntDay(epoch)} ${huntClock(epoch)}';
String _hm(int seconds) {
  final s = math.max(0, seconds);
  return '${_two(s ~/ 3600)}:${_two((s % 3600) ~/ 60)}';
}

int _int(Object? v) => v is num ? v.toInt() : 0;
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Map<String, dynamic>>[];

const ColorFilter _grey = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

const Map<String, String> _errors = {
  'gone': 'این مظنون از شهر رفته.',
  'already_held': 'این مظنون یک بار نگه داشته شده.',
  'already_accused': 'یه بار متهم کردی.',
  'no_evidence': 'این مدرک هنوز دستت نرسیده.',
  'hunt_over': 'وقت شکار تموم شده.',
  'not_started': 'شکار هنوز شروع نشده.',
  'nothing_left': 'همه‌ی مدارک باز شده.',
};

/// The hunt's entry card (weekend tab): only when the server shows a hunt to this player.
class HuntEntryCard extends StatelessWidget {
  const HuntEntryCard({super.key, required this.hunt, required this.onOpen});
  final Map<String, dynamic> hunt;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final status = hunt['status'];
    final now = _int(hunt['now']);
    final line = status == 'scheduled'
        ? 'شروع: ${huntWhen(_int(hunt['starts_at']))}'
        : status == 'ended'
            ? 'نتیجه اعلام شد'
            : 'تا ${huntWhen(_int(hunt['deadline_at']))} · ${fa(_int((hunt['collective'] as Map?)?['pct']))}٪ پیداش کردن';
    return GestureDetector(
      key: const ValueKey('hunt-entry'),
      onTap: onOpen,
      child: Container(
        height: 150,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: K.night2, border: Border.all(color: K.stamp.withValues(alpha: 0.7))),
        child: Stack(fit: StackFit.expand, children: [
          _NetImage(hunt, 'cover', fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22000000), Color(0xEE121315)]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('${hunt['kicker']} · آزمایشی', style: tBody(12, color: K.kraft, w: FontWeight.w900)),
              Text('${hunt['title']}', style: tDisplay(22)),
              Text(line, style: tBody(12.5, color: K.textSoft)),
            ]),
          ),
          if (status == 'live' && now > 0)
            const PositionedDirectional(
              top: 12,
              end: 12,
              child: _LiveDot(),
            ),
        ]),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: K.stamp, shape: BoxShape.circle, boxShadow: [BoxShadow(color: K.stamp.withValues(alpha: 0.6), blurRadius: 10)]),
      );
}

/// A picture of the hunt, from the server (a dark box while it loads or when it is missing).
class _NetImage extends StatelessWidget {
  const _NetImage(this.hunt, this.name, {this.fit = BoxFit.cover});
  final Map<String, dynamic> hunt;
  final String name;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.network(
        Api.i.huntImage('${hunt['img_base']}', name),
        fit: fit,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF1A1714)),
        loadingBuilder: (_, child, p) => p == null ? child : const ColoredBox(color: Color(0xFF1A1714)),
      );
}

class HuntScreen extends StatefulWidget {
  const HuntScreen({super.key, this.initial});
  final Map<String, dynamic>? initial;

  @override
  State<HuntScreen> createState() => _HuntScreenState();
}

class _HuntScreenState extends State<HuntScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _j;
  int _offset = 0;
  Timer? _tick;
  int _tab = 0;
  bool _loading = false;
  bool _review = false;
  final Set<String> _crossed = {};
  int _seenMsgs = 0;
  int _seenItems = 0;
  DateTime _lastTry = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initial != null) _take(widget.initial!);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000 + _offset;

  void _take(Map<String, dynamic> j) {
    _j = j;
    _offset = _int(j['now']) - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final plan = _maps(j['schedule']);
    unawaited(Reminders.i.huntPlan(plan));
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    _lastTry = DateTime.now();
    final j = await Api.i.hunt();
    _loading = false;
    if (!mounted) return;
    if (j == null) {
      if (_j == null) Navigator.of(context).maybePop();
      return;
    }
    setState(() => _take(j));
    _maybeIntro();
  }

  /// The next moment something changes (a drop, a message, a departure, the end): reload just after it.
  int? _nextChange() {
    final j = _j;
    if (j == null) return null;
    final now = _int(j['now']);
    final times = <int>[
      if (j['status'] == 'scheduled') _int(j['starts_at']),
      _int(j['deadline_at']),
      for (final e in _maps(j['schedule'])) _int(e['at']),
      for (final s in _maps(j['suspects']))
        if (s['leave_at'] != null && s['gone'] != true) _int(s['leave_at']),
    ].where((t) => t > now).toList()
      ..sort();
    return times.isEmpty ? null : times.first;
  }

  void _onTick() {
    if (!mounted || _j == null) return;
    final next = _nextChange();
    if (next != null && _now >= next + 2 && DateTime.now().difference(_lastTry).inSeconds >= 15) {
      _load();
    } else {
      setState(() {});
    }
  }

  Map<String, dynamic> get j => _j!;
  List<Map<String, dynamic>> get _suspects => _maps(j['suspects']);
  Map<String, dynamic>? get _mine => (j['mine'] as Map?)?.cast<String, dynamic>();
  int get _pct => _int((j['collective'] as Map?)?['pct']);
  int get _threshold => _int(j['threshold']);

  bool _gone(Map<String, dynamic> s) {
    if (s['gone'] == true) return true;
    final at = s['leave_at'];
    return at is num && _now >= at.toInt() && _mine?['suspect'] != s['id'];
  }

  Map<String, dynamic>? _nextLeaver() {
    Map<String, dynamic>? best;
    if (_mine != null) return null;
    for (final s in _suspects) {
      if (_gone(s) || s['leave_at'] is! num) continue;
      if (best == null || _int(s['leave_at']) < _int(best['leave_at'])) best = s;
    }
    return best;
  }

  List<Map<String, dynamic>> get _openItems => [
        for (final d in _maps(j['drops']))
          if (d['open'] == true) ..._maps(d['items']),
        ..._maps(j['message_items']),
      ];

  // ---------------------------------------------------------------- actions

  Future<void> _act(String action, [Map<String, dynamic>? body]) async {
    try {
      final r = await Api.i.huntAction(action, body);
      if (!mounted) return;
      setState(() => _take(r));
      if (action == 'accuse') _showVerdict(r);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'not_enough_coins') {
        await showNeedCoins(context, e.need, starter: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errors[e.code] ?? 'الان نشد. دوباره امتحان کن.')));
      }
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اینترنت وصل نیست.')));
    }
  }

  void _invite() {
    SharePlus.instance.share(ShareParams(
        text: 'یه قاتل تو ${j['place']}ـه و تا ${huntWhen(_int(j['deadline_at']))} وقت داریم. اگه کمتر از ${fa(_threshold)}٪ کارآگاه‌ها پیداش کنن، دوباره می‌کشه. بیا کمک: «پرونده» رو از کافه‌بازار بگیر.'));
  }

  void _maybeIntro() {
    if (_j == null || j['status'] != 'live') return;
    final key = 'hunt_intro_${j['id']}';
    if (Api.i.flag(key)) return;
    unawaited(Api.i.setFlag(key));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showRules();
    });
  }

  void _showRules() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: K.night2,
      builder: (ctx) => _Sheet(children: [
        Text('${j['kicker']}', style: tBody(13, color: K.kraft, w: FontWeight.w900)),
        Text('${j['title']}', style: tDisplay(26)),
        const SizedBox(height: 14),
        for (final r in (j['rules'] as List? ?? const []))
          if (r is List && r.length == 2) _RuleRow(kind: '${r[0]}', text: '${r[1]}'),
        const SizedBox(height: 10),
        StampButton(label: 'پرونده رو باز کن', icon: Icons.search_rounded, color: K.brass, onTap: () => Navigator.pop(ctx)),
      ]),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_j == null) {
      return const Scaffold(backgroundColor: K.night, body: Center(child: CircularProgressIndicator(color: K.brass)));
    }
    final status = j['status'];
    Widget body;
    if (status == 'scheduled') {
      body = _scheduled();
    } else if (status == 'ended' && !_review) {
      body = _ending();
    } else {
      body = Column(children: [
        _header(),
        Expanded(
          child: IndexedStack(index: _tab, children: [_suspectsTab(), _evidenceTab(), _messagesTab()]),
        ),
      ]);
    }
    final showNav = status == 'live' || (status == 'ended' && _review);
    return Scaffold(
      backgroundColor: K.night,
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: showNav ? _nav() : null,
    );
  }

  Widget _backButton() => IconButton(
        tooltip: 'برگشت',
        onPressed: () {
          if (_review) {
            setState(() => _review = false);
          } else {
            Navigator.of(context).maybePop();
          }
        },
        icon: const Icon(Icons.arrow_forward_rounded, color: K.text),
      );

  Widget _header() {
    final now = _now;
    final left = _int(j['deadline_at']) - now;
    final pct = _pct, th = _threshold;
    final reached = pct >= th;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: K.night3))),
      child: Column(children: [
        Row(children: [
          _backButton(),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(huntDay(now), style: tBody(11.5, color: K.textSoft)),
            Text(huntClock(now), style: tDisplay(22)),
          ]),
          const Spacer(),
          _CoinChip(coins: Api.i.coins),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(j['status'] == 'ended' ? 'تموم شد' : 'تا قتل بعدی', style: tBody(11, color: K.textSoft)),
            Text(j['status'] == 'ended' ? '—' : _hm(left), style: tDisplay(18, color: K.stamp)),
          ]),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${fa(pct)}٪', style: tBody(14, w: FontWeight.w900)),
                  TextSpan(text: ' از ${fa(_int((j['collective'] as Map?)?['players']))} کارآگاه پیداش کردن', style: tBody(12, color: K.textSoft)),
                ])),
              ),
              TextButton(onPressed: _invite, child: Text('دعوت', style: tBody(12.5, color: K.clue, w: FontWeight.w900))),
            ]),
            LayoutBuilder(builder: (_, c) {
              final w = c.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned.fill(
                    top: 3,
                    bottom: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0.0, 1.0),
                        backgroundColor: K.night3,
                        color: reached ? K.ok : K.stamp,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: w * th / 100 - 1,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: K.text),
                  ),
                ]),
              );
            }),
          ]),
        ),
      ]),
    );
  }

  Widget _nav() {
    final msgs = _maps(j['messages']).length;
    final items = _openItems.length;
    Widget tab(int i, IconData icon, String label, int badge) => Expanded(
          child: InkWell(
            onTap: () => setState(() {
              _tab = i;
              if (i == 1) _seenItems = items;
              if (i == 2) _seenMsgs = msgs;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Badge(
                  isLabelVisible: badge > 0 && _tab != i,
                  label: Text(fa(badge)),
                  backgroundColor: K.stamp,
                  child: Icon(icon, color: _tab == i ? K.brass : K.textSoft),
                ),
                const SizedBox(height: 2),
                Text(label, style: tBody(11, color: _tab == i ? K.text : K.textSoft)),
              ]),
            ),
          ),
        );
    final canAccuse = _mine == null && j['status'] == 'live';
    return Container(
      decoration: const BoxDecoration(color: K.night2, border: Border(top: BorderSide(color: K.night3))),
      child: SafeArea(
        top: false,
        child: Row(children: [
          tab(0, Icons.groups_rounded, 'مظنون‌ها', 0),
          tab(1, Icons.folder_open_rounded, 'مدارک', items - _seenItems),
          Expanded(
            child: InkWell(
              key: const ValueKey('hunt-accuse'),
              onTap: canAccuse ? () => _accuseSheet() : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: canAccuse ? K.stamp : K.night3, shape: BoxShape.circle),
                    child: const Icon(Icons.gavel_rounded, color: Colors.white, size: 22),
                  ),
                  Text('متهم کن', style: tBody(11, color: canAccuse ? K.text : K.textSoft)),
                ]),
              ),
            ),
          ),
          tab(2, Icons.chat_bubble_rounded, 'پیام‌ها', msgs - _seenMsgs),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------- suspects

  Widget _suspectsTab() {
    final v = (j['victim'] as Map?)?.cast<String, dynamic>() ?? const {};
    final next = _nextLeaver();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ColorFiltered(colorFilter: _grey, child: SuspectPortrait(AvatarSpec({'portrait': v['portrait']}), size: 64)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${v['name']}، ${fa(_int(v['age']))}', style: tDisplay(16, color: K.ink)),
              Text('${v['line']}', style: tBody(12, color: K.inkSoft)),
            ]),
          ),
          Transform.rotate(
            angle: -0.14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(border: Border.all(color: K.stamp, width: 2), borderRadius: BorderRadius.circular(4)),
              child: Text('${v['stamp']}', style: tBody(11, color: K.stamp, w: FontWeight.w900)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.58,
        children: [for (final s in _suspects) _suspectCell(s, next?['id'] == s['id'])],
      ),
    ]);
  }

  Widget _suspectCell(Map<String, dynamic> s, bool isNext) {
    final gone = _gone(s);
    final id = '${s['id']}';
    final accused = _mine?['suspect'] == id;
    final held = _int(s['held']) > 0 && !gone;
    Color ring = K.night3;
    if (isNext) ring = K.stamp;
    if (held) ring = K.brass;
    if (accused) ring = K.clue;
    Widget face = SuspectPortrait(AvatarSpec({'portrait': s['portrait'], 'gender': s['gender']}), size: 120, circle: true);
    if (gone) face = Opacity(opacity: 0.45, child: ColorFiltered(colorFilter: _grey, child: face));
    final left = isNext ? _int(s['leave_at']) - _now : 0;
    return GestureDetector(
      key: ValueKey('hunt-suspect-$id'),
      onTap: () => _suspectSheet(s),
      child: Column(children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(shape: BoxShape.circle, color: ring,
                    boxShadow: isNext ? [BoxShadow(color: K.stamp.withValues(alpha: 0.35), blurRadius: 14)] : null),
                child: ClipOval(child: face),
              ),
            ),
            if (isNext)
              Positioned.fill(
                child: CustomPaint(painter: _RingPainter((left / (_int(j['hold_hours']) * 3600)).clamp(0.0, 1.0))),
              ),
            if (_crossed.contains(id))
              Positioned.fill(
                child: Transform.rotate(
                  angle: -0.6,
                  child: Center(child: Container(height: 3, color: K.stamp)),
                ),
              ),
            if (isNext)
              PositionedDirectional(
                bottom: -6,
                start: 0,
                end: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(99)),
                    child: Text(_hm(left), style: tBody(10, w: FontWeight.w900)),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Text('${s['name']}', textAlign: TextAlign.center, maxLines: 2, style: tBody(11.5, w: FontWeight.w900).copyWith(height: 1.3)),
        Text('${s['role']}'.split('،').first, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: tBody(10, color: K.textSoft).copyWith(height: 1.3)),
      ]),
    );
  }

  void _suspectSheet(Map<String, dynamic> s) {
    final gone = _gone(s);
    final id = '${s['id']}';
    final leaveAt = s['leave_at'];
    final live = j['status'] == 'live';
    final canHold = live && !gone && leaveAt is num && _int(s['held']) < 1 && _mine == null;
    final canAccuse = live && !gone && _mine == null;
    final price = _int((j['prices'] as Map?)?['hold']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: K.night2,
      builder: (ctx) => _Sheet(children: [
        Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: gone
                ? ColorFiltered(colorFilter: _grey, child: SuspectPortrait(AvatarSpec({'portrait': s['portrait']}), size: 84))
                : SuspectPortrait(AvatarSpec({'portrait': s['portrait']}), size: 84),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['name']}', style: tDisplay(20)),
              Text('${fa(_int(s['age']))} ساله · ${s['role']}', style: tBody(13, color: K.textSoft)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        _Paper(child: Text('«${s['quote']}»', style: tBody(15, color: K.ink))),
        const SizedBox(height: 10),
        Row(children: [
          Icon(gone ? Icons.flight_takeoff_rounded : Icons.schedule_rounded, color: K.textSoft, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              gone
                  ? 'از شهر رفته.'
                  : leaveAt is num
                      ? 'می‌ره: ${huntWhen(leaveAt.toInt())} · ${s['why']}'
                      : '${s['why']}',
              style: tBody(13, color: K.textSoft),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _SheetButton(
              label: '${fa(price)} سکه · منع خروج',
              color: K.brass,
              dark: true,
              onTap: canHold
                  ? () {
                      Navigator.pop(ctx);
                      _act('hold', {'suspect': id});
                    }
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _SheetButton(
              label: _crossed.contains(id) ? 'برگردون' : 'خط بزن',
              color: K.night3,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _crossed.contains(id) ? _crossed.remove(id) : _crossed.add(id));
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        _SheetButton(
          label: 'متهمش کن',
          color: K.stamp,
          onTap: canAccuse
              ? () {
                  Navigator.pop(ctx);
                  _accuseSheet(preselect: id);
                }
              : null,
        ),
        if (canHold) ...[
          const SizedBox(height: 10),
          Text('منع خروج: ${fa(_int(j['hold_hours']))} ساعت بیشتر تو شهر می‌مونه.', style: tBody(12, color: K.textSoft)),
        ],
      ]),
    );
  }

  // ---------------------------------------------------------------- evidence

  Widget _evidenceTab() {
    final drops = _maps(j['drops']);
    final open = drops.where((d) => d['open'] == true).toList();
    final closed = drops.where((d) => d['open'] != true).toList();
    final msgItems = _maps(j['message_items']);
    final price = _int((j['prices'] as Map?)?['early']);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      for (final d in open) ...[
        _dropHeader('${d['title']}', d['early'] == true ? 'زودتر باز شد' : huntWhen(_int(d['at']))),
        for (final it in _maps(d['items'])) _ItemCard(hunt: j, item: it),
        const SizedBox(height: 8),
      ],
      if (msgItems.isNotEmpty) ...[
        _dropHeader('از پیام‌های قاتل', ''),
        for (final it in msgItems) _ItemCard(hunt: j, item: it),
        const SizedBox(height: 8),
      ],
      for (final d in closed)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: K.night3, width: 1.5)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d == closed.first ? '${d['title']}' : '؟', style: tBody(14, w: FontWeight.w900)),
                Text(huntWhen(_int(d['at'])), style: tBody(12, color: K.textSoft)),
              ]),
            ),
            if (d == closed.first && j['status'] == 'live')
              FilledButton(
                key: const ValueKey('hunt-early'),
                style: FilledButton.styleFrom(backgroundColor: K.brass, foregroundColor: K.ink),
                onPressed: () => _act('early'),
                child: Text('${fa(price)} سکه · همین الان', style: tBody(12.5, color: K.ink, w: FontWeight.w900)),
              ),
          ]),
        ),
    ]);
  }

  Widget _dropHeader(String title, String when) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: tDisplay(15))),
          Text(when, style: tBody(11, color: K.textSoft)),
        ]),
      );

  // ---------------------------------------------------------------- messages

  Widget _messagesTab() {
    final v = (j['victim'] as Map?)?.cast<String, dynamic>() ?? const {};
    final msgs = _maps(j['messages']);
    String? lastDay;
    final children = <Widget>[];
    for (final m in msgs) {
      final at = _int(m['at']);
      final day = huntDay(at);
      if (day != lastDay) {
        lastDay = day;
        children.add(Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(99)),
            child: Text(day, style: tBody(11, color: K.textSoft)),
          ),
        ));
      }
      for (final p in _maps(m['parts'])) {
        children.add(_Bubble(hunt: j, part: p, time: huntClock(at)));
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Row(children: [
        ClipOval(child: ColorFiltered(colorFilter: _grey, child: SuspectPortrait(AvatarSpec({'portrait': v['portrait']}), size: 44))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${v['name']}', style: tBody(15, w: FontWeight.w900)),
          Text('${v['last_seen']}', style: tBody(11, color: K.textSoft)),
        ]),
      ]),
      const Divider(color: K.night3, height: 24),
      ...children,
    ]);
  }

  // ---------------------------------------------------------------- accuse

  Future<void> _accuseSheet({String? preselect}) async {
    if (_mine != null || j['status'] != 'live') return;
    String? who = preselect;
    String? key;
    final items = _openItems;
    final pick = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: K.night2,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final name = who == null ? null : '${_suspects.firstWhere((s) => s['id'] == who)['name']}';
        return _Sheet(children: [
          Text('کی؟', style: tDisplay(18)),
          Text('فقط یه بار. کسی که رفته رو نمی‌شه متهم کرد.', style: tBody(12.5, color: K.textSoft)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.78,
            children: [
              for (final s in _suspects)
                GestureDetector(
                  onTap: _gone(s) ? null : () => set(() => who = '${s['id']}'),
                  child: Opacity(
                    opacity: _gone(s) ? 0.25 : 1,
                    child: Column(children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(2.5),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: who == s['id'] ? K.stamp : Colors.transparent),
                          child: ClipOval(child: SuspectPortrait(AvatarSpec({'portrait': s['portrait']}), size: 70, circle: true)),
                        ),
                      ),
                      Text('${s['name']}'.split(' ').first, style: tBody(11, w: FontWeight.w900)),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('چطور فهمیدی؟', style: tDisplay(18)),
          Text('مدرکی که دستش رو رو می‌کنه.', style: tBody(12.5, color: K.textSoft)),
          const SizedBox(height: 8),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => set(() => key = '${it['id']}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: key == it['id'] ? const Color(0xFF2F2A1C) : K.night3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: key == it['id'] ? K.clue : K.night3, width: 1.5),
                  ),
                  child: Text('${it['short']}', style: tBody(13.5)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          StampButton(
            label: name == null ? 'متهم کن' : '$name رو متهم کن',
            icon: Icons.gavel_rounded,
            onTap: who != null && key != null ? () => Navigator.pop(ctx, (who!, key!)) : null,
          ),
        ]);
      }),
    );
    if (pick == null || !mounted) return;
    await _act('accuse', {'suspect': pick.$1, 'evidence': pick.$2});
  }

  void _showVerdict(Map<String, dynamic> r) {
    final mine = (r['mine'] as Map?)?.cast<String, dynamic>();
    if (mine == null) return;
    final ok = mine['solved'] == true;
    final stars = _int(mine['stars']);
    final reward = _int(r['reward']);
    final s = _suspects.firstWhere((x) => x['id'] == mine['suspect'], orElse: () => <String, dynamic>{});
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: K.night2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipOval(
              child: ok
                  ? SuspectPortrait(AvatarSpec({'portrait': s['portrait']}), size: 110, circle: true)
                  : ColorFiltered(colorFilter: _grey, child: SuspectPortrait(AvatarSpec({'portrait': s['portrait']}), size: 110, circle: true)),
            ),
            const SizedBox(height: 10),
            Text(ok ? 'درست گرفتی.' : 'اون نبود.', style: tDisplay(26)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (int i = 1; i <= 3; i++) Icon(Icons.star_rounded, size: 34, color: i <= stars ? K.brass : K.night3),
            ]),
            const SizedBox(height: 6),
            Text(
              ok
                  ? (stars == 3
                      ? 'قبل از عکس‌ها فهمیدی. کمتر کارآگاهی این کارو کرد.'
                      : stars == 2
                          ? 'با عکس‌ها فهمیدی.'
                          : 'آدمش درست بود، دلیلت نه.')
                  : 'پرونده برای تو بسته شد. جواب ${huntWhen(_int(j['deadline_at']))} اعلام می‌شه.',
              textAlign: TextAlign.center,
              style: tBody(13.5, color: K.textSoft),
            ),
            if (reward > 0) Text('+${fa(reward)} سکه', style: tBody(15, color: K.brass, w: FontWeight.w900)),
            if (ok) ...[
              const SizedBox(height: 10),
              Text('حالا بقیه باید برسن. هر کارآگاهی که دعوت کنی و حلش کنه، ما رو به ${fa(_threshold)}٪ نزدیک‌تر می‌کنه.',
                  textAlign: TextAlign.center, style: tBody(12.5, color: K.textSoft)),
              const SizedBox(height: 12),
              StampButton(label: 'دعوت کارآگاه', icon: Icons.person_add_alt_1_rounded, color: K.brass, onTap: _invite),
            ],
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('ادامه', style: tBody(14, w: FontWeight.w900))),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- before / after

  Widget _scheduled() {
    final start = _int(j['starts_at']);
    return ListView(padding: const EdgeInsets.fromLTRB(8, 8, 16, 24), children: [
      Align(alignment: AlignmentDirectional.centerStart, child: _backButton()),
      SizedBox(height: 220, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: _NetImage(j, 'cover'))),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${j['kicker']} · ${j['place']}', style: tBody(13, color: K.kraft, w: FontWeight.w900)),
          Text('${j['title']}', style: tDisplay(28)),
          const SizedBox(height: 8),
          Text('شروع: ${huntWhen(start)}', style: tBody(14, color: K.textSoft)),
          Text(_hm(start - _now), style: tDisplay(34, color: K.brass)),
          const SizedBox(height: 14),
          for (final r in (j['rules'] as List? ?? const []))
            if (r is List && r.length == 2) _RuleRow(kind: '${r[0]}', text: '${r[1]}'),
        ]),
      ),
    ]);
  }

  Widget _ending() {
    final e = (j['ending'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mine = _mine;
    final reached = e['reached'] == true;
    final lines = (e['lines'] as List? ?? const []).map((x) => '$x').toList();
    String myLine;
    if (mine == null) {
      myLine = 'کسی رو متهم نکردی.';
    } else if (mine['solved'] == true) {
      myLine = 'تو درست گرفته بودی · ${'★' * _int(mine['stars'])}';
    } else {
      final s = _suspects.firstWhere((x) => x['id'] == mine['suspect'], orElse: () => <String, dynamic>{'name': ''});
      myLine = 'تو ${s['name']} رو متهم کرده بودی.';
    }
    return ListView(padding: const EdgeInsets.fromLTRB(8, 8, 16, 32), children: [
      Align(alignment: AlignmentDirectional.centerStart, child: _backButton()),
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('نتیجه‌ی ${j['kicker']}', textAlign: TextAlign.center, style: tBody(12, color: K.kraft, w: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('${fa(_pct)}٪ کارآگاه‌ها\n${e['culprit_name']} رو نشون دادن.', textAlign: TextAlign.center, style: tDisplay(26)),
          const SizedBox(height: 6),
          Text(myLine, textAlign: TextAlign.center, style: tBody(13.5, color: K.textSoft)),
          const SizedBox(height: 14),
          if (reached)
            _Paper(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['caught']} ${lines.isNotEmpty ? lines.first : ''}', style: tBody(14.5, color: K.ink)),
                for (final l in lines.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: l.startsWith('«') ? _Quote(l) : Text(l, style: tBody(14.5, color: K.ink)),
                  ),
              ]),
            )
          else
            _Paper(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e['fail_title']}', style: tDisplay(16, color: K.ink)),
                const SizedBox(height: 4),
                Text('${e['fail_body']}', style: tBody(14.5, color: K.ink)),
              ]),
            ),
          const SizedBox(height: 12),
          _Paper(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('چه اتفاقی افتاد', style: tDisplay(15, color: K.ink)),
              const SizedBox(height: 6),
              _Timeline(e['truth']),
              const SizedBox(height: 8),
              Text('کلید پرونده: ${e['key']}', style: tBody(13.5, color: K.ink, w: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 16),
          StampButton(label: 'مرور پرونده', icon: Icons.folder_open_rounded, color: K.night3, onTap: () => setState(() => _review = true)),
        ]),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- pieces

class _RingPainter extends CustomPainter {
  _RingPainter(this.frac);
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 + 3);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = K.stamp;
    // from the top, counter-clockwise (RTL): the time left shrinks toward the top
    canvas.drawArc(r, -math.pi / 2, -2 * math.pi * frac, false, p);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.frac != frac;
}

class _CoinChip extends StatelessWidget {
  const _CoinChip({required this.coins});
  final int coins;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.monetization_on_rounded, color: K.brass, size: 16),
          const SizedBox(width: 4),
          Text(fa(coins), style: tBody(13, w: FontWeight.w900)),
        ]),
      );
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            ...children,
          ]),
        ),
      );
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({required this.label, required this.color, required this.onTap, this.dark = false});
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.35 : 1,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
              child: Text(label, textAlign: TextAlign.center, style: tBody(14, color: dark ? K.ink : K.text, w: FontWeight.w900)),
            ),
          ),
        ),
      );
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.kind, required this.text});
  final String kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (kind) {
      'clock' => (Icons.schedule_rounded, K.stamp),
      'chat' => (Icons.chat_bubble_outline_rounded, K.clue),
      _ => (Icons.groups_rounded, K.ok),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: K.night3.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(14), border: Border.all(color: K.night3)),
      child: Row(children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: tBody(14))),
      ]),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: K.paper,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: child,
      );
}

class _Quote extends StatelessWidget {
  const _Quote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.only(start: 10),
        decoration: const BoxDecoration(border: BorderDirectional(start: BorderSide(color: K.kraft, width: 3))),
        child: Text(text, style: tBody(14.5, color: K.ink)),
      );
}

class _Timeline extends StatelessWidget {
  const _Timeline(this.rows);
  final Object? rows;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final r in (rows is List ? rows as List : const []))
          if (r is List && r.length == 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 50, child: Text('${r[0]}', style: tBody(13.5, color: K.kraftDark, w: FontWeight.w900))),
                Expanded(child: Text('${r[1]}', style: tBody(13.5, color: K.ink))),
              ]),
            ),
      ]);
}

/// One evidence card: title, picture, then its blocks (p, q, src, tl, contact).
class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.hunt, required this.item});
  final Map<String, dynamic> hunt;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final img = item['img'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _Paper(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['title']}', style: tDisplay(14.5, color: K.ink)),
          if (img is String) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: AspectRatio(aspectRatio: img == 'killer_photo' ? 4 / 3 : 1, child: _NetImage(hunt, img)),
            ),
          ],
          const SizedBox(height: 4),
          for (final b in (item['blocks'] as List? ?? const []))
            if (b is List && b.length == 2) _block('${b[0]}', b[1]),
        ]),
      ),
    );
  }

  Widget _block(String kind, Object? v) {
    switch (kind) {
      case 'q':
        return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _Quote('$v'));
      case 'src':
        return Padding(padding: const EdgeInsets.only(top: 4), child: Text('$v', style: tBody(11.5, color: K.inkSoft)));
      case 'tl':
        return Padding(padding: const EdgeInsets.only(top: 6), child: _Timeline(v));
      case 'contact':
        final shots = v is List ? v.whereType<List>().toList() : <List>[];
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.05,
              children: [
                for (int i = 0; i < shots.length; i++)
                  Container(
                    padding: const EdgeInsets.fromLTRB(3, 3, 3, 2),
                    decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(2)),
                    child: Column(children: [
                      Expanded(child: CustomPaint(size: Size.infinite, painter: _FramePainter(tripod: '${shots[i][2]}' == 't', index: i))),
                      const SizedBox(height: 2),
                      Row(children: [
                        Expanded(child: Text('${shots[i][0]}', style: const TextStyle(fontSize: 8.5, color: Color(0xFFD9D2C2)))),
                        Text('${shots[i][1]}mm', style: const TextStyle(fontSize: 8.5, color: Color(0xFF8B877D))),
                      ]),
                    ]),
                  ),
              ],
            ),
          ),
        );
      default:
        return Padding(padding: const EdgeInsets.only(top: 4), child: Text('$v', style: tBody(14, color: K.ink)));
    }
  }
}

/// A thumbnail of the photographer's contact sheet: hand-held frames vary, tripod frames are all the same picture.
class _FramePainter extends CustomPainter {
  _FramePainter({required this.tripod, required this.index});
  final bool tripod;
  final int index;

  static const _bg = [Color(0xFF3A3A3F), Color(0xFF2C2F34), Color(0xFF40362A), Color(0xFF33363B), Color(0xFF3B3330), Color(0xFF2E3236)];

  void _person(Canvas c, double x, double y, double s, Paint p) {
    c.drawCircle(Offset(x, y), s * 0.11, p);
    final body = Path()
      ..moveTo(x - s * 0.16, y + s * 0.62)
      ..quadraticBezierTo(x, y + s * 0.05, x + s * 0.16, y + s * 0.62)
      ..close();
    c.drawPath(body, p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.clipRect(Offset.zero & size);
    if (tripod) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF120D08));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w / 2, h * 0.66), width: w * 0.8, height: h * 0.6),
        Paint()
          ..shader = const RadialGradient(colors: [Color(0xAAFFB347), Color(0x00FFB347)])
              .createShader(Rect.fromCenter(center: Offset(w / 2, h * 0.66), width: w * 0.8, height: h * 0.6)),
      );
      final p = Paint()..color = const Color(0xFF2A1D12);
      _person(canvas, w * 0.42, h * 0.42, h, p);
      _person(canvas, w * 0.58, h * 0.42, h, p);
      final candle = Paint()..color = const Color(0xFFFFD27A);
      for (final x in [0.22, 0.32, 0.68, 0.78]) {
        canvas.drawCircle(Offset(w * x, h * 0.8), 1.3, candle);
      }
      canvas.drawRect(Rect.fromLTWH(w * 0.86, h * 0.76, w * 0.1, h * 0.1), Paint()..color = const Color(0x999EC7FF));
      return;
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = _bg[index % _bg.length]);
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(((index * 37) % 11 - 5) * 0.02);
    canvas.translate(-w / 2, -h / 2);
    final p = Paint()..color = const Color(0xFF1B1B1E);
    final x = w * (0.2 + ((index * 29) % 50) / 100);
    _person(canvas, x, h * 0.4, h, p);
    _person(canvas, x + w * 0.24, h * 0.45, h * 0.9, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.tripod != tripod || old.index != index;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.hunt, required this.part, required this.time});
  final Map<String, dynamic> hunt;
  final Map<String, dynamic> part;
  final String time;

  @override
  Widget build(BuildContext context) {
    final img = part['img'];
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        margin: const EdgeInsets.only(bottom: 6),
        padding: img is String ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: const BoxDecoration(
          color: K.night3,
          borderRadius: BorderRadiusDirectional.only(
            topStart: Radius.circular(16),
            topEnd: Radius.circular(16),
            bottomStart: Radius.circular(16),
            bottomEnd: Radius.circular(4),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (img is String)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(aspectRatio: 4 / 3, child: _NetImage(hunt, img)),
            )
          else
            Text('${part['text']}', style: tBody(14.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(time, style: tBody(10, color: K.textSoft)),
          ),
        ]),
      ),
    );
  }
}
