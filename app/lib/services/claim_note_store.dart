import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// App-private, offline storage, partitioned by account and case. No network or clipboard.
class ClaimNoteStore {
  ClaimNoteStore(this.prefs);
  final SharedPreferences prefs;
  static const _prefix = 'investigation_notes_v1:';
  static const _legacyOwner = 'investigation_legacy_owner_v1';
  String _owner(String owner) => '$_prefix${Uri.encodeComponent(owner)}:';
  String _key(String owner, String caseId) => '${_owner(owner)}${Uri.encodeComponent(caseId)}';

  Future<void> migrateLegacy(String? owner) async {
    if (prefs.containsKey(_legacyOwner)) return;
    // The old app cleared notes on account switches. Bind its surviving legacy notes
    // to the account present at upgrade, never to a subsequently logged-in account.
    if (owner != null && owner.isNotEmpty) {
      for (final k in prefs.getKeys().where((k) => k.startsWith('notes_')).toList()) {
        final raw = prefs.get(k);
        final target = _key(owner, k.substring('notes_'.length));
        if (raw is String && !prefs.containsKey(target)) {
          if (!await prefs.setString(target, raw)) throw StateError('notes_not_saved');
        }
      }
    }
    // Unknown-owner legacy records are preserved but never adopted by a future account.
    if (!await prefs.setString(_legacyOwner, owner ?? '')) throw StateError('notes_not_saved');
  }

  Map<String, dynamic> load(String? owner, String caseId) {
    if (owner == null || owner.isEmpty) return {};
    try {
      final raw = prefs.getString(_key(owner, caseId));
      final value = raw == null ? null : jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) { return {}; }
  }

  Future<void> save(String owner, String caseId, Map<String, dynamic> notes) async {
    if (owner.isEmpty) throw StateError('no_note_owner');
    if (!await prefs.setString(_key(owner, caseId), jsonEncode(notes))) throw StateError('notes_not_saved');
  }

  Future<void> removeAccount(String? owner) async {
    if (owner == null) return;
    for (final k in prefs.getKeys().where((k) => k.startsWith(_owner(owner))).toList()) {
      await prefs.remove(k);
    }
  }
}
