import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/offline.dart';
import 'case_screen.dart';

/// A stepper: who did it, which evidence proves their lie (and, for the weekend case, why).
/// Pops with the server's answer.
class AccuseScreen extends StatefulWidget {
  const AccuseScreen({super.key, required this.caseData, required this.progress, required this.marks});
  final CaseData caseData;
  final Progress progress;
  final Map<String, SuspectMark> marks;

  @override
  State<AccuseScreen> createState() => _AccuseScreenState();
}

class _AccuseScreenState extends State<AccuseScreen> with SingleTickerProviderStateMixin {
  String? _suspect;
  String? _evidence;
  String? _motive; // the weekend case also asks why
  int _step = 0; // 0 who, 1 which proof, 2 why (weekend case only)
  bool _busy = false;
  String? _feedback;
  late int _left = widget.progress.attemptsLeft;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  final ScrollController _scroll = ScrollController();

  int get _steps => widget.caseData.weekly ? 3 : 2;
  bool get _last => _step == _steps - 1;

  /// Whether the current step has its choice.
  bool get _picked => switch (_step) { 0 => _suspect != null, 1 => _evidence != null, _ => _motive != null };

  @override
  void initState() {
    super.initState();
    Sfx.i.play('heartbeat', volume: 0.5); // the moment of accusing
  }

  @override
  void dispose() {
    _shake.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    Sfx.i.play('paper', volume: 0.4);
    setState(() => _step = max(0, min(step, _steps - 1)));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _submit() async {
    if (_suspect == null || _evidence == null) return;
    // the choices stay on screen; nothing is sent without the server
    if (!needOnline(context)) return;
    setState(() => _busy = true);
    try {
      final r = await Api.i.accuse(widget.caseData.id, _suspect!, _evidence!, motive: _motive);
      if (!mounted) return;
      if (r.result == 'solved' || r.result == 'failed') {
        Navigator.pop(context, r);
        return;
      }
      Sfx.i.play('wrong', volume: 0.6);
      _shake.forward(from: 0);
      setState(() {
        _busy = false;
        _left = r.attemptsLeft;
        _feedback = switch (r.result) {
          'wrong_proof' => 'آدم درست رو گرفتی، ولی این مدرک دروغش رو ثابت نمی‌کنه. یه ستاره کم شد؛ مدرک دیگه‌ای رو امتحان کن.',
          'wrong_motive' => 'آدم و مدرک درسته، ولی انگیزه‌اش این نبود. یه ستاره کم شد؛ دوباره فکر کن چرا این کار رو کرد.',
          _ => 'اشتباه بود! این آدم بی‌گناهه. ${fa(r.attemptsLeft)} فرصت دیگه داری.',
        };
        // back to the step that was wrong
        switch (r.result) {
          case 'wrong_motive':
            _motive = null;
            _step = 2;
          case 'wrong_proof':
            _evidence = null;
            _step = 1;
          default:
            _suspect = null;
            _evidence = null;
            _step = 0;
        }
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      // keep the wrong result for the case screen to update its counters
      _lastWrong = r;
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, Api.friendly(e));
    }
  }

  AccuseResult? _lastWrong;

  @override
  Widget build(BuildContext context) {
    final c = widget.caseData;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // back goes one step back first, then leaves
        if (_step > 0 && !_busy) {
          _go(_step - 1);
        } else {
          Navigator.pop(context, _lastWrong);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: K.night,
          title: Text('متهم کردن', style: tDisplay(20)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: K.stamp.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: K.stamp),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.gavel_rounded, size: 15, color: K.stamp),
                    const SizedBox(width: 4),
                    Text('${fa(_left)} فرصت', style: tBody(13, w: FontWeight.w900)),
                  ]),
                ),
              ),
            ),
          ],
        ),
        body: GrainBackground(
          child: AnimatedBuilder(
            animation: _shake,
            builder: (_, child) => Transform.translate(offset: Offset(sin(_shake.value * pi * 6) * 10 * (1 - _shake.value), 0), child: child),
            child: Column(children: [
              _progressBar(),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: ListView(
                    key: ValueKey(_step),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      const OfflineBanner(margin: EdgeInsets.only(bottom: 10)),
                      ..._stepBody(c),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
        // A real bottom bar (not a sheet over the list): the list ends above it,
        // and it stays clear of the phone's navigation / gesture bar.
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(color: K.night2, border: Border(top: BorderSide(color: K.night3))),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // the verdict of a wrong try sits right above the buttons, never hidden under them
                if (_feedback != null) ...[
                  Container(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.2),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: K.stamp.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: K.stamp)),
                    child: SingleChildScrollView(child: Text(_feedback!, style: tBody(14, w: FontWeight.w700))),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_last && _picked) ...[_summary(c), const SizedBox(height: 10)],
                Row(children: [
                  if (_step > 0) ...[
                    GhostButton(label: 'قبلی', icon: Icons.chevron_right_rounded, onTap: _busy ? null : () => _go(_step - 1)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: _mainButton(c)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mainButton(CaseData c) {
    if (!_last) {
      return StampButton(
        label: _picked ? 'ادامه' : (_step == 0 ? 'یه مظنون انتخاب کن' : 'یه مدرک انتخاب کن'),
        icon: Icons.chevron_left_rounded,
        onTap: _picked && !_busy ? () => _go(_step + 1) : null,
      );
    }
    final ready = _suspect != null && _evidence != null && (!c.weekly || _motive != null);
    return StampButton(
      label: _busy
          ? '...'
          : ready
              ? 'متهم می‌کنم: ${c.suspect(_suspect!).name}'
              : (c.weekly ? 'انگیزه رو انتخاب کن' : 'یه مدرک انتخاب کن'),
      icon: Icons.gavel_rounded,
      onTap: _busy || !ready ? null : _submit,
    );
  }

  /// "Step N of M" and a bar.
  Widget _progressBar() {
    final labels = ['مقصر', 'مدرک', if (widget.caseData.weekly) 'انگیزه'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('مرحله‌ی ${fa(_step + 1)} از ${fa(_steps)}', style: tBody(13, color: K.brass, w: FontWeight.w900)),
          const Spacer(),
          Flexible(
            child: Text(labels.join('  ·  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.textSoft)),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          for (int i = 0; i < _steps; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 6,
                margin: EdgeInsets.only(left: i < _steps - 1 ? 4 : 0),
                decoration: BoxDecoration(
                  color: i <= _step ? K.stamp : K.night3,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
        ]),
      ]),
    );
  }

  List<Widget> _stepBody(CaseData c) => switch (_step) {
        0 => [
            Text('مقصر کیه؟', style: tDisplay(20)),
            Text('کسی رو انتخاب کن که درباره‌ی چیزی دروغ گفته.', style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
              children: [for (final s in c.suspects) _suspectTile(s)],
            ),
          ],
        1 => [
            Text('کدوم مدرک دروغش رو ثابت می‌کنه؟', style: tDisplay(20)),
            Text('فقط یه مدرک انتخاب کن: همونی که با حرف ${_suspect == null ? 'مقصر' : c.suspect(_suspect!).name} جور درنمیاد.',
                style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 10),
            for (final e in c.evidence) _evidenceTile(e),
          ],
        _ => [
            Text('چرا این کار رو کرد؟', style: tDisplay(20)),
            Text('انگیزه‌ی واقعی رو انتخاب کن.', style: tBody(13, color: K.textSoft)),
            const SizedBox(height: 10),
            for (final m in c.motives) _motiveTile(m.id, m.text),
          ],
      };

  /// The amber card above the final button: who, with which card (and why).
  Widget _summary(CaseData c) {
    if (_suspect == null || _evidence == null) return const SizedBox.shrink();
    final who = c.suspect(_suspect!);
    final card = c.evidenceById(_evidence!)?.title ?? '';
    String? why;
    if (c.weekly && _motive != null) {
      for (final m in c.motives) {
        if (m.id == _motive) why = m.text;
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: K.brass.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: K.brass),
      ),
      child: Row(children: [
        const Icon(Icons.assignment_ind_rounded, color: K.brass),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'اتهام تو: ', style: tBody(13, color: K.textSoft, w: FontWeight.w700)),
              TextSpan(text: who.name, style: tBody(14, w: FontWeight.w900)),
              TextSpan(text: ' · با ', style: tBody(13, color: K.textSoft, w: FontWeight.w700)),
              TextSpan(text: card, style: tBody(14, color: K.brass, w: FontWeight.w900)),
              if (why != null) ...[
                TextSpan(text: ' · چون ', style: tBody(13, color: K.textSoft, w: FontWeight.w700)),
                TextSpan(text: why, style: tBody(13, w: FontWeight.w700)),
              ],
            ]),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }

  Widget _suspectTile(Suspect s) {
    final on = _suspect == s.id;
    final mark = widget.marks[s.id] ?? SuspectMark.none;
    return GestureDetector(
      onTap: () => setState(() => _suspect = s.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF3A1C1A) : K.night2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: on ? K.stamp : (mark == SuspectMark.suspicious ? K.brass : K.night3), width: on ? 2.5 : 1),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(children: [
          Expanded(child: AnimatedSuspect(avatar: s.avatar, size: 90, mood: on ? Mood.nervous : Mood.calm)),
          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13, w: FontWeight.w900)),
          if (mark == SuspectMark.innocent) Text('بی‌گناه؟', style: tBody(10, color: K.ok)),
        ]),
      ),
    );
  }

  Widget _motiveTile(String id, String text) {
    final on = _motive == id;
    return GestureDetector(
      onTap: () => setState(() => _motive = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? const Color(0xFF3A1C1A) : K.night2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? K.stamp : K.night3, width: on ? 2 : 1),
        ),
        child: Row(children: [
          Icon(on ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded, color: on ? K.stamp : K.textSoft),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: tBody(14.5, w: FontWeight.w700))),
        ]),
      ),
    );
  }

  Widget _evidenceTile(Evidence e) {
    final on = _evidence == e.id;
    return GestureDetector(
      onTap: () => setState(() => _evidence = e.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: on ? K.clue : K.paper,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? K.stamp : Colors.transparent, width: 2),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(evidenceIcon(e.type), color: K.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.title, style: tBody(14.5, color: K.ink, w: FontWeight.w900)),
              Text(e.text, style: tBody(13, color: K.ink), maxLines: on ? 8 : 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (on) const Icon(Icons.check_circle_rounded, color: K.stamp),
        ]),
      ),
    );
  }
}
