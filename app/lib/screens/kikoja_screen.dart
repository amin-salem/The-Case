import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/api.dart';
import '../theme.dart';

/// «کی کجا؟» (Amin, 25 Nov 2026): the small deduction game. The game itself is one page shipped with the app
/// (assets/kikoja/index.html); it never knows an answer. Everything that earns something (today's puzzle, hints, the
/// accusation, coins) is asked from the server through this screen: the page posts `{id, op, body}` on the `KK` channel
/// and this screen answers with `window.__kkReply(id, {ok, data | error})`.
///
/// One screen per level (`easy`, `medium`, `hard`). It closes with `'next'` when the player asks for the next level.
class KikojaScreen extends StatefulWidget {
  const KikojaScreen({super.key, required this.level, this.back = 0});
  final String level;

  /// 0 = today's puzzle, 1.. = a day of the archive.
  final int back;

  @override
  State<KikojaScreen> createState() => _KikojaScreenState();
}

class _KikojaScreenState extends State<KikojaScreen> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(K.night)
      ..setNavigationDelegate(NavigationDelegate(
        // the page is local: nothing else may load inside it
        onNavigationRequest: (r) => r.url.startsWith('file:') || r.url.startsWith('about:') || r.url.startsWith('data:')
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
      ))
      ..addJavaScriptChannel('KK', onMessageReceived: (m) => _onMessage(m.message))
      ..loadFlutterAsset('assets/kikoja/index.html');
  }

  Future<void> _reply(int id, bool ok, Object? payload) async {
    if (id == 0 || !mounted) return;
    final body = jsonEncode(ok ? {'ok': true, 'data': payload} : {'ok': false, 'error': payload});
    try {
      await _web.runJavaScript('window.__kkReply($id, $body)');
    } catch (e) {
      debugPrint('kikoja reply: $e');
    }
  }

  Future<void> _onMessage(String raw) async {
    int id = 0;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      id = (m['id'] as num?)?.toInt() ?? 0;
      final body = (m['body'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
      switch (m['op']) {
        case 'close':
          if (mounted) Navigator.of(context).pop(body['next'] == true ? 'next' : null);
          return;
        case 'share':
          final text = '${body['text'] ?? ''}'.trim();
          if (text.isNotEmpty) await SharePlus.instance.share(ShareParams(text: text.length > 400 ? text.substring(0, 400) : text));
          await _reply(id, true, const <String, dynamic>{});
          return;
        case 'state':
          final s = await Api.i.kikojaLevel(widget.level, back: widget.back);
          if (widget.back == 0) {
            final today = await Api.i.kikojaToday();
            if (today != null) s['levels'] = today['levels'];
          } else {
            final arc = await Api.i.kikojaArchive();
            final days = ((arc?['days'] as List?) ?? const []).cast<Map>();
            final day = days.where((d) => d['back'] == widget.back).firstOrNull;
            if (day != null) s['levels'] = day['levels'];
          }
          await _reply(id, true, s);
          return;
        case 'hint':
        case 'accuse':
        case 'reopen':
          await _reply(id, true, await Api.i.kikojaAction(widget.level, '${m['op']}', body, back: widget.back));
          return;
        default:
          await _reply(id, false, 'bad_op');
      }
    } on ApiException catch (e) {
      await _reply(id, false, e.code);
    } catch (e) {
      debugPrint('kikoja: $e');
      await _reply(id, false, 'error');
    }
  }

  /// The page's own history (intro, game, result...) goes back first; the screen closes from its home.
  Future<void> _back() async {
    bool handled = false;
    try {
      final r = await _web.runJavaScriptReturningResult('window.__kkBack ? window.__kkBack() : false');
      handled = '$r' == 'true';
    } catch (_) {}
    if (!handled && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: K.night,
        body: SafeArea(child: WebViewWidget(controller: _web)),
      ),
    );
  }
}
