import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/data/whats_new.dart';
import 'package:the_case/services/whats_new.dart';
import 'package:the_case/widgets/whats_new_ui.dart';

const _list = [
  WhatsNewRelease(54, '۱.۲۶', '2026-10-20', [WhatsNewItem('b', 'ب', WhatsNewTarget.missions)]),
  WhatsNewRelease(53, '۱.۲۵', '2026-10-14', [
    WhatsNewItem('a', 'الف', WhatsNewTarget.weekend, tags: ['t1']),
    WhatsNewItem('c', 'ج', WhatsNewTarget.avatars),
  ]),
];

void main() {
  var clock = DateTime(2026, 10, 14, 12);
  setUp(() {
    clock = DateTime(2026, 10, 14, 12);
    WhatsNew.now = () => clock;
  });

  test('list: newest first, titles for this release, no «نفر»', () {
    expect(kWhatsNew.first.id, 65);
    expect(kWhatsNew.first.items.length, 4);
    for (final r in kWhatsNew) {
      for (final it in r.items) {
        expect(it.title.contains('نفر'), isFalse);
      }
    }
    for (int i = 1; i < kWhatsNew.length; i++) {
      expect(kWhatsNew[i - 1].id > kWhatsNew[i].id, isTrue);
    }
    expect(WhatsNew.i.recent(5).length <= 5, isTrue);
  });

  test('fresh install: nothing is new', () async {
    SharedPreferences.setMockInitialValues({});
    await WhatsNew.i.init(list: _list);
    expect(WhatsNew.i.pending, isFalse);
    expect(WhatsNew.i.tagVisible('t1'), isFalse);
  });

  test('update: banner shows once, closing marks it seen for good', () async {
    SharedPreferences.setMockInitialValues({'player': 'p1', 'wn_seen': 53});
    await WhatsNew.i.init(list: _list);
    expect(WhatsNew.i.pending, isTrue); // 54 not seen yet
    expect(WhatsNew.i.recent(1).single.id, 54);
    await WhatsNew.i.markSeen();
    expect(WhatsNew.i.pending, isFalse);
    await WhatsNew.i.init(list: _list); // next app start
    expect(WhatsNew.i.pending, isFalse);
  });

  test('«بعداً یادم بنداز» hides now and returns at the next start', () async {
    SharedPreferences.setMockInitialValues({'player': 'p1', 'wn_seen': 53});
    await WhatsNew.i.init(list: _list);
    await WhatsNew.i.markSeen();
    await WhatsNew.i.remindLater(53);
    expect(WhatsNew.i.pending, isFalse);
    await WhatsNew.i.init(list: _list);
    expect(WhatsNew.i.pending, isTrue);
  });

  test('tag: visible for 7 days from first sight, gone once opened', () async {
    SharedPreferences.setMockInitialValues({'player': 'p1'});
    await WhatsNew.i.init(list: _list);
    expect(WhatsNew.i.tagVisible('t1'), isTrue);
    clock = clock.add(const Duration(days: 6, hours: 23));
    expect(WhatsNew.i.tagVisible('t1'), isTrue);
    clock = clock.add(const Duration(hours: 2));
    expect(WhatsNew.i.tagVisible('t1'), isFalse); // expired after 7 days

    clock = DateTime(2026, 10, 14, 12);
    SharedPreferences.setMockInitialValues({'player': 'p1'});
    await WhatsNew.i.init(list: _list);
    await WhatsNew.i.tagOpened('t1');
    expect(WhatsNew.i.tagVisible('t1'), isFalse);
    await WhatsNew.i.init(list: _list); // remembered
    expect(WhatsNew.i.tagVisible('t1'), isFalse);
  });

  testWidgets('banner: one line with the count; × closes it', (tester) async {
    SharedPreferences.setMockInitialValues({'player': 'p1'});
    await WhatsNew.i.init(list: _list);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WhatsNewBanner())));
    expect(find.text('تازه‌ها در این نسخه'), findsOneWidget);
    expect(find.textContaining('تغییر'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text('تازه‌ها در این نسخه'), findsNothing);
    expect(WhatsNew.i.pending, isFalse);
  });
}
