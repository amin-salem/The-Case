import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/widgets/scene.dart';

/// Every scene paints without errors at several moments of its animation.
/// Set SCENE_OUT=/some/dir to also save PNGs and look at them.
const scenes = [
  'bazaar_night', 'office', 'train', 'museum', 'villa_rain', 'warehouse', 'harbor', 'hospital', 'library', 'theater',
  'hotel', 'kitchen', 'snow_lodge', 'desert', 'subway', 'lab', 'wedding', 'school', 'airport', 'tower', 'unknown',
];

void main() {
  testWidgets('all scenes paint', (tester) async {
    final out = Platform.environment['SCENE_OUT'];
    for (final scene in scenes) {
      for (final t in [0.5, 3.0, 7.7]) {
        final key = GlobalKey();
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(key: key, child: SizedBox(width: 360, height: 220, child: CustomPaint(painter: ScenePainter(scene, t, 0)))),
          ),
        ));
        expect(tester.takeException(), isNull, reason: '$scene @ $t');
        if (out != null && t == 3.0) {
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final img = await boundary.toImage(pixelRatio: 1);
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await File('$out/$scene.png').writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
      }
    }
  });
}
