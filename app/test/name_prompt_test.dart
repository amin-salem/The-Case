import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/name_ideas.dart';
import 'package:the_case/widgets/name_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the random default name is recognised, a chosen one is not', () {
    expect(NameIdeas.isDefault('کارآگاه1717'), isTrue);
    expect(NameIdeas.isDefault('کارآگاه۱۲۳'), isTrue);
    expect(NameIdeas.isDefault('روباه تیزبین'), isFalse);
    expect(NameIdeas.isDefault('کارآگاه علی'), isFalse);
  });

  test('ideas fit the server limit (16), never repeat the given one, are never empty', () {
    final rng = Random(1);
    var last = '';
    for (var i = 0; i < 300; i++) {
      final n = NameIdeas.next(rng, not: last);
      expect(n.isNotEmpty && n.length <= 16, isTrue, reason: n);
      expect(n, isNot(last));
      expect(n.contains('نفر'), isFalse);
      last = n;
    }
  });

  test('the home card: default name + a solved case + not closed', () async {
    expect(await NameIdeas.cardWanted(name: 'کارآگاه1', solved: 0), isFalse);
    expect(await NameIdeas.cardWanted(name: 'کارآگاه1', solved: 1), isTrue);
    expect(await NameIdeas.cardWanted(name: 'روباه تیزبین', solved: 5), isFalse);
    await NameIdeas.closeCard();
    expect(await NameIdeas.cardWanted(name: 'کارآگاه1', solved: 5), isFalse);
  });

  testWidgets('the name card shows nothing without a profile', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: const [NamePromptCard()]))));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('name_card')), findsNothing);
  });
}
