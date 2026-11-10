import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/app_update.dart';
import '../theme.dart';

/// Opens the update modal (centered, dimmed backdrop). Any way out (✕, «بعداً یادآوری کن», the system back button,
/// or the store button) hides it for 3 days for this `latest_version`; the home chip can open it again.
Future<void> showUpdateModal(BuildContext context) {
  AppUpdate.i.markModalShown();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xB8080705),
    builder: (_) => const UpdateModal(),
  ).whenComplete(AppUpdate.i.closeBanner);
}

class UpdateModal extends StatelessWidget {
  const UpdateModal({super.key});

  static const _gold1 = Color(0xFFF2C14E);
  static const _gold2 = Color(0xFFD9962A);

  @override
  Widget build(BuildContext context) {
    final bonus = AppUpdate.i.bonusCoins;
    return Dialog(
      key: const ValueKey('update_modal'),
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: K.paper,
            child: Stack(children: [
              SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 22),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [_gold1, _gold2]),
                    ),
                    child: Column(children: [
                      Transform.rotate(
                        angle: -0.1,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(color: K.night, borderRadius: BorderRadius.circular(20)),
                          child: const Icon(Icons.system_update_rounded, size: 42, color: _gold1),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text('نسخه‌ی تازه آماده‌ست',
                          textAlign: TextAlign.center, style: tBody(20, w: FontWeight.w900, color: K.ink)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('پرونده‌ها و امکانات تازه فقط توی نسخه‌ی جدید باز می‌شن؛ پیشرفتت سر جاشه.',
                          textAlign: TextAlign.center, style: tBody(13.5, w: FontWeight.w700, color: K.inkSoft)),
                      if (bonus > 0) ...[
                        const SizedBox(height: 14),
                        Container(
                          key: const ValueKey('update_reward'),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(color: K.night, borderRadius: BorderRadius.circular(14)),
                          child: Text('${fa(bonus)} سکه هدیه‌ی آپدیت',
                              textAlign: TextAlign.center, style: tBody(14, w: FontWeight.w900, color: _gold1)),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: FilledButton(
                          key: const ValueKey('update_open'),
                          style: FilledButton.styleFrom(
                              backgroundColor: K.stamp, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                          onPressed: () async {
                            final nav = Navigator.of(context);
                            final ok = await AppUpdate.i.open();
                            if (!context.mounted) return;
                            if (ok) {
                              nav.pop();
                            } else {
                              toast(context, 'صفحه باز نشد');
                            }
                          },
                          child: Text('آپدیت در کافه بازار', style: tBody(16, w: FontWeight.w900, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 48,
                        child: TextButton(
                          key: const ValueKey('update_later'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text('بعداً یادآوری کن', style: tBody(13, w: FontWeight.w800, color: K.inkSoft)),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
              PositionedDirectional(
                top: 8,
                end: 8,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    key: const ValueKey('update_close'),
                    tooltip: 'بستن',
                    style: IconButton.styleFrom(backgroundColor: const Color(0x14000000)),
                    icon: const Icon(Icons.close_rounded, size: 20, color: K.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Slim chip on the home page after the modal was closed: «نسخه‌ی تازه هست · N سکه هدیه» (no coins part when there is none).
class UpdateChip extends StatefulWidget {
  const UpdateChip({super.key});

  @override
  State<UpdateChip> createState() => _UpdateChipState();
}

class _UpdateChipState extends State<UpdateChip> {
  @override
  void initState() {
    super.initState();
    AppUpdate.i.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppUpdate.i, Api.i]),
      builder: (context, _) {
        if (!AppUpdate.i.chipVisible) return const SizedBox.shrink();
        final bonus = AppUpdate.i.bonusCoins;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            height: 44,
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const ValueKey('update_chip'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: K.brass,
                  side: BorderSide(color: K.brass.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => showUpdateModal(context),
              icon: const Icon(Icons.system_update_rounded, size: 18),
              label: Text(bonus > 0 ? 'نسخه‌ی تازه هست · ${fa(bonus)} سکه هدیه' : 'نسخه‌ی تازه هست',
                  style: tBody(12.5, w: FontWeight.w900, color: K.brass)),
            ),
          ),
        );
      },
    );
  }
}

/// Full page (not a dialog) for builds older than `min_version`: the only action is the store button.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const ValueKey('update_required'),
        body: GrainBackground(
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.system_update_rounded, size: 56, color: K.brass),
                  const SizedBox(height: 18),
                  Text('برای ادامه باید برنامه رو از کافه بازار آپدیت کنی',
                      textAlign: TextAlign.center, style: tBody(17, w: FontWeight.w800)),
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const ValueKey('update_open'),
                    style: FilledButton.styleFrom(backgroundColor: K.stamp, minimumSize: const Size(220, 48)),
                    onPressed: () async {
                      final ok = await AppUpdate.i.open();
                      if (!ok && context.mounted) toast(context, 'صفحه باز نشد');
                    },
                    child: Text('باز کردن کافه بازار', style: tBody(15, w: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
