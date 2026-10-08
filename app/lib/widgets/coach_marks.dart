import 'package:flutter/material.dart';

import '../theme.dart';

/// A dimmed layer with a hole around one target (found by its GlobalKey) and a small
/// paper note next to it: step N of M, a title, a line, «رد کن» and «بعدی» / «فهمیدم».
class CoachMarks extends StatefulWidget {
  const CoachMarks({
    super.key,
    required this.step,
    required this.targets,
    required this.steps,
    required this.onNext,
    required this.onSkip,
  });

  final int step;
  final List<GlobalKey> targets;
  final List<(String, String)> steps;
  final VoidCallback onNext, onSkip;

  @override
  State<CoachMarks> createState() => _CoachMarksState();
}

class _CoachMarksState extends State<CoachMarks> {
  final _self = GlobalKey();
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    _measureSoon();
  }

  @override
  void didUpdateWidget(covariant CoachMarks old) {
    super.didUpdateWidget(old);
    if (old.step != widget.step) _measureSoon();
  }

  /// The targets are laid out by now (or after the tab switch settles), so measure after the frame.
  void _measureSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    Future<void>.delayed(const Duration(milliseconds: 350), _measure);
  }

  void _measure() {
    if (!mounted) return;
    final i = widget.step;
    if (i < 0 || i >= widget.targets.length) return;
    final target = widget.targets[i].currentContext?.findRenderObject();
    final me = _self.currentContext?.findRenderObject();
    if (target is! RenderBox || me is! RenderBox || !target.hasSize || !me.hasSize || !target.attached) return;
    final topLeft = target.localToGlobal(Offset.zero, ancestor: me);
    final r = (topLeft & target.size).inflate(6);
    if (r != _hole) setState(() => _hole = r);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final (title, text) = widget.steps[step];
    final last = step == widget.steps.length - 1;
    return LayoutBuilder(
      key: _self,
      builder: (context, box) {
        final hole = _hole;
        // the note sits under a target in the top half, above one in the bottom half
        final below = hole == null || hole.center.dy < box.maxHeight / 2;
        final note = Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: K.paper,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fa(step + 1)} از ${fa(widget.steps.length)}', style: tBody(12, color: K.inkSoft, w: FontWeight.w700)),
              Text(title, style: tDisplay(20, color: K.ink)),
              const SizedBox(height: 4),
              Text(text, style: tBody(14, color: K.ink)),
              const SizedBox(height: 10),
              Row(children: [
                TextButton(
                  onPressed: widget.onSkip,
                  style: TextButton.styleFrom(foregroundColor: K.inkSoft),
                  child: Text('رد کن', style: tBody(14, color: K.inkSoft, w: FontWeight.w700)),
                ),
                const Spacer(),
                StampButton(label: last ? 'فهمیدم' : 'بعدی', height: 42, onTap: widget.onNext),
              ]),
            ]),
          ),
        );
        return Stack(children: [
          // the dim layer swallows taps, so the player goes through the steps (or skips)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _HolePainter(hole)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: below ? (hole == null ? box.maxHeight * 0.3 : hole.bottom + 14) : null,
            bottom: below ? null : box.maxHeight - hole!.top + 14,
            child: note,
          ),
        ]);
      },
    );
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter(this.hole);
  final Rect? hole;

  @override
  void paint(Canvas c, Size s) {
    final all = Path()..addRect(Offset.zero & s);
    final h = hole;
    if (h == null) {
      c.drawPath(all, Paint()..color = const Color(0xB3000000));
      return;
    }
    final rr = RRect.fromRectAndRadius(h, const Radius.circular(14));
    c.drawPath(Path.combine(PathOperation.difference, all, Path()..addRRect(rr)), Paint()..color = const Color(0xB3000000));
    c.drawRRect(
        rr,
        Paint()
          ..color = K.brass
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _HolePainter old) => old.hole != hole;
}
