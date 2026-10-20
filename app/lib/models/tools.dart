/// Detective tools «ابزارهای کارآگاهی» (server: app/tools.py). The server decides every answer; this is only the shape.
library;

int _i(Object? v, [int d = 0]) => v is int ? v : (v is num ? v.toInt() : d);
String _s(Object? v, [String d = '']) => v is String ? v : d;
bool _b(Object? v) => v == true;

class ToolResult {
  ToolResult(Map<String, dynamic> j)
      : text = _s(j['text']),
        card = _s(j['card']),
        suspect = _s(j['suspect']);

  final String text;

  /// magnifier: the evidence card marked «بی‌ربط» ('' for the other tools)
  final String card;
  final String suspect;
}

class ToolInfo {
  ToolInfo(Map<String, dynamic> j)
      : kind = _s(j['kind']),
        title = _s(j['title']),
        desc = _s(j['desc']),
        price = _i(j['price']),
        count = _i(j['count']),
        freeAvailable = _b(j['free_available']),
        available = _b(j['available']),
        used = _b(j['used']),
        usable = _b(j['usable']),
        suspects = j['suspects'] is List ? [for (final x in j['suspects'] as List) '$x'] : null,
        result = j['result'] is Map ? ToolResult((j['result'] as Map).cast<String, dynamic>()) : null;

  final String kind, title, desc;
  final int price;

  /// tools in stock (drops); the free tutorial tool is separate
  final int count;
  final bool freeAvailable;

  /// the case file has what this tool needs
  final bool available;
  final bool used;

  /// can be used on this case right now (case in progress, not used yet)
  final bool usable;

  /// the suspects this tool can look at (null: it needs no suspect)
  final List<String>? suspects;
  final ToolResult? result;

  bool get needsSuspect => suspects != null;

  /// true when one tap uses it (stock or the tutorial tool); false when it has to be bought first.
  bool get hasOne => count > 0 || freeAvailable;
}

class ToolTray {
  ToolTray(Map<String, dynamic> j)
      : enabled = _b(j['enabled']),
        daily = j['daily'] != false,
        message = _s(j['message']),
        coins = _i(j['coins']),
        tools = [
          for (final t in (j['tools'] as List? ?? const []))
            if (t is Map) ToolInfo(t.cast<String, dynamic>())
        ];

  final bool enabled;

  /// false for weekend and story cases (the tray says tools are for daily cases only)
  final bool daily;
  final String message;
  final int coins;
  final List<ToolInfo> tools;

  ToolInfo? byKind(String kind) {
    for (final t in tools) {
      if (t.kind == kind) return t;
    }
    return null;
  }

  /// Evidence ids the magnifier marked as irrelevant.
  Set<String> get irrelevantCards => {
        for (final t in tools)
          if (t.result != null && t.result!.card.isNotEmpty) t.result!.card
      };

  /// Results to show pinned on the case, in tool order.
  List<ToolInfo> get pinned => [
        for (final t in tools)
          if (t.result != null) t
      ];
}

/// What one use/buy call answered.
class ToolOutcome {
  ToolOutcome(Map<String, dynamic> j)
      : consumed = _b(j['consumed']),
        nothingNew = _b(j['nothing_new']),
        text = _s(j['text']),
        result = j['result'] is Map ? ToolResult((j['result'] as Map).cast<String, dynamic>()) : null,
        tray = ToolTray(j);

  final bool consumed, nothingNew;
  final String text;
  final ToolResult? result;
  final ToolTray tray;
}
