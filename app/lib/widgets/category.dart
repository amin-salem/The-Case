import 'package:flutter/material.dart';

import '../theme.dart';

/// Topic categories of a case (server: app/content.py CATEGORIES). key -> (Persian name, icon).
/// An empty or unknown key (old server, old case) shows nothing.
const Map<String, ({String name, IconData icon})> kCategories = {
  'medical': (name: 'پزشکی', icon: Icons.medical_services_rounded),
  'art': (name: 'هنر و صحنه', icon: Icons.palette_rounded),
  'family': (name: 'خانواده و ارث', icon: Icons.family_restroom_rounded),
  'business': (name: 'تجارت و پول', icon: Icons.storefront_rounded),
  'science': (name: 'علم و پژوهش', icon: Icons.science_rounded),
  'travel': (name: 'سفر و مهمانی', icon: Icons.luggage_rounded),
  'crime': (name: 'جرم و قانون', icon: Icons.gavel_rounded),
};

String categoryName(String key) => kCategories[key]?.name ?? '';

/// A small icon + name tag, e.g. «پزشکی». [compact] = smaller text for the archive card.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.compact = false});
  final String category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = kCategories[category];
    if (c == null) return const SizedBox.shrink();
    final size = compact ? 11.5 : 12.5;
    return Semantics(
      label: 'دسته: ${c.name}',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('category-$category'),
        padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
        decoration: BoxDecoration(
          color: K.night3.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: K.kraft.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(c.icon, size: size + 2, color: K.kraft),
          const SizedBox(width: 3),
          Text(c.name, maxLines: 1, style: tBody(size, color: K.text)),
        ]),
      ),
    );
  }
}
