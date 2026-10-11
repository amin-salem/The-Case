import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/about.dart';
import 'package:the_case/services/api.dart';

http.Response _json(Object? body, [int status = 200, Map<String, String> headers = const {}]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8', ...headers});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('backoff', () {
    test('grows exponentially from Retry-After, with a little jitter, and is capped', () {
      final rng = Random(7);
      final a = Api.backoffDelay(0, 2, rng).inMilliseconds;
      final b = Api.backoffDelay(1, 2, rng).inMilliseconds;
      expect(a, inInclusiveRange(2000, 2499));
      expect(b, inInclusiveRange(4000, 4499));
      expect(Api.backoffDelay(0, 0, rng).inMilliseconds, inInclusiveRange(1000, 1499)); // unknown = 1 s
      expect(Api.backoffDelay(5, 8, rng).inMilliseconds, 10000); // capped
    });
  });

  group('429 from the server', () {
    final calls = <String>[];
    final slept = <Duration>[];
    var mode = 'ok';
    var failsLeft = 0;
    var retryAfter = 2;

    setUpAll(() async {
      final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400;
      SharedPreferences.setMockInitialValues({'player': 'p1', 'secret': 's1', 'token': 't1', 'token_exp': exp});
      await Api.i.init();
      Api.i.sleep = (d) async => slept.add(d);
      Api.i.httpClient = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        final limited = mode == 'limited' || (mode == 'flaky' && failsLeft-- > 0);
        if (limited) {
          return _json({'error': 'rate_limited', 'message': 'x', 'retry_after': retryAfter}, 429,
              {'retry-after': '$retryAfter'});
        }
        switch ('${req.method} ${req.url.path}') {
          case 'GET /v1/cases':
            return _json({'today': {'id': 'c001', 'number': 1, 'title': 'قتل در باغ', 'today': true}, 'archive': []});
          case 'GET /v1/me':
            return _json({'player_id': 'p1', 'coins': 5});
        }
        return _json({'detail': 'not_found'}, 404);
      });
    });

    setUp(() {
      calls.clear();
      slept.clear();
      retryAfter = 2;
    });

    test('a GET is retried at most twice with growing pauses, then the saved copy is shown', () async {
      mode = 'ok';
      expect((await Api.i.cases()).today?.id, 'c001'); // saved on the phone
      calls.clear();
      mode = 'limited';
      expect((await Api.i.cases()).today?.id, 'c001'); // 429 -> the saved answer, the game stays usable
      expect(calls.length, 3); // 1 try + 2 retries, never more
      expect(slept.length, 2);
      expect(slept[0].inMilliseconds, inInclusiveRange(2000, 2499));
      expect(slept[1].inMilliseconds, inInclusiveRange(4000, 4499));
      expect(Api.i.rateLimitedUntil.value, isNotNull);
    });

    test('a POST is never repeated', () async {
      mode = 'limited';
      await expectLater(
        Api.i.buyHint('c001'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 429).having((e) => e.retryAfter, 'retryAfter', 2)),
      );
      expect(calls, ['POST /v1/cases/c001/hint']);
      expect(slept, isEmpty);
    });

    test('a long wait is not slept through: the error carries the countdown instead', () async {
      mode = 'limited';
      retryAfter = 30;
      Object? error;
      try {
        await Api.i.refreshProfile();
      } catch (e) {
        error = e;
      }
      expect(error, isA<ApiException>());
      expect(calls.length, 1);
      expect(slept, isEmpty);
      expect(Api.friendly(error!), contains('۳۰'));
    });

    test('a GET that was limited once just works on the retry', () async {
      mode = 'flaky';
      failsLeft = 1;
      final p = await Api.i.refreshProfile();
      expect(p?.coins, 5);
      expect(calls.length, 2);
      expect(slept.length, 1);
    });

    test('the message is friendly Persian, with and without a countdown', () {
      expect(Api.rateLimitedText(5), allOf(contains('۵'), isNot(matches(RegExp(r'[A-Za-z0-9]')))));
      expect(Api.rateLimitedText(0), isNot(matches(RegExp(r'[A-Za-z0-9]'))));
      expect(Api.friendly(ApiException(429, {'error': 'rate_limited', 'retry_after': 12})), contains('۱۲'));
    });
  });

  group('support block', () {
    test('has the facts and no secrets', () {
      const info = AboutInfo(
        appName: 'پرونده',
        version: '1.20.3',
        build: '39',
        store: 'مایکت',
        packageName: 'ir.aminsalem.the_case',
        serverVersion: '1.18.0',
        serverOk: true,
        playerShortId: 'a1b2c3d4',
        inviteCode: 'K7Q2MX',
        language: 'fa-IR',
      );
      final t = info.supportText();
      for (final s in ['1.20.3', '39', 'مایکت', 'ir.aminsalem.the_case', '1.18.0', 'a1b2c3d4', 'K7Q2MX', 'fa-IR']) {
        expect(t, contains(s));
      }
      expect(t.toLowerCase(), isNot(contains('token')));
      expect(t.toLowerCase(), isNot(contains('secret')));
      expect(t.toLowerCase(), isNot(contains('password')));
    });

    test('the player id is shortened', () {
      expect(AboutInfo.shortId('0123456789abcdef0123456789abcdef'), '01234567');
      expect(AboutInfo.shortId(null), '');
    });
  });
}
