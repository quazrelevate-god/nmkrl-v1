import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/coordinator_data.dart';

/// Device-local session for the signed-in coordinator account.
///
/// The full profile (returned by /api/auth/coordinator/login) is cached so
/// the app can re-open without a network round-trip; the constituency stays
/// fixed to that profile.
///
/// The old per-user verifiedIds / falsePetitionIds are gone — those live on
/// the backend now (issues.assigned_coordinator, escalated_at), so partitioning
/// works consistently across coordinators. Notification poll cursor is the
/// only thing kept per-account.
class CoordinatorStore {
  CoordinatorStore(this._prefs);

  final SharedPreferences _prefs;

  static const _profileKey = 'nk_coord_profile';
  static const _notifCursorPrefix = 'nk_coord_notif_cursor_';

  Coordinator? get session {
    final raw = _prefs.getString(_profileKey);
    if (raw == null) return null;
    try {
      return Coordinator.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(Coordinator c) =>
      _prefs.setString(_profileKey, jsonEncode(c.toJson()));

  Future<void> clearSession() => _prefs.remove(_profileKey);

  String? notifCursor(String username) =>
      _prefs.getString('$_notifCursorPrefix$username');

  Future<void> setNotifCursor(String username, String isoTs) =>
      _prefs.setString('$_notifCursorPrefix$username', isoTs);
}
