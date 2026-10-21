import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/case_screen.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/chapter_ui.dart';

http.Response response(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> suspect(String id, {int appears = 0}) => {
      'id': id, 'name': 'مظنون $id', 'role': 'نقش', 'intro': 'کسی که اینجاست', 'age': 30, 'avatar': <String, dynamic>{},
      'statement': 'حرف $id', 'appears_chapter': appears, 'questions': <dynamic>[],
    };

Map<String, dynamic> card(String id, int chapter) => {'id': id, 'type': 'document', 'title': 'مدرک $id', 'text': 'متن $id', 'chapter': chapter};

/// A weekend case of 3 chapters, all open: chapter 1 has 2 cards, chapter 2 has NO card but brings the suspect s3,
/// chapter 3 has 2 cards. The extra entries are what a server would never send (chapter 4): they must not leak.
Map<String, dynamic> weekendJson({bool leak = false, int open = 3}) => {
      'id': 'w900', 'number': 900, 'title': 'پرونده‌ی آخر هفته', 'location': 'جایی', 'scene': 'office', 'intro': 'مقدمه',
      'category': '', 'difficulty': 3, 'format': 2,
      'suspects': [suspect('s1'), suspect('s2'), suspect('s3', appears: 1), if (leak) suspect('s9', appears: 3)],
      'evidence': [card('e1', 1), card('e2', 1), card('e3', 3), card('e4', 3), if (leak) card('e9', 4)],
      'motives': [{'id': 'm1', 'text': 'الف'}, {'id': 'm2', 'text': 'ب'}],
      'chapters': [for (int i = 1; i <= open; i++) {'title': 'فصل $i', 'text': 'متن $i'}],
      'chapters_total': 3,
      'next_chapter_at': null,
      'shows_per_chapter': 3,
    };

Map<String, dynamic> nightlyJson() => {
      'id': 'c900', 'number': 900, 'title': 'پرونده‌ی شبانه', 'location': 'جایی', 'scene': 'office', 'intro': 'مقدمه',
      'category': '', 'difficulty': 3,
      'suspects': [suspect('s1'), suspect('s2')],
      'evidence': [{'id': 'e1', 'type': 'document', 'title': 'مدرک e1', 'text': 'متن'}, {'id': 'e2', 'type': 'cctv', 'title': 'مدرک e2', 'text': 'متن'}],
    };

void serve(Map<String, dynamic> caseJson) {
  Api.i.httpClient = MockClient((r) async {
    if (r.url.path == '/v1/cases/${caseJson['id']}') {
      return response({'case': caseJson, 'progress': {'attempts': 1, 'attempts_left': 3}, 'today': false});
    }
    return response({'detail': 'none'}, 404);
  });
}

Future<void> pump(WidgetTester t, [int times = 4]) async {
  for (int i = 0; i < times; i++) {
    await t.pump(const Duration(milliseconds: 400));
  }
}

Future<void> openCase(WidgetTester t, Map<String, dynamic> json) async {
  serve(json);
  t.view.physicalSize = const Size(800, 6000); // tall: every card is built (lists are lazy)
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(theme: buildTheme(), home: CaseScreen(caseId: json['id'] as String)));
  await pump(t);
}

Future<void> goTab(WidgetTester t, String prefix) async {
  await t.tap(find.textContaining(prefix));
  await pump(t);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'player': 'p', 'secret': 's', 'token': 't',
      'token_exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400});
    await Api.i.init();
    Api.i.online = true;
    Api.i.profile = Profile({'player_id': 'p', 'coins': 500, 'cases_solved': 5});
  });

  testWidgets('weekend case: chapter badges, new tags, filter chips (an empty chapter included)', (t) async {
    await openCase(t, weekendJson());
    // the banner of the newest chapter: counts come from the data (2 cards and no suspect in chapter 3)
    expect(find.byKey(const ValueKey('chap-banner')), findsOneWidget);
    expect(find.text('فصل ۳ باز شد: ۲ مدرک تازه'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('chap-banner-close')));
    await pump(t);
    expect(find.byKey(const ValueKey('chap-banner')), findsNothing);

    await goTab(t, 'مدارک (');
    for (final id in ['all', '1', '2', '3']) {
      expect(find.byKey(ValueKey('chap-chip-$id')), findsOneWidget, reason: 'chip $id');
    }
    expect(find.byKey(const ValueKey('chap-chip-4')), findsNothing); // no chapter that is not open
    expect(find.byKey(const ValueKey('chap-e-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chap-e-e3')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-e-e1')), findsNothing); // chapter 1 is not «new»
    expect(find.byKey(const ValueKey('new-e-e3')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-e-e4')), findsOneWidget);
    expect(find.byKey(const ValueKey('chap-new-3')), findsOneWidget); // the count on the chip of chapter 3
    expect(find.byKey(const ValueKey('chap-new-2')), findsNothing);

    // the empty chapter 2: the chips stay, with an empty state
    await t.tap(find.byKey(const ValueKey('chap-chip-2')));
    await pump(t);
    for (final id in ['all', '1', '2', '3']) {
      expect(find.byKey(ValueKey('chap-chip-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('chap-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('chap-e-e1')), findsNothing);

    // chapter 3 only; opening a card removes its «تازه»
    await t.tap(find.byKey(const ValueKey('chap-chip-3')));
    await pump(t);
    expect(find.byKey(const ValueKey('chap-e-e1')), findsNothing);
    expect(find.byKey(const ValueKey('new-e-e3')), findsOneWidget);
    await t.tap(find.text('مدرک e3'));
    await pump(t);
    expect(find.byKey(const ValueKey('new-e-e3')), findsNothing);
    expect(find.byKey(const ValueKey('new-e-e4')), findsOneWidget);
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('chap-chip-3'))).selected, isTrue);

    // «همه» shows everything again
    await t.tap(find.byKey(const ValueKey('chap-chip-all')));
    await pump(t);
    expect(find.byKey(const ValueKey('chap-e-e1')), findsOneWidget);
  });

  testWidgets('weekend case: the newcomer is tagged and listed first until opened, the header counts the new ones', (t) async {
    await openCase(t, weekendJson());
    await t.tap(find.byKey(const ValueKey('chap-banner-close')));
    await pump(t);
    await goTab(t, 'مظنون‌ها (');
    expect(find.byKey(const ValueKey('sus-new-header')), findsOneWidget);
    expect(find.text('۱ مظنون تازه'), findsOneWidget);
    expect(find.text('مظنون تازه · فصل ۲'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-s-s1')), findsNothing);
    // listed first
    final top = t.getTopLeft(find.text('مظنون s3')).dy;
    expect(top < t.getTopLeft(find.text('مظنون s1')).dy, isTrue);
    expect(top < t.getTopLeft(find.text('مظنون s2')).dy, isTrue);
    // open him (the sheet closes with one tap outside), the tag and the header go
    await t.tap(find.text('مظنون s3'));
    await pump(t);
    await t.tapAt(const Offset(4, 4));
    await pump(t);
    expect(find.byKey(const ValueKey('new-s-s3')), findsNothing);
    expect(find.byKey(const ValueKey('sus-new-header')), findsNothing);
  });

  testWidgets('the banner names the chapter, and one tap on it opens that chapter in the evidence list', (t) async {
    await openCase(t, weekendJson());
    expect(find.text('فصل ۳ باز شد: ۲ مدرک تازه'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('chap-banner')));
    await pump(t);
    expect(find.byKey(const ValueKey('chap-banner')), findsNothing);
    expect(t.widget<ChoiceChip>(find.byKey(const ValueKey('chap-chip-3'))).selected, isTrue);
    expect(find.byKey(const ValueKey('chap-e-e3')), findsOneWidget);
    expect(find.byKey(const ValueKey('chap-e-e1')), findsNothing);
  });

  testWidgets('a nightly case looks exactly as before: no badges, no chips, no banner, no tags', (t) async {
    await openCase(t, nightlyJson());
    expect(find.byKey(const ValueKey('chap-banner')), findsNothing);
    await goTab(t, 'مدارک (');
    expect(find.text('مدرک e1'), findsOneWidget);
    expect(find.byKey(const ValueKey('chap-chip-all')), findsNothing);
    expect(find.byKey(const ValueKey('chap-e-e1')), findsNothing);
    expect(find.byKey(const ValueKey('new-e-e1')), findsNothing);
    await goTab(t, 'مظنون‌ها (');
    expect(find.byKey(const ValueKey('sus-new-header')), findsNothing);
    expect(find.textContaining('مظنون تازه'), findsNothing);
  });

  testWidgets('nothing of a chapter that is not open leaks: cards, suspects and chips stop at the open chapters', (t) async {
    await openCase(t, weekendJson(leak: true, open: 2));
    // chapter 3 is closed: its cards (chapter 3 and 4) and the suspect of chapter 4 are not shown
    expect(find.byKey(const ValueKey('chap-banner')), findsOneWidget); // chapter 2 brings the suspect s3
    expect(find.text('فصل ۲ باز شد: ۱ مظنون تازه'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('chap-banner-close')));
    await pump(t);
    await goTab(t, 'مدارک (');
    expect(find.byKey(const ValueKey('chap-chip-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('chap-chip-3')), findsNothing);
    expect(find.byKey(const ValueKey('chap-e-e1')), findsOneWidget);
    for (final id in ['e3', 'e4', 'e9']) {
      expect(find.byKey(ValueKey('chap-e-$id')), findsNothing, reason: id);
    }
    await goTab(t, 'مظنون‌ها (');
    expect(find.text('مظنون s9'), findsNothing);
    expect(find.text('مظنون s3'), findsOneWidget);
  });

  group('chapter helpers', () {
    test('counts, banner text and the chapter of a suspect come from the data', () {
      final c = CaseData(weekendJson());
      expect(isChaptered(c), isTrue);
      expect(openChapters(c), 3);
      expect(suspectChapter(c.suspects.firstWhere((s) => s.id == 's3')), 2);
      expect(chapterBannerText(c, 3), 'فصل ۳ باز شد: ۲ مدرک تازه');
      expect(chapterBannerText(c, 2), 'فصل ۲ باز شد: ۱ مظنون تازه');
      expect(chapterBannerText(c, 1), 'فصل ۱ باز شد: ۲ مدرک و ۲ مظنون تازه');
      expect(isChaptered(CaseData(nightlyJson())), isFalse);
      expect(newEvidence(CaseData(nightlyJson()), ChapterSeen('c900')), isEmpty);
    });

    test('the seen state is remembered per case and a broken store does not throw', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await ChapterSeen.load('w900');
      expect(a.evidence('e3'), isFalse);
      await a.markEvidence('e3');
      await a.markSuspect('s3');
      await a.setBanner(3);
      final b = await ChapterSeen.load('w900');
      expect(b.evidence('e3'), isTrue);
      expect(b.suspect('s3'), isTrue);
      expect(b.bannerChapter, 3);
      final other = await ChapterSeen.load('w901');
      expect(other.evidence('e3'), isFalse);
      final c = CaseData(weekendJson());
      expect(bannerChapter(c, b), isNull); // the banner of chapter 3 was closed
      expect(bannerChapter(c, other), 3);
    });
  });
}
