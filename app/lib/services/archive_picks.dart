import '../models/models.dart';
import '../widgets/category.dart';
import '../theme.dart' show fa;
import '../widgets/rate_card.dart' show faRating;

/// One «پیشنهاد برای تو» pick from `GET /v1/cases/picks`: a case id, one real reason and the real numbers behind it.
/// Everything shown comes from these numbers; a pick with an unknown reason is dropped (an older/newer server).
class ArchivePick {
  ArchivePick._(this.caseId, this.reason, this._j);

  final String caseId;
  final String reason; // easy | popular | taste
  final Map<String, dynamic> _j;

  static const reasons = ['easy', 'popular', 'taste'];

  static ArchivePick? parse(Object? j) {
    if (j is! Map) return null;
    final m = j.cast<String, dynamic>();
    final id = m['case_id'];
    final reason = m['reason'];
    if (id is! String || id.isEmpty || reason is! String || !reasons.contains(reason)) return null;
    return ArchivePick._(id, reason, m);
  }

  /// Parses the answer; never throws. At most three picks, one per case.
  static List<ArchivePick> parseAll(Object? body) {
    final list = body is Map ? body['picks'] : null;
    if (list is! List) return const [];
    final seen = <String>{};
    final out = <ArchivePick>[];
    for (final e in list) {
      final p = parse(e);
      if (p != null && seen.add(p.caseId)) out.add(p);
      if (out.length == 3) break;
    }
    return out;
  }

  int? _n(String k) => _j[k] is num ? (_j[k] as num).round() : null;

  String get label => switch (reason) { 'easy' => 'آسان', 'popular' => 'پرطرفدار', _ => 'سلیقه‌ی تو' };

  /// The one-line reason of the detail card, from the real numbers only (null part = the sentence is shortened, never invented).
  String get explanation {
    switch (reason) {
      case 'easy':
        final rate = _n('solve_rate');
        return rate == null ? 'ساده و سرراسته؛ برای یه شب کم‌وقت.' : 'ساده و سرراسته؛ برای یه شب کم‌وقت. ${fa(rate)}٪ کارآگاه‌ها حلش کردن.';
      case 'popular':
        final avg = _j['rating_avg'] is num ? (_j['rating_avg'] as num).toDouble() : null;
        final count = _n('rating_count');
        final recent = _n('solved_30d');
        if (avg != null && count != null) return 'کارآگاه‌ها بهش میانگین ${faRating(avg)} از ${fa(5)} دادن (${fa(count)} امتیاز).';
        if (recent != null) return 'این ماه ${fa(recent)} کارآگاه حلش کردن؛ از پرطرفدارهای بایگانیه.';
        return 'از پرطرفدارهای بایگانیه.';
      default:
        final cat = categoryName(_j['category'] is String ? _j['category'] as String : '');
        final n = _n('category_solved');
        if (cat.isNotEmpty && n != null) return 'تو ${fa(n)} پرونده‌ی «$cat» حل کردی؛ این یکی از همون جنسه.';
        return 'شبیه پرونده‌هایی که تا حالا حل کردی.';
    }
  }
}

/// The picks that can really be shown: the case is in the archive list, not solved and not lost.
List<({ArchivePick pick, CaseRow row})> showablePicks(List<ArchivePick> picks, List<CaseRow> rows) {
  final byId = {for (final r in rows) r.id: r};
  final out = <({ArchivePick pick, CaseRow row})>[];
  for (final p in picks) {
    final r = byId[p.caseId];
    if (r != null && !r.solved && !r.failed && !r.today) out.add((pick: p, row: r));
  }
  return out;
}
