import 'package:flutter/material.dart';

import '../data/story_art.dart';
import '../theme.dart';

/// A wide picture above a scene's text. Crops the tall artwork to a banner; never blocks the story if the file fails.
class StorySceneArt extends StatelessWidget {
  const StorySceneArt({super.key, required this.art});
  final StoryArt art;

  @override
  Widget build(BuildContext context) {
    // the banner grows a little with the system font so the layout keeps its proportions
    final h = (MediaQuery.sizeOf(context).height * 0.24).clamp(150.0, 230.0).toDouble();
    return Semantics(
      image: true,
      label: art.caption,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          key: const ValueKey('story-scene-art'),
          height: h,
          width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            Image.asset(
              art.asset,
              fit: BoxFit.cover,
              alignment: Alignment(0, art.focusY),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(color: K.night2),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xCC17181A)],
                  stops: [0.55, 1],
                ),
              ),
            ),
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 8,
              child: Text(art.caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, w: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The Taban photo clue: the photo as it was, and the same photo burnt. One tap switches; the label says which one is on.
class TabanPhotoClue extends StatefulWidget {
  const TabanPhotoClue({super.key});

  @override
  State<TabanPhotoClue> createState() => _TabanPhotoClueState();
}

class _TabanPhotoClueState extends State<TabanPhotoClue> {
  bool _burnt = false;

  @override
  Widget build(BuildContext context) {
    final asset = _burnt ? kTabanPhotoBurnt : kTabanPhotoIntact;
    Widget tab(String label, bool burnt) => Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _burnt = burnt),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _burnt == burnt ? K.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(label,
                  key: ValueKey(burnt ? 'photo-tab-burnt' : 'photo-tab-intact'),
                  style: tBody(12.5, color: _burnt == burnt ? K.brass : K.inkSoft, w: FontWeight.w900)),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 442 / 380,
          child: Image.asset(
            asset,
            key: ValueKey(asset),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: K.ink.withValues(alpha: 0.2)),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [tab('عکس سالم', false), const SizedBox(width: 6), tab('عکس سوخته', true)]),
    ]);
  }
}
