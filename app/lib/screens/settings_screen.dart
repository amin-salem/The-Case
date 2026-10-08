import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show StartScreen;
import '../services/api.dart';
import '../services/font_pref.dart';
import '../services/reminders.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/offline.dart';
import 'account_sheets.dart';
import 'dialogs.dart';

/// Settings: account, looks, sound and reminders, support. Every row is one tap; forms open in sheets.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final build = info.buildNumber.isEmpty ? '' : ' (${_faDigits(info.buildNumber)})';
      setState(() => _version = '${_faDigits(info.version)}$build');
    } catch (_) {
      // no platform (tests): the line is simply left out
    }
  }

  static String _faDigits(String s) =>
      s.replaceAllMapped(RegExp(r'[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[m[0]!.codeUnitAt(0) - 48]);

  Future<void> _open(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) toast(context, 'صفحه باز نشد');
    } catch (_) {
      if (mounted) toast(context, 'صفحه باز نشد');
    }
  }

  void _contact() {
    final url = Api.i.supportUrl;
    if (url != null) {
      _open(Uri.parse(url));
      return;
    }
    final mail = Api.i.supportEmail;
    if (mail != null) _open(Uri(scheme: 'mailto', path: mail, query: 'subject=${Uri.encodeComponent('پرونده')}'));
  }

  Future<void> _deleteAccount() async {
    if (!needOnline(context)) return;
    final ok = await confirm(context, 'حذف حساب',
        'حساب، پیشرفت، سکه‌ها و ایمیلت برای همیشه پاک می‌شه و برگشت‌پذیر نیست. مطمئنی؟', 'حذف برای همیشه');
    if (!ok || !mounted) return;
    final err = await Api.i.deleteAccount();
    if (!mounted) return;
    if (err != null) {
      toast(context, err);
      return;
    }
    toast(context, 'حسابت پاک شد');
    await Navigator.of(context)
        .pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const StartScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: K.night, title: Text('تنظیمات', style: tDisplay(20))),
      body: GrainBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([Api.i, Sfx.i, Reminders.i, FontPref.family, FontPref.scale]),
          builder: (context, _) {
            final p = Api.i.profile;
            final secured = p?.secured ?? false;
            final hasSupport = Api.i.supportUrl != null || Api.i.supportEmail != null;
            return SafeArea(
              top: false,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
                _group('حساب', [
                  if (!secured)
                    SettingsRow(
                      icon: Icons.shield_outlined,
                      iconColor: K.brass,
                      title: 'امن کردن حساب',
                      sub: 'با ایمیل و رمز · ${fa(Api.i.secureReward)} سکه هدیه',
                      end: const _Tag('مهمان', color: K.brass),
                      onTap: () => openAccountSheet(context, showSecureSheet),
                    )
                  else ...[
                    SettingsRow(
                      icon: Icons.verified_user_rounded,
                      iconColor: K.ok,
                      title: p?.email ?? '',
                      ltrTitle: true,
                      end: const _Tag('امن', color: K.ok),
                    ),
                    SettingsRow(
                      icon: Icons.password_rounded,
                      title: 'عوض کردن رمز',
                      onTap: () => openAccountSheet(context, showSecureSheet),
                    ),
                  ],
                  SettingsRow(
                    icon: Icons.phonelink_setup_rounded,
                    title: 'ورود یا انتقال از گوشی دیگر',
                    onTap: () => openAccountSheet(context, showLoginSheet),
                  ),
                ]),
                _group('ظاهر', [
                  SettingsRow(
                    icon: Icons.text_fields_rounded,
                    title: 'فونت و اندازه‌ی متن',
                    endText: '${FontPref.fonts[FontPref.family.value] ?? ''} · '
                        '${FontPref.sizeNames[FontPref.sizes.indexOf(FontPref.scale.value).clamp(0, FontPref.sizeNames.length - 1)]}',
                    onTap: () => showFontSheet(context),
                  ),
                ]),
                _group('صدا و اعلان', [
                  SettingsRow(
                    icon: Sfx.i.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    title: 'صدا و موسیقی',
                    end: _switch(!Sfx.i.muted, (v) => Sfx.i.setMuted(!v)),
                    onTap: () => Sfx.i.setMuted(!Sfx.i.muted),
                  ),
                  SettingsRow(
                    icon: Icons.notifications_active_rounded,
                    title: 'یادآوری پرونده‌ی هر شب',
                    sub: 'ساعت ۹ شب، و ۱۰:۳۰ اگه زنجیره در خطره',
                    end: _switch(Reminders.i.enabled, (v) => Reminders.i.setEnabled(v)),
                    onTap: () => Reminders.i.setEnabled(!Reminders.i.enabled),
                  ),
                ]),
                _group('پشتیبانی و قوانین', [
                  if (hasSupport) SettingsRow(icon: Icons.support_agent_rounded, title: 'تماس با ما', onTap: _contact),
                  SettingsRow(
                      icon: Icons.privacy_tip_rounded, title: 'حریم خصوصی', onTap: () => _open(Uri.parse(Api.i.privacyUrl))),
                  SettingsRow(icon: Icons.gavel_rounded, title: 'قوانین', onTap: () => _open(Uri.parse(Api.i.termsUrl))),
                ]),
                const SizedBox(height: 22),
                Center(
                  child: TextButton.icon(
                    onPressed: _deleteAccount,
                    icon: const Icon(Icons.delete_forever_rounded, color: K.stamp, size: 20),
                    label: Text('حذف حساب', style: tBody(14, color: K.stamp, w: FontWeight.w700)),
                  ),
                ),
                if (_version != null)
                  Center(child: Text('نسخه‌ی $_version', style: tBody(12, color: K.textSoft))),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _switch(bool v, ValueChanged<bool> on) => Switch(
        value: v,
        onChanged: on,
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : K.textSoft),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? K.stamp : K.night3),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _group(String title, List<Widget> rows) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, bottom: 6),
            child: Text(title, style: tBody(13, color: K.brass, w: FontWeight.w900)),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              for (int i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, indent: 52, color: K.night3),
                rows[i],
              ],
            ]),
          ),
        ]),
      );
}

/// One settings line: icon, title (and an optional small line under it), and what is at the end.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.sub,
    this.end,
    this.endText,
    this.onTap,
    this.iconColor = K.textSoft,
    this.ltrTitle = false,
  });
  final IconData icon;
  final String title;
  final String? sub;
  final Widget? end;
  final String? endText;
  final VoidCallback? onTap;
  final Color iconColor;
  final bool ltrTitle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              Sfx.i.play('tap', volume: 0.4);
              onTap!();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: ltrTitle ? TextDirection.ltr : null,
                    style: tBody(14.5, w: FontWeight.w700).copyWith(height: 1.4)),
                if (sub != null)
                  Text(sub!,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(12, color: K.textSoft).copyWith(height: 1.4)),
              ]),
            ),
            if (endText != null) ...[
              const SizedBox(width: 8),
              Text(endText!, style: tBody(12.5, color: K.textSoft)),
            ],
            if (end != null) ...[const SizedBox(width: 8), end!],
            if (onTap != null && end == null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_left_rounded, color: K.textSoft, size: 22),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(text, style: tBody(12, color: color, w: FontWeight.w900).copyWith(height: 1.5)),
      );
}

// ------------------------------------------------------------------ font and text size

Future<void> showFontSheet(BuildContext context) => showNoirSheet<void>(
      context,
      title: 'فونت و اندازه‌ی متن',
      sub: 'هر فونت و اندازه‌ای که چشمت باهاش راحت‌تره.',
      child: const FontSettings(),
    );

/// The font and text-size choices with a live sample.
class FontSettings extends StatelessWidget {
  const FontSettings({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([FontPref.family, FontPref.scale]),
        builder: (_, __) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('فونت', style: tBody(13, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in FontPref.fonts.entries)
              _choice(f.value, FontPref.family.value == f.key, () => FontPref.setFamily(f.key), font: f.key),
          ]),
          const SizedBox(height: 12),
          Text('اندازه‌ی متن', style: tBody(13, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (int i = 0; i < FontPref.sizes.length; i++)
              _choice(FontPref.sizeNames[i], FontPref.scale.value == FontPref.sizes[i],
                  () => FontPref.setScale(FontPref.sizes[i])),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: K.paper, borderRadius: BorderRadius.circular(10)),
            child: Text('نمونه: «در اتاق کار از داخل قفل بود. ساعت ۲۳:۴۰ چراغ‌ها خاموش شد و فقط یک نفر کلید داشت.»',
                style: tBody(14.5, color: K.ink)),
          ),
        ]),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap, {String? font}) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Sfx.i.play('tap', volume: 0.4);
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? K.brass.withValues(alpha: 0.18) : K.night3,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? K.brass : Colors.transparent, width: 1.5),
          ),
          child: Text(label,
              style: tBody(14, color: selected ? K.text : K.textSoft, w: FontWeight.w700)
                  .copyWith(fontFamily: font ?? kFont)),
        ),
      );
}
