import 'package:flutter/material.dart';

import '../models/album.dart';
import '../models/models.dart';
import '../theme.dart';
import 'character.dart';

/// The line under the title of the album strip on the home page: the next step, never a demand.
String albumStripLine(Album a) {
  final g = a.nextGroup;
  if (g == null) {
    if (a.solved == 0) return 'با حل هر پرونده، مجرمش یه کارت توی آلبومت می‌شه';
    if (a.groups.isNotEmpty && a.groups.every((x) => x.complete || x.total < 2)) return 'همه‌ی گروه‌ها رو کامل کردی';
    return 'کارت‌های مجرم‌ها رو ببین و گروه‌ها رو کامل کن';
  }
  final left = g.total - g.solved;
  final frame = a.frameWithinReach;
  if (left == 1) {
    return frame != null
        ? 'فقط ۱ پرونده تا «${frame.title}» · گروه «${g.title}»'
        : 'فقط ۱ پرونده تا کامل شدن گروه «${g.title}»';
  }
  return 'گروه «${g.title}»: ${fa(g.solved)} از ${fa(g.total)}'
      '${frame != null ? ' · برای «${frame.title}»' : ''}';
}

/// A full-width strip on the home page: how many culprits are in the album, a progress bar, and the next small goal.
/// One tap opens the album. It only appears once the server answered, and a failure just hides it.
class AlbumStrip extends StatelessWidget {
  const AlbumStrip({super.key, required this.album, required this.onTap});
  final Album album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final near = album.nextGroup != null && album.nextGroup!.total - album.nextGroup!.solved == 1;
    return Material(
      key: const ValueKey('album-strip'),
      color: K.night2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: near ? K.brass : K.night3, width: near ? 1.4 : 1),
          ),
          child: Row(children: [
            const Icon(Icons.collections_bookmark_rounded, color: K.brass, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('آلبوم مجرم‌ها · ${fa(album.solved)} از ${fa(album.total)}', style: tBody(14, w: FontWeight.w900)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: album.total == 0 ? 0 : album.solved / album.total,
                    minHeight: 6,
                    backgroundColor: K.night3,
                    valueColor: const AlwaysStoppedAnimation(K.brass),
                  ),
                ),
                const SizedBox(height: 6),
                Text(albumStripLine(album),
                    key: const ValueKey('album-strip-line'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tBody(12, color: near ? K.brass : K.textSoft, w: FontWeight.w700).copyWith(height: 1.5)),
              ]),
            ),
            const Icon(Icons.chevron_left_rounded, color: K.textSoft),
          ]),
        ),
      ),
    );
  }
}

/// On the result screen of a solved case: the culprit lands in the album as a card, with the progress of its group.
class AlbumEarnedCard extends StatelessWidget {
  const AlbumEarnedCard({super.key, required this.album, required this.caseId, required this.culprit, required this.onOpen});
  final Album album;
  final String caseId;
  final Suspect? culprit;
  final VoidCallback onOpen;

  String? _groupLine() {
    final g = album.groupOfCase(caseId);
    if (g == null || g.total < 2) return null;
    if (g.complete) {
      final owned = [for (final r in album.rewards) if (r.owned) r];
      final frame = owned.isEmpty ? '' : ' · ${owned.last.title} مال توئه';
      return 'گروه «${g.title}» کامل شد!$frame';
    }
    final left = g.total - g.solved;
    final frame = album.frameWithinReach;
    if (left == 1) {
      return 'گروه «${g.title}»: فقط ۱ پرونده مونده${frame != null ? ' تا «${frame.title}»' : ''}';
    }
    return 'گروه «${g.title}»: ${fa(g.solved)} از ${fa(g.total)}';
  }

  @override
  Widget build(BuildContext context) {
    final line = _groupLine();
    return Container(
      key: const ValueKey('album-earned'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: K.brass.withValues(alpha: 0.6), width: 1.4),
      ),
      child: Row(children: [
        if (culprit != null) ...[SuspectPortrait(culprit!.avatar, size: 54, circle: true), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('کارت مجرم به آلبومت اضافه شد', style: tBody(14, w: FontWeight.w900, color: K.brass)),
            if (culprit != null) Text(culprit!.name, style: tBody(13, color: K.textSoft)),
            if (line != null) ...[
              const SizedBox(height: 2),
              Text(line, key: const ValueKey('album-earned-line'), style: tBody(12.5, w: FontWeight.w700)),
            ],
          ]),
        ),
        TextButton(
          key: const ValueKey('album-earned-open'),
          onPressed: onOpen,
          child: Text('دیدن در آلبوم', style: tBody(13, w: FontWeight.w900, color: K.brass)),
        ),
      ]),
    );
  }
}
