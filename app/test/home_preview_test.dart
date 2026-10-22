import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'home_fixtures.dart';

/// Renders PNG previews of the home screen (only with --dart-define=HOME_PREVIEWS=true; CI uploads them).
const _on = bool.fromEnvironment('HOME_PREVIEWS');
final _boundary = GlobalKey();

Future<void> _capture(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 30));
  await t.runAsync(() async {
    final render = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('test_previews').create(recursive: true);
    await File('test_previews/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    if (!_on) return;
    final loader = FontLoader('Vazirmatn');
    loader.addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
    loader.addFont(rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf'));
    await loader.load();
    final roots = <String>[if (Platform.environment['FLUTTER_ROOT'] case final String root) root];
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++) { roots.add(dir.path); dir = dir.parent; }
    final font = roots.map((r) => File('$r/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'))
        .firstWhere((f) => f.existsSync());
    final icons = FontLoader('MaterialIcons');
    icons.addFont(font.readAsBytes().then((b) => b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes)));
    await icons.load();
  });

  for (final c in [
    ('home_before_solved', 'open', 1.0),
    ('home_after_solved', 'solved', 1.0),
    ('home_lost', 'lost', 1.0),
    ('home_before_solved_font13', 'open', 1.3),
  ]) {
    testWidgets('preview ${c.$1}', (t) async {
      if (!_on) return;
      await seedHome(tonight: c.$2, weekend: 'open');
      await pumpApp(t, scale: c.$3, boundary: _boundary);
      await _capture(t, c.$1);
    });
  }
}
