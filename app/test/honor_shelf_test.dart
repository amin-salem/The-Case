import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/avatars.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/honor_shelf.dart';

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
      theme: buildTheme(),
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: c!),
      ),
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
    );

Map<String, dynamic> _frame(String id, String title, {bool owned = false, String how = 'goal', int price = 0, String goal = '', int target = 0, int progress = 0}) =>
    {'id': id, 'title': title, 'owned': owned, 'how': how, 'price': price, 'goal': goal, 'target': target, 'progress': progress};

AvatarCatalog _catalog(List<Map<String, dynamic>> frames, {String frame = 'frame_brass'}) =>
    AvatarCatalog({'coins': 100, 'avatar': 'det_01', 'frame': frame, 'avatars': <Object>[], 'frames': frames});

CaseRow _row(int n, {bool solved = true, int stars = 3, String? id}) => CaseRow({
      'id': id ?? 'c$n', 'number': n, 'title': 'پرونده $n', 'solved': solved, 'stars': stars,
    });

CasesList _cases(List<CaseRow> rows) => CasesList({
      'next_case_at': 1800000000,
      'archive': [
        for (final r in rows)
          {'id': r.id, 'number': r.number, 'title': r.title, 'solved': r.solved, 'stars': r.stars}
      ],
    });

Profile _profile({int solved = 47, int best = 62}) =>
    Profile({'player_id': 'p', 'nickname': 'رها', 'cases_solved': solved, 'best_streak': best, 'invite_code': 'AB12CD'});

void main() {
  group('ShelfData (real data only)', () {
    test('owned frames: the equipped one first; next: closest goals, then one cheapest shop frame', () {
      final cat = _catalog([
        _frame('frame_brass', 'برنجی', owned: true, how: 'free'),
        _frame('frame_ember', 'شعله', owned: true),
        _frame('frame_a', 'الف', target: 100, progress: 10, goal: '۱۰۰ شب'),
        _frame('frame_b', 'ب', target: 100, progress: 80, goal: '۱۰۰ پرونده'),
        _frame('frame_c', 'ج', target: 100, progress: 50, goal: '۱۰۰ پلاک'),
        _frame('frame_s1', 'گران', how: 'shop', price: 900),
        _frame('frame_s2', 'ارزان', how: 'shop', price: 300),
      ], frame: 'frame_ember');
      final d = ShelfData.build(profile: _profile(), catalog: cat);
      expect(d.ownedFrames.map((f) => f.id), ['frame_ember', 'frame_brass']);
      expect(d.nextFrames.map((f) => f.id), ['frame_b', 'frame_c', 'frame_s2']);
      expect(d.casesKnown, isFalse);
    });

    test('three-plaque cases: only solved with 3, no duplicates, newest number first', () {
      final d = ShelfData.build(
        profile: _profile(),
        cases: _cases([_row(5), _row(9), _row(7, stars: 2), _row(8, solved: false, stars: 0), _row(5)]),
      );
      expect(d.threePlaque.map((r) => r.number), [9, 5]);
    });

    test('headline: parts without real numbers are left out', () {
      final all = ShelfData.build(profile: _profile(), cases: _cases([_row(1), _row(2)]));
      expect(all.headline, '${fa(47)} پرونده · ${fa(2)} با سه پلاک · بهترین زنجیره ${fa(62)} شب');
      final offline = ShelfData.build(profile: _profile());
      expect(offline.headline, '${fa(47)} پرونده · بهترین زنجیره ${fa(62)} شب');
      final fresh = ShelfData.build(profile: _profile(solved: 0, best: 0), cases: _cases(const []));
      expect(fresh.headline, '');
    });
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    group('HonorShelf at text scale $scale', () {
      testWidgets('empty shelf (0 items): calm lines, nothing broken', (t) async {
        final d = ShelfData.build(profile: _profile(solved: 0, best: 0), catalog: _catalog(const []), cases: _cases(const []));
        await t.pumpWidget(_app(HonorShelf(data: d), scale: scale));
        expect(find.text('قفسه‌ی افتخار'), findsOneWidget);
        expect(find.byKey(const ValueKey('shelf-headline')), findsNothing);
        expect(find.byKey(const ValueKey('shelf-cases-empty')), findsOneWidget);
        expect(find.text('هنوز قابی نیست'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('few items: frames, locked ones show how to get them, three cards, no +N', (t) async {
        var taps = 0;
        final cat = _catalog([
          _frame('frame_brass', 'برنجی', owned: true, how: 'free'),
          _frame('frame_ember', 'شعله', owned: true),
          _frame('frame_v', 'آتشفشان', target: 200, progress: 150, goal: '۲۰۰ شب زنجیره'),
          _frame('frame_s', 'طلایی', how: 'shop', price: 500),
        ]);
        final d = ShelfData.build(profile: _profile(), catalog: cat, cases: _cases([_row(50), _row(62), _row(38)]));
        await t.pumpWidget(_app(HonorShelf(data: d, onFrames: () => taps++), scale: scale));
        expect(find.byKey(const ValueKey('shelf-frame-frame_brass')), findsOneWidget);
        expect(find.byKey(const ValueKey('shelf-frame-frame_ember')), findsOneWidget);
        expect(find.byKey(const ValueKey('shelf-next-frame_v')), findsOneWidget);
        expect(find.text('۲۰۰ شب زنجیره'), findsOneWidget); // the locked frame says how to get it
        expect(find.byKey(const ValueKey('shelf-next-frame_s')), findsOneWidget);
        expect(find.text('فروشگاه'), findsOneWidget); // the shop frame points to the shop
        for (final n in [50, 62, 38]) {
          expect(find.byKey(ValueKey('shelf-case-c$n')), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('shelf-cases-more')), findsNothing);
        await t.tap(find.byKey(const ValueKey('shelf-next-frame_s')));
        expect(taps, 1);
        expect(t.takeException(), isNull);
      });

      testWidgets('many items: two cards and +N, owned frames capped with +N', (t) async {
        final cat = _catalog([for (int i = 0; i < 12; i++) _frame('frame_$i', 'قاب $i', owned: true, how: 'free')]);
        final d = ShelfData.build(profile: _profile(), catalog: cat, cases: _cases([for (int i = 1; i <= 29; i++) _row(i)]));
        await t.pumpWidget(_app(HonorShelf(data: d), scale: scale));
        expect(find.byKey(const ValueKey('shelf-case-c29')), findsOneWidget);
        expect(find.byKey(const ValueKey('shelf-case-c28')), findsOneWidget);
        expect(find.byKey(const ValueKey('shelf-case-c27')), findsNothing);
        expect(find.byKey(const ValueKey('shelf-cases-more')), findsOneWidget);
        expect(find.text('+${fa(27)}'), findsOneWidget);
        expect(find.byKey(const ValueKey('shelf-frames-more')), findsOneWidget);
        expect(find.text('+${fa(12 - HonorShelf.maxOwnedShown)}'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('offline (no catalog, no cases): only the headline, nothing invented', (t) async {
        final d = ShelfData.build(profile: _profile());
        await t.pumpWidget(_app(HonorShelf(data: d), scale: scale));
        expect(find.byKey(const ValueKey('shelf-headline')), findsOneWidget);
        expect(find.text('قاب‌ها'), findsNothing);
        expect(find.text('پرونده‌های سه‌پلاکی'), findsNothing);
        expect(t.takeException(), isNull);
      });
    });
  }

  testWidgets('share text: invite code and link, no case title', (t) async {
    final d = ShelfData.build(profile: _profile(), cases: _cases([_row(50)]));
    final text = shelfShareText(_profile(), d, friendCoins: 100);
    expect(text, contains('AB12CD'));
    expect(text, contains(Api.i.shareUrl));
    expect(text, isNot(contains('پرونده 50')));
  });
}
