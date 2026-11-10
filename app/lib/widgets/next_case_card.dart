import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/starter_offer.dart';
import '../theme.dart';
import 'category.dart';

/// «هنوز ذهنت گرمه؛ یکی دیگه؟» — the one primary next step after a solve: a suggested archive case and ONE button.
/// With too few coins the button says how many are missing and [onShort] opens the starter-pack sheet (or the shop).
class NextCaseCard extends StatelessWidget {
  const NextCaseCard({super.key, required this.row, required this.coins, required this.onOpen, required this.onShort, required this.onMore});
  final CaseRow row;
  final int coins;
  final VoidCallback onOpen, onShort, onMore;

  /// The button text, pure so tests can check it: free, enough coins, or how many coins are missing.
  static String buttonLabel(int price, int coins) {
    if (price <= 0) return 'باز کن';
    if (coins >= price) return 'باز کن · ${fa(price)} سکه';
    return 'باز کن · ${fa(price)} سکه (${fa(price - coins)} سکه کم داری)';
  }

  @override
  Widget build(BuildContext context) {
    final price = suggestedPrice(row);
    final enough = coins >= price;
    final meta = [if (categoryName(row.category).isNotEmpty) categoryName(row.category), if (row.suspectCount > 0) '${fa(row.suspectCount)} مظنون', 'سختی ${fa(row.difficulty)} از ${fa(5)}'];
    return Container(
      key: const ValueKey('next-case-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('هنوز ذهنت گرمه؛ یکی دیگه؟', style: tBody(12, color: K.inkSoft, w: FontWeight.w900)),
        const SizedBox(height: 10),
        // IntrinsicHeight: a stretching Row inside a scroll view gets an infinite height otherwise (CI, 10 Nov 2026).
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: K.ink, borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('پرونده', style: tBody(10.5, color: K.paper.withValues(alpha: 0.7), w: FontWeight.w800)),
              Text(fa(row.number), style: tDisplay(22, color: K.paper)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.title, key: const ValueKey('next-case-title'), style: tDisplay(16, color: K.ink)),
              Text(meta.join(' · '), style: tBody(12, color: K.inkSoft, w: FontWeight.w700)),
              if (row.solveRate != null)
                Text('${fa(row.solveRate!)}٪ کارآگاه‌ها حلش کردن', key: const ValueKey('next-case-rate'), style: tBody(11.5, color: const Color(0xFF3E6B4E), w: FontWeight.w800)),
            ]),
          ),
        ])),
        const SizedBox(height: 12),
        StampButton(
          key: const ValueKey('next-case-open'),
          label: buttonLabel(price, coins),
          icon: Icons.folder_open_rounded,
          height: 52,
          color: K.ink,
          onTap: enough ? onOpen : onShort,
        ),
        TextButton(
          key: const ValueKey('next-case-more'),
          onPressed: onMore,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          child: Text('یه پرونده‌ی دیگه نشونم بده', style: tBody(12.5, color: K.inkSoft, w: FontWeight.w800)),
        ),
      ]),
    );
  }
}

/// «فردا ساعت ۲۱ پرونده‌ی بعدی باز می‌شه» from the server's real next opening time.
String nextOpeningText(DateTime next, DateTime now) {
  final h = fa(next.hour), m = next.minute == 0 ? '' : ':${fa(next.minute).padLeft(2, '۰')}';
  final days = DateTime(next.year, next.month, next.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final when = days <= 0 ? 'امشب' : days == 1 ? 'فردا' : '${fa(days)} روز دیگه';
  return '$when ساعت $h$m پرونده‌ی بعدی باز می‌شه';
}
