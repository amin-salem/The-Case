/// The culprit album (GET /v1/album) and the first guess (GET /v1/cases/{id}/guess). The server decides what is shown:
/// a case the player has not solved arrives without title or culprit, so there is nothing to leak here.
library;

import 'models.dart' show AvatarSpec;

int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
bool _b(Object? v) => v == true;
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) x.cast<String, dynamic>()] : const [];

class AlbumCard {
  AlbumCard(Map<String, dynamic> j)
      : id = _s(j['id']),
        number = _i(j['number']),
        group = _s(j['group']),
        weekend = _b(j['weekend']),
        solved = _b(j['solved']),
        failed = _b(j['failed']),
        stars = _i(j['stars']),
        title = _s(j['title']),
        location = _s(j['location']),
        line = _s(j['line']),
        open = _b(j['open']),
        price = _i(j['price']),
        culpritName = _s((j['culprit'] as Map?)?['name']),
        culpritRole = _s((j['culprit'] as Map?)?['role']),
        culprit = j['culprit'] is Map && (j['culprit'] as Map)['avatar'] is Map
            ? AvatarSpec(((j['culprit'] as Map)['avatar'] as Map).cast<String, dynamic>())
            : null;

  final String id, group, title, location, line, culpritName, culpritRole;
  final int number, stars, price;
  final bool weekend, solved, failed, open;
  final AvatarSpec? culprit;
}

class AlbumGroup {
  AlbumGroup(Map<String, dynamic> j)
      : key = _s(j['key']),
        title = _s(j['title']),
        total = _i(j['total']),
        solved = _i(j['solved']),
        complete = _b(j['complete']);

  final String key, title;
  final int total, solved;
  final bool complete;

  /// The category key when the group is a topic ('medical' ...), '' for a scene group.
  String get category => key.startsWith('cat:') ? key.substring(4) : '';
}

class AlbumReward {
  AlbumReward(Map<String, dynamic> j)
      : id = _s(j['id']),
        title = _s(j['title']),
        need = _i(j['need']),
        owned = _b(j['owned']);

  final String id, title;
  final int need;
  final bool owned;
}

class Album {
  Album(Map<String, dynamic> j)
      : cards = [for (final c in _maps(j['cards'])) AlbumCard(c)],
        groups = [for (final g in _maps(j['groups'])) AlbumGroup(g)],
        rewards = [for (final r in _maps(j['rewards'])) AlbumReward(r)],
        newRewards = [for (final r in _maps(j['new'])) _s(r['title'])],
        groupsDone = _i(j['groups_done']),
        solved = _i(j['solved']),
        total = _i(j['total']);

  final List<AlbumCard> cards;
  final List<AlbumGroup> groups;
  final List<AlbumReward> rewards;
  final List<String> newRewards; // titles of frames unlocked by opening the album just now
  final int groupsDone, solved, total;

  List<AlbumCard> inGroup(String key) => [for (final c in cards) if (c.group == key) c];
}

/// «به نظر تو کیه؟»: the player's first guess ('' / null = none, '?' = «نمی‌دونم») and, once the answer is theirs to see,
/// the crowd's percentages.
class FirstGuess {
  FirstGuess(Map<String, dynamic> j)
      : guess = j['guess'] is String ? j['guess'] as String : null,
        culprit = j['culprit'] is String ? j['culprit'] as String : null,
        correct = j['correct'] is bool ? j['correct'] as bool : null,
        total = j['community'] is Map ? _i((j['community'] as Map)['total']) : 0,
        unknownPct = j['community'] is Map ? _i((j['community'] as Map)['unknown_pct']) : 0,
        suspects = j['community'] is Map
            ? {for (final s in _maps((j['community'] as Map)['suspects'])) _s(s['id']): _i(s['pct'])}
            : const {};

  static const unknown = '?';

  final String? guess, culprit;
  final bool? correct;
  final int total, unknownPct;
  final Map<String, int> suspects; // suspect id -> % of first guesses (empty until the server has enough guesses)

  bool get hasCommunity => suspects.isNotEmpty;
}
