import 'dart:async';

import 'package:flutter/material.dart';

/// Shows text letter by letter, like a typewriter. Tap to show it all.
class Typewriter extends StatefulWidget {
  const Typewriter(this.text, {super.key, required this.style, this.speed = const Duration(milliseconds: 28), this.onDone});
  final String text;
  final TextStyle style;
  final Duration speed;
  final VoidCallback? onDone;

  @override
  State<Typewriter> createState() => _TypewriterState();
}

class _TypewriterState extends State<Typewriter> {
  int _n = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.speed, (t) {
      if (!mounted) return t.cancel();
      setState(() => _n += 1);
      if (_n >= widget.text.length) {
        t.cancel();
        widget.onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _finish() {
    if (_n >= widget.text.length) return;
    _timer?.cancel();
    setState(() => _n = widget.text.length);
    widget.onDone?.call();
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.text.substring(0, _n.clamp(0, widget.text.length));
    return GestureDetector(
      onTap: _finish,
      behavior: HitTestBehavior.opaque,
      child: Stack(children: [
        // reserve the full height so the layout doesn't jump
        Opacity(opacity: 0, child: Text(widget.text, style: widget.style)),
        Text(shown, style: widget.style),
      ]),
    );
  }
}

/// Slams a stamp onto the screen (scale + fade in).
class StampIn extends StatefulWidget {
  const StampIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<StampIn> createState() => _StampInState();
}

class _StampInState extends State<StampIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final v = Curves.easeOutBack.transform(_c.value);
          return Opacity(opacity: _c.value.clamp(0.0, 1.0), child: Transform.scale(scale: 2.2 - 1.2 * v, child: child));
        },
        child: widget.child,
      );
}

/// Fades and slides a child in after a delay (for lists appearing one by one).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) => Opacity(
          opacity: _c.value,
          child: Transform.translate(offset: Offset(0, 18 * (1 - Curves.easeOut.transform(_c.value))), child: child),
        ),
        child: widget.child,
      );
}
