import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_case/models/claim_notes.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/claim_notes.dart';
import 'claim_notes_test.dart' show sample, linkFor;

Future<void> pump(WidgetTester t) async {
  await t.pump(); await t.pump(const Duration(milliseconds: 500)); await t.pump();
}
final boundary = GlobalKey();
Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('NOTE_PREVIEWS')) return;
  await t.pump(const Duration(milliseconds: 30));
  await t.runAsync(() async {
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('test_previews').create(recursive: true);
    await File('test_previews/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> openEditor(WidgetTester t, {ClaimLink? link, ValueNotifier<bool>? owner, double scale = 1}) async {
  final c = sample();
  await t.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(theme: buildTheme(),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(textDirection: TextDirection.rtl, child: child!)),
    home: Builder(builder: (context) => Scaffold(body: TextButton(onPressed: () async {
      final saved = await showClaimNoteEditor(context, caseData: c, existing: link,
        claim: linkFor(c).claim, evidence: 'e1', ownerChanges: owner, ownerCurrent: () => owner?.value ?? true);
      if (saved != null && context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ثبت شد: ${saved.note}')));
    }, child: const Text('یادداشت تازه')))))));
  await t.tap(find.text('یادداشت تازه')); await pump(t);
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('NOTE_PREVIEWS')) return;
    final loader = FontLoader('Vazirmatn');
    loader.addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
    await loader.load();
  });

  testWidgets('optional editor saves personal text, edits it, and cancels without saving', (t) async {
    await openEditor(t);
    await t.scrollUntilVisible(find.byKey(const ValueKey('note-text')), 200, scrollable: find.byType(Scrollable).last);
    await t.enterText(find.byKey(const ValueKey('note-text')), 'ساعت رسید رو بررسی کنم');
    FocusManager.instance.primaryFocus?.unfocus(); await pump(t);
    await t.scrollUntilVisible(find.text('ذخیره‌ی یادداشت'), 150, scrollable: find.byType(Scrollable).last);
    await t.tap(find.text('ذخیره‌ی یادداشت')); await pump(t);
    expect(find.text('ثبت شد: ساعت رسید رو بررسی کنم'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await openEditor(t, link: linkFor(sample(), note: 'یادداشت قبلی'));
    await t.scrollUntilVisible(find.byKey(const ValueKey('note-text')), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('یادداشت قبلی'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('note-text')), 'ویرایش شده');
    FocusManager.instance.primaryFocus?.unfocus(); await pump(t);
    await t.scrollUntilVisible(find.text('انصراف'), 200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.text('انصراف')); await pump(t);
    expect(find.text('ثبت شد: ویرایش شده'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 1.6]) {
    testWidgets('narrow RTL editor remains scrollable and usable at font scale $scale', (t) async {
      t.view.physicalSize = const Size(320, 720); t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize); addTearDown(t.view.resetDevicePixelRatio);
      await openEditor(t, link: linkFor(sample(), note: 'این فقط برداشت شخصی است؛ هنوز باید بررسی کنم.'), scale: scale);
      expect(t.takeException(), isNull);
      await capture(t, 'claim-note-editor-${scale == 1 ? 'normal' : 'large'}');
      await t.scrollUntilVisible(find.text('ذخیره‌ی یادداشت'), 200, scrollable: find.byType(Scrollable).last);
      expect(t.takeException(), isNull);
      await t.tap(find.text('ذخیره‌ی یادداشت')); await pump(t);
      expect(find.textContaining('ثبت شد:'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets('account switching clears the editor and blocks saving to the next account', (t) async {
    final owner = ValueNotifier(true);
    await openEditor(t, link: linkFor(sample(), note: 'متن خصوصی حساب اول'), owner: owner);
    owner.value = false; await pump(t);
    expect(find.text('متن خصوصی حساب اول'), findsNothing);
    expect(find.text('ذخیره‌ی یادداشت'), findsNothing);
    expect(find.textContaining('حساب عوض شده'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); owner.dispose();
  });

  testWidgets('notebook supports empty/missing references, revisiting, editing and removal offline', (t) async {
    var links = [linkFor(sample(), note: 'یادداشت من')];
    var edits = 0;
    await t.pumpWidget(RepaintBoundary(key: boundary, child: MaterialApp(theme: buildTheme(),
      home: StatefulBuilder(builder: (context, update) => Directionality(textDirection: TextDirection.rtl,
        child: Scaffold(body: ListView(children: [ClaimNotesPanel(caseData: sample(), links: links,
          onAdd: () {}, onEdit: (_) => edits++, onRemove: (link) => update(() => links = []))])))))));
    await t.tap(find.textContaining('یادداشت‌های شخصی')); await pump(t);
    await capture(t, 'claim-notebook');
    await t.tap(find.text('رسید')); await pump(t);
    expect(find.text('ساعت هفت ثبت شده.'), findsOneWidget);
    await t.tap(find.text('بستن')); await pump(t);
    await t.tap(find.byTooltip('ویرایش پیوند')); expect(edits, 1);
    await t.tap(find.byTooltip('حذف پیوند')); await pump(t);
    expect(find.text('یادداشت من'), findsNothing);
    expect(find.textContaining('می‌تونی یک حرف مظنون'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final original = linkFor(sample());
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(
      child: ClaimNotesPanel(caseData: sample(answer: 'حرف تازه'), links: [original], onAdd: () {}, onEdit: (_) {}, onRemove: (_) {})))));
    await t.tap(find.textContaining('یادداشت‌های شخصی')); await pump(t);
    expect(find.textContaining('حرف قبلی مظنون تغییر کرده'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
