import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/scene.dart';

void main() {
  test('detail and archive preserve the optional variant', () {
    for (final v in ['', 'clock']) {
      final json = <String, dynamic>{'scene': 'tower', if (v.isNotEmpty) 'scene_variant': v};
      expect(CaseRow(json).sceneVariant, v);
      expect(CaseData(json).sceneVariant, v);
    }
  });

  testWidgets('variant selects its image; a missing asset falls back to the base', (tester) async {
    Future<void> show(String v) async {
      await tester.pumpWidget(MaterialApp(home: AnimatedScene(scene: 'tower', variant: v, animated: false)));
      await tester.pumpAndSettle();
    }
    Finder asset(String path) => find.byWidgetPredicate((w) =>
        w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == path);
    await show('clock');
    expect(asset('assets/scenes/tower_clock.webp'), findsOneWidget);
    await show('not_shipped');
    await tester.runAsync(() async {
      try { await DefaultAssetBundle.of(tester.element(find.byType(AnimatedScene))).load('assets/scenes/tower_not_shipped.webp'); }
      catch (_) { /* Expected: this asset deliberately does not exist. */ }
    });
    await tester.pumpAndSettle();
    expect(asset('assets/scenes/tower.webp'), findsOneWidget);
    await show('../clock');
    expect(asset('assets/scenes/tower.webp'), findsOneWidget);
  });
}
