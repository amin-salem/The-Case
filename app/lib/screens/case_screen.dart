import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/case_clock.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/coach_marks.dart';
import '../widgets/crime_tape.dart';
import '../widgets/engagement.dart';
import '../widgets/fx.dart';
import '../widgets/offline.dart';
import '../widgets/scene.dart';
import '../widgets/typewriter.dart';
import 'accuse_screen.dart';
import 'dialogs.dart';
import 'result_screen.dart';
import 'suspect_sheet.dart';

IconData evidenceIcon(String type) => switch (type) {
      'cctv' => Icons.videocam_rounded,
      'document' => Icons.description_rounded,
      'forensic' => Icons.biotech_rounded,
      'phone' => Icons.smartphone_rounded,
      'receipt' => Icons.receipt_long_rounded,
      'witness' => Icons.record_voice_over_rounded,
      'object' => Icons.inventory_2_rounded,
      _ => Icons.push_pin_rounded,
    };

String evidenceType(String type) => switch (type) {
      'cctv' => 'دوربین',
      'document' => 'سند',
      'forensic' => 'پزشکی قانونی',
      'phone' => 'گوشی',
      'receipt' => 'فاکتور',
      'witness' => 'شاهد',
      'object' => 'شیء',
      _ => 'مدرک',
    };

/// Notes the player puts on suspects while thinking.
enum SuspectMark { none, suspicious, innocent }

class CaseScreen extends StatefulWidget {
  const CaseScreen({super.key, required this.caseId});
  final String caseId;

  @override
  State<CaseScreen> createState() => _CaseScreenState();
}

class _CaseScreenState extends State<CaseScreen> {
  CaseData? _case;
  Progress? _progress;
  String? _error;
  bool _intro = true;
  final Map<String, SuspectMark> _marks = {};
  final Set<String> _pins = {}; // evidence the player has pinned to the board
  final Set<String> _seen = {}; // evidence cards the player has tapped (read)

  // the first-case tutorial: null = not showing, else the step (0..2)
  int? _coach;
  bool _coachChecked = false;
  TabController? _tabs;
  final _evidenceTabKey = GlobalKey();
  final _suspectsTabKey = GlobalKey();
  final _accuseKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    CaseClock.i.start(widget.caseId); // solving time counts only while this screen is open
    _loadNotes();
    _load();
  }

  @override
  void dispose() {
    CaseClock.i.stop();
    super.dispose();
  }

  /// The player's marks and pins stay on the phone, so leaving the case (or having
  /// no internet) never loses them.
  void _loadNotes() {
    try {
      final n = Api.i.loadNotes(widget.caseId);
      final marks = n['marks'];
      if (marks is Map) {
        final byName = SuspectMark.values.asNameMap();
        for (final e in marks.entries) {
          final m = byName['${e.value}'];
          if (m != null) _marks['${e.key}'] = m;
        }
      }
      final pins = n['pins'];
      if (pins is List) _pins.addAll([for (final p in pins) '$p']);
      final seen = n['seen'];
      if (seen is List) _seen.addAll([for (final p in seen) '$p']);
    } catch (e) {
      debugPrint('notes: $e');
    }
  }

  void _saveNotes() {
    Api.i.saveNotes(widget.caseId, {
      'marks': {for (final e in _marks.entries) if (e.value != SuspectMark.none) e.key: e.value.name},
      'pins': _pins.toList(),
      'seen': _seen.toList(),
    });
  }

  Future<void> _retry() async {
    setState(() => _error = null);
    if (!Api.i.online) await Api.i.reconnect();
    await _load();
  }

  Future<void> _load() async {
    try {
      final (c, p, _) = await Api.i.openCase(widget.caseId);
      if (!mounted) return;
      setState(() {
        _case = c;
        _progress = p;
        if (p.finished || p.hints.isNotEmpty || p.attempts > 0) _intro = false;
      });
      // the case file opens with its own sting and the sounds of the place
      if (_intro) {
        Sfx.i.openCase(c.scene);
      } else {
        Sfx.i.ambient('amb_${c.scene}');
      }
    } catch (e) {
      if (!mounted) return;
      if (_case != null) {
        // already showing the case: keep it, just say what happened
        toast(context, Api.friendly(e));
      } else {
        setState(() => _error = Api.isNetworkFail(e) && !Api.i.online ? Api.notSavedText : Api.friendly(e));
      }
    }
  }

  Future<void> _hint() async {
    final p = _progress!;
    final cost = p.nextHintCost;
    if (cost == null) return;
    if (!needOnline(context)) return;
    final vipFree = (Api.i.profile?.vip ?? false) && p.hints.isEmpty;
    final ok = await confirm(context, 'سرنخ ${fa(p.hints.length + 1)} از ${fa(p.hintCosts.length)}',
        '${vipFree ? 'اولین سرنخ برای VIP رایگانه.' : 'این سرنخ ${fa(cost)} سکه هزینه داره.'} '
            '${p.hints.isEmpty ? 'ستاره‌ای کم نمی‌شه.' : 'یه ستاره از امتیازت کم می‌شه.'}',
        'بگیر');
    if (!ok || !mounted) return;
    try {
      final (hint, progress) = await Api.i.buyHint(_case!.id);
      if (!mounted) return;
      setState(() => _progress = progress);
      Sfx.i.play('clue');
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: StampIn(
            child: Paper(
              color: K.clue,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lightbulb_rounded, color: K.ink, size: 34),
                const SizedBox(height: 8),
                Text(hint, textAlign: TextAlign.center, style: tBody(17, color: K.ink, w: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
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

  Future<void> _accuse() async {
    if (!needOnline(context)) return;
    final r = await Navigator.of(context).push<AccuseResult>(
        MaterialPageRoute(builder: (_) => AccuseScreen(caseData: _case!, progress: _progress!, marks: _marks)));
    if (r == null || !mounted) return;
    if (r.progress != null) setState(() => _progress = r.progress);
    if (r.result == 'solved' || r.result == 'failed') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ResultScreen(caseData: _case!, result: r)));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: K.night),
        body: SafeArea(
          child: Center(
            child: _error == null
                ? const CircularProgressIndicator(color: K.brass)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Api.i.online ? Icons.cloud_off_rounded : Icons.wifi_off_rounded, color: K.textSoft, size: 40),
                      const SizedBox(height: 10),
                      Text(_error!, textAlign: TextAlign.center, style: tBody(15)),
                      const SizedBox(height: 14),
                      StampButton(label: 'دوباره امتحان کن', icon: Icons.refresh_rounded, onTap: _retry),
                    ]),
                  ),
          ),
        ),
      );
    }
    if (_intro) return _introView(c);
    return _investigation(c);
  }

  // ---------------------------------------------------------------- intro

  Widget _introView(CaseData c) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: AnimatedScene(scene: c.scene, height: double.infinity, dim: 0.55)),
        Positioned(left: -20, right: -20, top: MediaQuery.paddingOf(context).top + 52,
            child: Transform.rotate(angle: -0.05, child: const CrimeTape(height: 22))),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: max(0.0, box.maxHeight - 40)),
                child: IntrinsicHeight(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: K.text)),
                          const SoundButton(),
                        ]),
                      ),
                      const Spacer(),
                      StampIn(child: Align(alignment: Alignment.centerRight, child: StampMark('پرونده‌ی شماره‌ی ${fa(c.number)}', size: 22))),
                      const SizedBox(height: 14),
                      FadeSlideIn(delay: const Duration(milliseconds: 300), child: Text(c.title, style: tDisplay(32))),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 500),
                        child: Row(children: [
                          const Icon(Icons.place_rounded, size: 16, color: K.brass),
                          const SizedBox(width: 4),
                          Expanded(child: Text(c.location, style: tBody(14, color: K.textSoft))),
                          Difficulty(c.difficulty, color: K.brass),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 800),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
                          child: Typewriter(c.intro, style: tBody(16.5)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      StampButton(label: 'شروع تحقیقات', icon: Icons.search_rounded, onTap: () => setState(() => _intro = false)),
                  ]),
                ),
              ),
            ),
          ),
        ),
        const Positioned.fill(child: CrimeTapeIntro()),
      ]),
    );
  }

  // ---------------------------------------------------------------- investigation

  /// The first time a player ever opens a case: three coach marks (evidence, suspects, accuse).
  /// Players who already solved cases before this version never see it.
  void _maybeTutorial() {
    final p = _progress;
    if (!mounted || p == null || p.finished || Api.i.flag('tutorial_done')) return;
    unawaited(Api.i.setFlag('tutorial_done'));
    if ((Api.i.profile?.casesSolved ?? 0) > 0) return;
    setState(() => _coach = 0);
    _tabs?.animateTo(1);
  }

  void _coachTo(int? step) {
    setState(() => _coach = step);
    if (step == 0) _tabs?.animateTo(1);
    if (step == 1) _tabs?.animateTo(2);
  }

  Widget _investigation(CaseData c) {
    final p = _progress!;
    if (!_coachChecked) {
      _coachChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTutorial());
    }
    return DefaultTabController(
      length: 3,
      child: Builder(builder: (context) {
        _tabs = DefaultTabController.of(context);
        return Stack(children: [
          _investigationScaffold(c, p),
          if (_coach != null)
            Positioned.fill(
              child: CoachMarks(
                step: _coach!,
                targets: [_evidenceTabKey, _suspectsTabKey, _accuseKey],
                steps: const [
                  ('مدارک رو بخون', 'هر مدرکی رو که خوندی بزن تا نشانش کنی. دروغ مقصر لای همین‌هاست.'),
                  ('از مظنون‌ها سؤال کن', 'روی هر مظنون بزن، حرفش رو بخون و ازش بازجویی کن.'),
                  ('با مدرک متهم کن', 'وقتی دروغ رو پیدا کردی، مقصر رو انتخاب کن و مدرکی رو نشون بده که دروغش رو ثابت می‌کنه.'),
                ],
                onNext: () => _coachTo(_coach! + 1 < 3 ? _coach! + 1 : null),
                onSkip: () => _coachTo(null),
              ),
            ),
        ]);
      }),
    );
  }

  Widget _investigationScaffold(CaseData c, Progress p) {
    return Scaffold(
        // a real bottom bar: the body ends above it, and it keeps clear of the
        // phone's navigation / gesture bar
        bottomNavigationBar: p.finished ? null : _bottomBar(p),
        body: GrainBackground(
          child: SafeArea(
            child: Column(children: [
              _header(c, p),
              const OfflineBanner(margin: EdgeInsets.fromLTRB(12, 8, 12, 0)),
              TabBar(
                indicatorColor: K.stamp,
                labelColor: K.text,
                unselectedLabelColor: K.textSoft,
                labelStyle: tBody(15, w: FontWeight.w900),
                dividerColor: Colors.transparent,
                tabs: [
                  const Tab(text: 'پرونده'),
                  Tab(key: _evidenceTabKey, text: 'مدارک (${fa(c.evidence.length)})'),
                  Tab(key: _suspectsTabKey, text: 'مظنون‌ها (${fa(c.suspects.length)})'),
                ],
              ),
              Expanded(
                child: TabBarView(children: [_storyTab(c, p), _evidenceTab(c), _suspectsTab(c)]),
              ),
            ]),
          ),
        ),
    );
  }

  Widget _header(CaseData c, Progress p) {
    // fixed-height header: a very large system font is capped here so it never overflows
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SizedBox(
      height: 120,
      child: Stack(children: [
        Positioned.fill(child: AnimatedScene(scene: c.scene, height: 120, dim: 0.5)),
        const Positioned(left: 0, right: 0, bottom: 0, child: CrimeTape(height: 13)),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_forward_rounded, color: K.text)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 8),
                Text(c.title, style: tDisplay(20), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(c.location, style: tBody(12, color: K.textSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                const Spacer(),
                if (p.solved)
                  Row(children: [
                    Stars(count: p.stars, size: 18),
                    const SizedBox(width: 6),
                    Flexible(child: Text('حل شد', maxLines: 1, style: tBody(13, color: K.brass, w: FontWeight.w900))),
                  ])
                else if (p.failed)
                  Text('این پرونده رو باختی', style: tBody(13, color: K.stamp, w: FontWeight.w900))
                else
                  Row(children: [
                    for (int i = 0; i < p.attemptsLeft + p.attempts; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(Icons.gavel_rounded, size: 16, color: i < p.attemptsLeft ? K.stamp : K.textSoft.withValues(alpha: 0.3)),
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('${fa(p.attemptsLeft)} فرصت متهم کردن',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.textSoft)),
                    ),
                  ]),
              ]),
            ),
            const SoundButton(),
            ListenableBuilder(listenable: Api.i, builder: (_, __) => CoinChip(coins: Api.i.coins)),
          ]),
        ),
      ]),
      ),
    );
  }

  Widget _storyTab(CaseData c, Progress p) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Paper(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SectionTitle(c.weekly && c.chapters.isNotEmpty ? c.chapters.first.title : 'گزارش اولیه'),
          Text(c.intro, style: tBody(16, color: K.ink)),
        ]),
      ),
      for (final ch in c.chapters.skip(1)) ...[
        const SizedBox(height: 12),
        Paper(
          color: K.paperDark,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(ch.title),
            Text(ch.text, style: tBody(15.5, color: K.ink)),
          ]),
        ),
      ],
      if (c.weekly && c.nextChapterAt != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: K.brass.withValues(alpha: 0.5))),
          child: Row(children: [
            const Icon(Icons.lock_clock_rounded, color: K.brass),
            const SizedBox(width: 8),
            Expanded(
              child: Text('فصل ${fa(c.chapters.length + 1)} از ${fa(c.chaptersTotal)} با مدارک تازه باز می‌شه',
                  style: tBody(13.5, w: FontWeight.w700)),
            ),
            Text(faClock(c.nextChapterAt!.difference(DateTime.now()).isNegative
                    ? Duration.zero
                    : c.nextChapterAt!.difference(DateTime.now())),
                style: tDisplay(16, color: K.brass)),
          ]),
        ),
      ],
      if (p.hints.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (int i = 0; i < p.hints.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: K.clue, borderRadius: BorderRadius.circular(6)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_rounded, color: K.ink, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('سرنخ ${fa(i + 1)}: ${p.hints[i]}', style: tBody(14, color: K.ink, w: FontWeight.w700))),
            ]),
          ),
      ],
      if (p.finished && c.explanation != null) ...[
        const SizedBox(height: 14),
        _solutionBox(c),
        const SizedBox(height: 14),
        GuessStatsCard(key: ValueKey('stats-${c.id}'), caseData: c),
      ] else ...[
        const SizedBox(height: 14),
        Text('چطور حل کنم؟', style: tDisplay(16)),
        const SizedBox(height: 4),
        Text('مدارک رو بخون و از مظنون‌ها سؤال کن. مقصر درباره‌ی چیزی دروغ گفته. '
            'وقتی پیداش کردی، متهمش کن و مدرکی رو نشون بده که دروغش رو ثابت می‌کنه. '
            'اتهام اشتباه و سرنخ دوم و سوم، ستاره‌هات رو کم می‌کنه.', style: tBody(14, color: K.textSoft)),
      ],
    ]);
  }

  Widget _solutionBox(CaseData c) {
    final culprit = c.culprit == null ? null : c.suspect(c.culprit!);
    return Paper(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (culprit != null) AnimatedSuspect(avatar: culprit.avatar, size: 64, mood: Mood.sad),
          const SizedBox(width: 10),
          Expanded(child: Text('مقصر: ${culprit?.name ?? ''}', style: tDisplay(19, color: K.stamp))),
        ]),
        const SizedBox(height: 8),
        Text(c.explanation ?? '', style: tBody(15.5, color: K.ink)),
        if (c.proof.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('مدرک کلیدی: ${c.proof.map((id) => c.evidenceById(id)?.title ?? id).join('، ')}',
              style: tBody(13, color: K.inkSoft, w: FontWeight.w700)),
        ],
      ]),
    );
  }

  /// "X of Y evidence seen": the cards tapped or pinned (kept with the notes).
  Widget _evidenceHeader(CaseData c) {
    final ids = {for (final e in c.evidence) e.id};
    final seen = {..._seen, ..._pins}.where(ids.contains).length;
    final total = c.evidence.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Icon(seen >= total ? Icons.task_alt_rounded : Icons.visibility_rounded, size: 18, color: K.brass),
        const SizedBox(width: 6),
        Text('${fa(seen)} از ${fa(total)} مدرک دیده شده', style: tBody(13, w: FontWeight.w700)),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : seen / total,
              minHeight: 6,
              color: K.brass,
              backgroundColor: K.night3,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _evidenceTab(CaseData c) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: c.evidence.length + 1,
      itemBuilder: (_, j) {
        if (j == 0) return _evidenceHeader(c);
        final i = j - 1;
        final e = c.evidence[i];
        final key = (_progress?.finished ?? false) && c.proof.contains(e.id);
        final pinned = _pins.contains(e.id);
        return FadeSlideIn(
          delay: Duration(milliseconds: 50 * i),
          child: GestureDetector(
            onTap: () {
              Sfx.i.play('paper', volume: 0.4);
              setState(() {
                pinned ? _pins.remove(e.id) : _pins.add(e.id);
                _seen.add(e.id);
              });
              _saveNotes();
            },
            child: AnimatedRotation(
            turns: pinned ? 0 : ((i % 3) - 1) * 0.0015,
            duration: const Duration(milliseconds: 250),
            child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: Stack(clipBehavior: Clip.none, children: [
            Paper(
              color: key ? K.clue : K.paper,
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: K.ink, borderRadius: BorderRadius.circular(10)),
                  child: Icon(evidenceIcon(e.type), color: K.paper, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(e.title, style: tBody(15, color: K.ink, w: FontWeight.w900))),
                      const SizedBox(width: 6),
                      Text(evidenceType(e.type), style: tBody(11, color: K.inkSoft)),
                    ]),
                    const SizedBox(height: 4),
                    Text(e.text, style: tBody(14.5, color: K.ink)),
                    if (key) Text('مدرک کلیدی', style: tBody(12, color: K.stamp, w: FontWeight.w900)),
                    if (pinned && !key) Text('نشان‌شده', style: tBody(11, color: K.stamp, w: FontWeight.w900)),
                  ]),
                ),
              ]),
            ),
            Positioned(top: -8, left: 10, child: PinBadge(on: pinned)),
            Positioned(top: -10, right: 8, child: EvidenceMarker(i + 1)),
            ]),
          ),
          ),
          ),
        );
      },
    );
  }

  Widget _suspectsTab(CaseData c) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: c.suspects.length,
      itemBuilder: (_, i) {
        final s = c.suspects[i];
        final mark = _marks[s.id] ?? SuspectMark.none;
        final culprit = (_progress?.finished ?? false) && c.culprit == s.id;
        return FadeSlideIn(
          delay: Duration(milliseconds: 60 * i),
          child: GestureDetector(
            onTap: () async {
              unawaited(Api.i.markSeen(widget.caseId, s.id));
              void keep(SuspectMark m) {
                _marks[s.id] = m; // saved at once: closing the sheet any way must not lose it
                _saveNotes();
                if (mounted) setState(() {});
              }
              final m = await showSuspect(context, s, mark, onMark: keep);
              if (m != null && mounted) keep(m);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: K.night2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: culprit ? K.stamp : mark == SuspectMark.suspicious ? K.brass : K.night3, width: culprit ? 2 : 1),
              ),
              child: Row(children: [
                Container(
                  decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
                  child: AnimatedSuspect(avatar: s.avatar, size: 78, mood: culprit ? Mood.sad : Mood.calm),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(s.name, style: tBody(16, w: FontWeight.w900))),
                      if (culprit) Text('مقصر', style: tBody(12, color: K.stamp, w: FontWeight.w900))
                      else if (mark == SuspectMark.suspicious) Text('مشکوک', style: tBody(12, color: K.brass, w: FontWeight.w900))
                      else if (mark == SuspectMark.innocent) Text('بی‌گناه', style: tBody(12, color: K.ok, w: FontWeight.w900)),
                    ]),
                    Text('${s.role} · ${fa(s.age)} ساله', style: tBody(12, color: K.textSoft)),
                    const SizedBox(height: 4),
                    Text('«${s.statement}»', maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(13.5)),
                    Text('برای بازجویی بزن', style: tBody(11, color: K.brass)),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _bottomBar(Progress p) {
    final cost = p.nextHintCost;
    return Container(
      decoration: const BoxDecoration(color: K.night2, border: Border(top: BorderSide(color: K.night3))),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(children: [
              Expanded(
                flex: 2,
                child: StampButton(
                  label: cost == null ? 'سرنخی نمونده' : 'سرنخ · ${fa(cost)}',
                  icon: Icons.lightbulb_rounded,
                  color: K.night3,
                  onTap: cost == null ? null : _hint,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: KeyedSubtree(
                    key: _accuseKey,
                    child: _case!.weekly && _case!.chapters.length < _case!.chaptersTotal
                        // the proof cards come with the last chapter: accusing earlier only wastes a try
                        ? GhostButton(
                            label: 'متهم کردن از فصل آخر',
                            icon: Icons.lock_clock_rounded,
                            onTap: () => toast(context, 'مدرک اصلی توی فصل آخره. بعد از باز شدن فصل ${fa(_case!.chaptersTotal)} می‌تونی متهم کنی.'))
                        : StampButton(label: 'متهم کن', icon: Icons.gavel_rounded, onTap: _accuse)),
              ),
          ]),
        ),
      ),
    );
  }
}
