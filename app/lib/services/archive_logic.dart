import '../models/models.dart';

/// Status filters of the archive (one at a time). Pure functions: the screen only keeps the choice.
enum ArchiveFilter { all, unsolved, solved, threeStars, open, locked, weekend, unrated }

/// Sort orders of the archive.
enum ArchiveSort { newest, oldest, popular, commented, easiest, hardest }

const archiveFilterLabels = {
  ArchiveFilter.all: 'همه',
  ArchiveFilter.unsolved: 'حل‌نشده',
  ArchiveFilter.solved: 'حل‌شده',
  ArchiveFilter.threeStars: '۳ پلاک',
  ArchiveFilter.open: 'بدون قفل',
  ArchiveFilter.locked: 'قفل‌دار',
  ArchiveFilter.weekend: 'آخر هفته',
  ArchiveFilter.unrated: 'امتیاز ندادم',
};

const archiveSortLabels = {
  ArchiveSort.newest: 'تازه‌ترین',
  ArchiveSort.oldest: 'قدیمی‌ترین',
  ArchiveSort.popular: 'محبوب‌ترین',
  ArchiveSort.commented: 'پرنظرترین',
  ArchiveSort.easiest: 'آسان‌ترین',
  ArchiveSort.hardest: 'سخت‌ترین',
};

/// What each status filter means (also the contract the tests check).
bool archiveFilterKeeps(ArchiveFilter f, CaseRow r) => switch (f) {
      ArchiveFilter.all => true,
      ArchiveFilter.unsolved => !r.solved,
      ArchiveFilter.solved => r.solved,
      ArchiveFilter.threeStars => r.solved && r.stars >= 3,
      ArchiveFilter.open => !r.locked,
      ArchiveFilter.locked => r.locked,
      ArchiveFilter.weekend => r.weekend,
      ArchiveFilter.unrated => r.solved && r.myRating == 0,
    };

/// Lower-case Latin digits, one Persian «ی»/«ک», no ZWNJ, no diacritics: so «۳۱۱», «311» and «٣١١» match alike.
String normalizeSearch(String s) {
  final b = StringBuffer();
  for (final u in s.runes) {
    if (u >= 0x06F0 && u <= 0x06F9) {
      b.writeCharCode(u - 0x06F0 + 48);
    } else if (u >= 0x0660 && u <= 0x0669) {
      b.writeCharCode(u - 0x0660 + 48);
    } else if (u == 0x064A || u == 0x0649) {
      b.writeCharCode(0x06CC);
    } else if (u == 0x0643) {
      b.writeCharCode(0x06A9);
    } else if (u == 0x200C || u == 0x200D || u == 0x200F || u == 0x200E || (u >= 0x064B && u <= 0x065F) || u == 0x0640) {
      continue;
    } else {
      b.write(String.fromCharCode(u));
    }
  }
  return b.toString().toLowerCase().trim();
}

/// Search in title, location and case number. Words are all required (AND); an empty query keeps everything.
bool archiveSearchKeeps(String query, CaseRow r) {
  final q = normalizeSearch(query);
  if (q.isEmpty) return true;
  final hay = normalizeSearch('${r.title} ${r.location} ${r.number}');
  return q.split(RegExp(r'\s+')).every(hay.contains);
}

/// Cases that pass the topic ('' = all), the status filter and the search together.
List<CaseRow> archiveVisible(List<CaseRow> rows, {ArchiveFilter filter = ArchiveFilter.all, String category = '', String query = ''}) =>
    [for (final r in rows) if ((category.isEmpty || r.category == category) && archiveFilterKeeps(filter, r) && archiveSearchKeeps(query, r)) r];

/// Weight of the prior in the weighted rating: a case needs about this many votes before its own average counts as much
/// as the average of all cases.
const double kRatingPriorVotes = 10;

/// The mean rating of all rated cases (the prior), 4.0 when nothing is rated.
double ratingPrior(Iterable<CaseRow> rows) {
  var sum = 0.0, n = 0;
  for (final r in rows) {
    if (r.ratingCount > 0) {
      sum += r.ratingAvg * r.ratingCount;
      n += r.ratingCount;
    }
  }
  return n == 0 ? 4.0 : sum / n;
}

/// Bayesian (weighted) rating: one 5-star vote does not beat 4.8 from 200 votes.
double weightedRating(CaseRow r, double prior) =>
    (kRatingPriorVotes * prior + r.ratingAvg * r.ratingCount) / (kRatingPriorVotes + r.ratingCount);

int _byPublishDesc(CaseRow a, CaseRow b) {
  final c = b.publish.compareTo(a.publish);
  return c != 0 ? c : b.number.compareTo(a.number);
}

/// Sorted copy. Every order ends in the case number, so equal cases never swap places between refreshes.
/// [prior] is the rating prior of the WHOLE archive (so a filter does not change the order of what stays).
List<CaseRow> archiveSorted(List<CaseRow> rows, ArchiveSort sort, {double? prior}) {
  final l = [...rows];
  switch (sort) {
    case ArchiveSort.newest:
      l.sort(_byPublishDesc);
    case ArchiveSort.oldest:
      l.sort((a, b) => _byPublishDesc(b, a));
    case ArchiveSort.popular:
      // rated first by weighted rating (ties: more votes), then by votes; unrated last, newest number first
      final p = prior ?? ratingPrior(rows);
      l.sort((a, b) {
        final ra = a.ratingCount > 0, rb = b.ratingCount > 0;
        if (ra != rb) return ra ? -1 : 1;
        if (ra) {
          var c = weightedRating(b, p).compareTo(weightedRating(a, p));
          if (c == 0) c = b.ratingCount.compareTo(a.ratingCount);
          if (c != 0) return c;
        }
        return b.number.compareTo(a.number);
      });
    case ArchiveSort.commented:
      l.sort((a, b) {
        final c = b.commentCount.compareTo(a.commentCount);
        return c != 0 ? c : _byPublishDesc(a, b);
      });
    case ArchiveSort.easiest:
      l.sort((a, b) {
        final c = a.difficulty.compareTo(b.difficulty);
        return c != 0 ? c : _byPublishDesc(a, b);
      });
    case ArchiveSort.hardest:
      l.sort((a, b) {
        final c = b.difficulty.compareTo(a.difficulty);
        return c != 0 ? c : _byPublishDesc(a, b);
      });
  }
  return l;
}

/// Counts for the chips: how many cases each status filter would show with the current topic and search.
Map<ArchiveFilter, int> archiveFilterCounts(List<CaseRow> rows, {String category = '', String query = ''}) {
  final base = archiveVisible(rows, category: category, query: query);
  return {for (final f in ArchiveFilter.values) f: base.where((r) => archiveFilterKeeps(f, r)).length};
}

/// Counts for the topic chips under the current status filter and search ('' = all topics).
Map<String, int> archiveCategoryCounts(List<CaseRow> rows, {ArchiveFilter filter = ArchiveFilter.all, String query = ''}) {
  final base = archiveVisible(rows, filter: filter, query: query);
  final m = <String, int>{'': base.length};
  for (final r in base) {
    if (r.category.isNotEmpty) m[r.category] = (m[r.category] ?? 0) + 1;
  }
  return m;
}
