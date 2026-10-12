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

// ---------------------------------------------------------------- scenes with choices

/// One option of a scene. A locked one is shown dimmed with [reason]; the server refuses it anyway.
class ChoiceOption {
  ChoiceOption(Map<String, dynamic> j)
      : id = _s(j['id']),
        title = _s(j['title']),
        sub = _s(j['sub']),
        locked = j['locked'] == true,
        reason = _s(j['reason']);
  final String id, title, sub, reason;
  final bool locked;
}

class StoryScene {
  StoryScene(Map<String, dynamic> j)
      : id = _s(j['id']),
        text = _s(j['text']),
        speaker = j['speaker'] as String?,
        ending = j['ending'] == true,
        options = [
          for (final o in (j['options'] as List? ?? const []))
            if (o is Map) ChoiceOption(o.cast<String, dynamic>())
        ];
  final String id, text;
  final String? speaker; // "partner" = the partner's dialogue bubble, null = narration
  final bool ending;
  final List<ChoiceOption> options;

  bool get isPartner => speaker == 'partner';
}

/// A person on the case board. [state]: unmet | neutral | friendly | suspicious.
class BoardPerson {
  BoardPerson(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        role = _s(j['role']),
        state = _s(j['state'], 'unmet'),
        text = _s(j['text']),
        chapter = _i(j['chapter']);
  final String id, name, role, state, text;
  final int chapter;
}

/// A clue on the board. [status]: held | open (not found yet, title hidden) | missed (skipped, shown gray).
class BoardClue {
  BoardClue(Map<String, dynamic> j)
      : id = _s(j['id']),
        title = j['title'] as String?,
        text = j['text'] as String?,
        status = _s(j['status'], 'open'),
        byChoice = j['by_choice'] == true,
        chapter = _i(j['chapter']);
  final String id, status;
  final String? title, text;
  final bool byChoice;
  final int chapter;

  bool get held => status == 'held';
  bool get missed => status == 'missed';
}

class ChapterBoard {
  ChapterBoard(Map<String, dynamic> j)
      : people = [
          for (final p in (j['people'] as List? ?? const []))
            if (p is Map) BoardPerson(p.cast<String, dynamic>())
        ],
        clues = [
          for (final c in (j['clues'] as List? ?? const []))
            if (c is Map) BoardClue(c.cast<String, dynamic>())
        ];
  final List<BoardPerson> people;
  final List<BoardClue> clues;

  int get held => clues.where((c) => c.held).length;
}

/// The player's place in a chapter: GET /v1/story/chapter/{id}/state and the answer of choose.
class ChapterState {
  ChapterState(Map<String, dynamic> j)
      : chapterId = _s(j['chapter_id']),
        chapter = _i(j['chapter'], 1),
        done = j['done'] == true,
        scene = StoryScene(((j['scene'] as Map?) ?? const {}).cast<String, dynamic>()),
        step = _i(j['step'], 1),
        total = _i(j['total'], 1),
        board = ChapterBoard(((j['board'] as Map?) ?? const {}).cast<String, dynamic>());
  final String chapterId;
  final int chapter, step, total;
  final bool done;
  final StoryScene scene;
  final ChapterBoard board;
}

/// GET /v1/story/board: the whole season's people and clues.
class SeasonBoard {
  SeasonBoard(Map<String, dynamic> j)
      : people = [
          for (final p in (j['people'] as List? ?? const []))
            if (p is Map) BoardPerson(p.cast<String, dynamic>())
        ],
        clues = [
          for (final c in (j['clues'] as List? ?? const []))
            if (c is Map) BoardClue(c.cast<String, dynamic>())
        ],
        held = _i(j['held']),
        total = _i(j['total']),
        continueChapter = j['continue_chapter'] is num ? (j['continue_chapter'] as num).toInt() : null;
  final List<BoardPerson> people;
  final List<BoardClue> clues;
  final int held, total;
  final int? continueChapter; // the chapter still in its scenes, null = none
}
