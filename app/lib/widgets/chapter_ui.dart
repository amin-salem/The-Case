import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../theme.dart';

/// Weekend cases come in chapters (formats 2 and 3). Everything on this page is for them only: a nightly case
/// (no chapters) gets no badges, no filter row and no banner, so it looks exactly as before.
///
/// The data already exists on the server: every card carries `chapter` (1 = from the start), every suspect
/// `appears_chapter` (0 = from the start, 1 = appears with chapter 2), and the case file only lists what the
/// opened chapters hold (`chapters`), so a chapter that is not open yet is never named or counted here.
bool isChaptered(CaseData c) => c.weekly && c.chaptersTotal >= 2;

/// How many chapters are open (at least 1).
int openChapters(CaseData c) => c.chapters.isEmpty ? 1 : c.chapters.length;

/// The chapter number (1-based, like the cards) a suspect appears in.
int suspectChapter(Suspect s) => s.appearsChapter + 1;

/// The cards the player may see: a card of a chapter that is not open yet is dropped even if a server sent it.
List<Evidence> chapterEvidence(CaseData c) =>
    isChaptered(c) ? [for (final e in c.evidence) if (e.chapter <= openChapters(c)) e] : c.evidence;

List<Suspect> chapterSuspects(CaseData c) =>
    isChaptered(c) ? [for (final s in c.suspects) if (suspectChapter(s) <= openChapters(c)) s] : c.suspects;

/// What the player has opened of a weekend case, remembered on this phone (SharedPreferences, per case; every
/// read and write is wrapped, a failing store only means «everything looks new» again).
class ChapterSeen {
  ChapterSeen(this.caseId, [Set<String>? keys, this.bannerChapter = 0]) : keys = keys ?? <String>{};
  final String caseId;
  final Set<String> keys;

  /// The newest chapter whose banner the player already closed or followed.
  int bannerChapter;

  static String _kSeen(String caseId) => 'chapter_seen_$caseId';
  static String _kBanner(String caseId) => 'chapter_banner_$caseId';

  static Future<ChapterSeen> load(String caseId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return ChapterSeen(caseId, {...?p.getStringList(_kSeen(caseId))}, p.getInt(_kBanner(caseId)) ?? 0);
    } catch (e) {
      debugPrint('chapter seen: $e');
      return ChapterSeen(caseId);
    }
  }

  bool evidence(String id) => keys.contains('e:$id');
  bool suspect(String id) => keys.contains('s:$id');

  Future<void> markEvidence(String id) => _add('e:$id');
  Future<void> markSuspect(String id) => _add('s:$id');

  Future<void> _add(String key) async {
    if (!keys.add(key)) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kSeen(caseId), keys.toList());
    } catch (e) {
      debugPrint('chapter seen: $e');
    }
  }

  Future<void> setBanner(int chapter) async {
    if (chapter <= bannerChapter) return;
    bannerChapter = chapter;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kBanner(caseId), chapter);
    } catch (e) {
      debugPrint('chapter seen: $e');
    }
  }
}

/// Cards that arrived with chapter 2 or later and were not opened yet.
List<Evidence> newEvidence(CaseData c, ChapterSeen seen) =>
    isChaptered(c) ? [for (final e in chapterEvidence(c)) if (e.chapter >= 2 && !seen.evidence(e.id)) e] : const [];

/// Suspects who appear in chapter 2 or later and were not opened yet.
List<Suspect> newSuspects(CaseData c, ChapterSeen seen) =>
    isChaptered(c) ? [for (final s in chapterSuspects(c)) if (suspectChapter(s) >= 2 && !seen.suspect(s.id)) s] : const [];

/// For the chapter chips: chapter number -> how many of its cards are still new.
Map<int, int> newCardsByChapter(CaseData c, ChapterSeen seen) {
  final out = <int, int>{};
  for (final e in newEvidence(c, seen)) {
    out[e.chapter] = (out[e.chapter] ?? 0) + 1;
  }
  return out;
}

/// Suspects first when they are new, the rest keep their order.
List<Suspect> newSuspectsFirst(List<Suspect> all, CaseData c, ChapterSeen seen) {
  final fresh = {for (final s in newSuspects(c, seen)) s.id};
  return [for (final s in all) if (fresh.contains(s.id)) s, for (final s in all) if (!fresh.contains(s.id)) s];
}

/// The banner when a chapter opens: «فصل ۲ باز شد: ۳ مدرک و ۱ مظنون تازه». The numbers are the chapter's own items.
String chapterBannerText(CaseData c, int chapter) {
  final cards = chapterEvidence(c).where((e) => e.chapter == chapter).length;
  final suspects = chapterSuspects(c).where((s) => suspectChapter(s) == chapter).length;
  final parts = [if (cards > 0) '${fa(cards)} مدرک', if (suspects > 0) '${fa(suspects)} مظنون'];
  return 'فصل ${fa(chapter)} باز شد${parts.isEmpty ? '' : ': ${parts.join(' و ')} تازه'}';
}

/// Which chapter (if any) deserves the banner now: the newest open one, when something in it is not opened yet and
/// the player has not closed its banner.
int? bannerChapter(CaseData c, ChapterSeen seen) {
  if (!isChaptered(c)) return null;
  final n = openChapters(c);
  if (n < 2 || seen.bannerChapter >= n) return null;
  final fresh = newEvidence(c, seen).any((e) => e.chapter == n) || newSuspects(c, seen).any((s) => suspectChapter(s) == n);
  return fresh ? n : null;
}

/// «فصل ۲» on a card.
class ChapterBadge extends StatelessWidget {
  const ChapterBadge(this.chapter, {super.key});
  final int chapter;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: K.ink.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
        child: Text('فصل ${fa(chapter)}', style: tBody(11, color: K.inkSoft, w: FontWeight.w900)),
      );
}

/// The red «تازه» tag on a card (or «مظنون تازه · فصل ۲» on a suspect).
class NewTag extends StatelessWidget {
  const NewTag(this.text, {super.key, this.onDark = false});
  final String text;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: K.stamp.withValues(alpha: onDark ? 0.9 : 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: tBody(11, color: onDark ? Colors.white : K.stamp, w: FontWeight.w900)),
      );
}

/// «همه / فصل ۱ / فصل ۲ …»: one chip for every OPENED chapter, whether it holds cards or not. A small red number on
/// a chip says how many of its cards are new.
class ChapterFilterRow extends StatelessWidget {
  const ChapterFilterRow({super.key, required this.chapters, required this.selected, required this.newCounts, required this.onSelect});
  final int chapters;
  final int? selected; // null = all
  final Map<int, int> newCounts;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final totalNew = newCounts.values.fold(0, (a, b) => a + b);
    Widget chip(int? chapter, String label, int fresh) => ChoiceChip(
          key: ValueKey(chapter == null ? 'chap-chip-all' : 'chap-chip-$chapter'),
          selected: selected == chapter,
          selectedColor: K.brass,
          backgroundColor: K.night2,
          onSelected: (_) => onSelect(chapter),
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: tBody(12.5, w: FontWeight.w900)),
            if (fresh > 0) ...[
              const SizedBox(width: 6),
              Container(
                key: ValueKey('chap-new-${chapter ?? 'all'}'),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(99)),
                child: Text(fa(fresh), style: tBody(11, color: Colors.white, w: FontWeight.w900)),
              ),
            ],
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(spacing: 8, runSpacing: 6, children: [
        chip(null, 'همه', totalNew),
        for (int i = 1; i <= chapters; i++) chip(i, 'فصل ${fa(i)}', newCounts[i] ?? 0),
      ]),
    );
  }
}

/// A short, non-blocking strip: tap = go to the new items (and close), the cross = just close.
class ChapterBanner extends StatelessWidget {
  const ChapterBanner({super.key, required this.text, required this.onGo, required this.onClose});
  final String text;
  final VoidCallback onGo, onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: K.night3,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: const ValueKey('chap-banner'),
            borderRadius: BorderRadius.circular(12),
            onTap: onGo,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: K.brass.withValues(alpha: 0.6))),
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(children: [
                const Icon(Icons.fiber_new_rounded, color: K.brass, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: tBody(13.5, w: FontWeight.w800))),
                IconButton(
                  key: const ValueKey('chap-banner-close'),
                  tooltip: 'بستن',
                  icon: const Icon(Icons.close_rounded, size: 20, color: K.textSoft),
                  onPressed: onClose,
                ),
              ]),
            ),
          ),
        ),
      );
}
