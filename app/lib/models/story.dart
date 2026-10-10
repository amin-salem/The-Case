/// Story mode: the career map and the partner's lines.
library;

int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
DateTime? _t(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

/// ناصری's lines of one chapter. `outro` and `thread` come only once the chapter is finished.
class StoryLines {
  StoryLines(Map<String, dynamic> j)
      : season = _i(j['season'], 1),
        chapter = _i(j['chapter'], 1),
        intro = _s(j['intro']),
        outro = j['outro'] is String ? j['outro'] as String : null,
        thread = j['thread'] is String ? j['thread'] as String : null;
  final int season, chapter;
  final String intro;
  final String? outro, thread;
}

class StoryChapter {
  StoryChapter(Map<String, dynamic> j)
      : id = _s(j['id']),
        chapter = _i(j['chapter'], 1),
        title = j['title'] as String?,
        location = j['location'] as String?,
        scene = j['scene'] as String?,
        state = _s(j['state'], 'locked'),
        solved = j['solved'] == true,
        stars = _i(j['stars']),
        unlockAt = _t(j['unlock_at']),
        skipCost = j['skip_cost'] is num ? (j['skip_cost'] as num).toInt() : null,
        canWarrant = j['can_warrant'] == true;

  final String id, state; // state: done | open | ready | waiting | locked
  final int chapter, stars;
  final String? title, location, scene;
  final bool solved, canWarrant;
  final DateTime? unlockAt;
  final int? skipCost;
}

class StoryMap {
  StoryMap(Map<String, dynamic> j)
      : open = j['open'] == true,
        season = _i(j['season'], 1),
        title = _s(j['title']),
        tagline = _s(j['tagline']),
        partner = _s(j['partner'], 'سرگرد ناصری'),
        warrants = _i(j['warrants']),
        coins = _i(j['coins']),
        freeChapters = _i(j['free_chapters'], 3),
        waitHours = _i(j['wait_hours'], 12),
        nextOpenAt = _t(j['next_open_at']),
        caseId = j['case_id'] as String?,
        chapters = [
          for (final c in (j['chapters'] as List? ?? const []))
            if (c is Map) StoryChapter(c.cast<String, dynamic>())
        ];

  final bool open;
  final int season, warrants, coins, freeChapters, waitHours;
  final String title, tagline, partner;
  final DateTime? nextOpenAt;
  final String? caseId; // set by open / skip
  final List<StoryChapter> chapters;

  int get done => chapters.where((c) => c.state == 'done').length;
}
