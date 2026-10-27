import 'package:flutter/material.dart';

import '../theme.dart';

/// The metal of a medal, from how far up its chain or ladder it sits (0 = first step, 1 = the top).
enum MedalMetal { bronze, silver, gold, royal, locked }

MedalMetal metalFor(int index, int count) {
  if (count <= 1) return MedalMetal.gold;
  final f = index / (count - 1);
  if (f < 0.25) return MedalMetal.bronze;
  if (f < 0.55) return MedalMetal.silver;
  if (f < 0.9) return MedalMetal.gold;
  return MedalMetal.royal;
}

const Map<MedalMetal, List<Color>> _metal = {
  MedalMetal.bronze: [Color(0xFFE9B48A), Color(0xFF8A5226)],
  MedalMetal.silver: [Color(0xFFF4F6FA), Color(0xFF8D93A0)],
  MedalMetal.gold: [Color(0xFFFFE9A0), Color(0xFFC08A1C)],
  MedalMetal.royal: [Color(0xFFD9C4FF), Color(0xFF6A4BB8)],
  MedalMetal.locked: [Color(0xFF3A3C41), Color(0xFF26282C)],
};

/// A round medal with a ring: [child] (an icon or a number) sits in the middle. Drawn in code, sharp at every size.
class Medal extends StatelessWidget {
  const Medal({super.key, required this.metal, required this.size, this.child});
  final MedalMetal metal;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = _metal[metal]!;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: c),
        border: Border.all(color: Colors.white.withValues(alpha: metal == MedalMetal.locked ? 0.08 : 0.45), width: size * 0.04),
        boxShadow: metal == MedalMetal.locked
            ? null
            : [BoxShadow(color: c.last.withValues(alpha: 0.5), blurRadius: size * 0.22, spreadRadius: -size * 0.04)],
      ),
      child: Container(
        width: size * 0.74,
        height: size * 0.74,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black.withValues(alpha: 0.18), width: size * 0.02)),
        child: child,
      ),
    );
  }
}

/// The text colour that reads on a medal of this metal.
Color medalInk(MedalMetal m) => m == MedalMetal.locked ? K.textSoft : (m == MedalMetal.royal ? Colors.white : K.ink);
