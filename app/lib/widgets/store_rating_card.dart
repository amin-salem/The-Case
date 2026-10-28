import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/store_rating.dart';
import '../theme.dart';

/// Home card «از بازی راضی بودی؟»: see services/store_rating.dart for the rules (30 days, once, never blocks).
class StoreRatingCard extends StatefulWidget {
  const StoreRatingCard({super.key});

  @override
  State<StoreRatingCard> createState() => _StoreRatingCardState();
}

class _StoreRatingCardState extends State<StoreRatingCard> {
  @override
  void initState() {
    super.initState();
    StoreRating.i.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([StoreRating.i, Api.i]),
      builder: (context, _) {
        if (!StoreRating.i.visible) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey('rating_card'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: K.night3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: K.brass.withValues(alpha: 0.5)),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.star_rounded, size: 22, color: K.brass)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('از بازی راضی بودی؟ به ما توی کافه بازار امتیاز بده؛ به دیده شدن پرونده کمک می‌کنه.',
                        style: tBody(12.5, color: K.text)),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    FilledButton(
                      key: const ValueKey('rating_open'),
                      style: FilledButton.styleFrom(backgroundColor: K.stamp, visualDensity: VisualDensity.compact),
                      onPressed: () async {
                        final ok = await StoreRating.i.rate();
                        if (!ok && context.mounted) toast(context, 'صفحه باز نشد');
                      },
                      child: Text('امتیاز می‌دم', style: tBody(13, w: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const ValueKey('rating_later'),
                      onPressed: StoreRating.i.later,
                      child: Text('بعداً', style: tBody(13, color: K.textSoft)),
                    ),
                  ]),
                ]),
              ),
              IconButton(
                key: const ValueKey('rating_close'),
                tooltip: 'بستن',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: K.textSoft),
                onPressed: StoreRating.i.later,
              ),
            ]),
          ),
        );
      },
    );
  }
}
