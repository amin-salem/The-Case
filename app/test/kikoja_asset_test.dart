import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «کی کجا؟» is one local page inside the app (assets/kikoja/index.html). It must talk to the app only through the `KK`
/// channel, never load anything from the internet, and never carry a puzzle answer.
void main() {
  final html = File('assets/kikoja/index.html').readAsStringSync();

  test('the page is registered as an asset and answers the app', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/kikoja/'));
    expect(html, contains('window.KK'));
    expect(html, contains('window.__kkReply'));
    expect(html, contains('window.__kkBack'));
  });

  test('the page loads nothing from the internet', () {
    expect(RegExp(r'(src|href)="https?:').hasMatch(html), isFalse);
    expect(RegExp(r'url\(https?:').hasMatch(html), isFalse);
    expect(html, isNot(contains('fetch(')));
  });

  test('the app answers every operation the page asks for', () {
    final ops = RegExp(r"KKB\.call\('(\w+)'").allMatches(html).map((m) => m.group(1)).toSet();
    expect(ops, containsAll(['state', 'hint', 'accuse', 'reopen', 'share']));
    final screen = File('lib/screens/kikoja_screen.dart').readAsStringSync();
    for (final op in ops) {
      expect(screen, contains("case '$op'"), reason: 'the screen does not handle $op');
    }
  });

  test('UI texts call suspects «مظنون», not «نفر»', () {
    // the practice files' story text may say «نفر»; labels and tips may not
    expect(html, isNot(contains('یه نفر رو')));
    expect(html, isNot(contains('دو نفر که')));
  });
}
