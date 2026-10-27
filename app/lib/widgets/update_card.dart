import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/app_update.dart';
import '../theme.dart';

/// Home screen card for players on an older build: one tap opens Cafe Bazaar, ✕ hides it for 3 days.
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key});

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
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
        if (!AppUpdate.i.bannerVisible) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey('update_card'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: K.night3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: K.brass.withValues(alpha: 0.5)),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.system_update_rounded, size: 22, color: K.brass)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'نسخه‌ی تازه‌ی پرونده توی کافه بازار منتشر شده؛ آپدیت کن تا از تازه‌ترین پرونده‌ها و امکانات استفاده کنی.',
                        style: tBody(12.5, color: K.text)),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey('update_open'),
                    style: FilledButton.styleFrom(backgroundColor: K.stamp, visualDensity: VisualDensity.compact),
                    onPressed: () async {
                      final ok = await AppUpdate.i.open();
                      if (!ok && context.mounted) toast(context, 'صفحه باز نشد');
                    },
                    child: Text('باز کردن کافه بازار', style: tBody(13, w: FontWeight.w700)),
                  ),
                ]),
              ),
              IconButton(
                key: const ValueKey('update_close'),
                tooltip: 'بستن',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: K.textSoft),
                onPressed: AppUpdate.i.closeBanner,
              ),
            ]),
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
