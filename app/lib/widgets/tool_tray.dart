import 'package:flutter/material.dart';

import '../models/tools.dart';
import '../theme.dart';

IconData toolIcon(String kind) => switch (kind) {
      'magnifier' => Icons.search_rounded,
      'fingerprint' => Icons.fingerprint_rounded,
      'camera' => Icons.videocam_rounded,
      _ => Icons.build_rounded,
    };

/// The tool tray of a daily case: up to three icons with a count or a price. One tap uses (or, with none in hand, asks
/// once to buy). Only tools the case file supports are drawn; a weekend or story case just says tools are for daily cases.
class ToolTrayBar extends StatelessWidget {
  const ToolTrayBar({super.key, required this.tray, required this.onTap, this.busy = false});
  final ToolTray tray;
  final void Function(ToolInfo) onTap;
  final bool busy;

  String _sub(ToolInfo t) {
    if (t.used) return 'انجام شد ✓';
    if (t.count > 0) return '×${fa(t.count)}';
    if (t.freeAvailable) return 'رایگان';
    return '${fa(t.price)} سکه';
  }

  @override
  Widget build(BuildContext context) {
    if (!tray.daily) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(tray.message.isNotEmpty ? tray.message : 'ابزارهای کارآگاهی فقط توی پرونده‌های روزانه کار می‌کنن.',
            key: const ValueKey('tools-daily-only'), textAlign: TextAlign.center, style: tBody(12, color: K.textSoft)),
      );
    }
    final shown = [for (final t in tray.tools) if (t.available) t];
    if (!tray.enabled || shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        for (int i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _ToolButton(tool: shown[i], sub: _sub(shown[i]), busy: busy, onTap: () => onTap(shown[i]))),
        ],
      ]),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.sub, required this.busy, required this.onTap});
  final ToolInfo tool;
  final String sub;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = tool.used;
    final off = !tool.usable && !done;
    return Semantics(
      button: true,
      label: '${tool.title}، $sub',
      child: InkWell(
        key: ValueKey('tool-${tool.kind}'),
        borderRadius: BorderRadius.circular(10),
        onTap: busy || off ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          decoration: BoxDecoration(
            color: K.night3.withValues(alpha: off ? 0.5 : 1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: done ? K.ok.withValues(alpha: 0.7) : K.brass.withValues(alpha: 0.45)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(toolIcon(tool.kind), size: 20, color: done ? K.ok : K.brass),
            const SizedBox(width: 6),
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tool.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11.5, w: FontWeight.w900)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tBody(10.5, color: tool.freeAvailable && !done ? K.ok : K.textSoft)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
