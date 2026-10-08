import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import 'dialogs.dart';

/// The account forms (secure the account, change the password, sign in on a new phone,
/// a friend's invite code) as bottom sheets. Each sheet returns the success message,
/// which the opener shows; errors stay inside the sheet.

/// A night-blue sheet with a handle, a title and room for the keyboard.
Future<T?> showNoirSheet<T>(BuildContext context, {String? title, String? sub, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: K.night2,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          if (title != null) Text(title, style: tDisplay(19)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub, style: tBody(12.5, color: K.textSoft)),
          ],
          if (title != null || sub != null) const SizedBox(height: 14),
          child,
        ]),
      ),
    ),
  );
}

/// Opens a sheet and shows what it returned as a toast.
Future<void> openAccountSheet(BuildContext context, Future<String?> Function(BuildContext) sheet) async {
  final msg = await sheet(context);
  if (msg != null && context.mounted) toast(context, msg);
}

InputDecoration noirField(String hint, IconData icon) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: K.night,
      prefixIcon: Icon(icon, color: K.textSoft),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

/// Busy flag and an inline error line for a sheet.
mixin _SheetJob<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Future<void> run(Future<void> Function() job) async {
    if (busy) return;
    if (!Api.i.online) {
      setState(() => error = Api.needOnlineText);
      unawaited(Api.i.reconnect());
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => error = Api.friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void fail(String msg) {
    if (mounted) setState(() => error = msg);
  }

  void done(String msg) {
    if (mounted) Navigator.of(context).pop(msg);
  }

  Widget errorLine() => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!, style: tBody(13, color: K.stamp, w: FontWeight.w700)),
        );
}

// ------------------------------------------------------------------ secure / change password

Future<String?> showSecureSheet(BuildContext context) {
  final secured = Api.i.profile?.secured ?? false;
  return showNoirSheet<String>(
    context,
    title: secured ? 'عوض کردن رمز' : 'امن کردن حساب',
    sub: secured
        ? 'ایمیلت رو کامل بنویس و رمز جدید بذار.'
        : 'با ایمیل و رمز، روی هر گوشی وارد حسابت می‌شی و چیزی گم نمی‌شه. ${fa(Api.i.secureReward)} سکه هدیه!',
    child: _SecureForm(secured: secured),
  );
}

class _SecureForm extends StatefulWidget {
  const _SecureForm({required this.secured});
  final bool secured;

  @override
  State<_SecureForm> createState() => _SecureFormState();
}

class _SecureFormState extends State<_SecureForm> with _SheetJob {
  final _email = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
            decoration: noirField('ایمیل', Icons.email_rounded)),
        const SizedBox(height: 8),
        TextField(controller: _pass, obscureText: true, textDirection: TextDirection.ltr,
            decoration: noirField(widget.secured ? 'رمز جدید' : 'رمز (حداقل ۶ حرف)', Icons.lock_rounded)),
        errorLine(),
        const SizedBox(height: 12),
        StampButton(
          label: widget.secured ? 'عوض کردن رمز' : 'ثبت',
          color: widget.secured ? K.night3 : K.ok,
          onTap: busy
              ? null
              : () => run(() async {
                    final (reward, err) = await Api.i.secureWithEmail(_email.text.trim(), _pass.text);
                    if (err != null) {
                      fail(err);
                      return;
                    }
                    if (widget.secured) {
                      done('رمز عوض شد');
                      return;
                    }
                    done(reward > 0 ? 'حسابت امن شد! ${fa(reward)} سکه گرفتی' : 'ذخیره شد');
                  }),
        ),
      ]);
}

// ------------------------------------------------------------------ sign in / move from another phone

Future<String?> showLoginSheet(BuildContext context, {int tab = 0}) => showNoirSheet<String>(
      context,
      title: 'ورود یا انتقال از گوشی دیگر',
      child: LoginTransferForm(initialTab: tab),
    );

class LoginTransferForm extends StatefulWidget {
  const LoginTransferForm({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<LoginTransferForm> createState() => _LoginTransferFormState();
}

class _LoginTransferFormState extends State<LoginTransferForm> with SingleTickerProviderStateMixin, _SheetJob {
  late final TabController _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab)
    ..addListener(() {
      if (mounted) setState(() => error = null);
    });
  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();
  final _transfer = TextEditingController();
  String? _myCode;

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [_loginEmail, _loginPass, _transfer]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: K.brass.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: K.brass.withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: K.brass, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('پیشرفت این گوشی جاش با حساب قبلیت عوض می‌شه.', style: tBody(13, color: K.text))),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(color: K.night, borderRadius: BorderRadius.circular(12)),
          child: TabBar(
            controller: _tabs,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(10), border: Border.all(color: K.brass)),
            labelStyle: tBody(14, w: FontWeight.w900),
            unselectedLabelStyle: tBody(14, w: FontWeight.w700),
            labelColor: K.text,
            unselectedLabelColor: K.textSoft,
            tabs: const [Tab(text: 'با ایمیل', height: 42), Tab(text: 'با کد انتقال', height: 42)],
          ),
        ),
        const SizedBox(height: 14),
        if (_tabs.index == 0) _emailTab() else _codeTab(),
        errorLine(),
      ]);

  Widget _emailTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('قبلاً روی گوشی دیگه‌ای بازی کردی؟ با ایمیل و رمزت وارد شو.', style: tBody(12.5, color: K.textSoft)),
        const SizedBox(height: 8),
        TextField(controller: _loginEmail, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
            decoration: noirField('ایمیل', Icons.email_rounded)),
        const SizedBox(height: 8),
        TextField(controller: _loginPass, obscureText: true, textDirection: TextDirection.ltr,
            decoration: noirField('رمز', Icons.lock_rounded)),
        const SizedBox(height: 12),
        StampButton(
          label: 'ورود',
          color: K.night3,
          onTap: busy
              ? null
              : () => run(() async {
                    final ok = await confirm(context, 'مطمئنی؟', 'این گوشی وارد حساب قبلیت می‌شه.', 'وارد شو');
                    if (!ok || !mounted) return;
                    final err = await Api.i.loginWithEmail(_loginEmail.text.trim(), _loginPass.text);
                    if (err != null) {
                      fail(err);
                      return;
                    }
                    done('خوش برگشتی، کارآگاه!');
                  }),
        ),
      ]);

  Widget _codeTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('بدون ایمیل: روی گوشی قدیمی کد بگیر، روی گوشی جدید واردش کن.', style: tBody(12.5, color: K.textSoft)),
        const SizedBox(height: 10),
        Text('گوشی قدیمی', style: tBody(13, w: FontWeight.w900, color: K.brass)),
        const SizedBox(height: 4),
        if (_myCode != null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: K.night, borderRadius: BorderRadius.circular(12)),
            child: Center(child: SelectableText(_myCode!, style: tDisplay(28, color: K.brass))),
          )
        else
          StampButton(
            label: 'گرفتن کد (گوشی قدیمی)',
            color: K.night3,
            height: 48,
            onTap: busy
                ? null
                : () => run(() async {
                      final (c, err) = await Api.i.makeTransferCode();
                      if (c == null) {
                      fail(err ?? Api.genericText);
                      return;
                    }
                      if (mounted) setState(() => _myCode = c);
                    }),
          ),
        const SizedBox(height: 14),
        Text('گوشی جدید', style: tBody(13, w: FontWeight.w900, color: K.brass)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(controller: _transfer, textDirection: TextDirection.ltr, textCapitalization: TextCapitalization.characters,
                decoration: noirField('کد انتقال', Icons.swap_horiz_rounded)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: StampButton(
              label: 'انتقال',
              height: 48,
              onTap: busy
                  ? null
                  : () => run(() async {
                        final ok = await confirm(context, 'مطمئنی؟', 'این گوشی وارد حساب گوشی قدیمی می‌شه.', 'انتقال');
                        if (!ok || !mounted) return;
                        final err = await Api.i.useTransferCode(_transfer.text);
                        if (err != null) {
                      fail(err);
                      return;
                    }
                        done('حساب منتقل شد!');
                      }),
            ),
          ),
        ]),
      ]);
}

// ------------------------------------------------------------------ a friend's invite code

Future<String?> showInviteCodeSheet(BuildContext context) => showNoirSheet<String>(
      context,
      title: 'کد دوستت رو داری؟',
      sub: 'کد دعوتش رو بزن و ${fa(Api.i.inviteNewPlayer)} سکه هدیه بگیر.',
      child: const _InviteCodeForm(),
    );

class _InviteCodeForm extends StatefulWidget {
  const _InviteCodeForm();

  @override
  State<_InviteCodeForm> createState() => _InviteCodeFormState();
}

class _InviteCodeFormState extends State<_InviteCodeForm> with _SheetJob {
  final _invite = TextEditingController();

  @override
  void dispose() {
    _invite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(controller: _invite, textDirection: TextDirection.ltr, textCapitalization: TextCapitalization.characters,
                decoration: noirField('کد دعوت دوستت', Icons.redeem_rounded)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: StampButton(
              label: 'ثبت',
              height: 48,
              color: K.night3,
              onTap: busy
                  ? null
                  : () => run(() async {
                        final (coins, err) = await Api.i.redeemInvite(_invite.text);
                        if (err != null) {
                      fail(err);
                      return;
                    }
                        done('${fa(coins)} سکه هدیه گرفتی!');
                      }),
            ),
          ),
        ]),
        errorLine(),
      ]);
}
