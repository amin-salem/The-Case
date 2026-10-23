import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/claim_notes.dart';
import '../models/tools.dart';
import '../services/api.dart';
import '../services/case_clock.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/cast_strip.dart';
import '../widgets/claim_notes.dart';
import '../widgets/category.dart';
import '../widgets/chapter_ui.dart';
import '../widgets/profile_bell.dart';
import '../widgets/character.dart';
import '../widgets/coach_marks.dart';
import '../widgets/crime_tape.dart';
import '../widgets/engagement.dart';
import '../widgets/fx.dart';
import '../widgets/offline.dart';
import '../widgets/partner_card.dart';
import '../widgets/rate_card.dart';
import '../widgets/tool_tray.dart';
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
  List<ClaimLink> _claimLinks = [];
  late final String? _noteOwner;
  late final int _noteAccount;
  bool _notesInvalid = false;
  bool get _sameNoteOwner => !_notesInvalid && _noteOwner != null && Api.i.playerId == _noteOwner && Api.i.account == _noteAccount;

  // the first-case tutorial: null = not showing, else the step (0..2)
  int? _coach;
  bool _coachChecked = false;
  TabController? _tabs;
  // weekend cases (chapters): what the player has opened, the chapter filter, the «فصل N باز شد» banner
  ChapterSeen? _chSeen;
  int? _chFilter; // null = all chapters
  int _banner = 0; // the chapter whose banner is showing (0 = none)
  Timer? _chapterTimer;
  int _chapterRetries = 0;
  final _evidenceTabKey = GlobalKey();
  final _suspectsTabKey = GlobalKey();
  final _accuseKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _noteOwner = Api.i.playerId;
    _noteAccount = Api.i.account;
    Api.i.addListener(_noteAccountChanged);
    CaseClock.i.start(widget.caseId); // solving time counts only while this screen is open
    _loadNotes();
    _load();
    unawaited(_loadChapterSeen());
  }

  Future<void> _loadChapterSeen() async {
    final seen = await ChapterSeen.load(widget.caseId);
    if (!mounted) return;
    setState(() => _chSeen = seen);
    _updateBanner();
  }

  /// A weekend case: the banner for the newest chapter, when something in it has not been opened yet.
  void _updateBanner() {
    final c = _case, seen = _chSeen;
    if (c == null || seen == null || !mounted) return;
    final n = bannerChapter(c, seen);
    if (n != _banner) setState(() => _banner = n ?? 0);
  }

  /// The next chapter opens while the player is still in the case: load it again a moment after it opens.
  void _scheduleChapterReload(CaseData c) {
    _chapterTimer?.cancel();
    final at = c.nextChapterAt;
    if (!isChaptered(c) || at == null) return;
    final wait = at.difference(DateTime.now());
    final delay = wait.isNegative ? Duration(seconds: 15 * (_chapterRetries < 4 ? 1 : 4)) : wait + const Duration(seconds: 2);
    if (wait.isNegative) _chapterRetries++;
    _chapterTimer = Timer(delay, () {
      if (mounted) _load();
    });
  }

  void _closeBanner({bool go = false}) {
    final n = _banner;
    if (n == 0) return;
    setState(() {
      _banner = 0;
      if (go) _chFilter = n;
    });
    unawaited(_chSeen?.setBanner(n));
    if (go) _tabs?.animateTo(1);
  }

  @override
  void dispose() {
    _chapterTimer?.cancel();
    Api.i.removeListener(_noteAccountChanged);
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
      _claimLinks = ClaimLink.read(n['links']);
    } catch (e) {
      debugPrint('notes: $e');
    }
  }

  Future<void> _saveNotes() async {
    if (!_sameNoteOwner) return;
    try {
      await Api.i.saveNotes(widget.caseId, {
      ...Api.i.loadNotes(widget.caseId),
      'marks': {for (final e in _marks.entries) if (e.value != SuspectMark.none) e.key: e.value.name},
      'pins': _pins.toList(),
      'seen': _seen.toList(),
      'links': [for (final link in _claimLinks) link.toJson()],
    }, owner: _noteOwner);
    } catch (_) {
      if (mounted && _sameNoteOwner) toast(context, 'یادداشت روی گوشی ذخیره نشد؛ دوباره امتحان کن.');
    }
  }

  void _noteAccountChanged() {
    if (!mounted || (Api.i.playerId == _noteOwner && Api.i.account == _noteAccount)) return;
    final route = ModalRoute.of(context);
    setState(() { _notesInvalid = true; _claimLinks = []; _marks.clear(); _pins.clear(); _seen.clear(); });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || route == null || !route.isActive) return;
      Navigator.of(context).popUntil((r) => r == route || r.isFirst);
      if (route.isCurrent && !route.isFirst) Navigator.of(context).pop();
    });
  }

  Future<void> _editClaim({ClaimLink? existing, String? claim, String? evidence}) async {
    final c = _case;
    if (!_sameNoteOwner || c == null) return;
    final link = await showClaimNoteEditor(context, caseData: c, existing: existing, claim: claim, evidence: evidence,
      ownerChanges: Api.i, ownerCurrent: () => mounted && _sameNoteOwner);
    if (!mounted || !_sameNoteOwner || link == null) return;
    try {
      setState(() => _claimLinks = putClaimLink(_claimLinks, link, replacing: existing?.id));
      await _saveNotes();
    } on StateError catch (_) {
      if (mounted) toast(context, 'سقف یادداشت‌های این پرونده پر شده؛ یکی رو ویرایش یا حذف کن.');
    }
  }

  void _removeClaim(ClaimLink link) {
    if (!_sameNoteOwner) return;
    setState(() => _claimLinks.removeWhere((l) => l.id == link.id));
    _saveNotes();
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
        // a chapter that is open can be filtered; one that vanished (never expected) cannot stay selected
        if (_chFilter != null && _chFilter! > openChapters(c)) _chFilter = null;
      });
      if (isChaptered(c)) {
        if (c.nextChapterAt == null || c.nextChapterAt!.isAfter(DateTime.now())) _chapterRetries = 0;
        _scheduleChapterReload(c);
        _updateBanner();
      }
      unawaited(_loadTools());
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

  // ---------------------------------------------------------------- detective tools «ابزارهای کارآگاهی»

  ToolTray? _tray;
  bool _toolBusy = false;

  Future<void> _loadTools() async {
    final t = await Api.i.toolsTray(widget.caseId);
    if (mounted && t != null) setState(() => _tray = t);
  }

  Future<String?> _pickSuspect(ToolInfo t) {
    final list = [for (final s in _case!.suspects) if (t.suspects!.contains(s.id)) s];
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: K.night2,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text('${t.title}: روی کدوم مظنون؟', style: tDisplay(18)),
            ),
            for (final s in list)
              ListTile(
                key: ValueKey('tool-suspect-${s.id}'),
                title: Text(s.name, style: tBody(15, w: FontWeight.w900)),
                subtitle: Text(s.role, style: tBody(12.5, color: K.textSoft)),
                onTap: () => Navigator.pop(ctx, s.id),
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Future<void> _showToolResult(ToolInfo t, String text) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: StampIn(
          child: Paper(
            color: K.clue,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(toolIcon(t.kind), color: K.ink, size: 34),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: tBody(16.5, color: K.ink, w: FontWeight.w700)),
              const SizedBox(height: 12),
              StampButton(label: 'باشه', height: 44, onTap: () => Navigator.pop(ctx)),
            ]),
          ),
        ),
      ),
    );
  }

  /// One tap uses a tool the player holds; with none in hand it asks once and buys. Never blocks the case.
  Future<void> _useTool(ToolInfo t) async {
    if (_toolBusy) return;
    if (t.used && t.result != null) {
      await _showToolResult(t, t.result!.text);
      return;
    }
    if (!t.usable || !needOnline(context)) return;
    String? suspect;
    if (t.needsSuspect) {
      suspect = await _pickSuspect(t);
      if (suspect == null || !mounted) return;
    }
    var buy = !t.hasOne;
    final who = suspect == null ? '' : ' روی ${_case!.suspects.firstWhere((x) => x.id == suspect).name}';
    final ok = await confirm(
        context,
        '${t.title}$who',
        '${_toolDoes(t.kind)}\n${_toolNever(t.kind)}\n'
        '${buy ? 'هزینه: ${fa(t.price)} سکه (الان ${fa(_tray?.coins ?? 0)} سکه داری).' : (t.freeAvailable && t.count == 0 ? 'این بار رایگانه.' : 'یکی از ابزارهات مصرف می‌شه.')} '
        'پلاکی کم نمی‌شه و ${(_tray?.night ?? 1) > 1 || _case!.weekly ? 'برای هر شب' : 'برای هر پرونده'} فقط یک بار می‌شه. '
        'اگه چیز تازه‌ای پیدا نشه، چیزی ازت کم نمی‌شه.',
        buy ? 'بخر و استفاده کن' : 'استفاده کن');
    if (!ok || !mounted) return;
    setState(() => _toolBusy = true);
    try {
      final out = await Api.i.useTool(_case!.id, t.kind, suspect: suspect, buy: buy);
      if (!mounted) return;
      setState(() => _tray = out.tray);
      if (out.nothingNew || out.result == null) {
        toast(context, out.text.isNotEmpty ? out.text : 'این بار چیز تازه‌ای پیدا نشد. چیزی ازت کم نشد.');
      } else {
        Sfx.i.play('clue');
        await _showToolResult(t, out.result!.text);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'not_enough_coins') {
        await showNeedCoins(context, e.need);
      } else {
        toast(context, e.code == 'already_used' || e.code == 'no_tool' ? 'وضعیت ابزارها به‌روز شد.' : Api.friendly(e));
        unawaited(_loadTools());
      }
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    } finally {
      if (mounted) setState(() => _toolBusy = false);
    }
  }

  String _toolDoes(String kind) => switch (kind) {
        'magnifier' => 'ذره‌بین یکی از مدارک رو که جزو اصلی حل پرونده نیست علامت می‌زنه.',
        'fingerprint' => 'اثر انگشت‌خوان می‌گه اسم این مظنون توی چند تا از مدارک اومده.',
        'camera' => 'دوربین مخفی یک مشاهده‌ی تازه و بی‌طرف درباره‌ی این مظنون نشون می‌ده.',
        _ => '',
      };

  String _toolNever(String kind) => switch (kind) {
        'fingerprint' => 'حکم گناه یا بی‌گناهی نمی‌ده؛ فقط راهنماست.',
        _ => 'مقصر رو لو نمی‌ده و پرونده رو حل نمی‌کنه.',
      };

  Future<void> _showToolHelp() async {
    final tray = _tray;
    if (tray == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: K.night2,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('tools-help-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ابزارها چطور کار می‌کنن؟', style: tDisplay(18)),
            const SizedBox(height: 4),
            Text('کمک‌های کوچیک برای تنگ‌تر کردن جستجو. هیچ‌کدوم مقصر رو لو نمی‌دن و هیچ‌کدوم امتیاز و پلاک رو عوض نمی‌کنن.',
                style: tBody(12.5, color: K.textSoft)),
            for (final t in tray.tools) ...[
              const SizedBox(height: 14),
              Row(children: [
                Icon(toolIcon(t.kind), color: K.brass, size: 22),
                const SizedBox(width: 8),
                Text('${t.title} · ${fa(t.price)} سکه', style: tBody(14.5, w: FontWeight.w900)),
              ]),
              const SizedBox(height: 4),
              Text(t.desc, style: tBody(13)),
              if (tray.how[t.kind] != null) ...[
                const SizedBox(height: 4),
                Text('چطور به دست میاد: ${tray.how[t.kind]!.$1}', style: tBody(12.5, color: K.textSoft)),
                Text('کجا استفاده می‌شه: ${tray.how[t.kind]!.$2}', style: tBody(12.5, color: K.textSoft)),
              ],
            ],
            const SizedBox(height: 14),
            StampButton(label: 'باشه', height: 44, onTap: () => Navigator.pop(ctx)),
          ]),
        ),
      ),
    );
  }

  /// What the tools found, pinned on the case so reopening it does not lose it.
  Widget _toolFindings() {
    final pinned = _tray?.pinned ?? const <ToolInfo>[];
    final earlier = _tray?.earlier ?? const <ToolResult>[];
    if (pinned.isEmpty && earlier.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      for (final t in pinned)
        Container(
          key: ValueKey('tool-finding-${t.kind}'),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: K.clue, borderRadius: BorderRadius.circular(6)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(toolIcon(t.kind), color: K.ink, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(t.result!.text, style: tBody(14, color: K.ink, w: FontWeight.w700))),
          ]),
        ),
      for (final r in earlier)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: K.clue.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(6)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(toolIcon(r.kind), color: K.ink, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('شب قبل: ${r.text}', style: tBody(14, color: K.ink, w: FontWeight.w700))),
          ]),
        ),
    ]);
  }

  Future<void> _hint() async {
    final p = _progress!;
    final cost = p.nextHintCost;
    if (cost == null) return;
    if (!needOnline(context)) return;
    final vipFree = (Api.i.profile?.vip ?? false) && p.hints.isEmpty;
    final ok = await confirm(context, 'سرنخ ${fa(p.hints.length + 1)} از ${fa(p.hintCosts.length)}',
        '${vipFree ? 'اولین سرنخ برای VIP رایگانه.' : 'این سرنخ ${fa(cost)} سکه هزینه داره.'} '
            '${p.hints.isEmpty ? 'پلاکی کم نمی‌شه.' : 'یه پلاک از امتیازت کم می‌شه.'}',
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
    if (_notesInvalid) return const Scaffold(body: SafeArea(child: Center(child: Text('حساب عوض شده؛ پرونده رو دوباره باز کن.'))));
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
                      StampIn(child: Align(alignment: Alignment.centerRight, child: StampMark(c.story != null ? 'فصل ${fa(c.number)}' : 'پرونده‌ی شماره‌ی ${fa(c.number)}', size: 22))),
                      const SizedBox(height: 14),
                      FadeSlideIn(delay: const Duration(milliseconds: 300), child: Text(c.title, style: tDisplay(32))),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 500),
                        child: Row(children: [
                          const Icon(Icons.place_rounded, size: 16, color: K.brass),
                          const SizedBox(width: 4),
                          Expanded(child: Text(c.location, style: tBody(14, color: K.textSoft))),
                          DifficultyBar(c.difficulty),
                        ]),
                      ),
                      if (c.category.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(alignment: Alignment.centerRight, child: CategoryBadge(c.category)),
                        ),
                      const SizedBox(height: 16),
                      if (c.story != null) ...[
                        FadeSlideIn(delay: const Duration(milliseconds: 600), child: PartnerCard(text: c.story!.intro, dark: false)),
                        const SizedBox(height: 12),
                      ],
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
              if (_banner > 0 && isChaptered(c))
                ChapterBanner(text: chapterBannerText(c, _banner), onGo: () => _closeBanner(go: true), onClose: _closeBanner),
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
                    Plaques(count: p.stars, size: 18),
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
            const ProfileBell(size: 32),
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
              child: Text(c.twoNights
                  ? 'شب دوم: یه مظنون تازه و مدارک جدید باز می‌شه'
                  : 'فصل ${fa(c.chapters.length + 1)} از ${fa(c.chaptersTotal)} با مدارک تازه باز می‌شه',
                  style: tBody(13.5, w: FontWeight.w700)),
            ),
            Text(faClock(c.nextChapterAt!.difference(DateTime.now()).isNegative
                    ? Duration.zero
                    : c.nextChapterAt!.difference(DateTime.now())),
                style: tDisplay(16, color: K.brass)),
          ]),
        ),
      ],
      if (c.twoNights && c.night1 != null) ...[
        const SizedBox(height: 12),
        _night1Card(c, p),
      ],
      const SizedBox(height: 18),
      CastStrip(suspects: c.suspects, onOpen: _openSuspect),
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
      _toolFindings(),
      if (p.finished && c.explanation != null) ...[
        const SizedBox(height: 14),
        _solutionBox(c),
        const SizedBox(height: 14),
        GuessStatsCard(key: ValueKey('stats-${c.id}'), caseData: c),
        const SizedBox(height: 12),
        RateCard(key: ValueKey('rate-${c.id}'), caseId: c.id, title: c.title),
      ] else if (p.failed && c.explanation == null) ...[
        // lost, and the answer is still secret (anti-cheat): wait for it, it shows here by itself
        const SizedBox(height: 14),
        Paper(
          child: Center(
            child: p.answerAt != null
                ? AnswerCountdown(at: p.answerAt!, onDone: _load)
                : Text('پاسخ به‌زودی منتشر می‌شه', style: tBody(15, color: K.ink, w: FontWeight.w900)),
          ),
        ),
      ] else ...[
        const SizedBox(height: 14),
        Text('چطور حل کنم؟', style: tDisplay(16)),
        const SizedBox(height: 4),
        Text('مدارک رو بخون و از مظنون‌ها سؤال کن. مقصر درباره‌ی چیزی دروغ گفته. '
            'وقتی پیداش کردی، متهمش کن و مدرکی رو نشون بده که دروغش رو ثابت می‌کنه. '
            'اتهام اشتباه و سرنخ دوم و سوم، پلاک‌هات رو کم می‌کنه.', style: tBody(14, color: K.textSoft)),
      ],
    ]);
  }

  /// Weekend format 3, night 1: «کی دروغ می‌گه؟». One try, a small reward; the answer comes with the card that proves it.
  Widget _night1Card(CaseData c, Progress p) {
    final n = c.night1!;
    final a = p.night1;
    final canAnswer = n.open && a == null && !p.finished && Api.i.online;
    return Paper(
      color: K.paperDark,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.nightlight_round, color: K.stamp, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text('شب اول · ${n.question}', style: tDisplay(17, color: K.ink))),
          if (a != null && a.ok)
            Text('+${fa(a.reward)} سکه', style: tBody(13, color: K.stamp, w: FontWeight.w900)),
        ]),
        const SizedBox(height: 6),
        if (a == null && n.open)
          Text('یکی از مظنون‌ها توی حرفش با یکی از مدارک امشب نمی‌خونه. فقط یک بار می‌تونی جواب بدی؛ جواب درست ${fa(n.reward)} سکه‌ست. '
              'ربطی به متهم‌کردن اصلی نداره و فرصت اتهامت رو کم نمی‌کنه.', style: tBody(13.5, color: K.ink))
        else if (a == null)
          Text('وقتش گذشت؛ شب دوم شروع شده.', style: tBody(13.5, color: K.inkSoft))
        else ...[
          Text(a.ok ? 'درست گفتی!' : 'این بار نشد.', style: tBody(14.5, color: a.ok ? K.ok : K.stamp, w: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('دروغگو: ${c.suspect(a.liar).name}. مدرک: ${c.evidenceById(a.card)?.title ?? a.card}.',
              style: tBody(13.5, color: K.ink, w: FontWeight.w700)),
          Text(a.explanation, style: tBody(13.5, color: K.ink)),
        ],
        if (canAnswer) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in c.suspects.where((s) => !s.isNewcomer))
              ActionChip(
                key: ValueKey('liar-${s.id}'),
                label: Text(s.name, style: tBody(13, color: K.ink, w: FontWeight.w700)),
                backgroundColor: K.paper,
                onPressed: () => _answerLiar(c, s),
              ),
          ]),
        ],
      ]),
    );
  }

  Future<void> _answerLiar(CaseData c, Suspect s) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: K.night,
          title: Text('مطمئنی؟', style: tDisplay(18)),
          content: Text('فقط یک بار می‌تونی جواب بدی. «${s.name}» دروغ می‌گه؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('نه، صبر کن')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('آره، همینه')),
          ],
        ),
      ),
    );
    if (sure != true || !mounted) return;
    try {
      final r = await Api.i.answerLiar(c.id, s.id);
      if (!mounted) return;
      setState(() => _progress = r.progress ?? _progress);
      toast(context, r.ok ? 'آفرین! ${fa(r.reward)} سکه اضافه شد.' : 'این بار نشد؛ جواب درست رو پایین ببین.');
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
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

  /// Small portrait chips for the suspects an evidence card names; a tap opens a quick peek.
  List<Widget> _namedChips(CaseData c, Evidence e) {
    final named = suspectsNamedIn('${e.title} ${e.text}', c.suspects);
    if (named.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in named)
          SuspectChip(suspect: s, onTap: () => showSuspectPeek(context, s, onFull: () => _openSuspect(s))),
      ]),
      const SizedBox(height: 4),
    ];
  }

  Widget _evidenceTab(CaseData c) {
    final chaptered = isChaptered(c);
    final seen = _chSeen ?? ChapterSeen(c.id);
    final all = chapterEvidence(c); // a nightly case: exactly c.evidence
    final shown = chaptered && _chFilter != null ? [for (final e in all) if (e.chapter == _chFilter) e] : all;
    final fresh = {for (final e in newEvidence(c, seen)) e.id};
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: shown.length + 1 + (chaptered && shown.isEmpty ? 1 : 0),
      itemBuilder: (_, j) {
        if (j == 0) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _evidenceHeader(c),
          if (chaptered)
            ChapterFilterRow(
                chapters: openChapters(c), selected: _chFilter, newCounts: newCardsByChapter(c, seen),
                onSelect: (n) => setState(() => _chFilter = n)),
          ClaimNotesPanel(caseData: c, links: _claimLinks, onAdd: () => _editClaim(),
            onEdit: (link) => _editClaim(existing: link), onRemove: _removeClaim),
          const SizedBox(height: 8),
          ]);
        }
        if (shown.isEmpty) {
          return Padding(
            key: const ValueKey('chap-empty'),
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text('این فصل مدرک تازه‌ای نداره', textAlign: TextAlign.center, style: tBody(14, color: K.textSoft)),
          );
        }
        final e = shown[j - 1];
        final i = max(0, c.evidence.indexOf(e)); // the number on the card does not change with the filter
        final key = (_progress?.finished ?? false) && c.proof.contains(e.id);
        final pinned = _pins.contains(e.id);
        final irrelevant = _tray?.irrelevantCards.contains(e.id) ?? false;
        return FadeSlideIn(
          delay: Duration(milliseconds: 50 * i),
          child: GestureDetector(
            onTap: () {
              Sfx.i.play('paper', volume: 0.4);
              setState(() {
                pinned ? _pins.remove(e.id) : _pins.add(e.id);
                _seen.add(e.id);
              });
              CaseClock.i.card(e.id);
              _saveNotes();
              if (chaptered) {
                unawaited(seen.markEvidence(e.id));
                _chSeen ??= seen;
                setState(() {});
                _updateBanner();
              }
            },
            child: AnimatedRotation(
            turns: pinned ? 0 : ((i % 3) - 1) * 0.0015,
            duration: const Duration(milliseconds: 250),
            child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            child: Stack(clipBehavior: Clip.none, children: [
            Opacity(
              opacity: irrelevant ? 0.6 : 1,
              child: Paper(
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
                    if (chaptered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Wrap(spacing: 6, runSpacing: 4, children: [
                          KeyedSubtree(key: ValueKey('chap-e-${e.id}'), child: ChapterBadge(e.chapter)),
                          if (fresh.contains(e.id)) NewTag('تازه', key: ValueKey('new-e-${e.id}')),
                        ]),
                      ),
                    Row(children: [
                      Expanded(child: Text(e.title, style: tBody(15, color: K.ink, w: FontWeight.w900))),
                      const SizedBox(width: 6),
                      Text(evidenceType(e.type), style: tBody(11, color: K.inkSoft)),
                    ]),
                    const SizedBox(height: 4),
                    Text(e.text, style: tBody(14.5, color: K.ink)),
                    ..._namedChips(c, e),
                    TextButton.icon(onPressed: () => _editClaim(evidence: e.id),
                      icon: const Icon(Icons.add_link_rounded, size: 18, color: K.stamp),
                      label: Text('پیوند به حرف مظنون', style: tBody(12.5, color: K.stamp))),
                    if (irrelevant)
                      Text('بی‌ربط · ذره‌بین', key: ValueKey('irrelevant-${e.id}'), style: tBody(12, color: K.inkSoft, w: FontWeight.w900)),
                    if (key) Text('مدرک کلیدی', style: tBody(12, color: K.stamp, w: FontWeight.w900)),
                    if (pinned && !key) Text('نشان‌شده', style: tBody(11, color: K.stamp, w: FontWeight.w900)),
                  ]),
                ),
              ]),
            ),
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

  /// The full suspect sheet (interrogation); used by the Suspects tab, the cast strip and the chips.
  Future<void> _openSuspect(Suspect s) async {
    unawaited(Api.i.markSeen(widget.caseId, s.id));
    final caseNow = _case;
    if (caseNow != null && isChaptered(caseNow)) {
      final seen = _chSeen ??= ChapterSeen(widget.caseId);
      unawaited(seen.markSuspect(s.id));
      if (mounted) setState(() {});
      _updateBanner();
    }
    void keep(SuspectMark m) {
      _marks[s.id] = m; // saved at once: closing the sheet any way must not lose it
      _saveNotes();
      if (mounted) setState(() {});
    }

    final c = _case;
    final p = _progress;
    final show = (c != null && p != null && c.weekly && c.twoPart && !p.finished && Api.i.online)
        ? WeekendShow(
            caseId: widget.caseId,
            evidence: c.evidence,
            shows: p.shows,
            left: p.showsLeft,
            onProgress: (np) {
              if (mounted) setState(() => _progress = np);
            })
        : null;
    final m = await showSuspect(context, s, _marks[s.id] ?? SuspectMark.none, onMark: keep, weekend: show,
      onLinkClaim: (suspect, question) => _editClaim(claim: ClaimChoice(suspect,
        question < 0 ? null : suspect.questions[question]).key));
    if (m != null && mounted) keep(m);
  }

  Widget _suspectsTab(CaseData c) {
    final chaptered = isChaptered(c);
    final seen = _chSeen ?? ChapterSeen(c.id);
    final fresh = {for (final s in newSuspects(c, seen)) s.id};
    final list = chaptered ? newSuspectsFirst(chapterSuspects(c), c, seen) : c.suspects;
    final header = chaptered && fresh.isNotEmpty ? 1 : 0;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: list.length + header,
      itemBuilder: (_, k) {
        if (header == 1 && k == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('${fa(fresh.length)} مظنون تازه', key: const ValueKey('sus-new-header'), style: tBody(13.5, color: K.stamp, w: FontWeight.w900)),
          );
        }
        final i = k - header;
        final s = list[i];
        final isNew = fresh.contains(s.id);
        final mark = _marks[s.id] ?? SuspectMark.none;
        final culprit = (_progress?.finished ?? false) && c.culprit == s.id;
        return FadeSlideIn(
          delay: Duration(milliseconds: 60 * i),
          child: GestureDetector(
            onTap: () => _openSuspect(s),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: K.night2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: culprit ? K.stamp : isNew ? K.brass : mark == SuspectMark.suspicious ? K.brass : K.night3, width: culprit || isNew ? 2 : 1),
              ),
              child: Row(children: [
                Container(
                  decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
                  child: AnimatedSuspect(avatar: s.avatar, size: 78, mood: culprit ? Mood.sad : Mood.calm),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (isNew)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: NewTag('مظنون تازه · فصل ${fa(suspectChapter(s))}', key: ValueKey('new-s-${s.id}'), onDark: true),
                        ),
                      ),
                    Row(children: [
                      Expanded(child: Text(s.name, style: tBody(16, w: FontWeight.w900))),
                      if (culprit) Text('مقصر', style: tBody(12, color: K.stamp, w: FontWeight.w900))
                      else if (mark == SuspectMark.suspicious) Text('مشکوک', style: tBody(12, color: K.brass, w: FontWeight.w900))
                      else if (mark == SuspectMark.innocent) Text('بی‌گناه', style: tBody(12, color: K.ok, w: FontWeight.w900)),
                    ]),
                    Text('${s.role} · ${fa(s.age)} ساله', style: tBody(12, color: K.textSoft)),
                    if (s.intro.isNotEmpty) Text(s.intro, style: tBody(12, color: K.text.withValues(alpha: 0.85)).copyWith(height: 1.5)),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_tray != null) ToolTrayBar(tray: _tray!, busy: _toolBusy, onTap: _useTool, onHelp: _showToolHelp),
            Row(children: [
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
                    child: StampButton(label: 'متهم کن', icon: Icons.gavel_rounded, onTap: _accuse)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

