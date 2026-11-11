import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_case/services/api.dart';
import 'package:the_case/theme.dart';
import 'package:the_case/widgets/state_view.dart';

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1}) async {
  t.view.physicalSize = const Size(360, 740);
  t.view.devicePixelRatio = 1.0;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(),
    builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: TextDirection.rtl, child: c!)),
    home: Scaffold(body: child),
  ));
  await t.pump(const Duration(milliseconds: 100));
}

/// Every string on screen: no Latin letters and no digits-in-code («http503», «dns»).
List<String> _texts(WidgetTester t) => [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? ''];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Api.i.init();
    Api.i.online = true;
  });

  group('StateView', () {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('offline, error and empty at font $scale: no overflow, a primary button, nothing English', (t) async {
        final views = <Widget>[
          StateView.offline(onRetry: () {}, secondaryLabel: 'یادداشت‌ها', onSecondary: () {}),
          StateView.error(onRetry: () {}),
          StateView.empty(title: 'هنوز پیامی نیومده', body: 'هدیه‌ها این‌جا میان.', primaryLabel: 'برو سراغ پرونده‌ی امشب', onPrimary: () {}),
        ];
        for (final v in views) {
          await _pump(t, v, scale: scale);
          expect(t.takeException(), isNull);
          expect(find.byKey(const ValueKey('state-primary')), findsOneWidget);
          expect(find.byKey(const ValueKey('state-title')), findsOneWidget);
          final r = t.getRect(find.byKey(const ValueKey('state-primary')));
          expect(r.height, greaterThanOrEqualTo(48));
          for (final s in _texts(t)) {
            expect(RegExp('[A-Za-z]').hasMatch(s), isFalse, reason: 'English text on screen: $s');
          }
          // the button can always be reached (the view scrolls when the font is huge)
          await t.ensureVisible(find.byKey(const ValueKey('state-primary')));
          expect(t.takeException(), isNull);
        }
      });
    }

    testWidgets('inside a list (no height given) it takes its own height and does not throw', (t) async {
      await _pump(t, ListView(children: [StateView.error(onRetry: () {})]), scale: 2.0);
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('state-primary')), findsOneWidget);
    });

    testWidgets('the error says coins and progress are safe, with no technical code', (t) async {
      await _pump(t, StateView.error(onRetry: () {}));
      final body = t.widget<Text>(find.byKey(const ValueKey('state-body'))).data!;
      expect(body, contains('سکه'));
      expect(body, contains('پیشرفت'));
      final all = _texts(t).join(' ');
      expect(all, isNot(contains('http')));
      expect(all, isNot(contains('کد خطا')));
    });

    testWidgets('forError: no connection → offline view; server error → error view; the refusal keeps its own sentence', (t) async {
      await _pump(t, StateView.forError(http.ClientException('Failed host lookup'), onRetry: () {}));
      expect(find.text('خط تلفن قطعه'), findsOneWidget);
      Api.i.online = false; // a down server flips the flag too, but it is still an error page, not «offline»
      await _pump(t, StateView.forError(ApiException(503, null), onRetry: () {}));
      expect(find.text('پرونده‌خانه یه لحظه شلوغه'), findsOneWidget);
      await _pump(t, StateView.forError(ApiException(429, {'error': 'rate_limited', 'retry_after': 5}), onRetry: () {}));
      expect(t.widget<Text>(find.byKey(const ValueKey('state-body'))).data, startsWith('کمی صبر کن'));
    });

    testWidgets('the primary button runs the retry once even when tapped twice quickly', (t) async {
      final done = Completer<void>();
      var calls = 0;
      await _pump(t, StateView.error(onRetry: () {
        calls++;
        return done.future;
      }));
      await t.tap(find.byKey(const ValueKey('state-primary')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('state-primary')), warnIfMissed: false);
      await t.pump();
      expect(calls, 1);
      done.complete();
      await t.pump();
      expect(find.byKey(const ValueKey('state-primary')), findsOneWidget);
    });

    testWidgets('offline → online: the view retries by itself, once per return, with no tap', (t) async {
      var retries = 0;
      Api.i.online = false;
      await _pump(t, StateView.offline(onRetry: () => retries++));
      expect(retries, 0);
      // still offline: another notification changes nothing
      await Api.i.closeSecureRow();
      await t.pump();
      expect(retries, 0);
      // the connection returns
      Api.i.online = true;
      await Api.i.closeSecureRow();
      await t.pump();
      expect(retries, 1);
      // staying online does not retry again
      await Api.i.closeSecureRow();
      await t.pump();
      expect(retries, 1);
      // a second outage and return retries again
      Api.i.online = false;
      await Api.i.closeSecureRow();
      Api.i.online = true;
      await Api.i.closeSecureRow();
      await t.pump();
      expect(retries, 2);
    });

    testWidgets('a server error also retries by itself when the line returns', (t) async {
      var retries = 0;
      Api.i.online = false;
      await _pump(t, StateView.error(onRetry: () => retries++));
      Api.i.online = true;
      await Api.i.closeSecureRow();
      await t.pump();
      expect(retries, 1);
    });

    testWidgets('an empty page never retries by itself', (t) async {
      var taps = 0;
      Api.i.online = false;
      await _pump(t, StateView.empty(title: 'خالیه', body: 'چیزی نیست.', primaryLabel: 'برو', onPrimary: () => taps++));
      Api.i.online = true;
      await Api.i.closeSecureRow();
      await t.pump();
      expect(taps, 0);
    });
  });
}
