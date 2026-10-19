import 'package:flutter/material.dart';

import '../data/story_art.dart';
import '../models/story.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/offline.dart';
import '../widgets/story_art.dart';
import '../widgets/story_choice.dart';
import 'case_screen.dart';
import 'story_board_screen.dart';

/// A story chapter's scenes: narration, the partner's lines and 2-3 options. After the last scene the
/// normal case screen (interrogation, accusation) opens. Choices need the server; the scene itself is cached.
class StorySceneScreen extends StatefulWidget {
  const StorySceneScreen({super.key, required this.chapterId, required this.chapter});
  final String chapterId;
  final int chapter;

  @override
  State<StorySceneScreen> createState() => _StorySceneScreenState();
}

class _StorySceneScreenState extends State<StorySceneScreen> {
  ChapterState? _state;
  String? _error;
  String? _title;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final s = await Api.i.chapterState(widget.chapterId);
      if (mounted) setState(() => _state = s);
    } catch (e) {
      if (mounted) setState(() => _error = Api.isNetworkFail(e) && !Api.i.online ? Api.offlineText : Api.friendly(e));
    }
    try {
      final (c, _, _) = await Api.i.openCase(widget.chapterId);
      if (mounted) setState(() => _title = c.title);
    } catch (_) {
      // the title is only decoration
    }
  }

  Future<void> _pick(ChoiceOption o) async {
    final s = _state;
    if (s == null || _busy || o.locked || !needOnline(context)) return;
    setState(() => _busy = true);
    try {
      final next = await Api.i.chooseOption(widget.chapterId, s.scene.id, o.id);
      if (mounted) setState(() => _state = next);
    } catch (e) {
      if (!mounted) return;
      toast(context, Api.friendly(e));
      if (e is ApiException && e.code == 'wrong_scene') await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openBoard() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoryBoardScreen(onContinue: (_) => Navigator.pop(context)),
    ));
  }

  void _toCase() {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CaseScreen(caseId: widget.chapterId)));
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    final season = (Api.i.upcomingStory['title'] as String?) ?? 'کبریت سوخته';
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
            child: Row(children: [
              IconButton(
                tooltip: 'بازگشت',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.chevron_right_rounded, size: 30, color: K.text),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('فصل ${fa(widget.chapter)} · $season', style: tBody(12, color: K.kraft, w: FontWeight.w700)),
                  Text(_title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: tDisplay(17)),
                ]),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openBoard,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(16)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.dashboard_outlined, size: 16, color: K.brass),
                    const SizedBox(width: 6),
                    Text('تابلو', style: tBody(12.5, color: K.brass, w: FontWeight.w900)),
                  ]),
                ),
              ),
            ]),
          ),
          const OfflineBanner(margin: EdgeInsets.fromLTRB(16, 4, 16, 0)),
          Expanded(child: s == null ? _loading() : _scene(s)),
        ]),
      ),
    );
  }

  Widget _loading() => Center(
        child: _error == null
            ? const CircularProgressIndicator(color: K.brass)
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, style: tBody(14, color: K.textSoft)),
                TextButton(onPressed: _load, child: Text('دوباره', style: tBody(14, color: K.brass, w: FontWeight.w900))),
              ]),
      );

  Widget _scene(ChapterState s) {
    final filled = s.done ? s.total : s.step.clamp(1, s.total).toInt();
    final sc = s.scene;
    final h = MediaQuery.of(context).size.height;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          for (int i = 0; i < s.total; i++)
            Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsetsDirectional.only(end: i == s.total - 1 ? 0 : 6),
                decoration: BoxDecoration(color: i < filled ? K.brass : K.night3, borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(s.done ? 'پایان صحنه‌ها' : 'صحنه ${fa(filled)} از ${fa(s.total)}', style: tBody(11.5, color: K.textSoft)),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // the scene's picture (only chapters that have art; the others look as before)
            if (storySceneArt(widget.chapterId, sc.id) case final art?) ...[
              StorySceneArt(key: ValueKey('art-${sc.id}'), art: art),
              const SizedBox(height: 12),
            ],
            sc.isPartner ? _partner(sc.text) : _narration(sc.text),
          ]),
        ),
      ),
      ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.58),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: sc.ending || sc.options.isEmpty ? _toCaseButton() : _options(sc),
        ),
      ),
    ]);
  }

  Widget _narration(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(18)),
        child: Text(text, style: tBody(14.5, color: const Color(0xFFCFCBC2)).copyWith(height: 2.0)),
      );

  Widget _partner(String text) {
    final partner = (Api.i.upcomingStory['partner'] as String?) ?? 'سرگرد ناصری';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: K.night3, border: Border.all(color: K.kraft, width: 2)),
        child: Text('ن', style: tDisplay(17, color: K.kraft)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: const BoxDecoration(
            color: K.paper,
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(4),
              topEnd: Radius.circular(16),
              bottomStart: Radius.circular(16),
              bottomEnd: Radius.circular(16),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(partner, style: tBody(11.5, color: K.kraftDark, w: FontWeight.w900)),
            Text(text, style: tBody(14, color: K.ink).copyWith(height: 1.95)),
          ]),
        ),
      ),
    ]);
  }

  Widget _options(StoryScene sc) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
        Text('انتخاب کن', style: tBody(12, color: K.kraft, w: FontWeight.w900)),
        Text('هیچ‌کدام راه اشتباه نیست؛ فقط راه دیگری‌ست', style: tBody(12, color: K.textSoft)),
      ]),
      const SizedBox(height: 10),
      for (int i = 0; i < sc.options.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ChoiceCard(option: sc.options[i], index: i + 1, onTap: _busy ? null : () => _pick(sc.options[i])),
        ),
    ]);
  }

  Widget _toCaseButton() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: K.brass,
              foregroundColor: K.night,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _toCase,
            child: Text('برو سراغ پرونده', style: tBody(15, color: K.night, w: FontWeight.w900)),
          ),
        ),
      );
}
