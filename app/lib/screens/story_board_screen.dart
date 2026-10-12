import 'package:flutter/material.dart';

import '../models/story.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/offline.dart';
import '../widgets/story_choice.dart';

/// «تابلوی پرونده»: the season's people (with how they feel about the player) and the clues held, open or skipped.
/// [onContinue] is the brass button («ادامه‌ی فصل N»); it is hidden when there is no chapter in progress.
class StoryBoardScreen extends StatefulWidget {
  const StoryBoardScreen({super.key, this.onContinue});
  final void Function(int chapter)? onContinue;

  @override
  State<StoryBoardScreen> createState() => _StoryBoardScreenState();
}

class _StoryBoardScreenState extends State<StoryBoardScreen> {
  SeasonBoard? _board;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final b = await Api.i.storyBoard();
      if (mounted) setState(() => _board = b);
    } catch (e) {
      if (mounted) setState(() => _error = Api.isNetworkFail(e) && !Api.i.online ? Api.offlineText : Api.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _board;
    final season = (Api.i.upcomingStory['title'] as String?) ?? 'کبریت سوخته';
    final cont = b?.continueChapter;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(children: [
              IconButton(
                tooltip: 'بازگشت',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.chevron_right_rounded, size: 30, color: K.text),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(season, style: tBody(12, color: K.kraft, w: FontWeight.w700)),
                  Text('تابلوی پرونده', style: tDisplay(18)),
                ]),
              ),
            ]),
          ),
          const OfflineBanner(margin: EdgeInsets.fromLTRB(16, 4, 16, 0)),
          Expanded(
            child: b == null
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator(color: K.brass)
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(_error!, style: tBody(14, color: K.textSoft)),
                            TextButton(onPressed: _load, child: Text('دوباره', style: tBody(14, color: K.brass, w: FontWeight.w900))),
                          ]),
                  )
                : _content(b),
          ),
          if (b != null && cont != null && widget.onContinue != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: K.brass,
                    foregroundColor: K.night,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => widget.onContinue!(cont),
                  child: Text('ادامه‌ی فصل ${fa(cont)}', style: tBody(15, color: K.night, w: FontWeight.w900)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _content(SeasonBoard b) {
    return RefreshIndicator(
      color: K.brass,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('سرنخ‌های جمع‌شده', style: tBody(13, w: FontWeight.w900)),
                Text('در پایان فصل، اتهام نهایی با همین‌ها ساخته می‌شود', style: tBody(12, color: K.textSoft)),
              ]),
            ),
            const SizedBox(width: 10),
            Text.rich(TextSpan(children: [
              TextSpan(text: fa(b.held), style: tDisplay(22, color: K.brass)),
              TextSpan(text: ' از ${fa(b.total)}', style: tBody(12, color: K.textSoft)),
            ])),
          ]),
        ),
        if (b.people.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('آدم‌ها', style: tBody(12.5, color: K.kraft, w: FontWeight.w900)),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, c) {
            final w = (c.maxWidth - 16) / 3;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in b.people) SizedBox(width: w, child: PersonTile(person: p)),
            ]);
          }),
        ],
        if (b.clues.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('سرنخ‌ها', style: tBody(12.5, color: K.kraft, w: FontWeight.w900)),
          const SizedBox(height: 8),
          for (final c in b.clues) Padding(padding: const EdgeInsets.only(bottom: 8), child: ClueTile(clue: c)),
        ],
        if (b.people.isEmpty && b.clues.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text('هنوز چیزی روی تابلو نیست؛ فصل را شروع کن.', textAlign: TextAlign.center, style: tBody(14, color: K.textSoft)),
          ),
      ]),
    );
  }
}
