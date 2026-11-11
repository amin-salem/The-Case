import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Vibration on/off («لرزش» in Settings, on by default). Every haptic in the app goes through here, so the switch is
/// respected everywhere. Like [Sfx] it never breaks the game: a platform that cannot vibrate is a quiet no-op.
class Haptics extends ChangeNotifier {
  Haptics._();
  static final Haptics i = Haptics._();

  static const prefKey = 'haptics_on';

  bool _on = true;
  bool get on => _on;

  /// Reads the saved choice. Call once at start (and in tests after `SharedPreferences.setMockInitialValues`).
  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _on = p.getBool(prefKey) ?? true;
    } catch (_) {
      _on = true;
    }
    notifyListeners();
  }

  Future<void> setOn(bool v) async {
    _on = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(prefKey, v);
    } catch (_) {}
  }

  /// A button press.
  void light() => _run(HapticFeedback.lightImpact);

  /// The stamp landing on the file: one short, firm tap.
  void stamp() => _run(HapticFeedback.mediumImpact);

  void _run(Future<void> Function() f) {
    if (!_on) return;
    try {
      f().catchError((Object e) => debugPrint('haptic: $e'));
    } catch (e) {
      debugPrint('haptic: $e');
    }
  }
}
