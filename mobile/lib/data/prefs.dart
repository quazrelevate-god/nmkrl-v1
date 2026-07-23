import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local persistence: auth flag, citizen name and the stable per-device
/// user id (ports of localStorage keys nk_citizen_authed / nk_citizen_name /
/// fms_user_id).
class Prefs {
  Prefs(this._prefs);

  final SharedPreferences _prefs;

  static const _authedKey = 'nk_citizen_authed';
  static const _nameKey = 'nk_citizen_name';
  static const _userIdKey = 'fms_user_id';

  bool get authed => _prefs.getBool(_authedKey) ?? false;

  Future<void> setAuthed(bool v) => _prefs.setBool(_authedKey, v);

  String get citizenName => _prefs.getString(_nameKey) ?? 'Citizen';

  Future<void> setCitizenName(String name) => _prefs.setString(_nameKey, name);

  /// Stable per-device user id (`user-<rand36><time36>`, same shape as web).
  String get userId {
    var id = _prefs.getString(_userIdKey);
    if (id == null || id.isEmpty) {
      final rand = Random();
      String block() =>
          List.generate(6, (_) => '0123456789abcdefghijklmnopqrstuvwxyz'[rand.nextInt(36)])
              .join();
      final time36 =
          DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      id = 'user-${block()}${time36.substring(time36.length - 4)}';
      _prefs.setString(_userIdKey, id);
    }
    return id;
  }
}
