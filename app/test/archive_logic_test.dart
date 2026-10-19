import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/models.dart';
import 'package:the_case/services/archive_logic.dart';

CaseRow _r(int n,
        {double avg = 0,
        int votes = 0,
        int comments = 0,
        int diff = 2,
        String cat = '',
        bool solved = false,
        bool locked = false,
        bool weekend = false,
        int stars = 0,
        int mine = 0,
        String? title,
        String publish = ''}) =>
    CaseRow({
      'id': 'c${n.toString().padLeft(3, '0')}',
      'number': n,
      'title': title ?? 'پرونده $n',
      'location': 'تهران',
      'publish': publish.isEmpty ? '2026-10-${(n % 28 + 1).toString().padLeft(2, '0')}' : publish,
      'rating_avg': avg,
      'rating_count': votes,
      'comment_count': comments,
      'difficulty': diff,
      'category': cat,
      'solved': solved,
      'locked': locked,
      'weekend': weekend,
      'stars': stars,
      'my_rating': mine,
    });

List<int> _nums(List<CaseRow> l) => [for (final r in l) r.number];

void main() {
  group('popular sort (weighted rating)', () {
    test('one 5-star vote does not beat 4.8 from 200 votes', () {
      final rows = [_r(1, avg: 5, votes: 1), _r(2, avg: 4.8, votes: 200)];
      expect(_nums(archiveSorted(rows, ArchiveSort.popular)), [2, 1]);
    });

    test('rated first by weighted rating, then unrated last by case number (newest first)', () {
      final rows = [
        _r(1), // unrated
        _r(2, avg: 3.0, votes: 50),
        _r(3, avg: 4.5, votes: 40),
        _r(4), // unrated
        _r(5, avg: 1.5, votes: 30), // lowest rated must NOT come first
        _r(6, avg: 4.5, votes: 90), // same average, more votes
      ];
      expect(_nums(archiveSorted(rows, ArchiveSort.popular)), [6, 3, 2, 5, 4, 1]);
    });

    test('equal weighted rating: more votes first; then the case number; stable across refreshes', () {
      final rows = [_r(1, avg: 4, votes: 10), _r(2, avg: 4, votes: 10), _r(3, avg: 4, votes: 20)];
      expect(_nums(archiveSorted(rows, ArchiveSort.popular)), [3, 2, 1]);
      expect(_nums(archiveSorted(rows.reversed.toList(), ArchiveSort.popular)), [3, 2, 1]);
    });

    test('nothing rated: order falls back to the case number, no crash on an empty list', () {
      expect(_nums(archiveSorted([_r(1), _r(3), _r(2)], ArchiveSort.popular)), [3, 2, 1]);
      expect(archiveSorted(const [], ArchiveSort.popular), isEmpty);
    });

    test('few votes are pulled toward the modest prior, many votes are not', () {
      expect(weightedRating(_r(1, avg: 5, votes: 1)), closeTo(3.636, 0.001));
      expect(weightedRating(_r(2, avg: 4.8, votes: 200)), closeTo(4.738, 0.001));
    });

    test('does not change the input list', () {
      final rows = [_r(1), _r(2, avg: 4, votes: 5)];
      archiveSorted(rows, ArchiveSort.popular);
      expect(_nums(rows), [1, 2]);
    });
  });

  group('other sorts', () {
    final rows = [
      _r(1, publish: '2026-10-01', comments: 3, diff: 4),
      _r(2, publish: '2026-10-03', comments: 9, diff: 1),
      _r(3, publish: '2026-10-02', comments: 3, diff: 4),
      _r(4, publish: '2026-10-03', comments: 0, diff: 5), // same day as 2: the higher number is newer
    ];
    test('newest / oldest by publish, ties by number', () {
      expect(_nums(archiveSorted(rows, ArchiveSort.newest)), [4, 2, 3, 1]);
      expect(_nums(archiveSorted(rows, ArchiveSort.oldest)), [1, 3, 2, 4]);
    });
    test('most commented, ties newest first', () {
      expect(_nums(archiveSorted(rows, ArchiveSort.commented)), [2, 3, 1, 4]);
    });
    test('easiest / hardest, ties newest first', () {
      expect(_nums(archiveSorted(rows, ArchiveSort.easiest)), [2, 3, 1, 4]);
      expect(_nums(archiveSorted(rows, ArchiveSort.hardest)), [4, 3, 1, 2]);
    });
  });

  group('status filters', () {
    final rows = [
      _r(1, solved: true, stars: 3, mine: 5),
      _r(2, solved: true, stars: 2),
      _r(3, locked: true),
      _r(4),
      _r(5, locked: true, weekend: true),
      _r(6, weekend: true, solved: true, stars: 3),
    ];
    List<int> f(ArchiveFilter x) => _nums(archiveVisible(rows, filter: x));
    test('meaning of every filter', () {
      expect(f(ArchiveFilter.all), [1, 2, 3, 4, 5, 6]);
      expect(f(ArchiveFilter.unsolved), [3, 4, 5]);
      expect(f(ArchiveFilter.solved), [1, 2, 6]);
      expect(f(ArchiveFilter.threeStars), [1, 6]);
      expect(f(ArchiveFilter.open), [1, 2, 4, 6]);
      expect(f(ArchiveFilter.locked), [3, 5]);
      expect(f(ArchiveFilter.weekend), [5, 6]);
      expect(f(ArchiveFilter.unrated), [2, 6]); // solved but I gave no rating
    });
    test('chip counts equal what the filter shows', () {
      final c = archiveFilterCounts(rows);
      for (final x in ArchiveFilter.values) {
        expect(c[x], f(x).length, reason: x.name);
      }
    });
  });

  group('combined filters, topic and search', () {
    final rows = [
      _r(11, cat: 'crime', solved: true, title: 'قتل در اتاق ۳۱۱'),
      _r(12, cat: 'crime', title: 'سرقت از موزه'),
      _r(13, cat: 'art', solved: true, title: 'نقاشی گم‌شده'),
      _r(14, cat: '', locked: true, title: 'كتاب ممنوعه'), // Arabic kaf
    ];
    test('topic + status filter + search work together', () {
      expect(_nums(archiveVisible(rows, category: 'crime', filter: ArchiveFilter.solved)), [11]);
      expect(_nums(archiveVisible(rows, category: 'art', filter: ArchiveFilter.unsolved)), isEmpty);
      expect(_nums(archiveVisible(rows, category: 'crime', query: 'موزه')), [12]);
    });
    test('search ignores digit script, ZWNJ, Arabic letters and word order', () {
      expect(_nums(archiveVisible(rows, query: '311')), [11]);
      expect(_nums(archiveVisible(rows, query: '۳۱۱')), [11]);
      expect(_nums(archiveVisible(rows, query: '٣١١')), [11]);
      expect(_nums(archiveVisible(rows, query: 'نقاشی گمشده')), [13]);
      expect(_nums(archiveVisible(rows, query: 'کتاب')), [14]);
      expect(_nums(archiveVisible(rows, query: '  اتاق   قتل ')), [11]);
      expect(_nums(archiveVisible(rows, query: 'تهران')), [11, 12, 13, 14]); // location
      expect(_nums(archiveVisible(rows, query: 'zzz')), isEmpty);
      expect(_nums(archiveVisible(rows, query: '')), [11, 12, 13, 14]);
    });
    test('topic counts follow the status filter, filter counts follow the topic', () {
      final cc = archiveCategoryCounts(rows, filter: ArchiveFilter.solved);
      expect(cc[''], 2);
      expect(cc['crime'], 1);
      expect(cc['art'], 1);
      final fc = archiveFilterCounts(rows, category: 'crime');
      expect(fc[ArchiveFilter.all], 2);
      expect(fc[ArchiveFilter.solved], 1);
      expect(fc[ArchiveFilter.locked], 0);
    });
    test('empty input gives empty results everywhere', () {
      expect(archiveVisible(const [], filter: ArchiveFilter.locked, query: 'x'), isEmpty);
      expect(archiveFilterCounts(const []).values.every((v) => v == 0), isTrue);
    });
  });
}
