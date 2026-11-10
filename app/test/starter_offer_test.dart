import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/services/starter_offer.dart';
import 'package:the_case/widgets/next_case_card.dart';
import 'package:the_case/widgets/starter_sheet.dart';

CaseRow row(String id, int number, {int d = 3, int cost = 150, bool solved = false, bool failed = false, bool today = false,
        bool weekend = false, bool locked = true, double rating = 0}) =>
    CaseRow({'id': id, 'number': number, 'title': 'پرونده $id', 'difficulty': d, 'unlock_cost': cost, 'solved': solved,
      'failed': failed, 'today': today, 'weekend': weekend, 'locked': locked, 'rating_avg': rating, 'rating_count': rating > 0 ? 20 : 0});

http.Response json(Object data) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('pickSuggestedCase', () {
    test('only unsolved, never lost, not tonight, not a weekend case, not the one just solved', () {
      final rows = [
        row('solved', 1, solved: true), row('lost', 2, failed: true), row('tonight', 3, today: true),
        row('wk', 4, weekend: true), row('just', 5), row('ok', 6, d: 5),
      ];
      expect(pickSuggestedCase(rows, rank: 0, excludeId: 'just')!.id, 'ok');
      expect(pickSuggestedCase([row('solved', 1, solved: true)], rank: 0), isNull);
      expect(pickSuggestedCase(const [], rank: 0), isNull);
    });

    test('a case that fits the level beats a harder one; the closest to the level wins', () {
      // rank 0-2: target difficulty 2; rank 3-5: 3; 6-8: 4; 9+: 5
      final rows = [row('hard', 9, d: 5, cost: 100), row('easy', 8, d: 1), row('fit', 7, d: 2), row('mid', 6, d: 3)];
      expect(pickSuggestedCase(rows, rank: 0)!.id, 'fit');
      expect(pickSuggestedCase(rows, rank: 4)!.id, 'mid');
      expect(pickSuggestedCase(rows, rank: 12)!.id, 'hard');
    });

    test('only harder cases left: the nearest one is suggested rather than nothing', () {
      expect(pickSuggestedCase([row('a', 1, d: 5), row('b', 2, d: 4)], rank: 0)!.id, 'b');
    });

    test('equal fit: the cheaper, then the better rated, then the newer', () {
      expect(pickSuggestedCase([row('dear', 5, d: 2, cost: 200), row('cheap', 4, d: 2, cost: 120)], rank: 0)!.id, 'cheap');
      expect(pickSuggestedCase([row('plain', 5, d: 2), row('loved', 4, d: 2, rating: 4.8)], rank: 0)!.id, 'loved');
      expect(pickSuggestedCase([row('old', 4, d: 2), row('new', 9, d: 2)], rank: 0)!.id, 'new');
    });

    test('a case that is already open costs nothing', () {
      expect(suggestedPrice(row('open', 1, locked: false, cost: 150)), 0);
      expect(suggestedPrice(row('shut', 1, cost: 150)), 150);
    });
  });

  group('starter rules', () {
    test('shown at most twice, never when bought, missing from the store or offline', () {
      bool may(int shown, {bool bought = false, bool product = true, bool online = true}) =>
          starterMayShow(shown: shown, bought: bought, productExists: product, online: online);
      expect(may(0), isTrue);
      expect(may(1), isTrue);
      expect(may(2), isFalse);
      expect(may(0, bought: true), isFalse);
      expect(may(0, product: false), isFalse);
      expect(may(0, online: false), isFalse);
    });

    test('archive cases the coins open are counted from the real prices, cheapest first', () {
      final rows = [row('a', 1, cost: 150), row('b', 2, cost: 200), row('c', 3, cost: 300), row('x', 4, solved: true, cost: 10),
        row('t', 5, today: true, cost: 10), row('free', 6, locked: false, cost: 0)];
      expect(archiveCasesFor(1000, rows), 3); // 150 + 200 + 300 = 650; nothing else left
      expect(archiveCasesFor(350, rows), 2);
      expect(archiveCasesFor(340, rows), 1); // 150, then 190 left: not enough for 200
      expect(archiveCasesFor(100, rows), 0);
      expect(archiveCasesFor(1000, const []), 0);
    });

    test('tiles: no tile for a number that is zero or unknown; ads tile always', () {
      final t = starterTiles(coins: 1000, archive: [for (var i = 0; i < 6; i++) row('r$i', i + 1, cost: 250)], cheapestHint: 40);
      expect(t.map((e) => e.$2), ['پرونده‌ی بایگانی', 'سرنخ', 'تبلیغ، برای همیشه']);
      expect(t[0].$1, '≈ ۴');
      expect(t[1].$1, '≈ ۲۵');
      final none = starterTiles(coins: 1000, archive: const [], cheapestHint: 0);
      expect(none.map((e) => e.$2), ['تبلیغ، برای همیشه']);
    });
  });

  group('counter', () {
    final events = <String>[];
    setUp(() async {
      SharedPreferences.setMockInitialValues({'player': 'p1', 'secret': 's1', 'token': 't1',
        'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
      await Api.i.init();
      Api.i.online = true;
      Api.i.profile = Profile({'player_id': 'p1', 'coins': 10});
      Api.i.config = {'prices': {'starter_pack': '۷۹٬۰۰۰ تومان'}, 'economy': {'products': {'starter_pack': {'coins': 1000, 'no_ads': true}}}};
      events.clear();
      Api.i.httpClient = MockClient((r) async {
        if (r.url.path == '/v1/events') {
          for (final e in (jsonDecode(r.body)['events'] as List)) {
            events.add('${e['name']}:${e['props']['moment'] ?? ''}');
          }
        }
        return json(<String, dynamic>{});
      });
    });
    tearDown(() => Api.i.config = const {});

    test('two showings, then never again; every showing is logged', () async {
      expect(StarterOffer.eligible(), isTrue);
      await StarterOffer.noteShown('lack_coins');
      expect(StarterOffer.shown(), 1);
      expect(StarterOffer.eligible(), isTrue);
      await StarterOffer.noteShown('first_solve');
      expect(StarterOffer.shown(), 2);
      expect(StarterOffer.eligible(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(events, ['starter_offer_shown:lack_coins', 'starter_offer_shown:first_solve']);
    });

    test('another account has its own counter; a bought pack or a missing product ends the offer', () async {
      await StarterOffer.noteShown('lack_coins');
      await StarterOffer.noteShown('lack_coins');
      Api.i.profile = Profile({'player_id': 'p2', 'coins': 10});
      expect(StarterOffer.eligible(), isTrue);
      Api.i.profile = Profile({'player_id': 'p2', 'coins': 10, 'no_ads': true});
      expect(StarterOffer.eligible(), isFalse);
      Api.i.profile = Profile({'player_id': 'p2', 'coins': 10});
      Api.i.config = const {};
      expect(StarterOffer.eligible(), isFalse);
    });
  });

  test('button label: free, enough, or how many coins are missing', () {
    expect(NextCaseCard.buttonLabel(0, 5), 'باز کن');
    expect(NextCaseCard.buttonLabel(180, 400), 'باز کن · ۱۸۰ سکه');
    expect(NextCaseCard.buttonLabel(180, 85), 'باز کن · ۱۸۰ سکه (۹۵ سکه کم داری)');
  });

  test('tomorrow text comes from the real opening time', () {
    final now = DateTime(2026, 11, 10, 22, 10);
    expect(nextOpeningText(DateTime(2026, 11, 11, 21), now), 'فردا ساعت ۲۱ پرونده‌ی بعدی باز می‌شه');
    expect(nextOpeningText(DateTime(2026, 11, 10, 23, 30), now), 'امشب ساعت ۲۳:۳۰ پرونده‌ی بعدی باز می‌شه');
  });
}
