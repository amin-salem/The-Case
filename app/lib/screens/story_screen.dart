import 'dart:async';

import 'package:flutter/material.dart';

import '../models/story.dart';
import '../services/api.dart';
import '../services/reminders.dart';
import '../theme.dart';
import '../widgets/coming_soon.dart';
import '../widgets/offline.dart';
import '../widgets/partner_card.dart';
import 'case_screen.dart';
import 'dialogs.dart';

DateTime? _time(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

const String _partnerHello = '«سلام همکار. سه ساله دنبال کسی‌ام که سر هر صحنه یه کبریت سوخته جا می‌ذاره. '
    'تنهایی بهش نرسیدم؛ شاید با تو برسم. فقط زیاد حرف نزن، مدارک رو بخون.»';

/// The story tab. Until story mode opens (or while no chapters are written) it shows the season banner and
/// a countdown; after that, the career map.
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  StoryMap? _map;
  String? _error;
  bool _loading = false;

  bool get _open => Api.i.upcomingStory['open'] == true;

  @override
  void initState() {
    super.initState();
    Api.i.addListener(_onApi);
    if (_open) _load();
  }

  @override
  void dispose() {
    Api.i.removeListener(_onApi);
    super.dispose();
  }

  void _onApi() {
    if (!mounted) return;
    if (_open && _map == null && !_loading) _load();
    setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await Api.i.story();
      if (!mounted) return;
      setState(() => _map = m);
      _remind(m);
    } catch (e) {
      if (mounted) setState(() => _error = Api.isNetworkFail(e) && !Api.i.online ? Api.offlineText : Api.friendly(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The phone announces when the next chapter's 12-hour wait ends (replaces the old reminder).
  void _remind(StoryMap m) {
    final at = m.nextOpenAt;
    if (at == null) return;
    final next = m.chapters.where((c) => c.state == 'waiting').firstOrNull;
    unawaited(Reminders.i.storyReady(at, next?.title ?? 'پرونده‌ی بعدی'));
  }

  Future<void> _countdownDone() async {
    await Api.i.refreshConfig();
    if (mounted) setState(() {});
  }

  Future<void> _play(StoryChapter c, {bool warrant = false, bool skip = false}) async {
    if (!needOnline(context)) return;
    try {
      if (c.state == 'ready' || c.state == 'waiting') {
        final m = skip ? await Api.i.skipStoryWait(c.chapter) : await Api.i.openStoryChapter(c.chapter, warrant: warrant);
        if (mounted) setState(() => _map = m);
        _remind(m);
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaseScreen(caseId: c.id)));
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'not_enough_coins') {
        await showNeedCoins(context, e.need);
      } else {
        toast(context, Api.friendly(e));
      }
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
  }

  Future<void> _skip(StoryChapter c) async {
    final cost = c.skipCost ?? 0;
    final ok = await confirm(context, 'رد شدن از انتظار', 'با ${fa(cost)} سکه همین الان پرونده‌ی «${c.title ?? 'بعدی'}» باز می‌شه.', 'باز کن');
    if (ok && mounted) await _play(c, skip: true);
  }

  Future<void> _useWarrant(StoryChapter c) async {
    final ok = await confirm(context, 'حکم بازرسی', 'یه حکم خرج می‌شه و پرونده‌ی «${c.title ?? 'بعدی'}» همین الان باز می‌شه.', 'باز کن');
    if (ok && mounted) await _play(c, warrant: true);
  }

  @override
  Widget build(BuildContext context) {
    final m = _map;
    if (_open && m != null && m.open) return _mapView(m);
    return _comingSoon();
  }

  // ---------------------------------------------------------------- before it opens

  Widget _comingSoon() {
    final s = Api.i.upcomingStory;
    // the planned start (Mon 12 Oct 00:00 Tehran) if the server doesn't say
    final at = _time(s['opens_at']) ?? DateTime.utc(2026, 10, 11, 20, 30).toLocal();
    final timePassed = !at.isAfter(DateTime.now());
    final season = (s['season'] as num?)?.toInt() ?? 1;
    final waiting = _open && _error == null; // open, the map is on its way
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          Text('داستان', style: tDisplay(26)),
          Text('پرونده‌های سرگرد ناصری · یه مسیر بی‌پایان', style: tBody(13, color: K.textSoft)),
          const SizedBox(height: 14),
          SectionBanner(
            background: Image.asset('assets/banners/story_s01.webp', fit: BoxFit.cover),
            chip: 'فصل ${fa(season)} · ${_open ? 'شروع شد' : 'به‌زودی'}',
            title: (s['title'] as String?) ?? 'کبریت سوخته',
            subtitle: s['tagline'] as String?,
            countdownLabel: timePassed ? null : 'تا شروع داستان',
            at: timePassed ? null : at,
            onCountdownDone: _countdownDone,
            button: _open
                ? _note(_error ?? (waiting ? 'پرونده‌ها دارن آماده می‌شن...' : ''), retry: _error != null)
                : (timePassed ? _note('ناصری هنوز داره پرونده‌های فصل اول رو آماده می‌کنه. چند روز دیگه!') : null),
          ),
          const SizedBox(height: 14),
          const PartnerCard(text: _partnerHello),
          const SizedBox(height: 14),
          _howItWorks(),
        ]),
      ),
    );
  }

  Widget _note(String text, {bool retry = false}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Text(text, style: tBody(13.5, w: FontWeight.w700))),
          if (retry) TextButton(onPressed: _load, child: Text('دوباره', style: tBody(13.5, color: K.brass, w: FontWeight.w900))),
        ]),
      );

  Widget _howItWorks() => const InfoCard(title: 'چطوری کار می‌کنه؟', lines: [
        (Icons.route_rounded, 'هر فصل ده پرونده داره و پشت همه‌شون یه راز بزرگه که توی پرونده‌ی آخر معلوم می‌شه.'),
        (Icons.lock_open_rounded, 'سه پرونده‌ی اول رایگانه و پشت سر هم، بدون انتظار باز می‌شن.'),
        (Icons.gavel_rounded, 'از پرونده‌ی چهارم، بعد از تموم کردن پرونده‌ی قبلی یا یه «حکم بازرسی» می‌خوای، یا ۱۲ ساعت صبر می‌کنی، یا با سکه از انتظار رد می‌شی.'),
        (Icons.verified_rounded, 'حکم می‌گیری: با حل پرونده‌ی هر شب، با انجام هر سه مأموریت روزانه، با زنجیره‌ی ۳، ۷، ۱۴ و ۳۰ شب و با حل پرونده‌ی آخر هفته.'),
        (Icons.all_inclusive_rounded, 'فصل که تموم بشه، فصل بعدی شروع می‌شه. داستان تموم نمی‌شه.'),
      ]);

  // ---------------------------------------------------------------- the career map

  Widget _mapView(StoryMap m) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: K.brass,
          onRefresh: _load,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
            Row(children: [
              Expanded(child: Text('داستان', style: tDisplay(26))),
              _warrantChip(m.warrants),
            ]),
            Text('پرونده‌های ${m.partner} · فصل ${fa(m.season)}', style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 14),
            SectionBanner(
              background: Image.asset('assets/banners/story_s01.webp', fit: BoxFit.cover),
              chip: 'فصل ${fa(m.season)} · ${fa(m.done)} از ${fa(m.chapters.length)} پرونده',
              title: m.title,
              subtitle: m.tagline,
            ),
            const SizedBox(height: 16),
            if (m.done == 0 && m.chapters.isNotEmpty) ...[
              const PartnerCard(text: _partnerHello),
              const SizedBox(height: 16),
            ],
            for (int i = 0; i < m.chapters.length; i++) _node(m, m.chapters[i]),
            _soon(),
            const SizedBox(height: 16),
            _howItWorks(),
          ]),
        ),
      ),
    );
  }

  Widget _warrantChip(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: K.brass.withValues(alpha: n > 0 ? 0.2 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: K.brass.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.gavel_rounded, size: 16, color: K.brass),
          const SizedBox(width: 5),
          Text('${fa(n)} حکم', style: tBody(13, color: K.brass, w: FontWeight.w900)),
        ]),
      );

  Color _nodeColor(String state) => switch (state) {
        'done' => K.brass,
        'open' || 'ready' => K.stamp,
        _ => K.night3,
      };

  Widget _node(StoryMap m, StoryChapter c) {
    final active = c.state == 'open' || c.state == 'ready';
    final icon = switch (c.state) {
      'done' => c.solved ? Icons.check_rounded : Icons.close_rounded,
      'waiting' => Icons.hourglass_top_rounded,
      'locked' => Icons.lock_rounded,
      _ => null,
    };
    final dot = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _nodeColor(c.state),
        border: Border.all(color: c.state == 'locked' ? K.textSoft.withValues(alpha: 0.4) : K.brass, width: 2),
        boxShadow: active ? [BoxShadow(color: K.stamp.withValues(alpha: 0.5), blurRadius: 14)] : null,
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: 22, color: c.state == 'done' ? K.ink : K.textSoft)
          : Text(fa(c.chapter), style: tDisplay(18, color: Colors.white)),
    );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 44,
          child: Column(children: [
            dot,
            Expanded(child: Container(width: 3, margin: const EdgeInsets.symmetric(vertical: 2), color: K.textSoft.withValues(alpha: 0.35))),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 12), child: _chapterCard(m, c))),
      ]),
    );
  }

  Widget _chapterCard(StoryMap m, StoryChapter c) {
    final locked = c.state == 'locked';
    final title = locked ? 'پرونده‌ی ${fa(c.chapter)}' : (c.title ?? 'پرونده‌ی ${fa(c.chapter)}');
    final body = switch (c.state) {
      'done' => c.solved ? Stars(count: c.stars, size: 20) : Text('این یکی از دستت در رفت', style: tBody(12.5, color: K.stamp, w: FontWeight.w700)),
      'open' => Text('در جریان؛ ادامه بده', style: tBody(12.5, color: K.brass, w: FontWeight.w700)),
      'ready' => Text('آماده‌ست', style: tBody(12.5, color: K.ok, w: FontWeight.w700)),
      'waiting' => _waiting(c),
      _ => Text('اول پرونده‌ی قبلی رو تموم کن', style: tBody(12.5, color: K.textSoft)),
    };
    final tappable = c.state == 'done' || c.state == 'open' || c.state == 'ready';
    return GestureDetector(
      onTap: tappable ? () => _play(c) : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: locked ? K.night2.withValues(alpha: 0.6) : K.night2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: (c.state == 'open' || c.state == 'ready') ? K.stamp.withValues(alpha: 0.8) : K.night3, width: 1.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(title, style: tBody(15, w: FontWeight.w900, color: locked ? K.textSoft : K.text))),
            if (tappable) const Icon(Icons.chevron_left_rounded, color: K.textSoft),
          ]),
          if (c.location != null && !locked) Text(c.location!, style: tBody(12, color: K.textSoft)),
          const SizedBox(height: 6),
          body,
        ]),
      ),
    );
  }

  Widget _waiting(StoryChapter c) {
    final at = c.unlockAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (at != null) _Remaining(at: at, onDone: _load),
      const SizedBox(height: 8),
      StampButton(
        label: 'با یک حکم باز کن',
        icon: Icons.gavel_rounded,
        height: 44,
        onTap: c.canWarrant ? () => _useWarrant(c) : null,
      ),
      if (!c.canWarrant)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('حکمی نداری؛ با حل پرونده‌ی امشب یکی می‌گیری', style: tBody(11.5, color: K.textSoft)),
        ),
      const SizedBox(height: 6),
      GhostButton(label: 'رد شدن با سکه · ${fa(c.skipCost ?? 0)}', icon: Icons.monetization_on_rounded, color: K.brass, onTap: () => _skip(c)),
    ]);
  }

  Widget _soon() => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 44,
            child: Column(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: K.textSoft.withValues(alpha: 0.5), width: 2)),
                child: const Icon(Icons.more_horiz_rounded, color: K.textSoft),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('پرونده‌های بعدی به‌زودی می‌رسن', style: tBody(13, color: K.textSoft)),
            ),
          ),
        ]),
      );
}

/// "Opens in 07:42:10", ticking; [onDone] when the time is reached.
class _Remaining extends StatefulWidget {
  const _Remaining({required this.at, this.onDone});
  final DateTime at;
  final VoidCallback? onDone;

  @override
  State<_Remaining> createState() => _RemainingState();
}

class _RemainingState extends State<_Remaining> {
  Timer? _t;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (!_fired && !widget.at.isAfter(DateTime.now())) {
        _fired = true;
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var left = widget.at.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    String two(int v) => fa(v).padLeft(2, '۰');
    return Row(children: [
      const Icon(Icons.timer_outlined, size: 16, color: K.brass),
      const SizedBox(width: 6),
      Text('باز می‌شه تا ${two(left.inHours)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)} دیگه',
          style: tBody(12.5, color: K.brass, w: FontWeight.w700)),
    ]);
  }
}
