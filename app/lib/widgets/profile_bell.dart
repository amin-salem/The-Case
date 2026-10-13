import 'package:flutter/material.dart';

import '../screens/messages_hub_screen.dart';
import '../services/api.dart';
import '../theme.dart';
import 'character.dart';

/// "99+" for big numbers, Persian digits.
String unreadLabel(int n) => n > 99 ? '99+' : fa(n);

/// The player's avatar with a small bell and a red unread pill. Tapping it opens the messages hub.
/// The number comes from one place (`Api.i.unread`), so every bell on every screen changes together.
class ProfileBell extends StatelessWidget {
  const ProfileBell({super.key, this.size = 46, this.onTap});
  final double size;

  /// Replaces the default action (open the messages hub).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = size >= 40 ? 26.0 : 20.0;
    return Semantics(
      button: true,
      label: 'پیام‌ها و نشان‌ها',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () => openMessagesHub(context),
        child: SizedBox(
          width: size + 8,
          height: size + 8,
          child: ListenableBuilder(
            listenable: Listenable.merge([Api.i, Api.i.unread]),
            builder: (context, _) {
              final n = Api.i.unread.value;
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  right: 0,
                  top: 4,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(color: K.night3, shape: BoxShape.circle, border: Border.all(color: K.brass, width: 2)),
                    child: DetectiveFace(Api.i.profile?.avatar ?? 0, size: size - 4),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: Container(
                    key: const ValueKey('bell-chip'),
                    width: chip,
                    height: chip,
                    decoration: BoxDecoration(color: K.night3, shape: BoxShape.circle, border: Border.all(color: K.night, width: 2)),
                    child: Icon(Icons.notifications_rounded, size: chip * 0.58, color: K.text),
                  ),
                ),
                if (n > 0)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      key: const ValueKey('bell-pill'),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: K.stamp, borderRadius: BorderRadius.circular(99), border: Border.all(color: K.night, width: 1.5)),
                      child: Text(unreadLabel(n),
                          style: tBody(10, w: FontWeight.w900, color: K.text).copyWith(height: 1.25)),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
