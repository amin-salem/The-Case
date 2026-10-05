import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All the game's sound. Every sound is synthesised by tools/make_sounds.py and shipped as a tiny .ogg:
///  * `amb_<scene>`  a looping mystery bed with the sounds of that place (rain, train clacks, ward monitors ...)
///  * `sting_<scene>` the hit that plays when a case file opens
///  * interface sounds: tap, paper, stamp, clue, reveal, wrong, win, lose, heartbeat
/// Sound never breaks the game: if the platform can't play (tests, a broken device) every call is a quiet no-op.
class Sfx extends ChangeNotifier {
  Sfx._();
  static final Sfx i = Sfx._();

  static const _ambientVolume = 0.42;
  bool _muted = false;
  bool get muted => _muted;
  bool _ready = false;

  AudioPlayer? _amb;
  String? _ambName;
  double _ambVolume = _ambientVolume; // the volume the current bed is meant to play at
  double _ambNow = 0; // where the fade is right now
  final Map<String, DateTime> _lastPlayed = {};
  Timer? _fade;
  final List<AudioPlayer> _pool = [];
  int _next = 0;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _muted = p.getBool('muted') ?? false;
    } catch (_) {}
    try {
      // play alongside the player's own music or podcast instead of pausing it
      await AudioPlayer.global.setAudioContext(
          AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build());
    } catch (e) {
      if (kDebugMode) debugPrint('sfx context: $e');
    }
    _ready = true;
  }

  Future<void> setMuted(bool v) async {
    _muted = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('muted', v);
    } catch (_) {}
    if (v) {
      await _stopNow();
    } else if (_ambName != null) {
      final n = _ambName!;
      _ambName = null;
      await ambient(n, volume: _ambVolume);
    }
  }

  Future<void> toggle() => setMuted(!_muted);

  AudioPlayer _oneShotPlayer() {
    for (final p in _pool) {
      if (p.state != PlayerState.playing) return p; // an idle player first, so nothing gets cut off
    }
    if (_pool.length < 5) {
      final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
      _pool.add(p);
      return p;
    }
    return _pool[_next++ % _pool.length];
  }

  /// A one-off sound, e.g. `Sfx.i.play('stamp')`.
  Future<void> play(String name, {double volume = 0.8}) async {
    if (_muted || !_ready) return;
    // the same small sound never stacks up when tapped quickly
    final now = DateTime.now();
    final last = _lastPlayed[name];
    if (last != null && now.difference(last).inMilliseconds < 150) return;
    _lastPlayed[name] = now;
    try {
      await _oneShotPlayer().play(AssetSource('sounds/$name.ogg'), volume: volume);
    } catch (e) {
      if (kDebugMode) debugPrint('sfx $name: $e');
    }
  }

  /// The case-opening sting for a scene, with its ambience fading in underneath.
  Future<void> openCase(String scene) async {
    await play('sting_$scene', volume: 0.9);
    await ambient('amb_$scene', delay: const Duration(milliseconds: 1400));
  }

  /// Loops a background bed (fading in). Asking again for the one already playing does nothing.
  Future<void> ambient(String name, {Duration delay = Duration.zero, double volume = _ambientVolume}) async {
    if (_ambName == name && _amb != null) return;
    final previous = _ambName;
    _ambName = name;
    _ambVolume = volume;
    if (_muted || !_ready) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (_ambName != name) return; // asked for something else while waiting
    try {
      if (previous != null) await _fadeOutAndStop();
      final p = _amb ?? (_amb = AudioPlayer());
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(0);
      _ambNow = 0;
      await p.play(AssetSource('sounds/$name.ogg'));
      _fadeTo(volume);
    } catch (e) {
      if (kDebugMode) debugPrint('sfx ambient $name: $e');
    }
  }

  /// Leaving a case: the ambience fades away.
  Future<void> stopAmbient() async {
    _ambName = null;
    await _fadeOutAndStop();
  }

  /// Lower the bed for a big moment (the verdict), then bring it back.
  void duck() => _fadeTo(_ambVolume * 0.3, ms: 300);
  void unduck() => _fadeTo(_ambVolume, ms: 800);

  /// App went to the background / came back.
  Future<void> pauseAll() async {
    try {
      await _amb?.pause();
    } catch (_) {}
  }

  Future<void> resumeAll() async {
    if (_muted) return;
    try {
      if (_ambName != null) await _amb?.resume();
    } catch (_) {}
  }

  void _fadeTo(double target, {int ms = 1200}) {
    _fade?.cancel();
    final p = _amb;
    if (p == null) return;
    const step = 60;
    final steps = (ms / step).ceil();
    var k = 0;
    final from = _ambNow;
    _fade = Timer.periodic(const Duration(milliseconds: step), (t) async {
      k++;
      final v = from + (target - from) * (k / steps);
      _ambNow = v.clamp(0.0, 1.0);
      try {
        await p.setVolume(_ambNow);
      } catch (_) {}
      if (k >= steps) t.cancel();
    });
  }

  Future<void> _fadeOutAndStop() async {
    _fade?.cancel();
    final p = _amb;
    if (p == null) return;
    try {
      for (var v = _ambNow; v > 0; v -= 0.06) {
        await p.setVolume(v.clamp(0.0, 1.0));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      _ambNow = 0;
      await p.stop();
    } catch (_) {}
  }

  Future<void> _stopNow() async {
    _fade?.cancel();
    try {
      await _amb?.stop();
      for (final p in _pool) {
        await p.stop();
      }
    } catch (_) {}
  }
}
