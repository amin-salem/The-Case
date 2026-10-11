import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'panel_url.dart';

/// Everything the app remembers lives in the Android Keystore-backed secure storage.
/// The admin key is typed once on the phone: it is never part of the APK or the repository.
class Store {
  Store([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;

  static const _key = 'admin_key';
  static const _server = 'server';
  static const _bio = 'biometric';
  static const _secure = 'secure_screen';

  Future<String?> _read(String k) async {
    try {
      return await _s.read(key: k);
    } catch (_) {
      return null;
    }
  }

  Future<String?> adminKey() async {
    final v = await _read(_key);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setAdminKey(String? v) async {
    if (v == null || v.isEmpty) {
      await _s.delete(key: _key);
    } else {
      await _s.write(key: _key, value: v);
    }
  }

  Future<String> server() async => normalizeServer(await _read(_server));
  Future<void> setServer(String v) => _s.write(key: _server, value: normalizeServer(v));

  /// null = never chosen (the app then turns it on when the phone supports a lock).
  Future<bool?> biometric() async {
    final v = await _read(_bio);
    return v == null ? null : v == '1';
  }

  Future<void> setBiometric(bool v) => _s.write(key: _bio, value: v ? '1' : '0');

  Future<bool> secureScreen() async => (await _read(_secure)) != '0';
  Future<void> setSecureScreen(bool v) => _s.write(key: _secure, value: v ? '1' : '0');
}
