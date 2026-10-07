import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'crime_tape.dart';

/// Days, hours, minutes and seconds left, in Persian digits, ticking every second.
/// [onDone] is called once when the time is reached.
class BigCountdown extends StatefulWidget {
  const BigCountdown({super.key, required this.at, this.onDone});
  final DateTime at;
  final VoidCallback? onDone;

  @override
  State<BigCountdown> createState() => _BigCountdownState();
}

class _BigCountdownState extends State<BigCountdown> {
  Timer? _t;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (!_done && !widget.at.isAfter(DateTime.now())) {
      _done = true;
      widget.onDone?.call();
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var left = widget.at.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    String two(int v) => fa(v).padLeft(2, '۰');
    Widget cell(String v, String label) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: K.brass.withValues(alpha: 0.5)),
            ),
            child: Column(children: [
              Text(v, style: tDisplay(22, color: K.brass)),
              Text(label, style: tBody(10.5, color: K.textSoft)),
            ]),
          ),
        );
    // right to left: days, hours, minutes, seconds
    return Row(children: [
      cell(fa(left.inDays), 'روز'),
      cell(two(left.inHours % 24), 'ساعت'),
      cell(two(left.inMinutes % 60), 'دقیقه'),
      cell(two(left.inSeconds % 60), 'ثانیه'),
    ]);
  }
}

/// A big banner for a section: picture, crime tape, a chip, title, line, and a countdown or a button.
class SectionBanner extends StatelessWidget {
  const SectionBanner({
    super.key,
    required this.background,
    required this.chip,
    required this.title,
    this.subtitle,
    this.countdownLabel,
    this.at,
    this.onCountdownDone,
    this.button,
    this.onTap,
  });

  final Widget background;
  final String chip;
  final String title;
  final String? subtitle;
  final String? countdownLabel;
  final DateTime? at;
  final VoidCallback? onCountdownDone;
  final Widget? button;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: K.brass, width: 1.5),
          boxShadow: [BoxShadow(color: K.brass.withValues(alpha: 0.16), blurRadius: 20)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(children: [
            Positioned.fill(child: background),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.82)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 26,
              left: -60,
              right: -60,
              child: Transform.rotate(angle: -0.09, child: const CrimeTape(height: 22)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 70, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(999)),
                  child: Text(chip, style: tBody(11.5, color: K.ink, w: FontWeight.w900)),
                ),
                const SizedBox(height: 10),
                Text(title, style: tDisplay(28)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: tBody(13.5, color: K.text.withValues(alpha: 0.85))),
                ],
                if (at != null) ...[
                  const SizedBox(height: 14),
                  if (countdownLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6, right: 3),
                      child: Text(countdownLabel!, style: tBody(12.5, color: K.textSoft, w: FontWeight.w700)),
                    ),
                  BigCountdown(at: at!, onDone: onCountdownDone),
                ],
                if (button != null) ...[const SizedBox(height: 14), button!],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A row of "how it works" lines with icons, on a dark card.
class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.title, required this.lines});
  final String title;
  final List<(IconData, String)> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: tDisplay(17)),
        const SizedBox(height: 8),
        for (final (icon, text) in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 18, color: K.brass),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: tBody(13.5))),
            ]),
          ),
      ]),
    );
  }
}
