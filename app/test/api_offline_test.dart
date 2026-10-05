import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/api.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// Server state for the fake server.
enum _Net { up, offline, down }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('friendly messages (no technical text for the player)', () {
    test('no internet', () {
      expect(Api.friendly(http.ClientException('Failed host lookup: thecase.liara.run')), Api.offlineText);
      expect(Api.friendly(Exception('SocketException: Network is unreachable')), Api.offlineText);
    });

    test('server down, slow or answering garbage', () {
      expect(Api.friendly(ApiException(500, 'Internal Server Error')), Api.serverDownText);
      expect(Api.friendly(ApiException(503, null)), Api.serverDownText);
      expect(Api.friendly(TimeoutException('slow')), Api.serverDownText);
      expect(Api.friendly(const FormatException('<html>')), Api.serverDownText);
      expect(Api.friendly(Exception('HandshakeException: CERTIFICATE_VERIFY_FAILED')), Api.serverDownText);
    });

    test('game reasons keep their own texts', () {
      expect(Api.friendly(ApiException(400, {'error': 'not_enough_coins', 'need': 30})), 'سکه‌ات کافی نیست');
      expect(Api.friendly(ApiException(409, 'email_taken')), Api.errorText('email_taken'));
      expect(Api.friendly(ApiException(404, 'no_case')), 'هنوز پرونده‌ای باز نشده');
      expect(Api.friendly(ApiException(418, 'something_new')), Api.genericText);
    });

    test('anything else', () {
      expect(Api.friendly(StateError('bug')), Api.genericText);
      expect(Api.friendly(Exception('weird')), Api.genericText);
    });

    test('never shows Latin text, URLs or status codes', () {
      final errors = <Object>[
        http.ClientException('Connection closed'),
        ApiException(500, 'boom'),
        ApiException(422, {'error': 'bad_email'}),
        ApiException(401, 'bad_token'),
        TimeoutException('x'),
        const FormatException('x'),
        StateError('x'),
      ];
      for (final e in errors) {
        final t = Api.friendly(e);
        expect(t, isNot(matches(RegExp(r'[A-Za-z0-9]'))), reason: '$e -> $t');
      }
    });

    test('only "could not reach the server" counts as a network failure', () {
      expect(Api.isNetworkFail(http.ClientException('Failed host lookup')), isTrue);
      expect(Api.isNetworkFail(ApiException(502, null)), isTrue);
      expect(Api.isNetworkFail(TimeoutException('x')), isTrue);
      expect(Api.isNetworkFail(ApiException(400, 'locked')), isFalse);
      expect(Api.isNetworkFail(StateError('x')), isFalse);
    });
  });

  group('offline cache', () {
    var net = _Net.up;
    final profile = {
      'player_id': 'p1',
      'nickname': 'کارآگاه',
      'coins': 340,
      'streak': 3,
      'login_reward': 20,
      'login_day': 2,
    };
    final caseList = {
      'today': {'id': 'c001', 'number': 1, 'title': 'قتل در باغ', 'today': true},
      'next_case_at': 1900000000,
      'archive': [
        {'id': 'c002', 'number': 2, 'title': 'پرونده‌ی قدیمی', 'locked': true},
      ],
    };
    Map<String, dynamic> caseFile(List<String> hints) => {
          'case': {
            'id': 'c001',
            'number': 1,
            'title': 'قتل در باغ',
            'suspects': [
              {'id': 's1', 'name': 'باغبان'},
            ],
            'evidence': [
              {'id': 'e1', 'title': 'ردپا'},
            ],
          },
          'progress': {'hints': hints, 'attempts': 1, 'attempts_left': 2},
          'today': true,
        };

    setUpAll(() async {
      final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400;
      SharedPreferences.setMockInitialValues({'player': 'p1', 'secret': 's1', 'token': 't1', 'token_exp': exp});
      await Api.i.init();
      Api.i.httpClient = MockClient((req) async {
        if (net == _Net.offline) throw http.ClientException('Failed host lookup: thecase.liara.run');
        if (net == _Net.down) return http.Response('<html>502 Bad Gateway</html>', 502);
        switch ('${req.method} ${req.url.path}') {
          case 'GET /v1/config':
            return _json({'economy': {'freeze_cost': 175}});
          case 'GET /v1/me':
            return _json(profile);
          case 'GET /v1/cases':
            return _json(caseList);
          case 'GET /v1/cases/c001':
            return _json(caseFile(['سرنخ اول']));
          case 'POST /v1/cases/c001/hint':
            return _json({
              'hint': 'سرنخ دوم',
              'coins': 290,
              'progress': {'hints': ['سرنخ اول', 'سرنخ دوم'], 'attempts': 1, 'attempts_left': 2},
            });
          case 'GET /v1/inbox':
            return _json(<Object>[]);
        }
        return _json({'detail': 'not_found'}, 404);
      });
    });

    test('online answers are saved, and come back when the internet is gone', () async {
      await Api.i.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20)); // the inbox refresh
      expect(Api.i.online, isTrue);
      expect(Api.i.coins, 340);
      expect((await Api.i.cases()).today?.id, 'c001');
      expect((await Api.i.openCase('c001')).$2.hints, ['سرنخ اول']);

      // a hint bought online is part of the saved case
      final (hint, _) = await Api.i.buyHint('c001');
      expect(hint, 'سرنخ دوم');
      expect(Api.i.coins, 290);

      net = _Net.offline;
      final list = await Api.i.cases();
      expect(Api.i.online, isFalse);
      expect(list.today?.title, 'قتل در باغ');
      expect(list.archive.single.locked, isTrue);

      final (c, p, today) = await Api.i.openCase('c001');
      expect(c.suspects.single.name, 'باغبان');
      expect(p.hints, ['سرنخ اول', 'سرنخ دوم']);
      expect(p.attemptsLeft, 2);
      expect(today, isTrue);

      // a case never opened can't come from nowhere
      Object? error;
      try {
        await Api.i.openCase('c002');
      } catch (e) {
        error = e;
      }
      expect(error, isNotNull);
      expect(Api.isNetworkFail(error!), isTrue);

      // coins are never invented offline
      expect(Api.i.coins, 290);
    });

    test('offline never drops the saved account', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('player'), 'p1');
      expect(prefs.getString('secret'), 's1');
    });

    test('after a restart without internet, the saved profile and config are there', () async {
      await Api.i.init();
      expect(Api.i.hasCache, isTrue);
      expect(Api.i.profile?.nickname, 'کارآگاه');
      expect(Api.i.coins, 290);
      expect(Api.i.profile?.loginReward, 0, reason: 'the login reward must not pop up again from the saved copy');
      expect(Api.i.freezeCost, 175);
    });

    test("the player's marks and pins stay on the phone", () async {
      await Api.i.saveNotes('c001', {
        'marks': {'s1': 'suspicious'},
        'pins': ['e1'],
      });
      final n = Api.i.loadNotes('c001');
      expect(n['marks'], {'s1': 'suspicious'});
      expect(n['pins'], ['e1']);
      expect(Api.i.loadNotes('nothing'), isEmpty);
    });

    test('a server that is down counts as offline too; reconnecting brings it back', () async {
      net = _Net.down;
      final list = await Api.i.cases();
      expect(list.today?.id, 'c001');
      expect(Api.i.online, isFalse);

      net = _Net.up;
      expect(await Api.i.reconnect(), isTrue);
      expect(Api.i.online, isTrue);
      expect(Api.i.lastError, '');
    });
  });
}
