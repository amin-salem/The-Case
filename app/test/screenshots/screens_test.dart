// Screenshots of the app's real screens, so the UI can be reviewed without a phone.
//
//   flutter test test/screenshots --dart-define=SCREENSHOTS=1
//
// writes build/screens/<name>.png (phone size 390 x 844 at 2.5x) and build/screens/report.txt.
// Without SCREENSHOTS every test returns at once, so a normal `flutter test` stays fast.
//
// The screens talk to a fake server (package:http MockClient) that serves the real case files
// from ../server/app/content/cases, so home, case, accuse, result, leaderboard ... all show real data.
// Sound is never initialised, so every Sfx call is a quiet no-op.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/main.dart' show StartScreen;
import 'package:the_case/models/models.dart';
import 'package:the_case/models/progress.dart';
import 'package:the_case/screens/accuse_screen.dart';
import 'package:the_case/screens/achievements_screen.dart';
import 'package:the_case/screens/account_screen.dart';
import 'package:the_case/screens/case_screen.dart';
import 'package:the_case/screens/dialogs.dart';
import 'package:the_case/screens/home_screen.dart';
import 'package:the_case/screens/inbox_sheet.dart';
import 'package:the_case/screens/leaderboard_screen.dart';
import 'package:the_case/screens/main_shell.dart';
import 'package:the_case/screens/result_screen.dart';
import 'package:the_case/screens/riddles_screen.dart';
import 'package:the_case/screens/shop_screen.dart';
import 'package:the_case/screens/suspect_sheet.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/character.dart';
import 'package:the_case/widgets/engagement.dart';
import 'package:the_case/widgets/missions_card.dart';
import 'package:the_case/widgets/scene.dart';

const String _flag = String.fromEnvironment('SCREENSHOTS');
final bool kShots = (_flag.isNotEmpty && _flag != '0' && _flag != 'false') ||
    (Platform.environment['SCREENSHOTS'] ?? '').isNotEmpty;

const double _dpr = 2.5;
const Size _phone = Size(390, 844);
const String _outDir = 'build/screens';
const String _casesDir = '../server/app/content/cases';

// ------------------------------------------------------------------ real data

final Map<String, Map<String, dynamic>> _json = {};

List<String> get _caseIds {
  if (_json.isEmpty) {
    final files = Directory(_casesDir).listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      _json['${j['id']}'] = j;
    }
  }
  return _json.keys.toList();
}

Map<String, dynamic> _raw(String id) {
  _caseIds;
  return _json[id] ?? _json.values.first;
}

/// What the server sends: no hints; the solution only once the case is finished.
Map<String, dynamic> _public(String id, {bool finished = false}) {
  final j = Map<String, dynamic>.from(_raw(id))..remove('hints');
  if (!finished) j.remove('solution');
  return j;
}

CaseData _full(String id) => CaseData(_raw(id));

Map<String, dynamic> _solution(String id) => (_raw(id)['solution'] as Map).cast<String, dynamic>();

List<String> _hints(String id) => [for (final h in (_raw(id)['hints'] as List? ?? const [])) '$h'];

// ------------------------------------------------------------------ fake server

final int _farFuture = DateTime(2100).millisecondsSinceEpoch ~/ 1000;

final Map<String, dynamic> _profileJson = {
  'player_id': 'p_demo',
  'nickname': 'کارآگاه شب',
  'avatar': 3,
  'invite_code': 'K7Q2M',
  'referred': false,
  'email': null,
  'secured': false,
  'coins': 840,
  'no_ads': false,
  'vip_until': null,
  'streak': 12,
  'best_streak': 31,
  'cases_solved': 27,
  'stars_total': 64,
  'login_reward': 0,
  'login_day': 4,
  'streak_freezes': 1,
  'xp': 1840,
  'rank': 3,
  'rank_title': 'کارآگاه ارشد',
  'rank_xp': 1300,
  'next_rank_xp': 2500,
  'next_rank_title': 'بازرس',
  'achievements': 4,
};

final Map<String, dynamic> _config = {
  'share_url': 'https://cafebazaar.ir/app/ir.aminsalem.the_case',
  'prices': {
    'coins_small': '۴۹٬۰۰۰ تومان',
    'coins_medium': '۱۲۹٬۰۰۰ تومان',
    'coins_large': '۲۹۹٬۰۰۰ تومان',
    'starter_pack': '۷۹٬۰۰۰ تومان',
    'remove_ads': '۹۹٬۰۰۰ تومان',
    'vip_monthly': '۱۴۹٬۰۰۰ تومان',
  },
  'economy': {
    'hint_costs': [30, 50, 80],
    'unlock_cost': 120,
    'max_attempts': 3,
    'ad_reward': 25,
    'ads_per_day': 5,
    'secure_reward': 200,
    'invite_reward': 300,
    'invite_new_player': 150,
    'login_calendar': [20, 30, 40, 50, 60, 80],
    'login_envelope': [100, 250],
    'freeze_cost': 150,
    'max_freezes': 2,
    'streak_badges': [7, 30, 100],
    'ranks': [
      {'xp': 0, 'title': 'کارآگاه تازه‌کار'},
      {'xp': 200, 'title': 'دستیار کارآگاه'},
      {'xp': 600, 'title': 'کارآگاه'},
      {'xp': 1300, 'title': 'کارآگاه ارشد'},
      {'xp': 2500, 'title': 'بازرس'},
      {'xp': 4200, 'title': 'سربازرس'},
      {'xp': 6500, 'title': 'کارآگاه نخبه'},
      {'xp': 10000, 'title': 'استاد معما'},
      {'xp': 15000, 'title': 'افسانه'},
    ],
    'products': {
      'coins_small': {'coins': 400, 'no_ads': false, 'kind': 'consumable'},
      'coins_medium': {'coins': 1300, 'no_ads': false, 'kind': 'consumable'},
      'coins_large': {'coins': 3600, 'no_ads': false, 'kind': 'consumable'},
      'starter_pack': {'coins': 1000, 'no_ads': true, 'kind': 'permanent'},
      'remove_ads': {'coins': 0, 'no_ads': true, 'kind': 'permanent'},
      'vip_monthly': {'coins': 0, 'no_ads': false, 'kind': 'subscription'},
    },
  },
};

Map<String, dynamic> _freshProgress() =>
    {'hints': <String>[], 'attempts': 0, 'attempts_left': 3, 'solved': false, 'failed': false, 'stars': 0, 'hint_costs': [30, 50, 80]};

/// Per-case progress the fake server answers with (tests change it before rendering).
final Map<String, Map<String, dynamic>> _progress = {};
bool _offline = false;
Duration _configDelay = Duration.zero;

Map<String, dynamic> _row(String id, {bool today = false, bool locked = false, bool solved = false, bool failed = false, int stars = 0}) {
  final j = _raw(id);
  return {
    'id': j['id'],
    'number': j['number'],
    'title': j['title'],
    'location': j['location'],
    'scene': j['scene'],
    'difficulty': j['difficulty'],
    'publish': j['publish'] ?? '',
    'today': today,
    'locked': locked,
    'unlock_cost': 120,
    'solved': solved,
    'failed': failed,
    'stars': stars,
    'solvers': 300 + (j['number'] as int? ?? 1) * 37,
  };
}

Map<String, dynamic> _casesList() {
  final ids = _caseIds;
  final today = ids.last;
  final archive = ids.reversed.skip(1).take(10).toList();
  final states = [
    (solved: true, failed: false, locked: false, stars: 3),
    (solved: true, failed: false, locked: false, stars: 2),
    (solved: false, failed: true, locked: false, stars: 0),
    (solved: false, failed: false, locked: false, stars: 0),
    (solved: true, failed: false, locked: false, stars: 1),
    (solved: false, failed: false, locked: true, stars: 0),
  ];
  return {
    'today': _row(today, today: true),
    'next_case_at': DateTime.now().add(const Duration(hours: 5, minutes: 23)).millisecondsSinceEpoch ~/ 1000,
    'archive': [
      for (int i = 0; i < archive.length; i++)
        _row(archive[i],
            solved: states[i % states.length].solved,
            failed: states[i % states.length].failed,
            locked: i >= 6 || states[i % states.length].locked,
            stars: states[i % states.length].stars),
    ],
  };
}

Map<String, dynamic> _stats(String id) {
  final j = _raw(id);
  final suspects = (j['suspects'] as List).cast<Map<String, dynamic>>();
  const shares = [38, 27, 17, 11, 5, 2];
  return {
    'players': 1843,
    'solved_pct': 41,
    'first_try_pct': 18,
    'culprit': _solution(id)['culprit'],
    'suspects': [for (int i = 0; i < suspects.length; i++) {'id': suspects[i]['id'], 'pct': shares[i % shares.length]}],
  };
}

Map<String, dynamic> _leaderboard(String period) {
  const names = ['شرلوک تهرانی', 'مهتاب', 'پوآروی کوچک', 'کارآگاه نیما', 'سارا.ک', 'آرش', 'دختر باران', 'ردپا', 'میلاد', 'سایه'];
  return {
    'period': period,
    'title': switch (period) { 'weekly' => 'این هفته', 'all' => 'همیشه', _ => 'پرونده‌ی امروز' },
    'top': [
      for (int i = 0; i < names.length; i++)
        {'rank': i + 1, 'nickname': names[i], 'avatar': i % 12, 'value': 980 - i * 61, 'stars': 3 - (i ~/ 4), 'me': false,
          'rank_title': const ['استاد معما', 'کارآگاه نخبه', 'سربازرس', 'بازرس', 'کارآگاه ارشد'][min(i ~/ 2, 4)]},
    ],
    'me': {'rank': 23, 'nickname': 'کارآگاه شب', 'avatar': 3, 'value': 412, 'stars': 2, 'me': true, 'rank_title': 'کارآگاه ارشد'},
  };
}

// quick riddles: the first five real riddles; the first two answered, the last one locked
List<Map<String, dynamic>> get _riddleRaw =>
    (jsonDecode(File('../server/app/content/riddles.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();

Map<String, dynamic> _riddleItem(int i, {bool answered = false, bool correct = false, bool locked = false}) {
  final r = _riddleRaw[i];
  return {
    'id': r['id'],
    'slot': i + 1,
    'title': r['title'],
    'scene': r['scene'],
    'free': i < 3,
    'locked': locked,
    'answered': answered,
    'correct': correct,
    'choice': answered ? (correct ? 0 : 1) : null,
    'text': locked ? null : r['scene_text'],
    'clue': locked ? null : r['clue'],
    'choices': locked ? <String>[] : r['choices'],
    'answer': answered ? 0 : null,
    'explain': answered ? r['explain'] : null,
  };
}

Map<String, dynamic> _achievements() {
  const rows = [
    ('first_case', 'اولین پرونده', 'اولین پرونده‌ات را حل کن', 'cases', 1, 1, 50, 20),
    ('cases_10', 'کارآگاه پرکار', '۱۰ پرونده حل کن', 'cases', 10, 10, 100, 50),
    ('cases_25', 'پرونده‌خوار', '۲۵ پرونده حل کن', 'cases', 25, 27, 200, 100),
    ('cases_50', 'بایگانی زنده', '۵۰ پرونده حل کن', 'cases', 50, 27, 400, 200),
    ('stars_10', 'دقت بالا', '۱۰ پرونده را با ۳ ستاره حل کن', 'skill', 10, 7, 200, 100),
    ('fast_2', 'برق‌آسا', 'یک پرونده را زیر ۲ دقیقه حل کن', 'skill', 1, 0, 150, 80),
    ('streak_7', 'یک هفته‌ی کامل', '۷ شب پشت سر هم پرونده‌ی روز را حل کن', 'streak', 7, 12, 150, 80),
    ('streak_30', 'یک ماه بی‌وقفه', '۳۰ شب پشت سر هم پرونده‌ی روز را حل کن', 'streak', 30, 12, 600, 300),
    ('riddle_10', 'معماباز', '۱۰ معمای سریع را درست جواب بده', 'riddles', 10, 4, 80, 40),
    ('chest_week', 'هفته‌ی مأموریت', '۷ روز پشت سر هم همه‌ی مأموریت‌ها را انجام بده', 'missions', 7, 3, 300, 150),
    ('rank_inspector', 'نشان بازرسی', 'به درجه‌ی «بازرس» برس', 'rank', 4, 3, 200, 0),
  ];
  final items = [
    for (final r in rows)
      {'id': r.$1, 'title': r.$2, 'desc': r.$3, 'group': r.$4, 'target': r.$5, 'progress': min(r.$5, r.$6),
        'earned': r.$6 >= r.$5, 'earned_at': r.$6 >= r.$5 ? 1790000000 : null, 'coins': r.$7, 'xp': r.$8},
  ];
  return {'earned': items.where((x) => x['earned'] == true).length, 'total': 33, 'items': items};
}

Map<String, dynamic> _missionsDay({bool done = false}) => {
      'day': '2026-10-06',
      'missions': [
        {'id': 'riddle_play3', 'title': 'به ۳ معمای سریع جواب بده', 'target': 3, 'progress': done ? 3 : 2, 'done': done},
        {'id': 'daily_case', 'title': 'پرونده‌ی امروز را حل کن', 'target': 1, 'progress': done ? 1 : 0, 'done': done},
        {'id': 'interrogate_all', 'title': 'از همه‌ی مظنون‌های یک پرونده بازجویی کن', 'target': 1, 'progress': 1, 'done': true},
      ],
      'all_done': done,
      'claimed': false,
      'chest_coins': 80,
      'chest_streak': 3,
      'next_at': DateTime.now().add(const Duration(hours: 7, minutes: 12)).millisecondsSinceEpoch ~/ 1000,
      'coins': 840,
    };

Map<String, dynamic> _riddleDay() => {
      'day': '2026-10-06',
      'items': [
        _riddleItem(0, answered: true, correct: true),
        _riddleItem(1, answered: true),
        _riddleItem(2),
        _riddleItem(3),
        _riddleItem(4, locked: true),
      ],
      'unlock_cost': 20,
      'reward': 10,
      'seconds': 60,
      'next_at': DateTime.now().add(const Duration(hours: 7, minutes: 12)).millisecondsSinceEpoch ~/ 1000,
      'coins': 840,
    };

Future<http.Response> _serve(http.Request req) async {
  if (_offline) throw const SocketException('Failed host lookup: thecase.liara.run');
  final path = req.url.path;
  final parts = path.split('/'); // ['', 'v1', 'cases', id, action]
  Object? body;
  if (path == '/v1/config') {
    if (_configDelay > Duration.zero) await Future<void>.delayed(_configDelay);
    body = _config;
  } else if (path == '/v1/auth/register' || path == '/v1/auth/login') {
    body = {'player_id': 'p_demo', 'secret': 'secret', 'token': 'token', 'expires_at': _farFuture};
  } else if (path == '/v1/me') {
    body = _profileJson;
  } else if (path == '/v1/inbox') {
    body = [
      {'id': 'g1', 'title': 'هدیه‌ی افتتاحیه', 'message': 'به خاطر اینکه از اول با ما بودی!', 'grants': [{'type': 'coins', 'amount': 200}]},
      {'id': 'g2', 'title': 'جبران قطعی سرور', 'message': 'دیشب سرور یه ساعت قطع بود. ببخشید!', 'grants': [{'type': 'coins', 'amount': 50}]},
    ];
  } else if (path == '/v1/cases') {
    body = _casesList();
  } else if (path == '/v1/achievements') {
    body = _achievements();
  } else if (path == '/v1/missions') {
    body = _missionsDay();
  } else if (path == '/v1/missions/claim') {
    body = {'missions': {..._missionsDay(), 'claimed': true, 'chest_streak': 4}, 'reward': 80, 'gains': {}};
  } else if (path == '/v1/riddles') {
    body = _riddleDay();
  } else if (parts.length >= 5 && parts[2] == 'riddles') {
    final i = _riddleRaw.indexWhere((r) => r['id'] == parts[3]);
    body = {
      'correct': true, 'answer': 0, 'explain': _riddleRaw[i]['explain'], 'reward': 10, 'coins': 850,
      'item': _riddleItem(i, answered: true, correct: true),
      'gains': {'xp': 5, 'missions_done': ['۳ معمای سریع جواب بده'], 'achievements': [], 'rank_up': null},
    };
  } else if (path == '/v1/leaderboard') {
    body = _leaderboard(req.url.queryParameters['period'] ?? 'daily');
  } else if (parts.length >= 4 && parts[1] == 'v1' && parts[2] == 'cases') {
    final id = parts[3];
    final action = parts.length > 4 ? parts[4] : '';
    final p = _progress[id] ?? _freshProgress();
    switch (action) {
      case 'stats':
        body = _stats(id);
      case 'hint':
        final hints = _hints(id);
        final have = (p['hints'] as List).length;
        final next = {...p, 'hints': [...(p['hints'] as List), hints.isEmpty ? '' : hints[min(have, hints.length - 1)]]};
        _progress[id] = next;
        body = {'hint': hints.isEmpty ? '' : hints[min(have, hints.length - 1)], 'coins': 810, 'progress': next};
      case 'accuse':
        final next = {...p, 'attempts': (p['attempts'] as int) + 1, 'attempts_left': max(0, (p['attempts_left'] as int) - 1)};
        _progress[id] = next;
        body = {'result': 'wrong_suspect', 'attempts_left': next['attempts_left'], 'coins': 840, 'progress': next};
      default:
        final finished = p['solved'] == true || p['failed'] == true;
        body = {'case': _public(id, finished: finished), 'progress': p, 'today': id == _caseIds.last};
    }
  } else {
    return http.Response.bytes(utf8.encode(jsonEncode({'detail': 'not_found'})), 404);
  }
  return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
}

// ------------------------------------------------------------------ fonts

File? _materialIconsFile() {
  final roots = <String>[];
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) roots.add(env);
  // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/flutter_tester
  var dir = File(Platform.resolvedExecutable).parent;
  for (int i = 0; i < 8; i++) {
    roots.add(dir.path);
    dir = dir.parent;
  }
  for (final r in roots) {
    final f = File('$r/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) return f;
  }
  return null;
}

Future<void> _loadFonts() async {
  final vazir = FontLoader(kFont);
  for (final w in ['Regular', 'Bold', 'Black']) {
    final f = File('assets/fonts/Vazirmatn-$w.ttf');
    if (f.existsSync()) vazir.addFont(f.readAsBytes().then((b) => b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes)));
  }
  await vazir.load();
  final icons = _materialIconsFile();
  if (icons == null) {
    stdout.writeln('screens: MaterialIcons font not found, icons will be boxes');
    return;
  }
  await (FontLoader('MaterialIcons')..addFont(icons.readAsBytes().then((b) => b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes))))
      .load();
}

// ------------------------------------------------------------------ shooting

final List<String> _report = [];
List<String> _warnings = [];

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: home,
    );

String _firstLine(Object e) {
  final s = '$e'.trim();
  final i = s.indexOf('\n');
  return i < 0 ? s : s.substring(0, i);
}

/// Pumps frames for [d] so animations land in a natural mid state.
Future<void> _frames(WidgetTester tester, Duration d) async {
  const step = Duration(milliseconds: 50);
  var left = d;
  while (left > Duration.zero) {
    await tester.pump(left < step ? left : step);
    left -= step;
  }
}

/// Taps the first match; a missing widget is only a warning (the screen is still captured).
Future<void> _tap(WidgetTester tester, Finder f, {Duration wait = const Duration(milliseconds: 900)}) async {
  if (f.evaluate().isEmpty) {
    _warnings.add('nothing to tap: $f');
    return;
  }
  await tester.ensureVisible(f.first);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(f.first, warnIfMissed: false);
  await _frames(tester, wait);
}

Future<void> _precacheImages(WidgetTester tester) async {
  final images = find.byType(Image, skipOffstage: false).evaluate().toList();
  if (images.isEmpty) return;
  await tester.runAsync(() async {
    for (final e in images) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final ok = await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return false;
    final file = File('$_outDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    return true;
  });
  if (ok != true) throw StateError('could not encode $name.png');
}

/// One screenshot = one test. [before] sets up the fake server, [then] interacts before the capture.
void shot(
  String name,
  Widget Function() screen, {
  Size size = _phone,
  Size Function()? sizeOf,
  Duration wait = const Duration(milliseconds: 800),
  void Function()? before,
  Future<void> Function(WidgetTester tester)? then,
}) {
  testWidgets(name, (tester) async {
    if (!kShots) return;
    _warnings = [];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = (details) => _warnings.add(_firstLine(details.exceptionAsString()));
    debugDisableShadows = false;
    final key = GlobalKey();
    Object? failure;
    try {
      tester.view.physicalSize = (sizeOf?.call() ?? size) * _dpr;
      tester.view.devicePixelRatio = _dpr;
      before?.call();
      await tester.pumpWidget(RepaintBoundary(key: key, child: _app(screen())));
      await _frames(tester, wait);
      if (then != null) await then(tester);
      await _precacheImages(tester);
      await tester.pump(const Duration(milliseconds: 16));
      await _capture(tester, key, name);
    } catch (e) {
      failure = e;
    } finally {
      try {
        // unmount and let every delayed future / timer run out, so no timer outlives the test
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
      } catch (e) {
        _warnings.add('cleanup: ${_firstLine(e)}');
      }
      FlutterError.onError = oldOnError;
      debugDisableShadows = true;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      _offline = false;
      _configDelay = Duration.zero;
      Api.i.profile = Profile(_profileJson);
    }
    final line = failure == null ? 'OK    $name' : 'FAIL  $name: ${_firstLine(failure)}';
    _report.add(line);
    for (final w in _warnings.toSet().take(6)) {
      _report.add('        warning: $w');
    }
    stdout.writeln('screens: $line');
    if (failure != null) fail('screenshot $name failed: $failure');
  });
}

/// Opens a dialog / bottom sheet over [background] right after the first frame.
class _Host extends StatefulWidget {
  const _Host({required this.open, this.background});
  final void Function(BuildContext context) open;
  final Widget? background;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: widget.background ?? const GrainBackground(child: SizedBox.expand()));
}

Widget _sceneBackground(String scene) => AnimatedScene(scene: scene, height: double.infinity, dim: 0.5);

// ------------------------------------------------------------------ contact sheets

List<String> get _sceneNames {
  final seen = <String, String>{};
  for (final id in _caseIds) {
    seen.putIfAbsent('${_raw(id)['scene']}', () => '${_raw(id)['title']}');
  }
  return seen.keys.toList()..sort();
}

String _sceneTitle(String scene) {
  for (final id in _caseIds) {
    if (_raw(id)['scene'] == scene) return '${_raw(id)['title']}';
  }
  return '';
}

Widget _scenesGrid() {
  const w = 179.0;
  return Scaffold(
    body: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in _sceneNames)
          SizedBox(
            width: w,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: w, child: AnimatedScene(scene: s, height: 112))),
              Text(s, textDirection: TextDirection.ltr, style: tBody(11.5, w: FontWeight.w700)),
            ]),
          ),
      ]),
    ),
  );
}

Size get _scenesGridSize => Size(390, 24 + ((_sceneNames.length + 1) ~/ 2) * 148.0);

Widget _scenesLarge(List<String> names) => Scaffold(
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final s in names) ...[
            Text('$s · ${_sceneTitle(s)}', style: tBody(13, w: FontWeight.w700)),
            ClipRRect(borderRadius: BorderRadius.circular(12), child: AnimatedScene(scene: s, height: 210)),
            const SizedBox(height: 10),
          ],
        ]),
      ),
    );

List<List<String>> get _sceneHalves {
  final all = _sceneNames;
  final half = (all.length + 1) ~/ 2;
  return [all.sublist(0, half), all.sublist(half)];
}

Size _scenesLargeSize(int n) => Size(390, 24 + n * 256.0);

const _moodNames = {Mood.calm: 'آرام', Mood.nervous: 'مضطرب', Mood.angry: 'عصبانی', Mood.sad: 'غمگین'};

List<String> get _sheetCases {
  final ids = _caseIds;
  return [for (int i = 0; i < ids.length; i += max(1, ids.length ~/ 10)) ids[i]].take(10).toList();
}

Widget _suspectsSheet() {
  var n = 0;
  final cells = [
    for (final id in _sheetCases) [for (final s in _full(id).suspects) (s, Mood.values[n++ % Mood.values.length])],
  ];
  final cases = _sheetCases;
  return Scaffold(
    body: SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (int i = 0; i < cases.length; i++) ...[
          Text('${_raw(cases[i])['id']} · ${_raw(cases[i])['title']}', style: tDisplay(15, color: K.brass)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (s, mood) in cells[i])
              SizedBox(
                width: 88,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    decoration: BoxDecoration(color: K.night3, borderRadius: BorderRadius.circular(10)),
                    child: AnimatedSuspect(avatar: s.avatar, size: 84, mood: mood),
                  ),
                  Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: tBody(11, w: FontWeight.w700)),
                  Text(_moodNames[mood]!, style: tBody(9.5, color: K.textSoft)),
                ]),
              ),
          ]),
          const SizedBox(height: 12),
        ],
      ]),
    ),
  );
}

Size get _suspectsSheetSize {
  var h = 24.0;
  for (final id in _sheetCases) {
    h += 30 + ((_full(id).suspects.length + 3) ~/ 4) * 136 + 12;
  }
  return Size(390, h);
}

Widget _moodsSheet() {
  final people = [for (final id in _sheetCases.take(6)) _full(id).suspects.first];
  Widget cell(Widget child, String label) => SizedBox(
        width: 70,
        child: Column(mainAxisSize: MainAxisSize.min, children: [child, Text(label, style: tBody(10, color: K.textSoft))]),
      );
  return Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('حالت‌های چهره (ثابت) + در حال حرف زدن', style: tDisplay(15, color: K.brass)),
        const SizedBox(height: 6),
        for (final p in people)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (final m in Mood.values)
                cell(CustomPaint(size: const Size(70, 77), painter: CharacterPainter(p.avatar, mood: m)), _moodNames[m]!),
              cell(CustomPaint(size: const Size(70, 77), painter: CharacterPainter(p.avatar, mood: Mood.calm, mouth: 0.9)), 'حرف'),
            ]),
          ),
      ]),
    ),
  );
}

// ------------------------------------------------------------------ results

AccuseResult _solvedResult(String id) {
  final sol = _solution(id);
  return AccuseResult({
    'result': 'solved',
    'stars': 3,
    'reward': 120,
    'coins': 960,
    'streak': 12,
    'explanation': sol['explanation'],
    'culprit': sol['culprit'],
    'proof': sol['proof'],
    'rank': 4,
    'seconds': 252,
    'hints_used': 0,
    'freezes_used': 1,
    'badge': 7,
    'progress': {'attempts': 1, 'attempts_left': 2, 'solved': true, 'stars': 3},
  });
}

AccuseResult _failedResult(String id) {
  final sol = _solution(id);
  return AccuseResult({
    'result': 'failed',
    'attempts_left': 0,
    'streak': 0,
    'explanation': sol['explanation'],
    'culprit': sol['culprit'],
    'proof': sol['proof'],
    'seconds': 731,
    'hints_used': 2,
    'progress': {'attempts': 3, 'attempts_left': 0, 'failed': true},
  });
}

Widget _engagement() {
  const id = 'c027';
  return Scaffold(
    body: ListView(physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
      Text('StreakCard', textDirection: TextDirection.ltr, style: tBody(12, color: K.textSoft)),
      StreakCard(profile: Profile(_profileJson)),
      const SizedBox(height: 10),
      StreakCard(profile: Profile({..._profileJson, 'streak': 31, 'streak_freezes': 2})),
      const SizedBox(height: 10),
      StreakCard(profile: Profile({..._profileJson, 'streak': 0, 'streak_freezes': 0})),
      const SizedBox(height: 16),
      Text('StreakBadges (best 12 / best 120)', textDirection: TextDirection.ltr, style: tBody(12, color: K.textSoft)),
      const StreakBadges(best: 12),
      const SizedBox(height: 8),
      const StreakBadges(best: 120),
      const SizedBox(height: 16),
      Text('BadgeBanner', textDirection: TextDirection.ltr, style: tBody(12, color: K.textSoft)),
      const BadgeBanner(badge: 30),
      const SizedBox(height: 16),
      Text('ShareCard (solved / failed)', textDirection: TextDirection.ltr, style: tBody(12, color: K.textSoft)),
      ShareCard(caseData: _full(id), result: _solvedResult(id)),
      const SizedBox(height: 12),
      ShareCard(caseData: _full(id), result: _failedResult(id)),
    ]),
  );
}

// ------------------------------------------------------------------ the screens

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!kShots) return;
    await _loadFonts();
    SharedPreferences.setMockInitialValues({
      'player': 'p_demo',
      'secret': 'secret',
      'token': 'token',
      'token_exp': _farFuture,
    });
    // Api.i is created here, inside the zone, so its http client is the fake server
    http.runWithClient(() => Api.i, () => MockClient(_serve));
    await Api.i.init();
    await Api.i.connect();
    if (!Api.i.online) stdout.writeln('screens: fake server connect failed');
  });

  tearDownAll(() async {
    if (!kShots) return;
    final text = _report.join('\n');
    final f = File('$_outDir/report.txt');
    await f.parent.create(recursive: true);
    await f.writeAsString('$text\n');
    final failed = _report.where((l) => l.startsWith('FAIL')).toList();
    stdout.writeln('\n===== screenshots: ${_report.where((l) => l.startsWith('OK')).length} ok, ${failed.length} failed');
    stdout.writeln(text);
  });

  // start
  shot('start_loading', () => const StartScreen(), before: () => _configDelay = const Duration(seconds: 10));
  shot('start_offline', () => const StartScreen(), before: () => _offline = true, wait: const Duration(milliseconds: 1200));

  // home
  shot('home', () => const HomeScreen(), wait: const Duration(milliseconds: 1600));
  shot('shell_home', () => const MainShell(), wait: const Duration(milliseconds: 1600));
  shot('shell_daily', () => const MainShell(), size: const Size(390, 1500), wait: const Duration(milliseconds: 600), then: (t) async {
    await _tap(t, find.text('روزانه'), wait: const Duration(milliseconds: 1500));
  });
  shot('shell_profile', () => const MainShell(), wait: const Duration(milliseconds: 600), then: (t) async {
    await _tap(t, find.text('پروفایل'), wait: const Duration(milliseconds: 1500));
  });
  shot('home_full', () => const HomeScreen(), size: const Size(390, 2400), wait: const Duration(milliseconds: 1800));
  shot('home_login_calendar', () => const HomeScreen(),
      before: () => Api.i.profile = Profile({..._profileJson, 'login_reward': 50, 'login_day': 4}),
      wait: const Duration(milliseconds: 1600));
  shot('login_calendar_day7',
      () => _Host(open: (c) => showLoginCalendar(c, day: 7, reward: 250), background: _sceneBackground('villa_rain')),
      wait: const Duration(milliseconds: 1200));

  // a case
  shot('case_intro', () => const CaseScreen(caseId: 'c012'),
      before: () => _progress['c012'] = _freshProgress(), wait: const Duration(milliseconds: 3500));
  void midCase() => _progress['c027'] = {
        ..._freshProgress(),
        'attempts': 1,
        'attempts_left': 2,
        'hints': _hints('c027').take(1).toList(),
      };
  shot('case_story', () => const CaseScreen(caseId: 'c027'), before: midCase, wait: const Duration(milliseconds: 1200));
  shot('case_evidence', () => const CaseScreen(caseId: 'c027'),
      before: midCase, then: (t) => _tap(t, find.byType(Tab).at(1)));
  shot('case_evidence_full', () => const CaseScreen(caseId: 'c027'),
      size: const Size(390, 1900), before: midCase, then: (t) => _tap(t, find.byType(Tab).at(1)));
  shot('case_suspects', () => const CaseScreen(caseId: 'c027'),
      before: midCase, then: (t) => _tap(t, find.byType(Tab).at(2), wait: const Duration(milliseconds: 1200)));
  shot('case_hint_confirm', () => const CaseScreen(caseId: 'c027'),
      before: midCase, then: (t) => _tap(t, find.byIcon(Icons.lightbulb_rounded)));
  shot('case_hint', () => const CaseScreen(caseId: 'c027'), before: midCase, then: (t) async {
    await _tap(t, find.byIcon(Icons.lightbulb_rounded));
    await _tap(t, find.byType(FilledButton));
  });
  void solvedCase() => _progress['c005'] = {..._freshProgress(), 'attempts': 1, 'attempts_left': 2, 'solved': true, 'stars': 2};
  shot('case_solved', () => const CaseScreen(caseId: 'c005'), before: solvedCase, wait: const Duration(milliseconds: 1200));
  shot('case_solved_full', () => const CaseScreen(caseId: 'c005'),
      size: const Size(390, 1900), before: solvedCase, wait: const Duration(milliseconds: 1200));
  shot('case_solved_suspects', () => const CaseScreen(caseId: 'c005'),
      before: solvedCase, then: (t) => _tap(t, find.byType(Tab).at(2), wait: const Duration(milliseconds: 1200)));

  // interrogation
  Suspect suspect(int i) {
    final all = _full('c027').suspects;
    return all[min(i, all.length - 1)];
  }

  shot('portrait_sheet', () => _Host(open: (c) => showSuspect(c, _full('c008').suspects[4], SuspectMark.none), background: _sceneBackground('hospital')),
      wait: const Duration(milliseconds: 1800));
  shot('portrait_case_suspects', () => const CaseScreen(caseId: 'c008'),
      before: () => _progress['c008'] = {..._freshProgress(), 'attempts': 1, 'attempts_left': 2},
      then: (t) => _tap(t, find.byType(Tab).at(2), wait: const Duration(milliseconds: 1500)));
  shot('suspect_sheet', () => _Host(open: (c) => showSuspect(c, suspect(0), SuspectMark.none), background: _sceneBackground('harbor')),
      wait: const Duration(milliseconds: 1800));
  shot('suspect_sheet_question',
      () => _Host(open: (c) => showSuspect(c, suspect(2), SuspectMark.suspicious), background: _sceneBackground('harbor')),
      wait: const Duration(milliseconds: 1000), then: (t) async {
    final s = suspect(2);
    if (s.questions.length > 1) await _tap(t, find.text(s.questions[1].q), wait: const Duration(milliseconds: 2500));
  });

  // accuse
  Widget accuse() => AccuseScreen(
        caseData: _full('c027'),
        progress: Progress({'attempts': 1, 'attempts_left': 2}),
        marks: {suspect(0).id: SuspectMark.innocent, suspect(2).id: SuspectMark.suspicious},
      );
  Future<void> pick(WidgetTester t) async {
    final c = _full('c027');
    await _tap(t, find.text(suspect(2).name), wait: const Duration(milliseconds: 400));
    await _tap(t, find.text(c.evidence[min(1, c.evidence.length - 1)].title), wait: const Duration(milliseconds: 400));
  }

  shot('accuse', accuse);
  shot('accuse_selected', accuse, size: const Size(390, 1900), then: pick);
  shot('accuse_wrong', accuse,
      size: const Size(390, 1900), before: midCase, then: (t) async {
    await pick(t);
    await _tap(t, find.byIcon(Icons.gavel_rounded), wait: const Duration(milliseconds: 1200));
  });

  // achievements
  shot('achievements', () => const AchievementsScreen(), size: const Size(390, 1700), wait: const Duration(milliseconds: 1400));

  // daily missions
  shot('missions_done', () => Scaffold(
        body: GrainBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MissionsCard(day: MissionsDay(_missionsDay(done: true)), onChanged: (_) {}),
            ),
          ),
        ),
      ));
  shot('chest', () => _Host(open: (c) => showChest(c, 230, 7), background: _sceneBackground('villa_rain')),
      wait: const Duration(milliseconds: 1400));

  // quick riddles
  RiddleDay riddleDay() => RiddleDay(_riddleDay());
  shot('riddles', () => const RiddlesScreen(), wait: const Duration(milliseconds: 1400));
  shot('riddle_play', () => RiddlePlayScreen(item: riddleDay().items[2], day: riddleDay()),
      size: const Size(390, 1500), wait: const Duration(milliseconds: 1400));
  shot('riddle_answered', () => RiddlePlayScreen(item: riddleDay().items[2], day: riddleDay()),
      size: const Size(390, 1900), wait: const Duration(milliseconds: 600), then: (t) async {
    await _tap(t, find.text('الف'), wait: const Duration(milliseconds: 1500));
  });

  // result
  shot('result_solved', () => ResultScreen(caseData: _full('c027'), result: _solvedResult('c027')),
      wait: const Duration(milliseconds: 2600));
  shot('result_solved_full', () => ResultScreen(caseData: _full('c027'), result: _solvedResult('c027')),
      size: const Size(390, 2200), wait: const Duration(milliseconds: 2600));
  shot('result_failed', () => ResultScreen(caseData: _full('c005'), result: _failedResult('c005')),
      wait: const Duration(milliseconds: 2600));
  shot('result_failed_full', () => ResultScreen(caseData: _full('c005'), result: _failedResult('c005')),
      size: const Size(390, 2000), wait: const Duration(milliseconds: 2600));

  // art
  shot('scenes_grid', _scenesGrid, sizeOf: () => _scenesGridSize, wait: const Duration(milliseconds: 2400));
  shot('scenes_large_1', () => _scenesLarge(_sceneHalves[0]),
      sizeOf: () => _scenesLargeSize(_sceneHalves[0].length), wait: const Duration(milliseconds: 2400));
  shot('scenes_large_2', () => _scenesLarge(_sceneHalves[1]),
      sizeOf: () => _scenesLargeSize(_sceneHalves[1].length), wait: const Duration(milliseconds: 2400));
  shot('suspects_sheet', _suspectsSheet, sizeOf: () => _suspectsSheetSize, wait: const Duration(milliseconds: 900));
  shot('suspect_moods', _moodsSheet, size: const Size(390, 760));

  // engagement & money
  shot('engagement_widgets', _engagement, size: const Size(390, 1500), wait: const Duration(milliseconds: 2000));
  shot('need_coins', () => _Host(open: (c) => showNeedCoins(c, 150)));
  shot('streak_insurance_confirm', () => _Host(open: buyStreakInsurance));
  shot('shop', () => const ShopScreen());
  shot('shop_full', () => const ShopScreen(), size: const Size(390, 1400));
  shot('account', () => const AccountScreen());
  shot('account_full', () => const AccountScreen(), size: const Size(390, 2000));
  shot('leaderboard', () => const LeaderboardScreen(), wait: const Duration(milliseconds: 1200));
  shot('inbox', () => _Host(open: showInbox), wait: const Duration(milliseconds: 1200));
}
