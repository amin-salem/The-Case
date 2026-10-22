import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/api.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <String>[];
  var ratingRoute = 'ok'; // ok | missing | no_case

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'player': 'p1', 'secret': 's1', 'token': 't1',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
    await Api.i.init();
    Api.i.httpClient = MockClient((req) async {
      calls.add('${req.method} ${req.url.path} ${req.body}');
      if (req.url.path.endsWith('/rating')) {
        if (ratingRoute == 'missing') return _json({'detail': 'Not Found'}, 404);
        if (ratingRoute == 'no_case') return _json({'detail': 'no_case'}, 404);
        return _json({'id': 1, 'status': 'approved', 'rating': 4, 'already': false});
      }
      return _json({'id': 1, 'status': 'approved'});
    });
  });

  setUp(calls.clear);

  test('stars-only rating uses the new route', () async {
    ratingRoute = 'ok';
    await Api.i.rateCase('c001', 4);
    expect(calls, ['POST /v1/cases/c001/rating {"rating":4}']);
  });

  test('an unknown case is a real error and is not retried on the comment route', () async {
    ratingRoute = 'no_case';
    await expectLater(Api.i.rateCase('zzz', 4), throwsA(isA<ApiException>()));
    expect(calls.length, 1);
  });

  test('an older server (404) falls back to the comment route, and remembers it', () async {
    ratingRoute = 'missing';
    await Api.i.rateCase('c001', 5);
    expect(calls.length, 2);
    expect(calls[0], startsWith('POST /v1/cases/c001/rating'));
    expect(calls[1], startsWith('POST /v1/cases/c001/comments'));
    expect(calls[1], contains('"rating":5'));
    calls.clear();
    await Api.i.rateCase('c002', 3);
    expect(calls.length, 1, reason: 'the missing route is not asked again');
    expect(calls[0], startsWith('POST /v1/cases/c002/comments'));
  });
}
