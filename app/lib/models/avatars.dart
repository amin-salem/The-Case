/// The avatar and frame catalog from GET /v1/avatars (the server decides what is owned).
library;

int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
bool _b(Object? v) => v == true;

class AvatarItem {
  AvatarItem(Map<String, dynamic> j, {required this.isFrame})
      : id = _s(j['id']),
        title = _s(j['title']),
        story = _s(j['story']),
        rarity = _s(j['rarity'], 'common'),
        how = _s(j['how'], 'free'),
        price = _i(j['price']),
        owned = _b(j['owned']),
        goal = _s(j['goal']),
        target = _i(j['target']),
        progress = _i(j['progress']);

  final String id, title, story, rarity, how, goal; // how: free | goal | shop
  final int price, target, progress;
  final bool owned, isFrame;

  bool get isShop => how == 'shop';
  bool get isGoal => how == 'goal';
  bool get legendary => rarity == 'legendary';
  double get fraction => target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0);
}

class AvatarCatalog {
  AvatarCatalog(Map<String, dynamic> j)
      : coins = _i(j['coins']),
        avatar = _s(j['avatar'], 'det_01'),
        frame = _s(j['frame'], 'frame_brass'),
        avatars = [
          for (final a in (j['avatars'] as List? ?? const []))
            if (a is Map) AvatarItem(a.cast<String, dynamic>(), isFrame: false)
        ],
        frames = [
          for (final a in (j['frames'] as List? ?? const []))
            if (a is Map) AvatarItem(a.cast<String, dynamic>(), isFrame: true)
        ];

  final int coins;
  final String avatar, frame; // equipped
  final List<AvatarItem> avatars, frames;
}
