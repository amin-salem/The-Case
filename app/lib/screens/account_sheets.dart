import 'dart:async';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

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

// ------------------------------------------------------------------ secure with a phone number

/// Not secured yet: the phone-number sheet. (Email + password is gone: it was never verified.)
Future<String?> showSecureSheet(BuildContext context) async {
  if (Api.i.profile?.secured ?? false) return null;
  return showNoirSheet<String>(
    context,
    title: 'امن کردن حساب با شماره',
    sub: 'با شماره‌ی موبایلت روی هر گوشی وارد می‌شی و چیزی گم نمی‌شه. ${fa(Api.i.secureReward)} سکه هدیه!',
    child: const _PhoneForm(login: false),
  );
}

Future<String?> showPhoneLoginSheet(BuildContext context) => showNoirSheet<String>(
      context,
      title: 'ورود با شماره‌ی موبایل',
      sub: 'گوشی جدید داری یا برنامه رو دوباره نصب کردی؟ با شماره‌ای که حساب رو امن کردی وارد شو. گوشی قبلی از حساب خارج می‌شه.',
      child: const _PhoneForm(login: true),
    );

/// The two-step phone form: number, then the 5-digit SMS code.
class _PhoneForm extends StatefulWidget {
  const _PhoneForm({required this.login, this.gate = false});
  final bool login;
  final bool gate; // email account asked to link a phone: no email link, no way out

  @override
  State<_PhoneForm> createState() => _PhoneFormState();
}

class _PhoneFormState extends State<_PhoneForm> with _SheetJob {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  int _wait = 0;
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _countdown() {
    _tick?.cancel();
    setState(() => _wait = 60);
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait = _wait > 0 ? _wait - 1 : 0);
      if (_wait == 0) t.cancel();
    });
  }

  Future<void> _send() => run(() async {
        final phone = _phone.text.trim();
        final err = widget.login ? await Api.i.phoneLoginSend(phone) : await Api.i.phoneSend(phone);
        if (err != null) {
          fail(err);
          return;
        }
        if (mounted) setState(() => _sent = true);
        _countdown();
      });

  Future<void> _verify() => run(() async {
        final phone = _phone.text.trim();
        final code = _code.text.trim();
        if (widget.login) {
          final err = await Api.i.phoneLogin(phone, code);
          if (err != null) {
            fail(err);
            return;
          }
          done('خوش برگشتی، کارآگاه!');
          return;
        }
        final (reward, err) = await Api.i.phoneVerify(phone, code);
        if (err != null) {
          fail(err);
          return;
        }
        done(widget.gate ? 'شماره به حسابت وصل شد' : reward > 0 ? 'حسابت امن شد! ${fa(reward)} سکه گرفتی' : 'حسابت امن شد');
      });

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _phone,
          enabled: !_sent,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          style: tBody(20, w: FontWeight.w700),
          decoration: noirField('شماره‌ی موبایل (۰۹۱۲…)', Icons.phone_android_rounded),
        ),
        if (_sent) ...[
          const SizedBox(height: 10),
          Text('کد ۵ رقمی پیامک شد.', style: tBody(12.5, color: K.textSoft)),
          const SizedBox(height: 6),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 5,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: tDisplay(26),
            decoration: noirField('کد پیامکی', Icons.sms_rounded).copyWith(counterText: ''),
          ),
        ],
        errorLine(),
        const SizedBox(height: 12),
        StampButton(
          label: _sent ? 'تأیید' : 'ارسال کد',
          color: K.brass,
          onTap: busy ? null : (_sent ? _verify : _send),
        ),
        if (_sent)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: busy || _wait > 0 ? null : _send,
              child: Text(_wait > 0 ? 'ارسال دوباره‌ی کد تا ${fa(_wait)} ثانیه' : 'ارسال دوباره‌ی کد',
                  style: tBody(13.5, color: K.textSoft, w: FontWeight.w700)),
            ),
          ),
        if (!widget.login && !widget.gate) ...[
          const SizedBox(height: 6),
          Text('شماره‌ات فقط برای ورود و بازیابی حساب استفاده می‌شه و روی سرور خودِ شماره ذخیره نمی‌شه، فقط یه اثر رمزشده از اون.',
              style: tBody(12, color: K.textSoft)),
        ],
      ]);
}

/// A friendly reminder to secure the account. [afterSolve]: after the first solved case (once ever);
/// otherwise before a purchase (once per app start). Returns true when the caller may go on
/// (skipped, or nothing to offer); false when the player went to secure the account.
bool _askedThisRun = false;

Future<bool> offerSecure(BuildContext context, {required bool afterSolve}) async {
  final p = Api.i.profile;
  if (p == null || p.secured || !Api.i.online) return true;
  final prefs = await SharedPreferences.getInstance();
  if (afterSolve) {
    if (prefs.getBool('secure_offer_solve') ?? false) return true;
    await prefs.setBool('secure_offer_solve', true);
  } else {
    if (_askedThisRun) return true;
    _askedThisRun = true;
  }
  if (!context.mounted) return true;
  final r = await showNoirSheet<String>(
    context,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Center(child: Icon(Icons.shield_rounded, color: K.brass, size: 44)),
      const SizedBox(height: 8),
      Text(afterSolve ? 'اولین پرونده‌ات رو حل کردی!\nحسابت رو امن کن' : 'قبل از خرید، حسابت رو امن کن',
          textAlign: TextAlign.center, style: tDisplay(20)),
      const SizedBox(height: 8),
      Text(
          afterSolve
              ? 'با شماره‌ی موبایلت، پیشرفت و سکه‌هات حتی با عوض کردن گوشی هم می‌مونه. یه کد پیامکی کافیه.'
              : 'سکه‌هایی که می‌خری روی حساب امن می‌مونه. اگه گوشی عوض بشه یا برنامه پاک بشه، با شماره‌ات همه‌چیز برمی‌گرده.',
          textAlign: TextAlign.center,
          style: tBody(13.5, color: K.textSoft)),
      const SizedBox(height: 10),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(99)),
          child: Text('${fa(Api.i.secureReward)} سکه هدیه بعد از امن شدن', style: tBody(13.5, color: K.brass, w: FontWeight.w900)),
        ),
      ),
      const SizedBox(height: 14),
      StampButton(label: 'امن کردن حساب با شماره‌ام', color: K.brass, onTap: () => Navigator.of(context).pop('secure')),
      TextButton(
        onPressed: () => Navigator.of(context).pop('skip'),
        child: Text(afterSolve ? 'بعداً' : 'ادامه‌ی خرید بدون امن کردن', style: tBody(14.5, color: K.textSoft, w: FontWeight.w700)),
      ),
    ]),
  );
  if (r != 'secure') return true;
  if (context.mounted) await openAccountSheet(context, showSecureSheet);
  return false;
}

// ------------------------------------------------------------------ sign in / move from another phone

const _phoneLogin = '__phone__';

Future<String?> showLoginSheet(BuildContext context, {int tab = 0}) async {
  final r = await showNoirSheet<String>(
    context,
    title: 'ورود یا انتقال از گوشی دیگر',
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StampButton(
        label: 'ورود با شماره‌ی موبایل',
        color: K.brass,
        icon: Icons.phone_android_rounded,
        onTap: () => Navigator.of(context).pop(_phoneLogin),
      ),
      const SizedBox(height: 12),
      LoginTransferForm(initialTab: tab),
    ]),
  );
  if (r == _phoneLogin && context.mounted) return showPhoneLoginSheet(context);
  return r;
}

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
            tabs: const [Tab(text: 'ایمیل قدیمی', height: 42), Tab(text: 'با کد انتقال', height: 42)],
          ),
        ),
        const SizedBox(height: 14),
        if (_tabs.index == 0) _emailTab() else _codeTab(),
        errorLine(),
      ]);

  Widget _emailTab() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('فقط برای حساب‌هایی که قبلاً با ایمیل امن شدن. بعد از ورود، شماره‌ات رو وصل کن.', style: tBody(12.5, color: K.textSoft)),
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


/// Full screen, cannot be closed: an email-secured account links a phone number (all progress stays).
bool _gateOpen = false;

Future<void> showPhoneGate(BuildContext context) async {
  if (_gateOpen) return;
  _gateOpen = true;
  try {
    final msg = await Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: K.night,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Center(child: Icon(Icons.phone_android_rounded, color: K.brass, size: 52)),
                const SizedBox(height: 16),
                Text('حسابت رو به شماره‌ات وصل کن', textAlign: TextAlign.center, style: tDisplay(22)),
                const SizedBox(height: 10),
                Text(
                    'از این به بعد ورود با شماره‌ی موبایله. همه‌ی پرونده‌های حل‌شده، دستاوردها و سکه‌هات همین‌جا سر جاشون می‌مونن.',
                    textAlign: TextAlign.center,
                    style: tBody(14, color: K.textSoft)),
                const SizedBox(height: 10),
                Text('حساب فعلی: ${Api.i.profile?.email ?? ''}',
                    textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: tBody(13, w: FontWeight.w700)),
                const SizedBox(height: 18),
                const _PhoneForm(login: false, gate: true),
              ]),
            ),
          ),
        ),
      ),
    ));
    if (msg != null && context.mounted) toast(context, msg);
  } finally {
    _gateOpen = false;
  }
}
