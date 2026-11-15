import 'package:flutter/material.dart';

import '../screens/account_sheets.dart' show showNoirSheet;
import '../services/reminders.dart';
import '../theme.dart';

/// Shown on the home screen only while reminders are ON in the app but the phone blocks notifications.
/// One tap opens the fix, one tap on ✕ closes it for 7 days. Never blocks anything.
class NotificationsOffCard extends StatelessWidget {
  const NotificationsOffCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Reminders.i,
      builder: (context, _) {
        if (!Reminders.i.bannerVisible) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: K.night3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: K.brass.withValues(alpha: 0.35)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final ok = await Reminders.i.fix();
                if (!context.mounted) return;
                if (ok) toast(context, 'اعلان‌ها روشن شد ✅');
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
                child: Row(children: [
                  const Icon(Icons.notifications_off_rounded, size: 20, color: K.brass),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('اعلان‌ها روی گوشی خاموشه؛ بزن تا روشنش کنی تا پرونده‌ی هر شب رو از دست ندی',
                          style: tBody(12.5, color: K.text)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'بستن',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18, color: K.textSoft),
                    onPressed: Reminders.i.closeBanner,
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// «اگه اعلان‌ها دیر میاد»: the Samsung battery steps in plain Persian, with a button to the phone's own screen.
Future<void> showBatteryHelpSheet(BuildContext context) {
  Widget step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: K.night3, shape: BoxShape.circle),
            child: Text(n, style: tBody(12, color: K.brass, w: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: tBody(13.5, color: K.text))),
        ]),
      );
  return showNoirSheet<void>(
    context,
    title: 'اگه اعلان‌ها دیر میاد',
    sub: 'بعضی گوشی‌ها (مثل سامسونگ) برنامه‌های بسته رو برای صرفه‌جویی باتری می‌خوابونن',
    child: Directionality(
      textDirection: TextDirection.rtl,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        step('۱', 'تنظیمات گوشی ← برنامه‌ها ← «پرونده» ← باتری ← گزینه‌ی «بدون محدودیت» (Unrestricted) رو بزن.'),
        step('۲', 'تنظیمات گوشی ← باتری ← محدودیت‌های پس‌زمینه ← «خوابوندن برنامه‌های استفاده‌نشده» '
            '(Put unused apps to sleep) رو خاموش کن، یا «پرونده» رو از لیست خوابیده‌ها دربیار.'),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () async {
            final ok = await Reminders.i.openSystem('battery');
            if (!context.mounted) return;
            if (!ok) toast(context, 'صفحه باز نشد؛ مراحل بالا رو دستی برو');
          },
          icon: const Icon(Icons.battery_charging_full_rounded, size: 18),
          label: const Text('باز کردن تنظیمات باتری'),
        ),
      ]),
    ),
  );
}
