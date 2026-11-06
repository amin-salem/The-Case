import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/character.dart';

void main() {
  testWidgets('every registered portrait is packaged and decodes', (tester) async {
    await tester.runAsync(() async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final shipped = manifest.listAssets().where((p) =>
          p.startsWith('assets/portraits/') && p.endsWith('.webp')).toSet();
      expect(shipped, kPortraits.map(portraitAsset).toSet());
      for (final path in shipped) {
        final bytes = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List(
            bytes.offsetInBytes, bytes.lengthInBytes));
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0), reason: path);
        expect(frame.image.height, greaterThan(0), reason: path);
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  for (final name in ['m_mid_researcher', 'm_mid_worker', 'f_mid_waitress']) {
    testWidgets('$name renders an asset in both suspect views', (tester) async {
      final avatar = AvatarSpec({'portrait': name});
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Column(children: [
        SuspectPortrait(avatar),
        AnimatedSuspect(avatar: avatar),
      ]))));
      await tester.runAsync(() async {
        await precacheImage(AssetImage(portraitAsset(name)),
            tester.element(find.byType(Scaffold)));
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Image), findsNWidgets(2));
      final procedural = tester.widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((w) => w.painter is CharacterPainter);
      expect(procedural, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
