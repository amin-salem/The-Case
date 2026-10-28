import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 28 Oct 2026: some phones (Xiaomi, Huawei, some operators) show the app as «offline» while the browser opens the
/// same site. The browser asks a public DNS over HTTPS and the app asks the phone's own DNS (or its IPv6 route), which
/// can answer nothing or a filter page. This client keeps the normal path first and only when the phone's DNS fails
/// (or answers a private/filter address) asks a public DNS over HTTPS and connects to that address. The TLS name stays
/// the real host, so the certificate is still checked. Never changes anything on a phone that already works.
class NetFallback {
  NetFallback._();

  /// What the phone's own DNS says (tests replace it).
  @visibleForTesting
  static Future<List<InternetAddress>> Function(String host) systemLookup = InternetAddress.lookup;

  /// A public DNS over HTTPS lookup (tests replace it). Returns IPv4 addresses, empty on failure.
  @visibleForTesting
  static Future<List<InternetAddress>> Function(String host) dohLookup = _dohLookup;

  static const _kSavedIp = 'net_fallback_ip';
  static final Map<String, (InternetAddress, DateTime)> _cache = {};
  static const cacheMinutes = 10;
  static DateTime Function() now = DateTime.now;

  /// Addresses a filter or a broken DNS hands out instead of the real server.
  static bool isBogus(InternetAddress a) {
    if (a.isLoopback || a.isLinkLocal || a.isMulticast) return true;
    final b = a.rawAddress;
    if (a.type == InternetAddressType.IPv4 && b.length == 4) {
      if (b[0] == 0 || b[0] == 10 || b[0] == 127 || b[0] >= 224) return true;
      if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
      if (b[0] == 192 && b[1] == 168) return true;
      if (b[0] == 100 && b[1] >= 64 && b[1] <= 127) return true;
      if (b[0] == 169 && b[1] == 254) return true;
    }
    if (a.type == InternetAddressType.IPv6 && b.every((x) => x == 0)) return true;
    return false;
  }

  /// Reads the answer of a DNS-over-HTTPS JSON reply: the A records (type 1) that are usable.
  static List<InternetAddress> parseDohAnswer(Object? json) {
    if (json is! Map || json['Answer'] is! List) return const [];
    final out = <InternetAddress>[];
    for (final r in json['Answer'] as List) {
      if (r is! Map || r['type'] != 1) continue;
      final a = InternetAddress.tryParse('${r['data']}');
      if (a != null && a.type == InternetAddressType.IPv4 && !isBogus(a)) out.add(a);
    }
    return out;
  }

  static Future<List<InternetAddress>> _dohLookup(String host) async {
    const endpoints = [
      'https://1.1.1.1/dns-query?name=%H&type=A',
      'https://8.8.8.8/resolve?name=%H&type=A',
    ];
    for (final e in endpoints) {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      try {
        final req = await c.getUrl(Uri.parse(e.replaceFirst('%H', Uri.encodeQueryComponent(host))));
        req.headers.set('accept', 'application/dns-json');
        final res = await req.close().timeout(const Duration(seconds: 5));
        final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 5));
        final found = parseDohAnswer(jsonDecode(text));
        if (found.isNotEmpty) return found;
      } catch (_) {
        // try the next resolver
      } finally {
        c.close(force: true);
      }
    }
    return const [];
  }

  /// Who to connect to for [host]: the host name itself (the phone's DNS works, the normal path) or a public-DNS
  /// address. Falls back to the last address that worked, and in the end to the name (so the usual error shows).
  static Future<Object> target(String host) async {
    try {
      final found = await systemLookup(host).timeout(const Duration(seconds: 5));
      if (found.any((a) => !isBogus(a))) return host;
    } catch (_) {
      // the phone's DNS failed: ask a public one
    }
    final hit = _cache[host];
    if (hit != null && hit.$2.isAfter(now())) return hit.$1;
    try {
      final found = await dohLookup(host);
      if (found.isNotEmpty) {
        _cache[host] = (found.first, now().add(const Duration(minutes: cacheMinutes)));
        await _save(found.first.address);
        debugPrint('NetFallback: $host via public DNS');
        return found.first;
      }
    } catch (_) {}
    final saved = await _saved();
    return saved ?? host;
  }

  static Future<void> _save(String ip) async {
    try {
      (await SharedPreferences.getInstance()).setString(_kSavedIp, ip);
    } catch (_) {}
  }

  static Future<InternetAddress?> _saved() async {
    try {
      final v = (await SharedPreferences.getInstance()).getString(_kSavedIp);
      final a = v == null ? null : InternetAddress.tryParse(v);
      return a == null || isBogus(a) ? null : a;
    } catch (_) {
      return null;
    }
  }

  /// The client the app uses for the server.
  static http.Client client() {
    if (kIsWeb) return http.Client();
    final hc = HttpClient();
    hc.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
      if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);
      return Socket.startConnect(await target(url.host), url.port);
    };
    return IOClient(hc);
  }
}
