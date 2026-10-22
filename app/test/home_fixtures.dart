import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/main_shell.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> caseRow(String id, int number, String title,
        {bool today = false, bool solved = false, bool failed = false, bool locked = false, int cost = 150, int stars = 0}) =>
    {
      'id': id, 'number': number, 'title': title, 'location': 'بندر انزلی', 'scene': 'harbor', 'category': 'murder',
      'difficulty': 3, 'today': today, 'weekend': false, 'locked': locked, 'unlock_cost': cost, 'solved': solved,
      'failed': failed, 'stars': stars, 'solvers': 12, 'my_rating': 0,
    };

/// Tonight's case state: 'open', 'solved' or 'lost'. [weekend]: null, 'open', 'solved'.
Map<String, dynamic> casesBody({String tonight = 'open', String? weekend, int archiveCount = 4}) {
  final archive = [
    for (int i = 0; i < archiveCount; i++)
      caseRow('a$i', 30 - i, 'پرونده‌ی قدیمی $i', solved: i == 0, stars: i == 0 ? 3 : 0, locked: i != 0),
  ];
  return {
    'today': caseRow('t1', 34, 'ساعت‌شمار موتور',
        today: true, solved: tonight == 'solved', failed: tonight == 'lost', stars: tonight == 'solved' ? 3 : 0,
        locked: tonight == 'lost', cost: 300),
    'next_case_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3 * 3600,
    'archive': archive,
    if (weekend != null) 'weekly': caseRow('w1', 9, 'شب بندر', solved: weekend == 'solved'),
    if (weekend != null) 'weekly_closes_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2 * 86400,
  };
}

Map<String, dynamic> missionsBody({int done = 1}) => {
      'day': '2026-10-22', 'all_done': false, 'claimed': false, 'chest_coins': 40, 'chest_streak': 0,
      'next_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 4 * 3600,
      'missions': [
        for (int i = 0; i < 3; i++)
          {'id': 'm$i', 'title': 'مأموریت ${i + 1}', 'target': 1, 'progress': i < done ? 1 : 0, 'done': i < done},
      ],
    };

Future<void> seedHome({String tonight = 'open', String? weekend, bool online = true, int streak = 4}) async {
  SharedPreferences.setMockInitialValues({'player': 'p', 'secret': 's', 'token': 't',
    'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
  await Api.i.init();
  Api.i.online = online;
  Api.i.profile = Profile({'player_id': 'p', 'nickname': 'آرش', 'coins': 500, 'cases_solved': 5, 'streak': streak, 'secured': true});
  Api.i.httpClient = MockClient((r) async {
    if (r.url.path == '/v1/cases') return jsonResponse(casesBody(tonight: tonight, weekend: weekend));
    if (r.url.path == '/v1/missions') return jsonResponse(missionsBody());
    return jsonResponse({});
  });
  MainShell.weekendOpen.value = false;
  MainShell.tab.value = MainShell.home;
}

/// The whole app frame in RTL at the given text scale.
Widget shellApp({double scale = 1, Key? boundary}) => RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Directionality(textDirection: TextDirection.rtl, child: child!)),
        home: const MainShell(),
      ),
    );

Future<void> pumpApp(WidgetTester t, {double scale = 1, Size size = const Size(360, 740), Key? boundary}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(() async {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
    await t.pumpWidget(const SizedBox());
  });
  await t.pumpWidget(shellApp(scale: scale, boundary: boundary));
  for (int i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}
