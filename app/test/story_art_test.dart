import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/data/story_art.dart';
import 'package:the_case/models/story.dart';
import 'package:the_case/widgets/story_art.dart';
import 'package:the_case/widgets/story_choice.dart';

Widget _wrap(Widget w, {double width = 360, double scale = 1}) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: SizedBox(width: width, child: w))),
        ),
      ),
    );

void main() {
  test('every asset the story art points at exists and is small', () {
    final all = storyArtAssets();
    expect(all.length, 5); // room, corridor, reception, photo_intact, photo_burnt
    for (final a in all) {
      final f = File(a);
      expect(f.existsSync(), isTrue, reason: a);
      expect(f.lengthSync(), lessThan(80 * 1024), reason: '$a is too big for an app asset');
    }
  });

  test('chapter 2 scenes have art, other chapters and unknown scenes have none (old chapters unchanged)', () {
    for (final id in ['sc1', 'room', 'corridor', 'desk', 'staff']) {
      expect(storySceneArt('s01ch02', id), isNotNull, reason: id);
    }
    expect(storySceneArt('s01ch02', 'nope'), isNull);
    for (final ch in ['s01ch01', 's01ch03', 'c001', '']) {
      for (final sc in ['sc1', 'room', 'shop', 'end']) {
        expect(storySceneArt(ch, sc), isNull, reason: '$ch/$sc');
      }
    }
    expect(storyClueIsTabanPhoto(2, 'e6'), isTrue);
    expect(storyClueIsTabanPhoto(1, 'e6'), isFalse);
    expect(storyClueIsTabanPhoto(2, 'e1'), isFalse);
  });

  testWidgets('scene art renders with its caption at 360 dp and a large font, no overflow', (t) async {
    for (final scale in [1.0, 2.0]) {
      await t.pumpWidget(_wrap(StorySceneArt(art: storySceneArt('s01ch02', 'room')!), scale: scale));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('story-scene-art')), findsOneWidget);
      expect(find.text('اتاق ۳۱۱'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    }
  });

  testWidgets('Taban photo clue: intact first, one tap shows the burnt photo and back', (t) async {
    await t.pumpWidget(_wrap(const TabanPhotoClue()));
    await t.pump();
    String shown() => ((t.widget<Image>(find.byType(Image)).image as AssetImage)).assetName;
    expect(shown(), kTabanPhotoIntact);
    await t.tap(find.byKey(const ValueKey('photo-tab-burnt')));
    await t.pump();
    expect(shown(), kTabanPhotoBurnt);
    await t.tap(find.byKey(const ValueKey('photo-tab-intact')));
    await t.pump();
    expect(shown(), kTabanPhotoIntact);
    expect(t.takeException(), isNull);
  });

  testWidgets('a held clue tile shows the photo only for the Taban clue of chapter 2', (t) async {
    BoardClue clue(String id, int chapter) =>
        BoardClue({'id': id, 'title': 'سرنخ', 'text': 'متن', 'status': 'held', 'by_choice': true, 'chapter': chapter});
    await t.pumpWidget(_wrap(ClueTile(clue: clue('e6', 2))));
    await t.pump();
    expect(find.byType(TabanPhotoClue), findsOneWidget);
    await t.pumpWidget(_wrap(ClueTile(clue: clue('e6', 1))));
    await t.pump();
    expect(find.byType(TabanPhotoClue), findsNothing);
    await t.pumpWidget(_wrap(ClueTile(clue: clue('e1', 2))));
    await t.pump();
    expect(find.byType(TabanPhotoClue), findsNothing);
  });
}
