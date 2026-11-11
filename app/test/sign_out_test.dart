import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/screens/signed_out_screen.dart';
import 'package:the_case/services/api.dart';

void main() {
  testWidgets('after a sign-out the phone offers a login or a fresh start, and no way back', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Directionality(textDirection: TextDirection.rtl, child: SignedOutScreen())));
    expect(find.text('از حسابت خارج شدی'), findsOneWidget);
    expect(find.byKey(const ValueKey('signed-out-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('signed-out-new')), findsOneWidget);
    expect(find.textContaining('پاک نشده'), findsOneWidget);
  });

  test('signOut forgets the identity on this phone and moves to another account number', () async {
    SharedPreferences.setMockInitialValues({'player': 'p1', 'secret': 's1', 'token': 't1', 'token_exp': 9999999999});
    await Api.i.init();
    expect(Api.i.playerId, 'p1');
    final before = Api.i.account;
    await Api.i.signOut();
    expect(Api.i.playerId, isNull);
    expect(Api.i.account, before + 1);
    final p = await SharedPreferences.getInstance();
    for (final k in ['player', 'secret', 'token', 'token_exp']) {
      expect(p.containsKey(k), isFalse, reason: k);
    }
  });
}
