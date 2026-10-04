import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';

import 'scene_render_test.dart' show scenes;

/// The app and the server share the case files. Every case must parse in the app,
/// use a scene the app can draw, draw only avatar parts the app knows, and have its sounds.
void main() {
  final dir = Directory('../server/app/content/cases');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()..sort((a, b) => a.path.compareTo(b.path));

  test('there are 50 cases', () => expect(files.length, 50));

  const hair = {'bald', 'short', 'slick', 'curly', 'long', 'cap', 'hijab'};
  const beard = {'none', 'full', 'mustache', 'stubble'};
  const acc = {'none', 'tie', 'badge', 'apron', 'scarf'};

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    test('case $name', () {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      // what the server sends before a case is finished: no hints, no solution
      final pub = Map<String, dynamic>.from(j)..remove('hints')..remove('solution');
      final c = CaseData(pub);
      expect(c.title, isNotEmpty);
      expect(c.suspects.length, inInclusiveRange(3, 6));
      expect(c.evidence.length, greaterThanOrEqualTo(5));
      expect(scenes, contains(c.scene), reason: 'scene ${c.scene} is not drawn by the app');
      expect(File('assets/sounds/amb_${c.scene}.ogg').existsSync(), isTrue);
      expect(File('assets/sounds/sting_${c.scene}.ogg').existsSync(), isTrue);
      for (final s in (j['suspects'] as List).cast<Map<String, dynamic>>()) {
        final a = s['avatar'] as Map<String, dynamic>;
        expect(hair, contains(a['hair']));
        expect(beard, contains(a['beard']));
        expect(acc, contains(a['accessory']));
        expect(a['skin'], inInclusiveRange(0, 3));
        expect((s['questions'] as List).length, greaterThanOrEqualTo(2));
      }
    });
  }

  test('interface sounds exist', () {
    for (final n in ['tap', 'paper', 'stamp', 'clue', 'reveal', 'wrong', 'win', 'lose', 'heartbeat', 'amb_home']) {
      expect(File('assets/sounds/$n.ogg').existsSync(), isTrue, reason: n);
    }
  });
}
