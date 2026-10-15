import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme.dart';
import '../widgets/scene.dart';
import 'account_sheets.dart' show noirField;

/// First run, after the guide: "have a friend's invite code?". Optional, closes in one tap («بعداً»), asked once.
/// The new detective gets the coins at once; the friend is paid later (see the invite card in the profile).
class InviteStepScreen extends StatefulWidget {
  const InviteStepScreen({super.key});

  /// Shows the step once for a player who has not solved a case and has not entered a code yet.
  static Future<void> maybeShow(BuildContext context) async {
    if (Api.i.flag('invite_asked')) return;
    final p = Api.i.profile;
    if (p == null || p.referred || p.casesSolved > 0 || !Api.i.online) return;
    await Api.i.setFlag('invite_asked');
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const InviteStepScreen()));
  }

  @override
  State<InviteStepScreen> createState() => _InviteStepScreenState();
}

class _InviteStepScreenState extends State<InviteStepScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int? _got; // coins received

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_code.text.trim().length < 4) {
      setState(() => _error = 'کد دعوت رو کامل بنویس');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final (coins, err) = await Api.i.redeemInvite(_code.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err != null) {
        _error = err;
      } else {
        _got = coins;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reward = Api.i.inviteNewPlayer;
    final got = _got;
    return Scaffold(
      backgroundColor: K.night,
      body: Stack(children: [
        const Positioned.fill(child: AnimatedScene(scene: 'villa_rain', height: double.infinity, dim: 0.75, animated: false)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Icon(got == null ? Icons.redeem_rounded : Icons.celebration_rounded, color: K.brass, size: 56)),
                const SizedBox(height: 12),
                Text(got == null ? 'کد دعوت داری؟' : '${fa(got)} سکه هدیه گرفتی!',
                    textAlign: TextAlign.center, style: tDisplay(24)),
                const SizedBox(height: 8),
                Text(
                    got == null
                        ? 'اگه دوستت کد دعوتش رو بهت داده، همین‌جا بزن و ${fa(reward)} سکه هدیه بگیر. نداری؟ مشکلی نیست، می‌تونی رد کنی.'
                        : 'سکه‌هات تو کیف پولته. کد دوستت ثبت شد؛ بعد از اینکه در ${fa(3)} روز مختلف پرونده حل کنی، اونم جایزه‌ش رو می‌گیره.',
                    textAlign: TextAlign.center,
                    style: tBody(14, color: K.textSoft)),
                const SizedBox(height: 20),
                if (got == null) ...[
                  TextField(
                    controller: _code,
                    enabled: !_busy,
                    textDirection: TextDirection.ltr,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    style: tDisplay(22, color: K.brass),
                    onSubmitted: (_) => _submit(),
                    decoration: noirField('کد دعوت دوستت', Icons.redeem_rounded),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, textAlign: TextAlign.center, style: tBody(13, color: K.stamp, w: FontWeight.w700)),
                    ),
                  const SizedBox(height: 14),
                  StampButton(label: _busy ? 'در حال ثبت…' : 'ثبت و گرفتن ${fa(reward)} سکه', onTap: _busy ? null : _submit),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    child: Text('بعداً', style: tBody(15, color: K.textSoft, w: FontWeight.w900)),
                  ),
                  Text('بعداً هم می‌تونی از پروفایل، بخش «دوستات رو دعوت کن»، کدش رو بزنی (تا ۷ روز اول).',
                      textAlign: TextAlign.center, style: tBody(12, color: K.textSoft)),
                ] else
                  StampButton(label: 'بزن بریم', onTap: () => Navigator.of(context).pop()),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
