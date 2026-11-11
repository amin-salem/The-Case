import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import 'id_card.dart';
import 'state_view.dart';

/// Tapping a detective on a board brings up HIS ID card (replaces the old bottom sheet): the card flips to its back,
/// and his three newest badges sit under it. Closes with ✕, a tap outside or back. A failed load keeps a calm retry.
Future<void> showPlayerCard(BuildContext context, LeaderRow row) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'بستن',
    barrierColor: const Color(0xD0000000),
    transitionDuration: const Duration(milliseconds: 220),
    transitionBuilder: (_, a, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
    pageBuilder: (_, __, ___) => PlayerCardOverlay(row: row),
  );
}

class PlayerCardOverlay extends StatefulWidget {
  const PlayerCardOverlay({super.key, required this.row});
  final LeaderRow row;

  @override
  State<PlayerCardOverlay> createState() => _PlayerCardOverlayState();
}

class _PlayerCardOverlayState extends State<PlayerCardOverlay> {
  PlayerCard? _card;
  Object? _error;
  bool _loading = true;
  bool _back = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await Api.i.playerCard(widget.row.pid);
      if (!mounted) return;
      setState(() {
        _card = c;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    final data = c == null ? null : IdCardData.of(widget.row, c);
    final look = LeagueLook.of(data?.league ?? 0);
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            key: const ValueKey('player-sheet'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    key: const ValueKey('player-sheet-close'),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    tooltip: 'بستن',
                    icon: const Icon(Icons.close_rounded, color: K.text),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                if (_loading)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 80), child: CircularProgressIndicator(color: K.brass))
                else if (data == null)
                  SizedBox(height: 260, child: StateView.forError(_error!, key: const ValueKey('player-sheet-state'), onRetry: _load))
                else ...[
                  IdCard(data: data, onFlip: (b) => setState(() => _back = b)),
                  const SizedBox(height: 14),
                  CardDots(back: _back, look: look),
                  if (data.recent.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    RecentBadges(key: const ValueKey('recent-badges'), badges: data.recent),
                  ],
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
