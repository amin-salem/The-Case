import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';
import 'avatar_frame.dart';
import 'state_view.dart';

/// The sheet that opens from a board row (UX pack, session 6): the public numbers of one detective.
/// Closes with ✕ (48 px), «بستن» or a swipe down. A failed load keeps the sheet with a calm line and a retry.
Future<void> showPlayerSheet(BuildContext context, LeaderRow row) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: K.night2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => PlayerSheet(row: row),
  );
}

class PlayerSheet extends StatefulWidget {
  const PlayerSheet({super.key, required this.row});
  final LeaderRow row;

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  PlayerCard? _card;
  Object? _error;
  bool _loading = true;

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

  Widget _tile(String key, String value, String label) => Expanded(
        child: Container(
          key: ValueKey(key),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(value, style: tBody(17, color: K.brass, w: FontWeight.w900)),
            Text(label, textAlign: TextAlign.center, style: tBody(11.5, color: K.textSoft)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final c = _card;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: SingleChildScrollView(
          key: const ValueKey('player-sheet'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: IconButton(
                key: const ValueKey('player-sheet-close'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: 'بستن',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            AvatarWithFrame(avatar: r.avatarId, frame: r.avatarFrame, size: 88, animate: true),
            const SizedBox(height: 8),
            Text(r.me ? '${r.nickname} (تو)' : r.nickname, style: tDisplay(19), textAlign: TextAlign.center),
            Text([if (r.rankTitle.isNotEmpty) r.rankTitle, if (r.rank > 0) 'رتبه‌ی ${fa(r.rank)}'].join(' · '),
                style: tBody(12.5, color: K.textSoft)),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: CircularProgressIndicator(color: K.brass))
            else if (c == null)
              SizedBox(height: 260, child: StateView.forError(_error!, key: const ValueKey('player-sheet-state'), onRetry: _load))
            else ...[
              Row(children: [
                _tile('stat-solved', fa(c.casesSolved), 'پرونده‌ی حل‌شده'),
                _tile('stat-streak', fa(c.streak), 'زنجیره‌ی الان'),
                _tile('stat-best', fa(c.bestStreak), 'بهترین زنجیره'),
              ]),
              if (c.leagueHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(alignment: AlignmentDirectional.centerStart, child: Text('لیگ‌های هفته‌های اخیر', style: tBody(13, color: K.brass, w: FontWeight.w900))),
                const SizedBox(height: 6),
                Wrap(
                  key: const ValueKey('league-history'),
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final w in c.leagueHistory)
                      Chip(
                        label: Text(w.league, style: tBody(12, w: FontWeight.w900)),
                        backgroundColor: K.night3,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
            const SizedBox(height: 14),
            OutlinedButton(
              key: const ValueKey('player-sheet-done'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('بستن'),
            ),
          ]),
        ),
      ),
    );
  }
}
