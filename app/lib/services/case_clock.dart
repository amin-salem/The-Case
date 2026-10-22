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

  // Investigation depth, reported with every tick and with the accusation (the server keeps the union, so a lost
  // report costs nothing): evidence cards the player tapped, and the interrogation questions asked ("suspect:index").
  final Set<String> _cards = {}, _asks = {};
  static const _depthCap = 80;
  List<String> get cards => _cards.toList();
  List<String> get asks => _asks.toList();

  /// The player opened (tapped) an evidence card of the current case.
  void card(String evidenceId) {
    if (_case != null && _cards.length < _depthCap) _cards.add(evidenceId);
  }

  /// The player asked question [index] of a suspect.
  void asked(String suspectId, int index) {
    if (_case != null && _asks.length < _depthCap) _asks.add('$suspectId:$index');
  }

  final Stopwatch _sw = Stopwatch();
  int _pending = 0; // seconds measured but not reported yet
  Timer? _flush;

  /// The case screen opened.
  void start(String caseId) {
    if (_case != null && _case != caseId) stop();
    if (_case != caseId) {
      _cards.clear();
      _asks.clear();
    }
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

  /// Is this the case whose screen is open right now?
  bool isOn(String caseId) => _case == caseId;

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
    if (!await Api.i.tickCase(id, s, cards: cards, asks: asks)) _pending += s; // offline: try again next time
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
