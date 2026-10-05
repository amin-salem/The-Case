import 'dart:math';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/offline.dart';
import 'case_screen.dart';

/// Two steps: who did it, and which evidence proves their lie.
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
  bool _busy = false;
  String? _feedback;
  late int _left = widget.progress.attemptsLeft;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    Sfx.i.play('heartbeat', volume: 0.5); // the moment of accusing
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_suspect == null || _evidence == null) return;
    // the choices stay on screen; nothing is sent without the server
    if (!needOnline(context)) return;
    setState(() => _busy = true);
    try {
      final r = await Api.i.accuse(widget.caseData.id, _suspect!, _evidence!);
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
        _feedback = r.result == 'wrong_proof'
            ? 'آدم درست رو گرفتی، ولی این مدرک دروغش رو ثابت نمی‌کنه. یه ستاره کم شد؛ مدرک دیگه‌ای رو امتحان کن.'
            : 'اشتباه بود! این آدم بی‌گناهه. ${fa(r.attemptsLeft)} فرصت دیگه داری.';
        _evidence = null;
      });
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
        if (!didPop) Navigator.pop(context, _lastWrong);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: K.night,
          title: Text('متهم کردن', style: tDisplay(20)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Center(child: Text('${fa(_left)} فرصت', style: tBody(14, color: K.stamp, w: FontWeight.w900))),
            ),
          ],
        ),
        body: GrainBackground(
          child: AnimatedBuilder(
            animation: _shake,
            builder: (_, child) => Transform.translate(offset: Offset(sin(_shake.value * pi * 6) * 10 * (1 - _shake.value), 0), child: child),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              const OfflineBanner(margin: EdgeInsets.only(bottom: 10)),
              Text('۱. مقصر کیه؟', style: tDisplay(19)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
                children: [for (final s in c.suspects) _suspectTile(s)],
              ),
              const SizedBox(height: 18),
              Text('۲. کدوم مدرک دروغش رو ثابت می‌کنه؟', style: tDisplay(19)),
              Text('فقط یه مدرک انتخاب کن: همونی که با حرفش جور درنمیاد.', style: tBody(13, color: K.textSoft)),
              const SizedBox(height: 8),
              for (final e in c.evidence) _evidenceTile(e),
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
                // the verdict of a wrong try sits right above the button, never hidden under it
                if (_feedback != null) ...[
                  Container(
                    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.25),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: K.stamp.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: K.stamp)),
                    child: SingleChildScrollView(child: Text(_feedback!, style: tBody(14, w: FontWeight.w700))),
                  ),
                  const SizedBox(height: 10),
                ],
                StampButton(
                  label: _busy
                      ? '...'
                      : (_suspect == null
                          ? 'یه مظنون انتخاب کن'
                          : _evidence == null
                              ? 'یه مدرک انتخاب کن'
                              : 'متهم می‌کنم: ${c.suspect(_suspect!).name}'),
                  icon: Icons.gavel_rounded,
                  onTap: _busy || _suspect == null || _evidence == null ? null : _submit,
                ),
              ]),
            ),
          ),
        ),
      ),
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
