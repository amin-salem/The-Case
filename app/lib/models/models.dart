/// Data shapes coming from the server.
library;

import 'progress.dart';
import 'story.dart';

export 'progress.dart' show Gains;

int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
bool _b(Object? v) => v == true;

/// The free portrait for an old numeric avatar (det_01 .. det_10).
String detId(int index) => 'det_${(index % 10 + 1).toString().padLeft(2, '0')}';
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
        accessory = _s(j['accessory'], 'none'),
        portrait = _s(j['portrait']);

  final String gender, age, hair, hairColor, beard, outfit, accessory;

  /// A painted portrait (`assets/portraits/NAME.webp`); empty = drawn in code.
  final String portrait;
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
        intro = _s(j['intro']),
        age = _i(j['age']),
        avatar = AvatarSpec((j['avatar'] as Map?)?.cast<String, dynamic>() ?? const {}),
        motive = _s(j['motive']),
        statement = _s(j['statement']),
        appearsChapter = _i(j['appears_chapter']),
        questions = [for (final q in _maps(j['questions'])) QA(q)];

  /// Weekend format 3: 1 = the newcomer who appears in chapter 2 (night 2); 0 = there from the start.
  final int appearsChapter;
  bool get isNewcomer => appearsChapter >= 1;
  final String id, name, role, motive, statement;
  final String intro; // one neutral line: who this is (empty in an old cached case)
  final int age;
  final AvatarSpec avatar;
  final List<QA> questions;
}

class Evidence {
  Evidence(Map<String, dynamic> j)
      : id = _s(j['id']),
        type = _s(j['type']),
        title = _s(j['title']),
        text = _s(j['text']),
        chapter = _i(j['chapter'], 1);

  /// Which night/chapter the card belongs to (1 = from the start; 2 = arrived with chapter 2).
  final int chapter;
  final String id, type, title, text;
}

/// Format 3, night 1: the question as the case file shows it (the answer is only given by the answer call).
class Night1Info {
  Night1Info(Map<String, dynamic> j)
      : question = _s(j['question'], 'کی دروغ می‌گه؟'),
        open = _b(j['open']),
        reward = _i(j['reward'], 10);
  final String question;
  final bool open; // false once chapter 2 has opened
  final int reward;
}

/// Format 3, night 2 teaser: when chapter 2 opens and how much is new (counts only, no names).
class Night2Info {
  Night2Info(Map<String, dynamic> j)
      : opensAt = j['opens_at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['opens_at'] as num).toInt() * 1000) : null,
        newSuspects = _i(j['new_suspects']),
        newCards = _i(j['new_cards']),
        open = _b(j['open']);
  final DateTime? opensAt;
  final int newSuspects, newCards;
  final bool open;
}

/// The player's answer to the night-1 question, with the reveal.
class Night1Answer {
  Night1Answer(Map<String, dynamic> j)
      : pick = _s(j['pick']),
        ok = _b(j['ok']),
        reward = _i(j['reward']),
        liar = _s(j['liar']),
        card = _s(j['card']),
        explanation = _s(j['explanation']);
  final String pick, liar, card, explanation;
  final bool ok;
  final int reward;
}

class CaseData {
  CaseData(Map<String, dynamic> j)
      : id = _s(j['id']),
        number = _i(j['number']),
        title = _s(j['title']),
        location = _s(j['location']),
        scene = _s(j['scene']),
        category = _s(j['category']),
        difficulty = _i(j['difficulty'], 2),
        intro = _s(j['intro']),
        suspects = [for (final s in _maps(j['suspects'])) Suspect(s)],
        evidence = [for (final e in _maps(j['evidence'])) Evidence(e)],
        culprit = (j['solution'] as Map?)?['culprit'] as String?,
        proof = [for (final p in ((j['solution'] as Map?)?['proof'] as List? ?? const [])) '$p'],
        explanation = (j['solution'] as Map?)?['explanation'] as String?,
        chapters = [for (final c in _maps(j['chapters'])) (title: _s(c['title']), text: _s(c['text']))],
        chaptersTotal = _i(j['chapters_total']),
        nextChapterAt = j['next_chapter_at'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['next_chapter_at'] as num).toInt() * 1000)
            : null,
        motives = [for (final m in _maps(j['motives'])) (id: _s(m['id']), text: _s(m['text']))],
        motive = (j['solution'] as Map?)?['motive'] as String?,
        story = j['story'] is Map ? StoryLines((j['story'] as Map).cast<String, dynamic>()) : null,
        format = _i(j['format']),
        night1 = j['night1'] is Map ? Night1Info((j['night1'] as Map).cast<String, dynamic>()) : null,
        night2 = j['night2'] is Map ? Night2Info((j['night2'] as Map).cast<String, dynamic>()) : null,
        showsPerChapter = _i(j['shows_per_chapter'], 3);

  /// Weekend case format (0/1 old, 2 two-part accusation, 3 two nights).
  final int format;
  bool get twoPart => format == 2 || format == 3;
  bool get twoNights => format == 3;

  /// Format 3: the night-1 question («کی دروغ می‌گه؟») and a teaser of night 2.
  final Night1Info? night1;
  final Night2Info? night2;

  final int showsPerChapter;

  /// A story chapter: ناصری's intro (and, once finished, outro and the season thread). Null for other cases.
  final StoryLines? story;

  /// The weekend case: chapters opened so far (and how many there are), and when the next one opens.
  final List<({String title, String text})> chapters;
  final int chaptersTotal;
  final DateTime? nextChapterAt;

  /// The weekend case also asks why; `motive` is the right one, only for finished cases.
  final List<({String id, String text})> motives;
  final String? motive;
  bool get weekly => motives.isNotEmpty;

  final String id, title, location, scene, intro;
  final String category; // topic key, '' when the case has none (old server)
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

class ShowNote {
  const ShowNote({required this.suspect, required this.evidence, required this.text});
  final String suspect, evidence, text;
}

class Progress {
  Progress(Map<String, dynamic> j)
      : hints = [for (final h in (j['hints'] as List? ?? const [])) '$h'],
        attempts = _i(j['attempts']),
        attemptsLeft = _i(j['attempts_left'], 3),
        solved = _b(j['solved']),
        failed = _b(j['failed']),
        stars = _i(j['stars']),
        hintCosts = [for (final c in (j['hint_costs'] as List? ?? const [30, 50, 80])) _i(c)],
        answerAt = j['answer_at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['answer_at'] as num).toInt() * 1000) : null,
        wrongTries = [
          for (final t in (j['wrong_tries'] as List? ?? const []))
            if (t is Map) WrongTry(t.cast<String, dynamic>())
        ],
        shows = [
          for (final t in (j['shows'] as List? ?? const []))
            if (t is Map) ShowNote(suspect: _s(t['s']), evidence: _s(t['e']), text: _s(t['t']))
        ],
        showsLeft = _i(j['shows_left']),
        night1 = j['night1'] is Map ? Night1Answer((j['night1'] as Map).cast<String, dynamic>()) : null;

  /// Weekend format 3: this player's answer to the night-1 question (null = not answered yet).
  final Night1Answer? night1;

  /// Weekend case: evidence cards this player showed to suspects, with what each suspect said.
  final List<ShowNote> shows;
  final int showsLeft;
  ShowNote? showFor(String suspect, String evidence) {
    for (final s in shows) {
      if (s.suspect == suspect && s.evidence == evidence) return s;
    }
    return null;
  }

  /// This player's wrong accusations on the case, in order (shown in red; reviewed after a solve).
  final List<WrongTry> wrongTries;

  /// A lost case: when its answer becomes public (anti-cheat: nobody reads the answer early). Null = public.
  final DateTime? answerAt;
  bool get answerPending => failed && answerAt != null && answerAt!.isAfter(DateTime.now());

  final List<String> hints;
  final int attempts, attemptsLeft, stars;
  final bool solved, failed;
  final List<int> hintCosts;

  bool get finished => solved || failed;
  int? get nextHintCost => hints.length < hintCosts.length ? hintCosts[hints.length] : null;
}

/// One wrong accusation: who, with which card, why (weekend case) and what was wrong.
class WrongTry {
  WrongTry(Map<String, dynamic> j)
      : suspect = _s(j['s']),
        evidence = _s(j['e']),
        motive = j['m'] as String?,
        kind = _s(j['r']);
  final String suspect, evidence, kind; // kind: wrong_suspect | hasty | wrong_proof | wrong_motive
  final String? motive;
  bool get suspectWrong => kind == 'wrong_suspect' || kind == 'hasty';
  bool get proofWrong => kind == 'wrong_proof';
  bool get motiveWrong => kind == 'wrong_motive';
}

class CaseRow {
  CaseRow(Map<String, dynamic> j)
      : id = _s(j['id']),
        number = _i(j['number']),
        title = _s(j['title']),
        location = _s(j['location']),
        scene = _s(j['scene']),
        category = _s(j['category']),
        difficulty = _i(j['difficulty'], 2),
        publish = _s(j['publish']),
        today = _b(j['today']),
        weekend = _b(j['weekend']),
        locked = _b(j['locked']),
        unlockCost = _i(j['unlock_cost'], 150),
        solved = _b(j['solved']),
        failed = _b(j['failed']),
        stars = _i(j['stars']),
        solvers = _i(j['solvers']),
        ratingAvg = j['rating_avg'] is num ? (j['rating_avg'] as num).toDouble() : 0,
        ratingCount = _i(j['rating_count']),
        commentCount = _i(j['comment_count']),
        myRating = _i(j['my_rating']);

  final String id, title, location, scene, publish;
  final String category; // topic key, '' when unknown
  final int number, difficulty, unlockCost, stars, solvers;
  final double ratingAvg; // average stars of all detectives (0 = nobody rated)
  final int ratingCount, commentCount, myRating;
  final bool today, locked, solved, failed;
  final bool weekend; // an expired weekend case in the archive (higher price)
}

/// The invite card's numbers (all counted by the server).
class ReferralStatus {
  ReferralStatus(Map<String, dynamic> j)
      : referred = _b(j['referred']),
        canRedeem = _b(j['can_redeem']),
        newPlayerReward = _i(j['new_player_reward'], 100),
        inviterReward = _i(j['inviter_reward'], 150),
        needDays = _i(j['need_days'], 3),
        myDays = _i(j['my_days']),
        myInviterPaid = _b(j['my_inviter_paid']),
        invited = _i(j['invited']),
        invitedPaid = _i(j['invited_paid']),
        bestDays = _i(j['best_days']),
        maxPaid = _i(j['max_paid'], 20);

  final bool referred, canRedeem, myInviterPaid;
  final int newPlayerReward, inviterReward, needDays, myDays, invited, invitedPaid, bestDays, maxPaid;
}

class CasesList {
  CasesList(Map<String, dynamic> j)
      : today = j['today'] is Map ? CaseRow((j['today'] as Map).cast<String, dynamic>()) : null,
        nextCaseAt = DateTime.fromMillisecondsSinceEpoch(_i(j['next_case_at']) * 1000),
        archive = [for (final r in _maps(j['archive'])) CaseRow(r)],
        weekly = j['weekly'] is Map ? CaseRow((j['weekly'] as Map).cast<String, dynamic>()) : null,
        weeklyClosesAt = j['weekly_closes_at'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['weekly_closes_at'] as num).toInt() * 1000)
            : null,
        weeklyNextChapterAt = j['weekly_next_chapter_at'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['weekly_next_chapter_at'] as num).toInt() * 1000)
            : null,
        weeklyFormat = _i(j['weekly_format']);
  final DateTime? weeklyNextChapterAt; // when chapter 2 opens (null once open)
  final int weeklyFormat; // 3 = two nights
  final CaseRow? weekly; // this weekend's big case, while it is open
  final DateTime? weeklyClosesAt;
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
        badge = j['badge'] is int ? j['badge'] as int : null,
        answerAt = j['answer_at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['answer_at'] as num).toInt() * 1000) : null,
        unranked = _b(j['unranked']),
        starsCapped = _b(j['stars_capped']),
        earlyBonus = _i(j['early_bonus']),
        howRight = j['how_right'] is bool ? j['how_right'] as bool : null,
        story = j['story'] is Map ? StoryLines((j['story'] as Map).cast<String, dynamic>()) : null,
        gains = Gains((j['gains'] as Map?)?.cast<String, dynamic>());

  final String result; // solved | wrong_suspect | wrong_proof | failed
  final int attemptsLeft, stars, reward, coins, streak;
  final int seconds, hintsUsed, freezesUsed;
  final int? badge; // a streak badge (7, 30, 100) reached right now
  final DateTime? answerAt; // lost: the answer (culprit, proof, explanation) is public from this time
  final int earlyBonus; // weekend case solved before its last chapter: extra coins (already in reward)
  final bool? howRight; // two-part accusation: was the why/how part right (null = not asked)
  final bool unranked, starsCapped; // solved without enough investigation: 1 star, no leaderboard place
  final String? explanation, culprit;
  final List<String> proof;
  final int? rank;
  final Progress? progress;
  final StoryLines? story; // a story chapter: ناصری's outro
  final Gains gains;
}

class Profile {
  Profile(Map<String, dynamic> j)
      : playerId = _s(j['player_id']),
        nickname = _s(j['nickname']),
        avatar = _i(j['avatar']),
        avatarId = _s(j['avatar_id']).isNotEmpty ? _s(j['avatar_id']) : detId(_i(j['avatar'])),
        avatarFrame = _s(j['avatar_frame'], 'frame_brass'),
        inviteCode = _s(j['invite_code']),
        referred = _b(j['referred']),
        email = j['email'] as String?,
        phone = j['phone'] as String?,
        secured = _b(j['secured']),
        needsPhone = _b(j['needs_phone']),
        coins = _i(j['coins']),
        noAds = _b(j['no_ads']),
        vipUntil = j['vip_until'] is int ? j['vip_until'] as int : null,
        streak = _i(j['streak']),
        bestStreak = _i(j['best_streak']),
        casesSolved = _i(j['cases_solved']),
        starsTotal = _i(j['stars_total']),
        loginReward = _i(j['login_reward']),
        loginDay = _i(j['login_day']),
        streakFreezes = _i(j['streak_freezes']),
        xp = _i(j['xp']),
        rank = _i(j['rank']),
        rankTitle = _s(j['rank_title'], 'کارآگاه تازه‌کار'),
        rankXp = _i(j['rank_xp']),
        nextRankXp = j['next_rank_xp'] is num ? (j['next_rank_xp'] as num).toInt() : null,
        nextRankTitle = j['next_rank_title'] as String?,
        achievements = _i(j['achievements']),
        warrants = _i(j['warrants']),
        unread = _i(j['unread']);

  final int unread; // unread items in the messages hub (the bell)
  final int achievements; // earned so far
  final int warrants; // story warrants held

  final int xp, rank, rankXp; // detective rank (index) and the XP where it starts
  final int? nextRankXp; // null at the top rank
  final String rankTitle;
  final String? nextRankTitle;

  /// How far along the way to the next rank (1 at the top).
  double get rankProgress {
    final next = nextRankXp;
    if (next == null || next <= rankXp) return 1;
    return ((xp - rankXp) / (next - rankXp)).clamp(0.0, 1.0);
  }

  final String playerId, nickname, inviteCode;
  final String avatarId, avatarFrame; // det_01, ex_cat ...; frame_brass ...
  final int avatar, coins, streak, bestStreak, casesSolved, starsTotal, loginReward;
  final int loginDay, streakFreezes; // 1..7 in the login calendar; streak insurance held
  final bool referred, secured, noAds, needsPhone;
  final String? email, phone;
  final int? vipUntil;

  bool get vip => vipUntil != null && vipUntil! * 1000 > DateTime.now().millisecondsSinceEpoch;
}

class LeaderRow {
  LeaderRow(Map<String, dynamic> j)
      : rank = _i(j['rank']),
        nickname = _s(j['nickname']),
        avatar = _i(j['avatar']),
        avatarId = _s(j['avatar_id']).isNotEmpty ? _s(j['avatar_id']) : detId(_i(j['avatar'])),
        avatarFrame = _s(j['avatar_frame'], 'frame_brass'),
        value = _i(j['value']),
        stars = _i(j['stars']),
        me = _b(j['me']),
        rankTitle = _s(j['rank_title']);
  final int rank, avatar, value, stars;
  final String nickname, rankTitle, avatarId, avatarFrame;
  final bool me;
}

class Leaderboard {
  Leaderboard(Map<String, dynamic> j)
      : period = _s(j['period']),
        title = _s(j['title']),
        top = [for (final r in _maps(j['top'])) LeaderRow(r)],
        me = j['me'] is Map ? LeaderRow((j['me'] as Map).cast<String, dynamic>()) : null,
        weekEndsAt = j['week_ends_at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['week_ends_at'] as num).toInt() * 1000) : null,
        league = j['league'] is num ? (j['league'] as num).toInt() : null,
        myLeague = j['my_league'] is num ? (j['my_league'] as num).toInt() : null,
        leagues = [for (final l in _maps(j['leagues'])) _s(l['name'])];
  final String period, title;
  final List<LeaderRow> top;
  final LeaderRow? me;
  /// Weekly board: when it closes (the moment the next week's first case opens), from the server's clock.
  final DateTime? weekEndsAt;
  /// Weekly board: the league shown / the player's own league / league names (empty = one board for everybody).
  final int? league, myLeague;
  final List<String> leagues;
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
