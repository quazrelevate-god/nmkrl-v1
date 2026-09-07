import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/citizen_user.dart';

/// Device-local session for the authenticated citizen account.
///
/// Phase-1 identity comes from the backend `users` table (one account per
/// phone number): [saveAccount] persists the server-issued id + name + phone
/// after POST /api/auth/login, and [userId] returns that id so every action
/// (report / upvote / verify / history) belongs to the signed-in account.
class Prefs {
  Prefs(this._prefs);

  final SharedPreferences _prefs;

  static const _authedKey = 'nk_citizen_authed';
  static const _nameKey = 'nk_citizen_name';
  static const _phoneKey = 'nk_citizen_phone';
  static const _accountIdKey = 'nk_account_id';
  static const _legacyUserIdKey = 'fms_user_id';
  static const _citizenNotifCursorKey = 'nk_citizen_notif_cursor';
  static const _pinHashKey = 'nk_citizen_pin_hash';

  String get citizenNotifCursor =>
      _prefs.getString(_citizenNotifCursorKey) ?? '';

  Future<void> setCitizenNotifCursor(String isoTs) =>
      _prefs.setString(_citizenNotifCursorKey, isoTs);

  bool get authed => _prefs.getBool(_authedKey) ?? false;

  /// Cached `sha256("<user_id>:<pin>")` for this account.
  ///
  /// Held locally so the app-open lock works with no network — the phone is
  /// already in the person's hand, and making them wait on a round trip to
  /// open their own app would be the wrong trade. The server holds the same
  /// hash as the source of truth for a reinstall or a second device.
  String get pinHash => _prefs.getString(_pinHashKey) ?? '';

  bool get hasPin => pinHash.isNotEmpty;

  Future<void> setPinHash(String hash) => _prefs.setString(_pinHashKey, hash);

  Future<void> setAuthed(bool v) => _prefs.setBool(_authedKey, v);

  String get citizenName => _prefs.getString(_nameKey) ?? 'Citizen';

  Future<void> setCitizenName(String name) => _prefs.setString(_nameKey, name);

  String get citizenPhone => _prefs.getString(_phoneKey) ?? '';

  /// Server-issued account id, null until the first successful login.
  String? get accountId => _prefs.getString(_accountIdKey);

  /// Persist the authenticated account returned by the backend.
  Future<void> saveAccount(CitizenUser user) async {
    await _prefs.setString(_accountIdKey, user.id);
    await _prefs.setString(_nameKey, user.name);
    await _prefs.setString(_phoneKey, user.phone);
    await _prefs.setBool(_authedKey, true);
  }

  /// Sign out: end the session and drop this account's PIN, so the next
  /// person on this phone cannot unlock into it. Name and phone stay to
  /// prefill the next login.
  Future<void> clearSession() async {
    await _prefs.remove(_pinHashKey);
    await _prefs.setBool(_authedKey, false);
  }

  /// The id every backend action is stamped with — the authenticated
  /// account's id. Falls back to the legacy per-device id only for the brief
  /// unauthenticated window (auth-gated screens never see it).
  String get userId {
    final account = accountId;
    if (account != null && account.isNotEmpty) return account;
    var id = _prefs.getString(_legacyUserIdKey);
    if (id == null || id.isEmpty) {
      final rand = Random();
      String block() =>
          List.generate(6, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[rand.nextInt(36)])
              .join();
      final time36 = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      id = 'user-${block()}${time36.substring(time36.length - 4)}';
      _prefs.setString(_legacyUserIdKey, id);
    }
    return id;
  }
}
