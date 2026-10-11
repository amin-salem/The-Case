import 'package:flutter/foundation.dart';

/// What «درباره‌ی برنامه» in Settings shows, and the plain-text block the player can copy for support.
/// Holds no secret: no token, no password, no login secret, no e-mail.
@immutable
class AboutInfo {
  const AboutInfo({
    required this.appName,
    required this.version,
    required this.build,
    required this.store,
    required this.packageName,
    required this.serverVersion,
    required this.serverOk,
    required this.playerShortId,
    required this.inviteCode,
    required this.language,
  });

  final String appName, version, build, store, packageName, serverVersion, playerShortId, inviteCode, language;

  /// Whether the server answered /health just now.
  final bool serverOk;

  /// First characters of the player id: enough for support to find the account, not a login.
  static String shortId(String? playerId) {
    final id = (playerId ?? '').trim();
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  /// The block copied to the clipboard (Persian labels, plain digits so it pastes cleanly anywhere).
  String supportText() {
    String v(String s) => s.isEmpty ? '—' : s;
    return [
      'اطلاعات برای پشتیبانی',
      'برنامه: $appName',
      'نسخه: ${v(version)} (بیلد ${v(build)})',
      'فروشگاه: ${v(store)}',
      'بسته: ${v(packageName)}',
      'نسخه‌ی سرور: ${v(serverVersion)}',
      'اتصال به سرور: ${serverOk ? 'برقرار' : 'قطع'}',
      'شناسه‌ی بازیکن: ${v(playerShortId)}',
      'کد دعوت: ${v(inviteCode)}',
      'زبان دستگاه: ${v(language)}',
    ].join('\n');
  }
}
