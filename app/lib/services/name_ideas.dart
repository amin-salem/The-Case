import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Detective-name helpers (Amin, 28 Oct 2026: most players kept the random «کارآگاه1234» because nobody knew what to
/// pick and the home screen had no way to rename).
class NameIdeas {
  NameIdeas._();

  static const _kClosed = 'name_prompt_closed';

  /// The random name every new account gets: «کارآگاه» + digits (server util.default_nickname).
  static bool isDefault(String name) => RegExp(r'^کارآگاه[0-9۰-۹]+$').hasMatch(name.trim());

  static const _firsts = [
    'روباه', 'شاهین', 'گربه‌ی', 'جغد', 'گرگ', 'پلنگ', 'عقاب', 'سایه‌ی', 'ستاره‌ی', 'کارآگاه', 'بازپرس', 'رد‌یاب',
  ];
  static const _seconds = [
    'تیزبین', 'شب‌زنده', 'بی‌خواب', 'هوشیار', 'ساکت', 'کنجکاو', 'زیرک', 'نکته‌سنج', 'شب', 'تهران', 'نیمه‌شب', 'مه‌آلود',
  ];

  /// A new idea each time; never longer than the 16 letters the server accepts; [not] is skipped.
  static String next(Random rng, {String? not}) {
    for (var i = 0; i < 20; i++) {
      final a = _firsts[rng.nextInt(_firsts.length)];
      final b = _seconds[rng.nextInt(_seconds.length)];
      final n = a == b ? '$a ${_seconds[0]}' : '$a $b';
      if (n.length <= 16 && n != not) return n;
    }
    return 'روباه تیزبین';
  }

  /// The home card: only for a default name, only after the first solved case, only until the player closed it.
  static Future<bool> cardWanted({required String name, required int solved}) async {
    if (solved < 1 || !isDefault(name)) return false;
    try {
      return !((await SharedPreferences.getInstance()).getBool(_kClosed) ?? false);
    } catch (_) {
      return true; // storage failed: show it (it never blocks anything)
    }
  }

  static Future<void> closeCard() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_kClosed, true);
    } catch (_) {}
  }
}
