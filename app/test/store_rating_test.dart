import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/services/app_update.dart';
import 'package:the_case/services/store_rating.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var clock = DateTime(2026, 11, 1, 12);
  final opened = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = DateTime(2026, 11, 1, 12);
    opened.clear();
    StoreRating.now = () => clock;
    StoreRating.store = 'bazaar';
    StoreRating.launcher = (u) async {
      opened.add(u.toString());
      return true;
    };
    StoreRating.i.resetForTest();
    AppUpdate.launcher = (u) async {
      opened.add(u.toString());
      return false;
    };
  });

  Future<void> solved3(int solved) async {
    await StoreRating.i.noteSolve(stars: 3, solved: solved);
  }

  // The card also needs the profile's solved count; these tests drive the same rules through noteSolve + visible.
  test('only a 3-star solve of a player with 3+ solved cases arms it (and only the Bazaar build)', () async {
    await StoreRating.i.noteSolve(stars: 2, solved: 10);
    expect(StoreRating.i.visible, isFalse);
    await StoreRating.i.noteSolve(stars: 3, solved: 2);
    expect(StoreRating.i.visible, isFalse);
    StoreRating.store = 'myket';
    await StoreRating.i.noteSolve(stars: 3, solved: 10);
    expect(StoreRating.i.visible, isFalse);
  });

  test('later hides it for 30 days; the button hides it for good', () async {
    await solved3(5);
    await StoreRating.i.load();
    // visible needs the profile too; with no profile it stays hidden (fails closed)
    expect(StoreRating.i.visible, isFalse);
    await StoreRating.i.later();
    await solved3(5);
    clock = clock.add(const Duration(days: 10));
    expect(StoreRating.i.visible, isFalse);
    expect(await StoreRating.i.rate(), isTrue);
    expect(opened.single, StoreRating.bazaarPage);
    await solved3(5);
    clock = clock.add(const Duration(days: 90));
    expect(StoreRating.i.visible, isFalse, reason: 'never again after the button');
  });

  test('the review links fall through: Bazaar page, then the web page', () async {
    StoreRating.launcher = (u) async {
      opened.add(u.toString());
      return u.scheme == 'https';
    };
    expect(await StoreRating.i.rate(), isTrue);
    expect(opened, [StoreRating.bazaarPage, StoreRating.webPage]);
    StoreRating.launcher = (u) async => throw Exception('no handler');
    expect(await StoreRating.i.rate(), isFalse);
  });

  test('the update button tries the in-app sheet, the app page, then the web link', () async {
    Api.i.config = {'update_url': 'https://cafebazaar.ir/app/ir.gammly.parvandeh'};
    expect(await AppUpdate.i.open(), isFalse);
    expect(opened, [AppUpdate.bazaarModal, AppUpdate.bazaarPage, 'https://cafebazaar.ir/app/ir.gammly.parvandeh']);
    opened.clear();
    AppUpdate.launcher = (u) async {
      opened.add(u.toString());
      return u.toString() == AppUpdate.bazaarPage;
    };
    expect(await AppUpdate.i.open(), isTrue);
    expect(opened, [AppUpdate.bazaarModal, AppUpdate.bazaarPage]);
    opened.clear();
    AppUpdate.launcher = (u) async => throw Exception('boom');
    expect(await AppUpdate.i.open(), isFalse);
    Api.i.config = const {};
  });
}
