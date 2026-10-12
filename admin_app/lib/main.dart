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
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: _bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const AdminApp());
}

/// Dark background with a warm brass glow, used by the lock, key and offline screens.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.7, -0.9),
          radius: 1.3,
          colors: [Color(0xFF3A2F12), _bg],
        ),
      ),
      child: SafeArea(child: Center(child: child)),
    );
  }
}

/// The brass magnifier in a glowing round badge.
class _Badge extends StatelessWidget {
  const _Badge({this.icon = Icons.search});
  final IconData icon;
  final double size = 92;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFFF3C964), Color(0xFFB9801A)], begin: Alignment.topRight, end: Alignment.bottomLeft),
        boxShadow: [BoxShadow(color: _brass.withValues(alpha: 0.35), blurRadius: 28, spreadRadius: 2)],
      ),
      child: Icon(icon, size: size * 0.5, color: _bg),
    );
  }
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
        body: _Backdrop(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const _Badge(icon: Icons.lock_outline),
            const SizedBox(height: 22),
            const Text('پنل پرونده', style: TextStyle(fontSize: 24, color: _brass, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('قفل است', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _brass, foregroundColor: _bg, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12)),
              onPressed: _unlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('باز کردن قفل'),
            ),
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
      body: _Backdrop(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Center(child: _Badge()),
              const SizedBox(height: 18),
              const Text('پنل پرونده', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, color: _brass, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(widget.message ?? 'کلید ادمین را یک بار وارد کن. فقط روی همین گوشی و در حافظه‌ی امن (Keystore) نگه داشته می‌شود.',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 18),
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
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _brass, foregroundColor: _bg, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: _go,
                child: const Text('ذخیره و ورود', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ]),
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
  bool _shown = false; // the first page has appeared: the splash is gone for good
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
          if (mounted) {
            setState(() {
              _loading = false;
              _shown = true;
            });
          }
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

  /// Two seconds after loading: is the panel still showing its own key form?
  ///  - the page understands the `#k=` sign-in and still shows the form -> the stored key was refused: ask for a new one;
  ///  - the page is an OLD server version (no `#k=` support, e.g. the new server is not deployed yet) -> do NOT ask for
  ///    the key again (it is already saved); tell the user to type it once in the page or wait for the deploy.
  Future<void> _checkSignedIn() async {
    final id = _loadId;
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || id != _loadId || _offline || _rejected) return;
    try {
      final r = await _web.runJavaScriptReturningResult(
          "(function(){var l=document.getElementById('login');if(!l||l.hidden)return 'ok';"
          "var n=false;for(var i=0;i<document.scripts.length;i++){if(document.scripts[i].text.indexOf('#k=')>=0)n=true;}"
          "return n?'rejected':'old';})()");
      final v = '$r';
      if (!mounted) return;
      if (v.contains('rejected')) {
        _rejected = true;
        _askNewKey('کلید ذخیره‌شده را سرور قبول نکرد. کلید تازه را وارد کن.');
      } else if (v.contains('old')) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(seconds: 8),
          content: Text('نسخه‌ی جدید سرور هنوز روی لیارا نیامده؛ کلید در برنامه ذخیره است. فعلاً یک بار کلید را در همین صفحه وارد کن.'),
        ));
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
          title: const Text('پنل پرونده', style: TextStyle(color: _brass, fontSize: 18, fontWeight: FontWeight.bold)),
          toolbarHeight: 44,
          backgroundColor: Colors.transparent,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF2A2514), Color(0xFF1D1E20)]),
              border: Border(bottom: BorderSide(color: Color(0xFF3D3A2C))),
            ),
          ),
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
              : Stack(children: [
                  WebViewWidget(controller: _web),
                  // branded splash until the first page is ready
                  IgnorePointer(
                    ignoring: _shown,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 350),
                      opacity: _shown ? 0 : 1,
                      child: const _Backdrop(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          _Badge(),
                          SizedBox(height: 22),
                          Text('در حال باز کردن پنل…', style: TextStyle(color: Colors.white70)),
                        ]),
                      ),
                    ),
                  ),
                ]),
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
    return _Backdrop(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const _Badge(icon: Icons.wifi_off),
        const SizedBox(height: 20),
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
