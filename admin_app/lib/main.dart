import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'panel_url.dart';
import 'store.dart';

const _brass = Color(0xFFE0A526);
const _bg = Color(0xFF17181A);
const _window = MethodChannel('app.parvandeh.admin/window');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'پنل پرونده',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _brass, surface: _bg),
        useMaterial3: true,
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const Gate(),
    );
  }
}

/// Start-up order: lock (device lock / fingerprint) -> admin key (asked once) -> the panel.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  final _store = Store();
  final _auth = LocalAuthentication();
  bool _ready = false;
  bool _unlocked = false;
  bool _checking = false;
  String? _key;
  String _server = defaultServer;
  bool _bio = false;
  bool _secure = true;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _boot() async {
    _key = await _store.adminKey();
    _server = await _store.server();
    _secure = await _store.secureScreen();
    var bio = await _store.biometric();
    if (bio == null) {
      // first start: on by default if the phone has any lock
      bio = await _supported();
      await _store.setBiometric(bio);
    }
    _bio = bio;
    await _applySecure(_secure);
    if (!mounted) return;
    setState(() => _ready = true);
    await _unlock();
  }

  Future<bool> _supported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<void> _applySecure(bool on) async {
    try {
      await _window.invokeMethod('setSecure', on);
    } catch (_) {}
  }

  Future<void> _unlock() async {
    if (_checking) return;
    if (!_bio) {
      if (mounted) setState(() => _unlocked = true);
      return;
    }
    _checking = true;
    var ok = false;
    try {
      ok = await _auth.authenticate(
        localizedReason: 'برای باز کردن پنل پرونده هویتت را تأیید کن',
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      ok = false;
    }
    _checking = false;
    if (mounted) setState(() => _unlocked = ok);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _bio && _unlocked) {
      final p = _pausedAt;
      // lock again after one minute in the background
      if (p != null && DateTime.now().difference(p) > const Duration(minutes: 1)) {
        setState(() => _unlocked = false);
        _unlock();
      }
    }
  }

  Future<void> _saveKey(String k) async {
    await _store.setAdminKey(k.trim());
    if (mounted) setState(() => _key = k.trim());
  }

  Future<void> _logout() async {
    await _store.setAdminKey(null);
    if (mounted) setState(() => _key = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_unlocked) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 56, color: _brass),
            const SizedBox(height: 16),
            const Text('پنل پرونده قفل است'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _unlock, child: const Text('باز کردن قفل')),
          ]),
        ),
      );
    }
    if (_key == null) return KeyScreen(onSave: _saveKey);
    return PanelScreen(
      key: ValueKey('$_server|${_key.hashCode}'),
      adminKey: _key!,
      server: _server,
      bio: _bio,
      secure: _secure,
      onServer: (s) async {
        await _store.setServer(s);
        setState(() => _server = normalizeServer(s));
      },
      onBio: (v) async {
        await _store.setBiometric(v);
        setState(() => _bio = v);
      },
      onSecure: (v) async {
        await _store.setSecureScreen(v);
        await _applySecure(v);
        setState(() => _secure = v);
      },
      onLogout: _logout,
      onNewKey: _saveKey,
      canLock: _supported,
    );
  }
}

class KeyScreen extends StatefulWidget {
  const KeyScreen({super.key, required this.onSave, this.message});
  final Future<void> Function(String) onSave;
  final String? message;

  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends State<KeyScreen> {
  final _c = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.search, size: 56, color: _brass),
              const SizedBox(height: 12),
              const Text('پنل پرونده', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, color: _brass)),
              const SizedBox(height: 8),
              Text(widget.message ?? 'کلید ادمین را یک بار وارد کن. فقط روی همین گوشی و در حافظه‌ی امن (Keystore) نگه داشته می‌شود.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: _c,
                obscureText: _hide,
                autocorrect: false,
                enableSuggestions: false,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'ADMIN_API_KEY',
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
                onSubmitted: (_) => _go(),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _go, child: const Text('ذخیره و ورود')),
            ]),
          ),
        ),
      ),
    );
  }

  void _go() {
    final v = _c.text.trim();
    if (v.isNotEmpty) widget.onSave(v);
  }
}

class PanelScreen extends StatefulWidget {
  const PanelScreen({
    super.key,
    required this.adminKey,
    required this.server,
    required this.bio,
    required this.secure,
    required this.onServer,
    required this.onBio,
    required this.onSecure,
    required this.onLogout,
    required this.onNewKey,
    required this.canLock,
  });
  final String adminKey;
  final String server;
  final bool bio;
  final bool secure;
  final Future<void> Function(String) onServer;
  final Future<void> Function(bool) onBio;
  final Future<void> Function(bool) onSecure;
  final Future<void> Function() onLogout;
  final Future<void> Function(String) onNewKey;
  final Future<bool> Function() canLock;

  @override
  State<PanelScreen> createState() => _PanelScreenState();
}

class _PanelScreenState extends State<PanelScreen> {
  late final WebViewController _web;
  bool _offline = false;
  bool _loading = true;
  bool _rejected = false;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    // No JavaScript channel is registered: the page cannot call into the app.
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_bg)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (req) => isAllowedUrl(req.url, widget.server)
            ? NavigationDecision.navigate
            : NavigationDecision.prevent,
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          _checkSignedIn();
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? true) {
            if (mounted) setState(() => _offline = true);
          }
        },
      ));
    _load();
  }

  void _load() {
    setState(() {
      _offline = false;
      _loading = true;
    });
    _loadId++;
    // the key travels in the URL fragment only; the page reads it once and removes it
    _web.loadRequest(panelUri(widget.server, key: widget.adminKey));
  }

  /// If the panel still shows its own key form two seconds after loading, the stored key was refused.
  Future<void> _checkSignedIn() async {
    final id = _loadId;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || id != _loadId || _offline || _rejected) return;
    try {
      final r = await _web.runJavaScriptReturningResult(
          "(function(){var l=document.getElementById('login');return !!l && !l.hidden;})()");
      if ('$r' == 'true' && mounted) {
        _rejected = true;
        _askNewKey('کلید ذخیره‌شده را سرور قبول نکرد. کلید تازه را وارد کن.');
      }
    } catch (_) {}
  }

  Future<void> _askNewKey(String message) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => KeyScreen(
        message: message,
        onSave: (k) async {
          await widget.onNewKey(k);
          if (ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    ));
  }

  Future<void> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    } else {
      await SystemNavigator.pop();
    }
  }

  Future<void> _settings() async {
    final canLock = await widget.canLock();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _SettingsSheet(
        server: widget.server,
        bio: widget.bio,
        secure: widget.secure,
        canLock: canLock,
        onServer: widget.onServer,
        onBio: widget.onBio,
        onSecure: widget.onSecure,
        onLogout: () async {
          Navigator.of(ctx).pop();
          try {
            await _web.clearLocalStorage();
            await _web.clearCache();
            await WebViewCookieManager().clearCookies();
          } catch (_) {}
          await widget.onLogout();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('پنل پرونده', style: TextStyle(color: _brass, fontSize: 18)),
          toolbarHeight: 44,
          backgroundColor: const Color(0xFF202124),
          actions: [
            IconButton(tooltip: 'تازه‌سازی', icon: const Icon(Icons.refresh), onPressed: _load),
            IconButton(tooltip: 'تنظیمات', icon: const Icon(Icons.settings), onPressed: _settings),
          ],
          bottom: _loading && !_offline
              ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
              : null,
        ),
        body: SafeArea(
          child: _offline
              ? _Offline(onRetry: _load)
              : WebViewWidget(controller: _web),
        ),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off, size: 56, color: _brass),
        const SizedBox(height: 16),
        const Text('اتصال برقرار نیست', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 8),
        const Text('اینترنت یا سرور در دسترس نیست.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('تلاش دوباره')),
      ]),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.server,
    required this.bio,
    required this.secure,
    required this.canLock,
    required this.onServer,
    required this.onBio,
    required this.onSecure,
    required this.onLogout,
  });
  final String server;
  final bool bio;
  final bool secure;
  final bool canLock;
  final Future<void> Function(String) onServer;
  final Future<void> Function(bool) onBio;
  final Future<void> Function(bool) onSecure;
  final Future<void> Function() onLogout;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late String _server = widget.server;
  late bool _bio = widget.bio;
  late bool _secure = widget.secure;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('آدرس سرور'),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: _server,
            isExpanded: true,
            items: [
              for (final s in allowedServers)
                DropdownMenuItem(value: s, child: Text(s, textDirection: TextDirection.ltr)),
            ],
            onChanged: (v) async {
              if (v == null) return;
              setState(() => _server = v);
              await widget.onServer(v);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          SwitchListTile(
            title: const Text('قفل هنگام باز کردن برنامه'),
            subtitle: Text(widget.canLock ? 'اثر انگشت یا قفل گوشی' : 'این گوشی قفل صفحه ندارد'),
            value: _bio && widget.canLock,
            onChanged: widget.canLock
                ? (v) async {
                    setState(() => _bio = v);
                    await widget.onBio(v);
                  }
                : null,
          ),
          SwitchListTile(
            title: const Text('مخفی کردن صفحه از اسکرین‌شات و برنامه‌های اخیر'),
            value: _secure,
            onChanged: (v) async {
              setState(() => _secure = v);
              await widget.onSecure(v);
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.logout),
            label: const Text('خروج (پاک کردن کلید از این گوشی)'),
            onPressed: widget.onLogout,
          ),
        ]),
      ),
    );
  }
}
