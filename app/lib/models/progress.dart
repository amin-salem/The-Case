/// Quick riddles, and what an action earned besides coins (XP, missions, achievements).
library;

int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
bool _b(Object? v) => v == true;

/// What the player just earned (the server says it with each action).
class Gains {
  Gains(Map<String, dynamic>? j)
      : xp = _i(j?['xp']),
        rankUp = j?['rank_up'] is String ? j!['rank_up'] as String : null,
        missionsDone = [for (final m in (j?['missions_done'] as List? ?? const [])) '$m'],
        achievements = [
          for (final a in (j?['achievements'] as List? ?? const []))
            if (a is Map) EarnedAchievement(a.cast<String, dynamic>())
        ];

  final int xp;
  final String? rankUp;
  final List<String> missionsDone;
  final List<EarnedAchievement> achievements;

  bool get isEmpty => rankUp == null && missionsDone.isEmpty && achievements.isEmpty;
}

class EarnedAchievement {
  EarnedAchievement(Map<String, dynamic> j)
      : id = _s(j['id']),
        title = _s(j['title']),
        coins = _i(j['coins']);
  final String id, title;
  final int coins;
}

class RiddleItem {
  RiddleItem(Map<String, dynamic> j)
      : id = _s(j['id']),
        slot = _i(j['slot'], 1),
        title = _s(j['title']),
        scene = _s(j['scene'], 'office'),
        free = _b(j['free']),
        locked = _b(j['locked']),
        answered = _b(j['answered']),
        correct = _b(j['correct']),
        choice = j['choice'] is num ? (j['choice'] as num).toInt() : null,
        text = _s(j['text']),
        clue = _s(j['clue']),
        choices = [for (final c in (j['choices'] as List? ?? const [])) '$c'],
        answer = j['answer'] is num ? (j['answer'] as num).toInt() : null,
        explain = _s(j['explain']);

  final String id, title, scene, text, clue, explain;
  final int slot;
  final bool free, locked, answered, correct;
  final int? choice, answer;
  final List<String> choices;
}

class RiddleDay {
  RiddleDay(Map<String, dynamic> j)
      : day = _s(j['day']),
        items = [for (final x in (j['items'] as List? ?? const [])) if (x is Map) RiddleItem(x.cast<String, dynamic>())],
        unlockCost = _i(j['unlock_cost'], 20),
        reward = _i(j['reward'], 10),
        seconds = _i(j['seconds'], 60),
        nextAt = DateTime.fromMillisecondsSinceEpoch(_i(j['next_at']) * 1000);

  final String day;
  final List<RiddleItem> items;
  final int unlockCost, reward, seconds;
  final DateTime nextAt;

  int get answered => items.where((r) => r.answered).length;
  int get correct => items.where((r) => r.correct).length;

  /// The next riddle worth playing: open and not answered yet.
  RiddleItem? get next => items.where((r) => !r.locked && !r.answered).firstOrNull;
}

class RiddleResult {
  RiddleResult(Map<String, dynamic> j)
      : correct = _b(j['correct']),
        answer = _i(j['answer']),
        explain = _s(j['explain']),
        reward = _i(j['reward']),
        coins = _i(j['coins']),
        item = RiddleItem((j['item'] as Map? ?? const {}).cast<String, dynamic>()),
        gains = Gains((j['gains'] as Map?)?.cast<String, dynamic>());

  final bool correct;
  final int answer, reward, coins;
  final String explain;
  final RiddleItem item;
  final Gains gains;
}

class MissionRow {
  MissionRow(Map<String, dynamic> j)
      : id = _s(j['id']),
        title = _s(j['title']),
        target = _i(j['target'], 1),
        progress = _i(j['progress']),
        done = _b(j['done']);
  final String id, title;
  final int target, progress;
  final bool done;
}

class MissionsDay {
  MissionsDay(Map<String, dynamic> j)
      : day = _s(j['day']),
        missions = [for (final x in (j['missions'] as List? ?? const [])) if (x is Map) MissionRow(x.cast<String, dynamic>())],
        allDone = _b(j['all_done']),
        claimed = _b(j['claimed']),
        chestCoins = _i(j['chest_coins']),
        chestStreak = _i(j['chest_streak']),
        nextAt = DateTime.fromMillisecondsSinceEpoch(_i(j['next_at']) * 1000);

  final String day;
  final List<MissionRow> missions;
  final bool allDone, claimed;
  final int chestCoins, chestStreak;
  final DateTime nextAt;

  int get done => missions.where((m) => m.done).length;
}

class AchievementRow {
  AchievementRow(Map<String, dynamic> j)
      : id = _s(j['id']),
        title = _s(j['title']),
        desc = _s(j['desc']),
        group = _s(j['group'], 'cases'),
        target = _i(j['target'], 1),
        progress = _i(j['progress']),
        earned = _b(j['earned']),
        earnedAt = j['earned_at'] is num ? DateTime.fromMillisecondsSinceEpoch((j['earned_at'] as num).toInt() * 1000) : null,
        coins = _i(j['coins']),
        xp = _i(j['xp']);

  final String id, title, desc, group;
  final int target, progress, coins, xp;
  final bool earned;
  final DateTime? earnedAt;
}

class AchievementsList {
  AchievementsList(Map<String, dynamic> j)
      : earned = _i(j['earned']),
        total = _i(j['total']),
        items = [for (final x in (j['items'] as List? ?? const [])) if (x is Map) AchievementRow(x.cast<String, dynamic>())];

  final int earned, total;
  final List<AchievementRow> items;
}
