import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/character.dart';
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

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
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
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await Api.i.updateProfile(nickname: name);
    } on ApiException catch (e) {
      if (mounted) toast(context, Api.errorText(e.code));
    } catch (_) {
      if (mounted) toast(context, 'اتصال به سرور برقرار نیست');
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
            if (p == null) return const SizedBox.shrink();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
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
                    onTap: () => Api.i.updateProfile(avatar: i).catchError((_) {}),
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.avatar == i ? K.brass : Colors.transparent, width: 2)),
                      child: CustomPaint(painter: CharacterPainter(kDetectives[i])),
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
              const SizedBox(height: 18),
              if (!p.secured) _secureBox() else _passwordHint(),
              const SizedBox(height: 14),
              _loginBox(),
              const SizedBox(height: 14),
              _inviteBox(p.inviteCode, p.referred),
              const SizedBox(height: 14),
              _transferBox(),
            ]);
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
                    if (!ok) return;
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
                      final c = await Api.i.makeTransferCode();
                      if (!mounted) return;
                      if (c == null) {
                        toast(context, 'اتصال به سرور برقرار نیست');
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
                        if (!ok) return;
                        final err = await Api.i.useTransferCode(_transfer.text);
                        if (mounted) toast(context, err ?? 'حساب منتقل شد!');
                      }),
            ),
          ),
        ]),
      ]);
}
