import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/tools.dart';
import 'package:the_case/widgets/tool_tray.dart';

Map<String, dynamic> _tool(String kind, {int price = 45, int count = 0, bool free = true, bool available = true,
        bool used = false, bool usable = true, Map<String, dynamic>? result, List<String>? suspects}) =>
    {
      'kind': kind, 'title': kind, 'desc': 'd', 'price': price, 'count': count, 'free_available': free,
      'available': available, 'used': used, 'usable': usable, 'suspects': suspects, 'result': result,
    };

Map<String, dynamic> _tray({bool enabled = true, bool daily = true, String? message, List<Map<String, dynamic>>? tools}) => {
      'enabled': enabled, 'daily': daily, 'message': message, 'coins': 100,
      'tools': tools ?? [_tool('magnifier', price: 25), _tool('fingerprint', suspects: ['s1', 's2']), _tool('camera', price: 70)],
    };

Future<void> _pump(WidgetTester t, ToolTray tray, void Function(ToolInfo) onTap) => t.pumpWidget(MaterialApp(
    home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: ToolTrayBar(tray: tray, onTap: onTap)))));

void main() {
  test('model: pinned results, irrelevant cards and who can be looked at', () {
    final tray = ToolTray(_tray(tools: [
      _tool('magnifier', used: true, usable: false, result: {'text': 'بی‌ربطه', 'card': 'e3'}),
      _tool('fingerprint', suspects: ['s1', 's2'], used: true, usable: false, result: {'text': 'نقش داره', 'suspect': 's1'}),
      _tool('camera', available: false),
    ]));
    expect(tray.irrelevantCards, {'e3'});
    expect(tray.pinned.map((t) => t.kind), ['magnifier', 'fingerprint']);
    expect(tray.byKind('fingerprint')!.needsSuspect, isTrue);
    expect(tray.byKind('magnifier')!.needsSuspect, isFalse);
    expect(tray.byKind('camera')!.available, isFalse);
  });

  test('model: an old or odd payload never throws', () {
    final tray = ToolTray({});
    expect(tray.tools, isEmpty);
    expect(tray.daily, isTrue);
    final out = ToolOutcome({'consumed': false, 'nothing_new': true, 'text': 'x'});
    expect(out.nothingNew, isTrue);
    expect(out.result, isNull);
  });

  test('hasOne: stock or the free tutorial tool means one tap uses it', () {
    expect(ToolInfo(_tool('camera', free: true)).hasOne, isTrue);
    expect(ToolInfo(_tool('camera', free: false, count: 2)).hasOne, isTrue);
    expect(ToolInfo(_tool('camera', free: false)).hasOne, isFalse);
  });

  testWidgets('tray: free tool, price, stock and done are labelled; a tap reports the tool', (t) async {
    ToolInfo? tapped;
    await _pump(t, ToolTray(_tray(tools: [
      _tool('magnifier', price: 25, free: false),
      _tool('fingerprint', free: true),
      _tool('camera', price: 70, free: false, count: 2),
    ])), (x) => tapped = x);
    expect(find.text('۲۵ سکه'), findsOneWidget);
    expect(find.text('رایگان'), findsOneWidget);
    expect(find.text('×۲'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('tool-magnifier')));
    expect(tapped?.kind, 'magnifier');
  });

  testWidgets('tray: a used tool says so and an unavailable one is not drawn', (t) async {
    await _pump(t, ToolTray(_tray(tools: [
      _tool('magnifier', available: false),
      _tool('fingerprint', used: true, usable: false, result: {'text': 'x'}),
    ])), (_) {});
    expect(find.byKey(const ValueKey('tool-magnifier')), findsNothing);
    expect(find.text('انجام شد ✓'), findsOneWidget);
  });

  testWidgets('tray: weekend and story cases say tools are for daily cases; a closed switch shows nothing', (t) async {
    await _pump(t, ToolTray(_tray(daily: false, enabled: false, tools: [])), (_) {});
    expect(find.byKey(const ValueKey('tools-daily-only')), findsOneWidget);
    await _pump(t, ToolTray(_tray(enabled: false)), (_) {});
    expect(find.byKey(const ValueKey('tool-fingerprint')), findsNothing);
    expect(find.byKey(const ValueKey('tools-daily-only')), findsNothing);
  });
}
