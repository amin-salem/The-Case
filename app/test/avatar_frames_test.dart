import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/avatars.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/widgets/avatar_frame.dart';

void main() {
  test('catalog parses owned, locked and shop items', () {
    final c = AvatarCatalog({
      'coins': 500,
      'avatar': 'ex_cat',
      'frame': 'frame_neon',
      'avatars': [
        {'id': 'det_01', 'title': 'a', 'how': 'free', 'owned': true},
        {'id': 'ex_rookie', 'title': 'b', 'how': 'goal', 'owned': false, 'goal': 'g', 'target': 10, 'progress': 4},
        {'id': 'ex_gold', 'title': 'c', 'how': 'shop', 'rarity': 'legendary', 'price': 2500, 'owned': false},
      ],
      'frames': [
        {'id': 'frame_brass', 'title': 'd', 'how': 'free', 'owned': true},
      ],
    });
    expect(c.avatar, 'ex_cat');
    expect(c.avatars[1].fraction, 0.4);
    expect(c.avatars[2].isShop && c.avatars[2].legendary, true);
    expect(c.frames.single.isFrame, true);
  });

  test('old profiles without avatar_id fall back to the numbered portrait', () {
    expect(detId(0), 'det_01');
    expect(detId(11), 'det_02');
  });

  testWidgets('every frame draws, still and animated', (tester) async {
    const frames = [
      'frame_brass', 'frame_bronze', 'frame_silver', 'frame_gold', 'frame_ember', 'frame_tape', 'frame_loupe',
      'frame_fingerprint', 'frame_blinds', 'frame_cuffs', 'frame_stamp', 'frame_neon', 'frame_royal',
      'frame_blaze', 'frame_inferno', 'frame_eternal', null,
    ];
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(children: [
        for (final f in frames) AvatarWithFrame(avatar: 'ex_missing', frame: f, size: 80, animate: true),
      ]),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AvatarWithFrame), findsNWidgets(frames.length));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
