import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/net_fallback.dart';

InternetAddress _ip(String s) => InternetAddress(s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('filter and private addresses are bogus, public ones are not', () {
    for (final s in ['10.10.34.35', '127.0.0.1', '192.168.1.1', '172.20.0.1', '100.64.0.1', '0.0.0.0', '169.254.1.1']) {
      expect(NetFallback.isBogus(_ip(s)), isTrue, reason: s);
    }
    for (final s in ['185.1.2.3', '8.8.8.8', '172.32.0.1']) {
      expect(NetFallback.isBogus(_ip(s)), isFalse, reason: s);
    }
  });

  test('reads the A records of a DNS-over-HTTPS answer and skips the rest', () {
    final got = NetFallback.parseDohAnswer({
      'Answer': [
        {'name': 'gaamly.ir.', 'type': 5, 'data': 'x.liara.run.'},
        {'name': 'x.liara.run.', 'type': 1, 'data': '10.10.34.35'},
        {'name': 'x.liara.run.', 'type': 1, 'data': '185.10.20.30'},
        {'type': 1, 'data': 'garbage'},
      ]
    });
    expect(got.map((a) => a.address), ['185.10.20.30']);
    expect(NetFallback.parseDohAnswer(null), isEmpty);
    expect(NetFallback.parseDohAnswer({'Status': 3}), isEmpty);
  });

  group('who to connect to', () {
    tearDown(() {
      NetFallback.systemLookup = InternetAddress.lookup;
    });

    test('a phone whose DNS works keeps the normal path (the host name)', () async {
      NetFallback.systemLookup = (_) async => [_ip('185.1.2.3')];
      NetFallback.dohLookup = (_) async => fail('must not be asked');
      expect(await NetFallback.target('a.example'), 'a.example');
    });

    test('DNS fails: the public DNS address is used and remembered', () async {
      NetFallback.systemLookup = (_) async => throw const SocketException('Failed host lookup');
      var asked = 0;
      NetFallback.dohLookup = (_) async {
        asked++;
        return [_ip('185.9.9.9')];
      };
      final t = await NetFallback.target('b.example');
      expect((t as InternetAddress).address, '185.9.9.9');
      await NetFallback.target('b.example');
      expect(asked, 1, reason: 'the second call comes from the short cache');
    });

    test('a filter page address counts as a failure', () async {
      NetFallback.systemLookup = (_) async => [_ip('10.10.34.35')];
      NetFallback.dohLookup = (_) async => [_ip('185.7.7.7')];
      expect(((await NetFallback.target('c.example')) as InternetAddress).address, '185.7.7.7');
    });

    test('nothing works: the last good address, else the name (the usual error shows)', () async {
      NetFallback.systemLookup = (_) async => throw const SocketException('x');
      NetFallback.dohLookup = (_) async => [_ip('185.5.5.5')];
      await NetFallback.target('d.example'); // saves 185.5.5.5
      NetFallback.now = () => DateTime.now().add(const Duration(hours: 1)); // the cache is old
      NetFallback.dohLookup = (_) async => const [];
      expect(((await NetFallback.target('d.example')) as InternetAddress).address, '185.5.5.5');
      SharedPreferences.setMockInitialValues({});
      expect(await NetFallback.target('d.example'), 'd.example');
      NetFallback.now = DateTime.now;
    });
  });
}
