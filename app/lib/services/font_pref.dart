import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The player's font and text size (profile → «فونت و اندازه‌ی متن»). Saved on the phone.
class FontPref {
  FontPref._();

  /// family name in pubspec → name shown to the player
  static const fonts = {'Vazirmatn': 'وزیرمتن', 'Sahel': 'ساحل', 'Shabnam': 'شبنم', 'Estedad': 'استعداد'};
  static const sizes = [0.9, 1.0, 1.12, 1.25];
  static const sizeNames = ['کوچک', 'معمولی', 'بزرگ', 'خیلی بزرگ'];

  static final ValueNotifier<String> family = ValueNotifier('Vazirmatn');
  static final ValueNotifier<double> scale = ValueNotifier(1.0);

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      final f = p.getString('font');
      if (f != null && fonts.containsKey(f)) family.value = f;
      final s = p.getDouble('font_scale');
      if (s != null && sizes.contains(s)) scale.value = s;
    } catch (_) {}
  }

  static Future<void> setFamily(String f) async {
    if (!fonts.containsKey(f) || f == family.value) return;
    family.value = f;
    try {
      await (await SharedPreferences.getInstance()).setString('font', f);
    } catch (_) {}
  }

  static Future<void> setScale(double s) async {
    if (!sizes.contains(s) || s == scale.value) return;
    scale.value = s;
    try {
      await (await SharedPreferences.getInstance()).setDouble('font_scale', s);
    } catch (_) {}
  }
}

/// Applies the chosen text size, and redraws every screen when the font changes
/// (screens build their text styles when they build, so each one must build again).
class FontScope extends StatefulWidget {
  const FontScope({super.key, required this.child});
  final Widget child;

  @override
  State<FontScope> createState() => _FontScopeState();
}

class _FontScopeState extends State<FontScope> {
  @override
  void initState() {
    super.initState();
    FontPref.family.addListener(_fontChanged);
    FontPref.scale.addListener(_sizeChanged);
  }

  @override
  void dispose() {
    FontPref.family.removeListener(_fontChanged);
    FontPref.scale.removeListener(_sizeChanged);
    super.dispose();
  }

  void _sizeChanged() => setState(() {});

  void _fontChanged() {
    if (!mounted) return;
    void rebuild(Element e) {
      e.markNeedsBuild();
      e.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final system = mq.textScaler.scale(14) / 14;
    return MediaQuery(
      data: mq.copyWith(textScaler: TextScaler.linear(system * FontPref.scale.value)),
      child: widget.child,
    );
  }
}
