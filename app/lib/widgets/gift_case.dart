import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

/// «پرونده‌ی هدیه‌ی تو»: an archive case the server made free to open for THIS (new) detective for a few hours
/// (`free_until`). Shown on the home page and pinned at the top of the archive, so a viewer who came from the ad video
/// finds the case without knowing where the archive is. Real data only: it exists only while the server sends `free_until`.

/// The case to offer, or null: free for him right now, not opened, solved or lost yet.
CaseRow? giftCase(Iterable<CaseRow> rows, DateTime now) {
  for (final c in rows) {
    final end = c.freeUntil;
    if (end != null && end.isAfter(now) && !c.solved && !c.failed) return c;
  }
  return null;
}

/// «۳۱ ساعت و ۲۰ دقیقه دیگه» / «۴۵ دقیقه دیگه» / «کمتر از یک دقیقه دیگه».
String giftLeftText(Duration left) {
  if (left.inMinutes < 1) return 'کمتر از یک دقیقه دیگه';
  final h = left.inHours, m = left.inMinutes % 60;
  if (h == 0) return '${fa(m)} دقیقه دیگه';
  if (h >= 24) return '${fa(h)} ساعت دیگه';
  return m == 0 ? '${fa(h)} ساعت دیگه' : '${fa(h)} ساعت و ${fa(m)} دقیقه دیگه';
}

class GiftCaseCard extends StatelessWidget {
  const GiftCaseCard({super.key, required this.row, required this.onOpen, this.onClose, this.margin = const EdgeInsets.only(bottom: 10)});

  final CaseRow row;
  final VoidCallback onOpen;
  final VoidCallback? onClose;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final left = (row.freeUntil ?? DateTime.now()).difference(DateTime.now());
    return Padding(
      padding: margin,
      child: Material(
        key: const ValueKey('gift-case'),
        color: K.night2,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: K.brass, width: 1.5)),
          child: Row(children: [
            Expanded(
              child: InkWell(
                key: const ValueKey('gift-open'),
                borderRadius: BorderRadius.circular(16),
                onTap: onOpen,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 6, 12),
                  child: Row(children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(color: K.night3, shape: BoxShape.circle),
                      child: const Icon(Icons.card_giftcard_rounded, color: K.brass, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text('پرونده‌ی هدیه‌ی تو', style: tBody(12.5, color: K.brass, w: FontWeight.w900)),
                        Text(row.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tBody(15, w: FontWeight.w900).copyWith(height: 1.5)),
                        Text('رایگان برای تو · ${giftLeftText(left)}',
                            style: tBody(12.5, color: K.textSoft).copyWith(height: 1.6)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
                      child: Text('باز کن', style: tBody(13, color: K.ink, w: FontWeight.w900).copyWith(height: 1.3)),
                    ),
                  ]),
                ),
              ),
            ),
            if (onClose != null)
              IconButton(
                key: const ValueKey('gift-close'),
                tooltip: 'بستن',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: K.textSoft, size: 20),
              ),
          ]),
        ),
      ),
    );
  }
}
