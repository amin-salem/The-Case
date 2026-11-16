import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/tools.dart';
import '../theme.dart';
import 'tool_tray.dart';

/// The three hint steps, by what they give (the hint TEXT stays in the case file).
const kHintNames = ['جهت فکر', 'مدرک کلیدی', 'تقریباً جواب'];
const _hintWhat = [
  'یه جهت فکر بهت می‌ده تا از کجا شروع کنی.',
  'مدرکی که باید روش تمرکز کنی رو نشون می‌ده.',
  'تقریباً جواب رو می‌گه؛ آخرین کمک.',
];
const _toolWhat = {
  'magnifier': 'یه مدرک بی‌ربط رو کنار می‌ذاره.',
  'fingerprint': 'یه ردِ فیزیکیِ تازه از یه مظنون.',
  'camera': 'یه مشاهده‌ی تازه از یه مظنون.',
};

/// One row of the «کمک کارآگاه» sheet: a tool or a hint, with what it gives and what it costs.
class HelpOption {
  const HelpOption({
    required this.id,
    required this.icon,
    required this.title,
    required this.what,
    required this.price,
    required this.plaque,
    this.free = false,
    this.stock = 0,
    this.locked = false,
    this.done = false,
    this.tool,
    this.hintIndex,
  });

  /// `magnifier`, `fingerprint`, `camera`, `hint1`, `hint2`, `hint3`.
  final String id;
  final IconData icon;
  final String title, what;
  final int price;

  /// true when taking it costs a plaque (hints 2 and 3 only; tools and hint 1 never do)
  final bool plaque;

  /// the one-time free tool, or a tool already in the bag: no coins are spent
  final bool free;
  final int stock;

  /// a hint whose earlier step is not taken yet
  final bool locked;

  /// already taken / used on this case
  final bool done;
  final ToolInfo? tool;
  final int? hintIndex;

  bool get isHint => hintIndex != null;
  bool get selectable => !locked && !done;
}

/// All helps, in the order of the board: magnifier, hint 1, fingerprint, camera, hint 2, hint 3.
/// Tools appear only when the server says the case supports them (`tray.daily`, `enabled`, `available`).
List<HelpOption> buildHelpOptions(Progress p, ToolTray? tray, {bool vipFree = false}) {
  HelpOption? tool(String kind) {
    final t = tray?.byKind(kind);
    if (tray == null || !tray.daily || !tray.enabled || t == null || !t.available) return null;
    return HelpOption(
      id: kind,
      icon: toolIcon(kind),
      title: t.title,
      what: _toolWhat[kind] ?? t.desc,
      price: t.price,
      plaque: false,
      free: t.hasOne,
      stock: t.count,
      done: t.used,
      locked: !t.usable && !t.used,
      tool: t,
    );
  }

  HelpOption? hint(int i) {
    if (i >= p.hintCosts.length) return null;
    return HelpOption(
      id: 'hint${i + 1}',
      icon: Icons.lightbulb_rounded,
      title: kHintNames[i.clamp(0, 2)],
      what: _hintWhat[i.clamp(0, 2)],
      price: p.hintCosts[i],
      plaque: i >= 1,
      free: i == 0 && vipFree && p.hints.isEmpty,
      done: i < p.hints.length,
      locked: i > p.hints.length,
      hintIndex: i,
    );
  }

  return [
    for (final o in [tool('magnifier'), hint(0), tool('fingerprint'), tool('camera'), hint(1), hint(2)])
      if (o != null) o,
  ];
}

/// How many of the one-time free tools can still be used here (the badge «N رایگان» on the help button).
int freeHelpCount(ToolTray? tray) {
  if (tray == null || !tray.daily || !tray.enabled) return 0;
  return tray.tools.where((t) => t.available && t.usable && t.freeAvailable && t.count == 0).length;
}

/// The three hint steps as a ladder: taken in colour, the next one larger and lit, the rest grey. Fills from the right.
class HintLadder extends StatelessWidget {
  const HintLadder({super.key, required this.taken});
  final int taken;

  @override
  Widget build(BuildContext context) {
    return Row(key: const ValueKey('hint-ladder'), children: [
      for (int i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _step(i)),
      ],
    ]);
  }

  Widget _step(int i) {
    final done = i < taken, current = i == taken;
    final color = done ? K.brass : (current ? K.brass : K.night3);
    return AnimatedContainer(
      key: ValueKey('hint-step-$i-${done ? 'taken' : current ? 'current' : 'ahead'}'),
      duration: const Duration(milliseconds: 200),
      height: current ? 12 : 8,
      decoration: BoxDecoration(
        color: done ? K.brass.withValues(alpha: 0.75) : (current ? color : K.night3),
        borderRadius: BorderRadius.circular(99),
        boxShadow: current ? [BoxShadow(color: K.brass.withValues(alpha: 0.55), blurRadius: 10)] : null,
      ),
    );
  }
}

/// The «کمک کارآگاه» sheet. Tapping a row selects it; the button at the bottom spends. Returns the chosen option, or null
/// when closed. The caller does the buying (the server is the boss of coins and prices).
Future<HelpOption?> showHelpSheet(
  BuildContext context, {
  required List<HelpOption> options,
  required int hintsTaken,
  required int coins,
  String? preselect,
}) {
  return showModalBottomSheet<HelpOption>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: K.night2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _HelpSheet(options: options, hintsTaken: hintsTaken, coins: coins, preselect: preselect),
  );
}

class _HelpSheet extends StatefulWidget {
  const _HelpSheet({required this.options, required this.hintsTaken, required this.coins, this.preselect});
  final List<HelpOption> options;
  final int hintsTaken, coins;
  final String? preselect;

  @override
  State<_HelpSheet> createState() => _HelpSheetState();
}

class _HelpSheetState extends State<_HelpSheet> {
  String? _sel;

  @override
  void initState() {
    super.initState();
    final pre = widget.preselect;
    if (pre != null && widget.options.any((o) => o.id == pre && o.selectable)) _sel = pre;
  }

  HelpOption? get _chosen {
    for (final o in widget.options) {
      if (o.id == _sel) return o;
    }
    return null;
  }

  String _priceText(HelpOption o) {
    if (o.done) return 'انجام شد';
    if (o.tool != null && o.stock > 0) return '×${fa(o.stock)} در کیف';
    if (o.free) return 'رایگان';
    return '${fa(o.price)} سکه';
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(9)))),
          const SizedBox(height: 12),
          Text('کمک کارآگاه', style: tDisplay(19)),
          const SizedBox(height: 10),
          HintLadder(taken: widget.hintsTaken),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              key: const ValueKey('help-list'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final o in widget.options) _row(o),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          _confirm(chosen),
        ]),
      ),
    );
  }

  Widget _row(HelpOption o) {
    final on = o.id == _sel;
    final off = !o.selectable;
    final tag = o.plaque ? '−۱ پلاک' : 'پلاک کم نمی‌شود';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: off ? 0.5 : 1,
        child: InkWell(
          key: ValueKey('help-opt-${o.id}'),
          borderRadius: BorderRadius.circular(14),
          onTap: off ? null : () => setState(() => _sel = o.id),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: on ? K.brass.withValues(alpha: 0.14) : K.night3.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? K.brass : K.night3, width: on ? 2 : 1),
            ),
            child: Row(children: [
              Icon(o.done ? Icons.check_circle_rounded : (o.locked ? Icons.lock_rounded : o.icon),
                  color: o.done ? K.ok : (o.locked ? K.textSoft : K.brass), size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.title, style: tBody(14.5, w: FontWeight.w900).copyWith(height: 1.4)),
                  Text(o.locked && o.isHint ? 'اول کمک قبلی رو بگیر.' : o.what, style: tBody(12.5, color: K.textSoft).copyWith(height: 1.5)),
                ]),
              ),
              const SizedBox(width: 8),
              if (!o.done && !o.locked)
                Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(_priceText(o),
                      style: tBody(13, color: (o.free || o.stock > 0) ? K.ok : K.text, w: FontWeight.w900).copyWith(height: 1.4)),
                  Text(tag, key: ValueKey('help-tag-${o.id}'), style: tBody(11, color: o.plaque ? K.stamp : K.textSoft).copyWith(height: 1.4)),
                ])
              else if (o.done)
                Text(_priceText(o), style: tBody(12, color: K.ok, w: FontWeight.w800)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _confirm(HelpOption? o) {
    final String label;
    if (o == null) {
      label = 'یکی رو انتخاب کن';
    } else if (o.free || (o.tool != null && o.stock > 0)) {
      label = '${o.title} · بگیر';
    } else {
      label = '${o.title} · ${fa(o.price)} سکه';
    }
    return Opacity(
      opacity: o == null ? 0.45 : 1,
      child: InkWell(
        key: const ValueKey('help-confirm'),
        onTap: o == null ? null : () => Navigator.of(context).pop(o),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(14)),
          child: Text(label, style: tBody(15, color: K.ink, w: FontWeight.w900).copyWith(height: 1.3)),
        ),
      ),
    );
  }
}

/// The small non-blocking strip above the bottom bar: one line, one tap to open the help, one tap to close.
class HelpNudgeStrip extends StatelessWidget {
  const HelpNudgeStrip({super.key, required this.text, required this.action, required this.onTap, required this.onClose});
  final String text, action;
  final VoidCallback onTap, onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: K.night3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: K.brass.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Expanded(
          child: InkWell(
            key: const ValueKey('help-nudge-tap'),
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                const Icon(Icons.lightbulb_outline_rounded, color: K.brass, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: tBody(12.5, w: FontWeight.w700).copyWith(height: 1.5))),
                const SizedBox(width: 8),
                Text(action, style: tBody(12.5, color: K.brass, w: FontWeight.w900)),
              ]),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('help-nudge-close'),
          tooltip: 'بستن',
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          icon: const Icon(Icons.close_rounded, size: 18, color: K.textSoft),
          onPressed: onClose,
        ),
      ]),
    );
  }
}
