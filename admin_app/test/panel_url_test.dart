import 'package:admin_panel/panel_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the two known servers are accepted, anything else falls back', () {
    expect(normalizeServer('https://gaamly.ir/'), 'https://gaamly.ir');
    expect(normalizeServer('https://thecase.liara.run'), 'https://thecase.liara.run');
    expect(normalizeServer('http://gaamly.ir'), defaultServer);
    expect(normalizeServer('https://evil.example'), defaultServer);
    expect(normalizeServer(null), defaultServer);
  });

  test('panel address is https on the panel path and the key rides in the fragment', () {
    final u = panelUri('https://gaamly.ir', key: 'abc/DEF+123 x%');
    expect(u.scheme, 'https');
    expect(u.host, 'gaamly.ir');
    expect(u.path, '/admin/ui');
    expect(u.query, isEmpty); // never in the query: that is sent to the server
    expect(u.fragment.startsWith('k='), isTrue);
    expect(Uri.decodeComponent(u.fragment.substring(2)), 'abc/DEF+123 x%');
    expect(panelUri('https://gaamly.ir').hasFragment, isFalse);
    expect(panelUri('http://evil.example', key: 'k').host, 'gaamly.ir');
  });

  test('navigation is allowed only inside the configured host over https', () {
    const s = 'https://gaamly.ir';
    expect(isAllowedUrl('https://gaamly.ir/admin/ui', s), isTrue);
    expect(isAllowedUrl('https://gaamly.ir/admin/api/health2?x=1', s), isTrue);
    expect(isAllowedUrl('https://GAAMLY.ir/admin/ui', s), isTrue);
    expect(isAllowedUrl('http://gaamly.ir/admin/ui', s), isFalse);
    expect(isAllowedUrl('https://thecase.liara.run/admin/ui', s), isFalse);
    expect(isAllowedUrl('https://gaamly.ir.evil.example/', s), isFalse);
    expect(isAllowedUrl('https://evil.example/gaamly.ir', s), isFalse);
    expect(isAllowedUrl('https://gaamly.ir@evil.example/', s), isFalse);
    expect(isAllowedUrl('https://user:pw@gaamly.ir/', s), isFalse);
    expect(isAllowedUrl('https://gaamly.ir:8443/', s), isFalse);
    expect(isAllowedUrl('file:///etc/passwd', s), isFalse);
    expect(isAllowedUrl('javascript:alert(1)', s), isFalse);
    expect(isAllowedUrl('intent://x#Intent;end', s), isFalse);
    expect(isAllowedUrl('not a url', s), isFalse);
    expect(isAllowedUrl('https://thecase.liara.run/admin/ui', 'https://thecase.liara.run'), isTrue);
    expect(isAllowedUrl('https://gaamly.ir/', 'https://evil.example'), isTrue); // unknown server -> default
  });
}
