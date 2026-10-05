/// Data shapes coming from the server.
library;

int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
bool _b(Object? v) => v == true;
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) x.cast<String, dynamic>()] : const [];

/// How a character looks (the app draws it).
class AvatarSpec {
  AvatarSpec(Map<String, dynamic> j)
      : gender = _s(j['gender'], 'm'),
        age = _s(j['age'], 'mid'),
        skin = _i(j['skin'], 1),
        hair = _s(j['hair'], 'short'),
        hairColor = _s(j['hairColor'], '#2a2a2a'),
        beard = _s(j['beard'], 'none'),
        glasses = _b(j['glasses']),
        outfit = _s(j['outfit'], '#3b4a5e'),
        accessory = _s(j['accessory'], 'none');

  final String gender, age, hair, hairColor, beard, outfit, accessory;
  final int skin;
  final bool glasses;
}

class QA {
  QA(Map<String, dynamic> j)
      : q = _s(j['q']),
        a = _s(j['a']);
  final String q, a;
}

class Suspect {
  Suspect(Map<String, dynamic> j)
      : id = _s(j['id']),
        name = _s(j['name']),
        role = _s(j['role']),
        age = _i(j['age']),
        avatar = AvatarSpec((j['avatar'] as Map?)?.cast<String, dynamic>() ?? const {}),
        motive = _s(j['motive']),
        statement = _s(j['statement']),
        questions = [for (final q in _maps(j['questions'])) QA(q)];

  final String id, name, role, motive, statement;
  final int age;
  final AvatarSpec avatar;
  final List<QA> questions;
}

class Evidence {
  Evidence(Map<String, dynamic> j)
      : id = _s(j['id']),
        type = _s(j['type']),
        title = _s(j['title']),
        text = _s(j['text']);
  final String id, type, title, text;
}

class CaseData {
  CaseData(Map<String, dynamic> j)
      : id = _s(j['id']),
        number = _i(j['number']),
        title = _s(j['title']),
        location = _s(j['location']),
        scene = _s(j['scene']),
        difficulty = _i(j['difficulty'], 2),
        intro = _s(j['intro']),
        suspects = [for (final s in _maps(j['suspects'])) Suspect(s)],
        evidence = [for (final e in _maps(j['evidence'])) Evidence(e)],
        culprit = (j['solution'] as Map?)?['culprit'] as String?,
        proof = [for (final p in ((j['solution'] as Map?)?['proof'] as List? ?? const [])) '$p'],
        explanation = (j['solution'] as Map?)?['explanation'] as String?;

  final String id, title, location, scene, intro;
  final String? culprit, explanation; // only for finished cases
  final List<String> proof;
  final int number, difficulty;
  final List<Suspect> suspects;
  final List<Evidence> evidence;

  Suspect suspect(String id) => suspects.firstWhere((s) => s.id == id, orElse: () => suspects.first);
  Evidence? evidenceById(String id) {
    for (final e in evidence) {
      if (e.id == id) return e;
    }
    return null;
  }
}

class Progress {
  Progress(Map<String, dynamic> j)
      : hints = [for (final h in (j['hints'] as List? ?? const [])) '$h'],
        attempts = _i(j['attempts']),
        attemptsLeft = _i(j['attempts_left'], 3),
        solved = _b(j['solved']),
        failed = _b(j['failed']),
        stars = _i(j['stars']),
        hintCosts = [for (final c in (j['hint_costs'] as List? ?? const [30, 50, 80])) _i(c)];

  final List<String> hints;
  final int attempts, attemptsLeft, stars;
  final bool solved, failed;
  final List<int> hintCosts;

  bool get finished => solved || failed;
  int? get nextHintCost => hints.length < hintCosts.length ? hintCosts[hints.length] : null;
}

class CaseRow {
  CaseRow(Map<String, dynamic> j)
      : id = _s(j['id']),
        number = _i(j['number']),
        title = _s(j['title']),
        location = _s(j['location']),
        scene = _s(j['scene']),
        difficulty = _i(j['difficulty'], 2),
        publish = _s(j['publish']),
        today = _b(j['today']),
        locked = _b(j['locked']),
        unlockCost = _i(j['unlock_cost'], 120),
        solved = _b(j['solved']),
        failed = _b(j['failed']),
        stars = _i(j['stars']),
        solvers = _i(j['solvers']);

  final String id, title, location, scene, publish;
  final int number, difficulty, unlockCost, stars, solvers;
  final bool today, locked, solved, failed;
}

class CasesList {
  CasesList(Map<String, dynamic> j)
      : today = j['today'] is Map ? CaseRow((j['today'] as Map).cast<String, dynamic>()) : null,
        nextCaseAt = DateTime.fromMillisecondsSinceEpoch(_i(j['next_case_at']) * 1000),
        archive = [for (final r in _maps(j['archive'])) CaseRow(r)];
  final CaseRow? today;
  final DateTime nextCaseAt;
  final List<CaseRow> archive;
}

class AccuseResult {
  AccuseResult(Map<String, dynamic> j)
      : result = _s(j['result']),
        attemptsLeft = _i(j['attempts_left']),
        stars = _i(j['stars']),
        reward = _i(j['reward']),
        coins = _i(j['coins']),
        streak = _i(j['streak']),
        explanation = j['explanation'] as String?,
        culprit = j['culprit'] as String?,
        proof = [for (final p in (j['proof'] as List? ?? const [])) '$p'],
        rank = j['rank'] is int ? j['rank'] as int : null,
        progress = j['progress'] is Map ? Progress((j['progress'] as Map).cast<String, dynamic>()) : null,
        seconds = _i(j['seconds']),
        hintsUsed = _i(j['hints_used']),
        freezesUsed = _i(j['freezes_used']),
        badge = j['badge'] is int ? j['badge'] as int : null;

  final String result; // solved | wrong_suspect | wrong_proof | failed
  final int attemptsLeft, stars, reward, coins, streak;
  final int seconds, hintsUsed, freezesUsed;
  final int? badge; // a streak badge (7, 30, 100) reached right now
  final String? explanation, culprit;
  final List<String> proof;
  final int? rank;
  final Progress? progress;
}

class Profile {
  Profile(Map<String, dynamic> j)
      : playerId = _s(j['player_id']),
        nickname = _s(j['nickname']),
        avatar = _i(j['avatar']),
        inviteCode = _s(j['invite_code']),
        referred = _b(j['referred']),
        email = j['email'] as String?,
        secured = _b(j['secured']),
        coins = _i(j['coins']),
        noAds = _b(j['no_ads']),
        vipUntil = j['vip_until'] is int ? j['vip_until'] as int : null,
        streak = _i(j['streak']),
        bestStreak = _i(j['best_streak']),
        casesSolved = _i(j['cases_solved']),
        starsTotal = _i(j['stars_total']),
        loginReward = _i(j['login_reward']),
        loginDay = _i(j['login_day']),
        streakFreezes = _i(j['streak_freezes']);

  final String playerId, nickname, inviteCode;
  final int avatar, coins, streak, bestStreak, casesSolved, starsTotal, loginReward;
  final int loginDay, streakFreezes; // 1..7 in the login calendar; streak insurance held
  final bool referred, secured, noAds;
  final String? email;
  final int? vipUntil;

  bool get vip => vipUntil != null && vipUntil! * 1000 > DateTime.now().millisecondsSinceEpoch;
}

class LeaderRow {
  LeaderRow(Map<String, dynamic> j)
      : rank = _i(j['rank']),
        nickname = _s(j['nickname']),
        avatar = _i(j['avatar']),
        value = _i(j['value']),
        stars = _i(j['stars']),
        me = _b(j['me']);
  final int rank, avatar, value, stars;
  final String nickname;
  final bool me;
}

class Leaderboard {
  Leaderboard(Map<String, dynamic> j)
      : period = _s(j['period']),
        title = _s(j['title']),
        top = [for (final r in _maps(j['top'])) LeaderRow(r)],
        me = j['me'] is Map ? LeaderRow((j['me'] as Map).cast<String, dynamic>()) : null;
  final String period, title;
  final List<LeaderRow> top;
  final LeaderRow? me;
}

class InboxGift {
  InboxGift(Map<String, dynamic> j)
      : id = _s(j['id']),
        title = _s(j['title']),
        message = _s(j['message']),
        coins = [for (final g in _maps(j['grants'])) if (g['type'] == 'coins') _i(g['amount'])]
            .fold(0, (a, b) => a + b);
  final String id, title, message;
  final int coins;
}

/// "What everyone else thought" for a finished case.
class CaseStats {
  CaseStats(Map<String, dynamic> j)
      : players = _i(j['players']),
        solvedPct = _i(j['solved_pct']),
        firstTryPct = _i(j['first_try_pct']),
        culprit = _s(j['culprit']),
        suspects = {for (final s in _maps(j['suspects'])) _s(s['id']): _i(s['pct'])};
  final int players, solvedPct, firstTryPct;
  final String culprit;
  final Map<String, int> suspects; // suspect id -> % of first accusations
}
