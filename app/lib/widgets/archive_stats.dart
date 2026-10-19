import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'rate_card.dart';

/// Fixed-size block of an archive card: the detectives' rating and the comments, always the same width and the same
/// place (the physical LEFT edge of the card), whatever the case has: ratings, comments, both or nothing.
/// Muted placeholders keep the slot the same size so nothing jumps between cards.
class ArchiveStatsSlot extends StatelessWidget {
  const ArchiveStatsSlot({super.key, required this.avg, required this.count, required this.comments});
  final double avg;
  final int count;
  final int comments;

  static const double ratingWidth = 86;
  static const double commentsWidth = 44;
  static const double gap = 8;
  static const double width = ratingWidth + gap + commentsWidth;
  static const double height = 22;

  static const _tab = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) {
    final rated = count > 0;
    final hasComments = comments > 0;
    final muted = K.textSoft.withValues(alpha: 0.55);
    return SizedBox(
      key: const ValueKey('archive-stats'),
      width: width,
      height: height,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(children: [
          SizedBox(
            key: const ValueKey('archive-rating-slot'),
            width: ratingWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: rated
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.star_rounded, color: K.brass, size: 16),
                      const SizedBox(width: 2),
                      Text(faRating(avg),
                          style: tBody(12.5, w: FontWeight.w900, color: K.brass).copyWith(height: 1.2, fontFeatures: _tab)),
                      Text(' (${fa(count)})',
                          style: tBody(11.5, color: K.textSoft).copyWith(height: 1.2, fontFeatures: _tab)),
                    ])
                  : Text('بدون امتیاز', style: tBody(11.5, color: muted).copyWith(height: 1.2)),
            ),
          ),
          const SizedBox(width: gap),
          SizedBox(
            key: const ValueKey('archive-comments-slot'),
            width: commentsWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chat_bubble_outline_rounded, color: hasComments ? K.textSoft : muted, size: 14),
                const SizedBox(width: 3),
                Text(fa(comments),
                    style: tBody(11.5, color: hasComments ? K.textSoft : muted).copyWith(height: 1.2, fontFeatures: _tab)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
