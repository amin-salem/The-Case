import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/screens/case_screen.dart' show SuspectMark;
import 'package:the_case/screens/suspect_sheet.dart';
import 'package:the_case/theme.dart';

Suspect _s() => Suspect({
      'id': 's1',
      'name': 'ناصر کیانی',
      'role': 'انباردار',
      'intro': 'انباردار سه‌ساله‌ی شرکت؛ کلید دوم انبار پیش اوست و شب‌ها دیرتر از همه می‌رود.',
      'age': 42,
      'statement': 'ساعت نه و نیم در رو قفل کردم و رفتم.',
      'avatar': <String, dynamic>{'gender': 'm'},
      'questions': [
        {'q': 'کسی تو را موقع رفتن دید؟', 'a': 'نه، کسی نبود.'},
        {'q': 'کلید دوم کجا بود؟', 'a': 'توی کشوی میزم.'},
      ],
    });

Widget _host(double scale, Future<SuspectMark?>? Function(BuildContext) open) => MaterialApp(
      theme: buildTheme(),
      builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: Directionality(textDirection: TextDirection.rtl, child: c!)),
      home: Scaffold(body: Builder(builder: (c) => Center(child: ElevatedButton(onPressed: () => open(c), child: const Text('go'))))),
    );

void main() {
  test('shortFinding keeps at most two distinct sentences', () {
    expect(shortFinding('یک. یک. دو. سه.'), 'یک. دو.');
    expect(shortFinding('  فقط یک جمله  '), 'فقط یک جمله');
    expect(shortFinding(''), '');
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('sheet: portrait frame, one role line, age, marks and findings (font scale $scale)', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      final marks = <SuspectMark>[];
      await t.pumpWidget(_host(scale, (c) => showSuspect(c, _s(), SuspectMark.none, onMark: marks.add, findings: const [
            SuspectFinding('camera', 'ساعت ۲۱:۵۰ به راهرو رفت. ساعت ۲۱:۵۰ به راهرو رفت.'),
            SuspectFinding('fingerprint', 'ردِ انگشتش روی دستگیره‌ی انبار.'),
          ])));
      await t.tap(find.text('go'));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const ValueKey('suspect-portrait-frame')), findsOneWidget);
      expect(find.text('ناصر کیانی'), findsOneWidget);
      expect(find.text('۴۲ ساله'), findsOneWidget);
      expect(find.textContaining('انباردار سه‌ساله'), findsOneWidget);
      expect(find.textContaining('انباردار سه‌ساله‌ی شرکت؛ کلید دوم انبار پیش اوست و شب‌ها دیرتر از همه می‌رود.'), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing); // no «role · age» line any more
      expect(find.text('یافته‌های ابزار', skipOffstage: false), findsOneWidget);
      expect(find.byKey(const ValueKey('suspect-finding-camera'), skipOffstage: false), findsOneWidget);
      expect(find.text('ساعت ۲۱:۵۰ به راهرو رفت.', skipOffstage: false), findsOneWidget); // the repeated sentence is shown once
      // the portrait is on the right of the text when there is room, stacked above it when narrow
      final frame = t.getRect(find.byKey(const ValueKey('suspect-portrait-frame')));
      final name = t.getRect(find.text('ناصر کیانی'));
      if (scale < 1.3) {
        expect(frame.center.dx, greaterThan(name.center.dx));
      } else {
        expect(name.top, greaterThanOrEqualTo(frame.bottom - 1));
      }
      await t.tap(find.byKey(const ValueKey('mark-suspicious')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('mark-suspicious')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('mark-innocent')));
      await t.pump();
      expect(marks, [SuspectMark.suspicious, SuspectMark.none, SuspectMark.innocent]);
      expect(t.takeException(), isNull);
    });
  }
}
