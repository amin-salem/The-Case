import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Voice lint (docs/app-voice.md): a curated list of the worst offenders in user-facing strings.
/// Comment lines and `lib/data/` (case and story content) are skipped.
void main() {
  const letters = '؀-ۿ‌';
  final rules = <String, RegExp>{
    'هٔ / ۀ form (write «‌ی»: پرونده‌ی)': RegExp('ٔ|ۀ'),
    '«شما» as a word (use «تو»)': RegExp('(?<![$letters])شما(?![$letters])'),
    'formal verb (می‌شود/می‌کند/می‌دهد/می‌توانی)': RegExp(
        '(?<![$letters])(می‌شود|می‌شوند|می‌کند|می‌کنند|می‌دهد|می‌توانید|می‌توانی|نمی‌توانید|نمی‌توانی)(?![$letters])'),
    '«بازیکن» (players are «کارآگاه»)': RegExp('بازیکن'),
  };

  /// `lib/path.dart:<trimmed line start>` exceptions, each with a reason. Keep empty when possible.
  const allowed = <String>[];

  test('no curated voice offenders in app/lib strings', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path.startsWith('lib/data/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        for (final e in rules.entries) {
          if (e.value.hasMatch(line) && !allowed.any((a) => '$path:${line.trim()}'.startsWith(a))) {
            bad.add('$path:${i + 1}  [${e.key}]  ${line.trim()}');
          }
        }
      }
    }
    expect(bad, isEmpty, reason: 'Fix the text (docs/app-voice.md) or add a reasoned exception:\n${bad.join('\n')}');
  });
}
