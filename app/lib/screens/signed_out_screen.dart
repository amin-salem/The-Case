import 'package:flutter/material.dart';

import '../main.dart' show StartScreen;
import '../theme.dart';
import 'account_sheets.dart';

/// After «خروج از حساب»: this phone has no account. The player logs in to another one (phone number, e-mail or a transfer
/// code) or starts as a fresh detective. Nothing is registered on the server until he chooses (no throwaway account is made).
class SignedOutScreen extends StatelessWidget {
  const SignedOutScreen({super.key});

  void _start(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const StartScreen()), (_) => false);
  }

  Future<void> _login(BuildContext context) async {
    final r = await showLoginSheet(context, replaceWarning: false);
    if (r != null && context.mounted) _start(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: GrainBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Icon(Icons.logout_rounded, color: K.brass, size: 48),
                  const SizedBox(height: 14),
                  Text('از حسابت خارج شدی', textAlign: TextAlign.center, style: tDisplay(24)),
                  const SizedBox(height: 8),
                  Text('حسابت سر جاشه و پاک نشده. وارد حساب دیگه‌ای شو یا با یه حساب تازه شروع کن.',
                      textAlign: TextAlign.center, style: tBody(14, color: K.textSoft).copyWith(height: 1.7)),
                  const SizedBox(height: 24),
                  StampButton(
                    key: const ValueKey('signed-out-login'),
                    label: 'ورود به حساب',
                    color: K.brass,
                    icon: Icons.login_rounded,
                    onTap: () => _login(context),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    key: const ValueKey('signed-out-new'),
                    onPressed: () => _start(context),
                    child: Text('شروع به‌عنوان کارآگاه تازه', style: tBody(14.5, color: K.textSoft, w: FontWeight.w700)),
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
