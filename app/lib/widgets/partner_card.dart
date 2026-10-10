import 'package:flutter/material.dart';

import '../theme.dart';
import 'character.dart';

/// ناصری's portrait: `assets/portraits/naseri.webp` once it is painted, until then the veteran officer.
const String kNaseriPortrait = 'm_mid_officer';

/// ناصری speaking: his portrait in a brass ring and his words on a paper card.
/// [thread] is the small clue of the season mystery a finished chapter leaves.
class PartnerCard extends StatelessWidget {
  const PartnerCard({super.key, required this.text, this.name = 'سرگرد ناصری', this.thread, this.dark = true});
  final String text, name;
  final String? thread;
  final bool dark; // on a dark panel (the story tab) or straight on a scene (the chapter intro)

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? K.night2 : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: dark ? null : Border.all(color: K.brass.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: K.brass, width: 2)),
          child: ClipOval(child: Image.asset(portraitAsset(kNaseriPortrait), fit: BoxFit.cover)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: tBody(15, w: FontWeight.w900, color: K.brass)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(12)),
              child: Text(text, style: tBody(13.5, color: K.ink)),
            ),
            if (thread != null && thread!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.push_pin_rounded, size: 16, color: K.brass),
                const SizedBox(width: 6),
                Expanded(child: Text('سرنخ فصل: $thread', style: tBody(12.5, color: K.clue, w: FontWeight.w700))),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
