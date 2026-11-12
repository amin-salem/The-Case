import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app is right to left and Flutter mirrors direction icons there, so the names are "reversed": a forward chevron is
/// `chevron_right` (it shows «<») and a back arrow is `arrow_forward` (it shows «→»). Writing the natural name gave a
/// wrong arrow again and again (Amin, 12 Nov 2026), so this test refuses the natural names.
void main() {
  test('no left/back icon names that would point the wrong way in RTL', () {
    // `chevron_left` is allowed only where it truly means «previous» (the step back inside the accusation wizard).
    const allowedChevronLeft = {'accuse_screen.dart'};
    final bad = <String>[];
    for (final f in Directory('lib').listFiles()) {
      final text = f.readAsStringSync();
      final name = f.path.split('/').last;
      if (RegExp(r'Icons\.(arrow_back|arrow_back_ios|keyboard_arrow_left|arrow_left)\w*').hasMatch(text)) bad.add('$name: arrow_back (use arrow_forward)');
      if (!allowedChevronLeft.contains(name) && RegExp(r'Icons\.chevron_left').hasMatch(text)) bad.add('$name: chevron_left (use chevron_right)');
    }
    expect(bad, isEmpty);
  });
}

extension on Directory {
  Iterable<File> listFiles() => listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
}
