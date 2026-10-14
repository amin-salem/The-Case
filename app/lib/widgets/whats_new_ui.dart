import 'package:flutter/material.dart';

import '../data/whats_new.dart';
import '../screens/main_shell.dart';
import '../services/sound.dart';
import '../services/whats_new.dart';
import '../theme.dart';

/// Small red «تازه» tag; [id] is a tag id from whats_new.dart. Shows nothing once opened or after 7 days.
class NewTag extends StatelessWidget {
  const NewTag(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: WhatsNew.i,
        builder: (_, __) => !WhatsNew.i.tagVisible(id)
            ? const SizedBox.shrink()
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: K.stamp, borderRadius: BorderRadius.circular(10)),
                child: Text('تازه', style: tBody(11.5, color: K.night, w: FontWeight.w900).copyWith(height: 1.5)),
              ),
      );
}


class _Sparkle extends StatelessWidget {
  const _Sparkle(this.size);
  final double size;
  @override
  Widget build(BuildContext context) => Icon(Icons.auto_awesome_rounded, size: size, color: K.brass);
}

/// One line on the home screen after an update.
class WhatsNewBanner extends StatelessWidget {
  const WhatsNewBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: WhatsNew.i,
        builder: (context, _) {
          final r = WhatsNew.i.latest;
          if (!WhatsNew.i.pending || r == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: K.brass, width: 1.5),
                gradient: const LinearGradient(colors: [Color(0xFF2A2418), K.night2]),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(children: [
                const _Sparkle(22),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showWhatsNewSheet(context),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text('تازه‌ها در این نسخه', style: tBody(14.5, w: FontWeight.w900).copyWith(height: 1.5)),
                      Text('${fa(r.items.length)} تغییر · ببین چی عوض شده',
                          style: tBody(12, color: K.textSoft).copyWith(height: 1.5)),
                    ]),
                  ),
                ),
                GestureDetector(
                  onTap: () => showWhatsNewSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: K.brass, borderRadius: BorderRadius.circular(10)),
                    child: Text('ببین', style: tBody(11.5, color: K.night, w: FontWeight.w900).copyWith(height: 1.5)),
                  ),
                ),
                const SizedBox(width: 6),
                InkResponse(
                  radius: 22,
                  onTap: WhatsNew.i.markSeen,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(color: K.night3, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, size: 16, color: K.textSoft),
                  ),
                ),
              ]),
            ),
          );
        },
      );
}

/// Jump to the place a change is about.
void whatsNewGo(WhatsNewTarget t) {
  switch (t) {
    case WhatsNewTarget.weekend:
      MainShell.tab.value = MainShell.weekend;
    case WhatsNewTarget.avatars:
      MainShell.tab.value = MainShell.profile;
    case WhatsNewTarget.comments:
    case WhatsNewTarget.caseToday:
    case WhatsNewTarget.missions:
      MainShell.tab.value = MainShell.home;
      WhatsNew.i.homeAction.value = t; // the home screen opens the case / missions
  }
}

/// «چی تازه شده؟». [all]: the Settings list, the last 5 releases; otherwise the newest release only.
Future<void> showWhatsNewSheet(BuildContext context, {bool all = false}) {
  final before = WhatsNew.i.latestId;
  final seenBefore = WhatsNew.i.pending;
  WhatsNew.i.markSeen(); // opening the list counts as seen
  final nav = Navigator.of(context);
  final releases = all ? WhatsNew.i.recent(5) : [if (WhatsNew.i.latest != null) WhatsNew.i.latest!];
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: K.night2,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheet).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('چی تازه شده؟', textAlign: TextAlign.center, style: tDisplay(20)),
            Text('فقط تیتر؛ روی هر مورد بزنی می‌بریمت همون‌جا',
                textAlign: TextAlign.center, style: tBody(12.5, color: K.textSoft)),
            const SizedBox(height: 14),
            for (final r in releases) ...[
              if (all)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Text('نسخه‌ی ${r.version}', style: tBody(13, color: K.brass, w: FontWeight.w900)),
                ),
              for (final it in r.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Sfx.i.play('tap', volume: 0.4);
                      Navigator.of(sheet).pop();
                      nav.popUntil((route) => route.isFirst);
                      whatsNewGo(it.target);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14), border: Border.all(color: K.night3, width: 1.5)),
                      child: Row(children: [
                        const _Sparkle(18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(it.title, style: tBody(13.5, w: FontWeight.w900).copyWith(height: 1.6))),
                        const SizedBox(width: 8),
                        Text('برو به ${it.target.label} ‹',
                            style: tBody(12, color: K.brass, w: FontWeight.w700).copyWith(height: 1.5)),
                      ]),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: K.brass, foregroundColor: K.ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: () => Navigator.of(sheet).pop(),
                child: Text('فهمیدم', style: tBody(16, color: K.ink, w: FontWeight.w900)),
              ),
            ),
            if (!all && seenBefore)
              SizedBox(
                height: 40,
                child: TextButton(
                  onPressed: () {
                    WhatsNew.i.remindLater(before - 1);
                    Navigator.of(sheet).pop();
                  },
                  child: Text('بعداً یادم بنداز', style: tBody(14, color: K.textSoft, w: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      ),
    ),
  );
}
