import 'dart:math';

import 'package:flutter/material.dart';

import '../screens/account_sheets.dart' show showNoirSheet;
import '../services/api.dart';
import '../services/name_ideas.dart';
import '../theme.dart';
import 'offline.dart';

/// «اسم کارآگاه»: one sheet used by the home screen, the profile and the card after the first solved case.
/// The dice button gives a new idea each tap; save sends it to the server (names are unique: a taken name says so).
Future<bool> showNameSheet(BuildContext context) async {
  if (!needOnline(context)) return false;
  final done = await showNoirSheet<bool>(
    context,
    title: 'اسم کارآگاهیت چیه؟',
    sub: 'این اسم توی جدول برترین‌ها و پیام‌ها دیده می‌شه. هر وقت خواستی عوضش کن.',
    child: const _NameForm(),
  );
  return done ?? false;
}

class _NameForm extends StatefulWidget {
  const _NameForm();

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  final _rng = Random();
  late final TextEditingController _c;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = Api.i.profile?.nickname ?? '';
    _c = TextEditingController(text: NameIdeas.isDefault(now) ? NameIdeas.next(_rng) : now);
    _c.selection = TextSelection(baseOffset: 0, extentOffset: _c.text.length);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _dice() => setState(() {
        _error = null;
        _c.text = NameIdeas.next(_rng, not: _c.text);
      });

  Future<void> _save() async {
    final name = _c.text.trim();
    if (name.isEmpty || _busy) return;
    if (name == Api.i.profile?.nickname) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.i.updateProfile(nickname: name);
      await NameIdeas.closeCard();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = Api.friendly(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        key: const ValueKey('name_field'),
        controller: _c,
        maxLength: 16,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        style: tBody(17, w: FontWeight.w800),
        decoration: InputDecoration(
          errorText: _error,
          suffixIcon: IconButton(
            key: const ValueKey('name_dice'),
            tooltip: 'یه اسم دیگه پیشنهاد بده',
            icon: const Icon(Icons.casino_rounded, color: K.brass),
            onPressed: _dice,
          ),
        ),
      ),
      const SizedBox(height: 8),
      FilledButton(
        key: const ValueKey('name_save'),
        style: FilledButton.styleFrom(backgroundColor: K.stamp, minimumSize: const Size.fromHeight(46)),
        onPressed: _busy ? null : _save,
        child: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text('ذخیره', style: tBody(15, w: FontWeight.w800)),
      ),
    ]);
  }
}

/// Home card after the first solved case, while the name is still the random one. ✕ closes it for good.
class NamePromptCard extends StatefulWidget {
  const NamePromptCard({super.key});

  @override
  State<NamePromptCard> createState() => _NamePromptCardState();
}

class _NamePromptCardState extends State<NamePromptCard> {
  bool _show = false;
  String _checked = '';

  Future<void> _check() async {
    final p = Api.i.profile;
    final key = '${p?.nickname}|${p?.casesSolved}';
    if (p == null || key == _checked) return;
    _checked = key;
    final want = await NameIdeas.cardWanted(name: p.nickname, solved: p.casesSolved);
    if (mounted && want != _show) setState(() => _show = want);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Api.i,
      builder: (context, _) {
        _check();
        if (!_show) return const SizedBox.shrink();
        return Padding(
          key: const ValueKey('name_card'),
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: K.night3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: K.brass.withValues(alpha: 0.5)),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.badge_rounded, size: 22, color: K.brass)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('اسمت توی جدول برترین‌ها دیده می‌شه؛ یه اسم باحال برای خودت بذار.', style: tBody(12.5, color: K.text)),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const ValueKey('name_open'),
                    style: FilledButton.styleFrom(backgroundColor: K.stamp, visualDensity: VisualDensity.compact),
                    onPressed: () async {
                      final ok = await showNameSheet(context);
                      if (ok && mounted) setState(() => _show = false);
                    },
                    child: Text('انتخاب اسم', style: tBody(13, w: FontWeight.w700)),
                  ),
                ]),
              ),
              IconButton(
                key: const ValueKey('name_close'),
                tooltip: 'بستن',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: K.textSoft),
                onPressed: () async {
                  await NameIdeas.closeCard();
                  if (mounted) setState(() => _show = false);
                },
              ),
            ]),
          ),
        );
      },
    );
  }
}
