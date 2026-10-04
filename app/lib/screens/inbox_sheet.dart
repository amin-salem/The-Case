import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api.dart';
import '../theme.dart';

Future<void> showInbox(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _InboxSheet(),
    );

class _InboxSheet extends StatefulWidget {
  const _InboxSheet();

  @override
  State<_InboxSheet> createState() => _InboxSheetState();
}

class _InboxSheetState extends State<_InboxSheet> {
  late Future<List<InboxGift>> _f = Api.i.inbox();
  final Set<String> _busy = {};

  Future<void> _claim(InboxGift g) async {
    setState(() => _busy.add(g.id));
    try {
      final coins = await Api.i.claim(g);
      if (mounted) toast(context, coins > 0 ? '${fa(coins)} سکه گرفتی!' : 'دریافت شد!');
    } catch (_) {
      if (mounted) toast(context, 'دریافت نشد، دوباره امتحان کن');
    }
    if (mounted) {
      setState(() {
        _busy.remove(g.id);
        _f = Api.i.inbox();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(22)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('صندوق نامه‌ها', style: tDisplay(22)),
        const SizedBox(height: 10),
        Flexible(
          child: FutureBuilder<List<InboxGift>>(
            future: _f,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(color: K.brass)));
              }
              final gifts = snap.data ?? const <InboxGift>[];
              if (gifts.isEmpty) {
                return Padding(padding: const EdgeInsets.all(24), child: Text('نامه‌ای نداری.', style: tBody(15, color: K.textSoft)));
              }
              return ListView(shrinkWrap: true, children: [
                for (final g in gifts)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Paper(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        const Icon(Icons.mark_email_unread_rounded, color: K.stamp, size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(g.title, style: tBody(15, color: K.ink, w: FontWeight.w900)),
                            if (g.message.isNotEmpty) Text(g.message, style: tBody(13, color: K.inkSoft)),
                            if (g.coins > 0) Text('${fa(g.coins)} سکه', style: tBody(13, color: K.kraftDark, w: FontWeight.w900)),
                          ]),
                        ),
                        SizedBox(
                          width: 84,
                          child: StampButton(label: 'بگیر', height: 42, color: K.ok, onTap: _busy.contains(g.id) ? null : () => _claim(g)),
                        ),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
