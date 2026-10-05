import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api.dart';

/// Counts how long a case screen is really open: it runs while the case is on screen and the app is
/// in front, and pauses when the player goes back, switches app or locks the phone. Every half
/// minute (and when leaving) the time is reported to the server, which uses it as the solving time.
class CaseClock with WidgetsBindingObserver {
  CaseClock._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final CaseClock i = CaseClock._();

  String? _case;
  final Stopwatch _sw = Stopwatch();
  int _pending = 0; // seconds measured but not reported yet
  Timer? _flush;

  /// The case screen opened.
  void start(String caseId) {
    if (_case != null && _case != caseId) stop();
    _case = caseId;
    _sw
      ..reset()
      ..start();
    _flush ??= Timer.periodic(const Duration(seconds: 30), (_) => _report());
  }

  /// The case screen closed.
  void stop() {
    _collect();
    _report();
    _sw
      ..stop()
      ..reset();
    _flush?.cancel();
    _flush = null;
    _case = null;
  }

  /// Time not reported yet, handed to the accusation (the server adds it to the case's time).
  int take(String caseId) {
    if (caseId != _case) return 0;
    _collect();
    final s = _pending;
    _pending = 0;
    return s;
  }

  void _collect() {
    _pending += _sw.elapsed.inSeconds;
    _sw.reset();
  }

  Future<void> _report() async {
    final id = _case;
    _collect();
    if (id == null || _pending <= 0) return;
    final s = _pending;
    _pending = 0;
    if (!await Api.i.tickCase(id, s)) _pending += s; // offline: try again next time
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_case == null) return;
    if (state == AppLifecycleState.resumed) {
      _sw.start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      _sw.stop();
      _report();
    }
  }
}
