import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show StartScreen;

import '../services/api.dart';
import '../services/font_pref.dart';
import '../services/reminders.dart';
import '../services/sound.dart';
import '../theme.dart';
import '../widgets/character.dart';
import '../widgets/engagement.dart';
import '../widgets/offline.dart';
import '../widgets/rank.dart';
import 'achievements_screen.dart';
import 'dialogs.dart';

/// The detective's profile: portrait, name, stats, account safety, invites.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  final _invite = TextEditingController();
  final _transfer = TextEditingController();
  String? _myCode;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_email, _pass, _loginEmail, _loginPass, _invite, _transfer]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Account actions all need the server.
  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    if (!needOnline(context)) return;
    setState(() => _busy = true);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: K.night,
        prefixIcon: Icon(icon, color: K.textSoft),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Future<void> _editName() async {
    if (!needOnline(context)) return;
    final c = TextEditingController(text: Api.i.profile?.nickname ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: K.paper,
        title: Text('اسم کارآگاه', style: tDisplay(20, color: K.ink)),
        content: TextField(controller: c, maxLength: 16, autofocus: true, style: tBody(16, color: K.ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('انصراف', style: tBody(14, color: K.inkSoft))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: K.stamp), onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text('ذخیره', style: tBody(14, color: Colors.white))),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await Api.i.updateProfile(nickname: name);
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
  }

  Future<void> _setAvatar(int i) async {
    if (!needOnline(context)) return;
    try {
      await Api.i.updateProfile(avatar: i);
    } catch (e) {
      if (mounted) toast(context, Api.friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: K.night, title: Text('پرونده‌ی شخصی', style: tDisplay(20))),
      body: GrainBackground(
        child: ListenableBuilder(
          listenable: Api.i,
          builder: (context, _) {
            final p = Api.i.profile;
            if (p == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(Api.i.online ? Api.genericText : Api.needOnlineText,
                      textAlign: TextAlign.center, style: tBody(15, color: K.textSoft)),
                ),
              );
            }
            // SafeArea: the last box must not end up under the phone's navigation bar
            return SafeArea(
              top: false,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
              const OfflineBanner(margin: EdgeInsets.only(bottom: 12)),
              Row(children: [
                Container(
                  width: 92,
                  height: 100,
                  decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(16), border: Border.all(color: K.brass)),
                  child: AnimatedSuspect(avatar: kDetectives[p.avatar % kDetectives.length], size: 90),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(p.nickname, style: tDisplay(22), overflow: TextOverflow.ellipsis)),
                      IconButton(onPressed: _editName, icon: const Icon(Icons.edit_rounded, size: 18, color: K.textSoft)),
                    ]),
                    if (p.vip) Text('کارآگاه ویژه (VIP)', style: tBody(13, color: K.brass, w: FontWeight.w900)),
                    Text(p.secured ? 'حساب امن: ${p.email ?? ''}' : 'حساب مهمان (امن نشده)',
                        style: tBody(12.5, color: p.secured ? K.ok : K.stamp)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text('چهره‌ی کارآگاه', style: tBody(14, w: FontWeight.w700)),
              const SizedBox(height: 6),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: kDetectives.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _setAvatar(i),
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.avatar == i ? K.brass : Colors.transparent, width: 2)),
                      child: Padding(padding: const EdgeInsets.all(4), child: DetectiveFace(i, size: 56)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                _stat('پرونده‌ی حل‌شده', fa(p.casesSolved)),
                _stat('ستاره', fa(p.starsTotal)),
                _stat('بهترین رکورد پشت سر هم', '${fa(p.bestStreak)} روز'),
              ]),
              const SizedBox(height: 14),
              RankLadder(profile: p),
              const SizedBox(height: 10),
              StampButton(
                label: p.achievements > 0 ? 'دستاوردها · ${fa(p.achievements)} تا گرفتی' : 'دستاوردها',
                icon: Icons.military_tech_rounded,
                color: K.night3,
                height: 48,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AchievementsScreen())),
              ),
              const SizedBox(height: 14),
              Text('نشان‌ها', style: tBody(14, w: FontWeight.w700)),
              const SizedBox(height: 6),
              StreakBadges(best: p.bestStreak),
              const SizedBox(height: 14),
              ListenableBuilder(
                listenable: Reminders.i,
                builder: (_, __) => _box('یادآوری‌ها', 'هر شب ساعت ۹ که پرونده‌ی تازه باز می‌شه خبرت می‌کنیم. اگه زنجیره داری و تا ساعت ۱۰:۳۰ هنوز حلش نکردی، یه یادآوری دیگه هم می‌فرستیم.', [
                  SwitchListTile(
                    value: Reminders.i.enabled,
                    onChanged: (v) => Reminders.i.setEnabled(v),
                    contentPadding: EdgeInsets.zero,
                    title: Text('یادآوری پرونده‌ی هر شب', style: tBody(14, w: FontWeight.w700)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              _fontBox(),
              const SizedBox(height: 18),
              if (!p.secured) _secureBox() else _passwordHint(),
              const SizedBox(height: 14),
              _loginBox(),
              const SizedBox(height: 14),
              _inviteBox(p.inviteCode, p.referred),
              const SizedBox(height: 14),
              _transferBox(),
              const SizedBox(height: 14),
              _legalBox(),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(value, style: tDisplay(18, color: K.brass)),
            Text(label, textAlign: TextAlign.center, style: tBody(11, color: K.textSoft)),
          ]),
        ),
      );

  Widget _fontBox() => ListenableBuilder(
        listenable: Listenable.merge([FontPref.family, FontPref.scale]),
        builder: (_, __) => _box('فونت و اندازه‌ی متن', 'هر فونت و اندازه‌ای که چشمت باهاش راحت‌تره.', [
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

  Widget _box(String title, String sub, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: K.night2, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: tDisplay(17)),
          Text(sub, style: tBody(12.5, color: K.textSoft)),
          const SizedBox(height: 10),
          ...children,
        ]),
      );

  Widget _secureBox() => _box('امن کردن حساب', 'با ایمیل و رمز، روی هر گوشی وارد حسابت می‌شی و چیزی گم نمی‌شه. ۲۰۰ سکه هدیه!', [
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
            decoration: _field('ایمیل', Icons.email_rounded)),
        const SizedBox(height: 8),
        TextField(controller: _pass, obscureText: true, textDirection: TextDirection.ltr,
            decoration: _field('رمز (حداقل ۶ حرف)', Icons.lock_rounded)),
        const SizedBox(height: 10),
        StampButton(
          label: 'ثبت',
          color: K.ok,
          onTap: _busy
              ? null
              : () => _run(() async {
                    final (reward, err) = await Api.i.secureWithEmail(_email.text.trim(), _pass.text);
                    if (!mounted) return;
                    toast(context, err ?? (reward > 0 ? 'حسابت امن شد! ${fa(reward)} سکه گرفتی' : 'ذخیره شد'));
                  }),
        ),
      ]);

  Widget _passwordHint() => _box('عوض کردن رمز', 'ایمیلت رو کامل بنویس و رمز جدید بذار.', [
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
            decoration: _field('ایمیل', Icons.email_rounded)),
        const SizedBox(height: 8),
        TextField(controller: _pass, obscureText: true, textDirection: TextDirection.ltr,
            decoration: _field('رمز جدید', Icons.lock_rounded)),
        const SizedBox(height: 10),
        StampButton(
          label: 'عوض کردن رمز',
          color: K.night3,
          onTap: _busy
              ? null
              : () => _run(() async {
                    final (_, err) = await Api.i.secureWithEmail(_email.text.trim(), _pass.text);
                    if (mounted) toast(context, err ?? 'رمز عوض شد');
                  }),
        ),
      ]);

  Widget _loginBox() => _box('ورود به حساب قبلی', 'قبلاً روی گوشی دیگه‌ای بازی کردی؟ با ایمیل و رمزت وارد شو.', [
        TextField(controller: _loginEmail, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
            decoration: _field('ایمیل', Icons.email_rounded)),
        const SizedBox(height: 8),
        TextField(controller: _loginPass, obscureText: true, textDirection: TextDirection.ltr,
            decoration: _field('رمز', Icons.lock_rounded)),
        const SizedBox(height: 10),
        StampButton(
          label: 'ورود',
          color: K.night3,
          onTap: _busy
              ? null
              : () => _run(() async {
                    final ok = await confirm(context, 'مطمئنی؟', 'این گوشی وارد حساب قبلیت می‌شه.', 'وارد شو');
                    if (!ok || !mounted) return;
                    final err = await Api.i.loginWithEmail(_loginEmail.text.trim(), _loginPass.text);
                    if (mounted) toast(context, err ?? 'خوش برگشتی، کارآگاه!');
                  }),
        ),
      ]);

  Widget _inviteBox(String code, bool referred) => _box(
        'دعوت دوستان',
        'دوستت با کد تو بیاد: اون ${fa(150)} سکه می‌گیره، تو ${fa(300)} سکه.',
        [
          Row(children: [
            Expanded(child: Text(code, textDirection: TextDirection.ltr, style: tDisplay(24, color: K.brass))),
            SizedBox(
              width: 110,
              child: StampButton(
                label: 'بفرست',
                height: 44,
                color: K.ok,
                onTap: () => SharePlus.instance.share(ShareParams(
                    text: 'بیا «پرونده» بازی کنیم! هر شب یه جنایت تازه 🕵️ موقع شروع کد دعوت من رو بزن: $code')),
              ),
            ),
          ]),
          if (!referred) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(controller: _invite, textDirection: TextDirection.ltr, textCapitalization: TextCapitalization.characters,
                    decoration: _field('کد دعوت دوستت', Icons.redeem_rounded)),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: StampButton(
                  label: 'ثبت',
                  height: 48,
                  color: K.night3,
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                            final (coins, err) = await Api.i.redeemInvite(_invite.text);
                            if (mounted) toast(context, err ?? '${fa(coins)} سکه هدیه گرفتی!');
                          }),
                ),
              ),
            ]),
          ],
        ],
      );

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) toast(context, 'صفحه باز نشد');
    }
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

  Widget _legalBox() => _box('قوانین و حریم خصوصی', 'اطلاعاتت فقط برای اجرای بازی نگه داشته می‌شه.', [
        Row(children: [
          Expanded(child: GhostButton(label: 'حریم خصوصی', icon: Icons.privacy_tip_rounded, onTap: () => _open(Api.i.privacyUrl))),
          const SizedBox(width: 10),
          Expanded(child: GhostButton(label: 'قوانین', icon: Icons.gavel_rounded, onTap: () => _open(Api.i.termsUrl))),
        ]),
        const SizedBox(height: 10),
        GhostButton(label: 'حذف حساب', icon: Icons.delete_forever_rounded, color: K.stamp, onTap: _deleteAccount),
      ]);

  Widget _transferBox() => _box('انتقال با کد', 'بدون ایمیل: روی گوشی قدیمی کد بگیر، روی گوشی جدید واردش کن.', [
        if (_myCode != null)
          Center(child: SelectableText(_myCode!, style: tDisplay(28, color: K.brass)))
        else
          StampButton(
            label: 'گرفتن کد (گوشی قدیمی)',
            color: K.night3,
            onTap: _busy
                ? null
                : () => _run(() async {
                      final (c, err) = await Api.i.makeTransferCode();
                      if (!mounted) return;
                      if (c == null) {
                        toast(context, err ?? Api.genericText);
                      } else {
                        setState(() => _myCode = c);
                      }
                    }),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(controller: _transfer, textDirection: TextDirection.ltr, textCapitalization: TextCapitalization.characters,
                decoration: _field('کد انتقال', Icons.swap_horiz_rounded)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: StampButton(
              label: 'انتقال',
              height: 48,
              onTap: _busy
                  ? null
                  : () => _run(() async {
                        final ok = await confirm(context, 'مطمئنی؟', 'این گوشی وارد حساب گوشی قدیمی می‌شه.', 'انتقال');
                        if (!ok || !mounted) return;
                        final err = await Api.i.useTransferCode(_transfer.text);
                        if (mounted) toast(context, err ?? 'حساب منتقل شد!');
                      }),
            ),
          ),
        ]),
      ]);
}
