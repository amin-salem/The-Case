/// Which servers the admin app may show, and how the admin key is passed to the panel page.
/// Pure Dart (no Flutter) so it can be unit tested.
library;

const String defaultServer = 'https://gaamly.ir';

/// The only servers the app can be pointed at. gaamly.ir is the main one; thecase.liara.run is the old fallback.
const List<String> allowedServers = <String>[defaultServer, 'https://thecase.liara.run'];

const String panelPath = '/admin/ui';

/// A saved/typed server value turned into one of [allowedServers] (anything else becomes the default).
String normalizeServer(String? value) {
  final v = (value ?? '').trim().replaceAll(RegExp(r'/+$'), '');
  return allowedServers.contains(v) ? v : defaultServer;
}

/// The panel address. With a [key] it ends in `#k=<key>`: a URL fragment is never sent to the server;
/// the page reads it once, signs in and removes it from the address bar.
Uri panelUri(String server, {String? key}) {
  final base = Uri.parse(normalizeServer(server));
  return Uri(
    scheme: 'https',
    host: base.host,
    path: panelPath,
    fragment: (key == null || key.isEmpty) ? null : 'k=${Uri.encodeComponent(key)}',
  );
}

/// Navigation is allowed ONLY inside the configured host, over https, on the default port, without credentials.
bool isAllowedNavigation(Uri target, String server) {
  final base = Uri.parse(normalizeServer(server));
  return target.scheme == 'https' &&
      target.host.toLowerCase() == base.host &&
      (!target.hasPort || target.port == 443) &&
      target.userInfo.isEmpty;
}

/// Same check for a raw string (the WebView gives urls as text); anything unparsable is refused.
bool isAllowedUrl(String url, String server) {
  final u = Uri.tryParse(url);
  return u != null && isAllowedNavigation(u, server);
}
