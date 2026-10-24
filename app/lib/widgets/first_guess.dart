import 'package:flutter/material.dart';

import '../models/album.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import 'character.dart';
import 'typewriter.dart';

/// «به نظر تو کیه؟»: before the evidence of a case is opened (first time only) the player may give a first guess.
/// One tap closes it; «الان نه» or a swipe skips it; it never blocks the case. Returns once the sheet is closed.
Future<void> askFirstGuess(BuildContext context, CaseData c) async {
  final flag = 'guess_asked_${c.id}';
  if (c.story != null || c.suspects.length < 3 || !Api.i.online || Api.i.flag(flag)) return;
  final mine = await Api.i.firstGuess(c.id);
  if (!context.mounted) return;
  if (mine == null || mine.guess != null) return; // offline / already guessed
  final pick = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: K.night2,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('به نظر تو کیه؟', style: tDisplay(22)),
          const SizedBox(height: 4),
          Text('قبل از شروع تحقیقات، حدس اولت رو بزن. چیزی ازت کم نمی‌شه و بعد از حل پرونده می‌بینی چقدر درست حدس زدی.',
              style: tBody(13.5, color: K.textSoft)),
          const SizedBox(height: 10),
          for (final s in c.suspects)
            ListTile(
              key: ValueKey('guess-${s.id}'),
              contentPadding: EdgeInsets.zero,
              leading: SuspectPortrait(s.avatar, size: 46, circle: true),
              title: Text(s.name, style: tBody(15, w: FontWeight.w900)),
              subtitle: Text(s.role, style: tBody(12.5, color: K.textSoft)),
              onTap: () => Navigator.pop(ctx, s.id),
            ),
          ListTile(
            key: const ValueKey('guess-unknown'),
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(backgroundColor: K.night3, child: Icon(Icons.help_outline_rounded, color: K.textSoft)),
            title: Text('نمی‌دونم', style: tBody(15, w: FontWeight.w900)),
            onTap: () => Navigator.pop(ctx, FirstGuess.unknown),
          ),
          TextButton(
            key: const ValueKey('guess-skip'),
            onPressed: () => Navigator.pop(ctx),
            child: Text('الان نه', style: tBody(14, color: K.textSoft)),
          ),
        ]),
      ),
    ),
  );
  // asked once per case on this phone, whatever the player chose (a skip is an answer too)
  await Api.i.setFlag(flag);
  if (pick != null) await Api.i.giveGuess(c.id, pick);
}

/// On the result screen: the first guess next to the truth, and what the other detectives first guessed
/// (the server sends percentages only when enough guesses exist). Nothing is shown for a player who did not guess.
class FirstGuessCard extends StatelessWidget {
  const FirstGuessCard({super.key, required this.caseData, required this.guess});
  final CaseData caseData;
  final FirstGuess? guess;

  @override
  Widget build(BuildContext context) {
    final g = guess;
    if (g == null || g.guess == null) return const SizedBox.shrink();
    final unknown = g.guess == FirstGuess.unknown;
    final who = unknown ? null : caseData.suspect(g.guess!);
    final verdict = g.correct == null ? '' : g.correct! ? ' و درست بود!' : '، ولی درست نبود.';
    final rows = [for (final x in caseData.suspects) (x, g.suspects[x.id] ?? 0)]..sort((a, b) => b.$2.compareTo(a.$2));
    return FadeSlideIn(
      child: Paper(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.psychology_alt_rounded, color: K.ink),
            const SizedBox(width: 8),
            Expanded(child: Text('حدس اولت', style: tDisplay(18, color: K.ink))),
          ]),
          const SizedBox(height: 2),
          Text(
            unknown ? 'قبل از شروع، نمی‌دونستی کیه؛ و این هم یه حدسه!' : 'قبل از شروع به ${who?.name ?? 'یکی از مظنون‌ها'} شک کردی$verdict',
            key: const ValueKey('first-guess-line'),
            style: tBody(14, color: K.inkSoft, w: FontWeight.w700),
          ),
          if (g.hasCommunity) ...[
            const SizedBox(height: 10),
            Text('حدس اولِ ${fa(g.total)} کارآگاه', style: tBody(13, color: K.inkSoft)),
            const SizedBox(height: 6),
            for (final r in rows) _bar(r.$1.name, r.$2, r.$1.id == g.culprit),
            if (g.unknownPct > 0) _bar('نمی‌دونستن', g.unknownPct, false),
          ],
        ]),
      ),
    );
  }

  Widget _bar(String name, int pct, bool culprit) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
            width: 104,
            child: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(13, color: K.ink, w: culprit ? FontWeight.w900 : FontWeight.w700)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: pct / 100, minHeight: 12, color: culprit ? K.stamp : K.inkSoft.withValues(alpha: 0.55), backgroundColor: K.paperDark),
            ),
          ),
          SizedBox(width: 46, child: Text('${fa(pct)}٪', textAlign: TextAlign.left, style: tBody(13, color: K.ink, w: FontWeight.w900))),
        ]),
      );
}
