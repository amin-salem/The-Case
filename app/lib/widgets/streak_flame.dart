import 'package:flutter/material.dart';

import '../theme.dart';

/// The colour of a streak's flame: orange at first, hotter with every step of the ladder.
Color streakFlameColor(int streak) {
  if (streak >= 365) return const Color(0xFFFFE08A);
  if (streak >= 100) return const Color(0xFFFFB347);
  if (streak >= 30) return const Color(0xFFFF8A3C);
  return K.stamp;
}

/// A small flame with the number of nights in a row, drawn next to a nickname (leaderboard rows, the profile).
/// Nothing for a streak of 0 or 1: a flame has to be earned.
class StreakFlame extends StatelessWidget {
  const StreakFlame(this.streak, {super.key, this.size = 15});
  final int streak;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (streak < 2) return const SizedBox.shrink();
    final color = streakFlameColor(streak);
    return Semantics(
      label: '${fa(streak)} شب پشت سر هم',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.local_fire_department_rounded, size: size + 2, color: color),
        Text(fa(streak), style: tBody(size - 2, w: FontWeight.w900, color: color)),
      ]),
    );
  }
}
