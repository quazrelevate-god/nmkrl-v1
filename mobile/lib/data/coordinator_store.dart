import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Coordinator-side persistence (port of the localStorage stores in
/// lib/coordinators.js + CoordinatorProvider):
///   • session (signed-in username)
///   • per-user ownership state (verifiedIds / falsePetitionIds)
///   • shared petition-action log (escalate / transfer / close / false)
///   • shared post+poll feed (drives the 1-post/1-poll daily limits)
class CoordinatorStore {
  CoordinatorStore(this._prefs, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const _sessionKey = 'nk_coord_session';
  static const _actionsKey = 'nk_coord_actions';
  static const _feedKey = 'nk_coord_feed';

  String _todayKey() {
    final d = _now();
    return '${d.year}-${d.month}-${d.day}';
  }

  // ── Session ────────────────────────────────────────────────────────────

  String? get sessionUsername => _prefs.getString(_sessionKey);

  Future<void> saveSession(String username) =>
      _prefs.setString(_sessionKey, username);

  Future<void> clearSession() async {
    await _prefs.remove(_sessionKey);
  }

  // ── Per-user ownership state ───────────────────────────────────────────

  String _stateKey(String username) => 'nk_coord_state_$username';

  Map<String, dynamic> _state(String username) {
    final raw = _prefs.getString(_stateKey(username));
    if (raw == null) return {'verifiedIds': <String>[], 'falsePetitionIds': <String>[]};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {'verifiedIds': <String>[], 'falsePetitionIds': <String>[]};
    }
  }

  Set<String> verifiedIds(String username) =>
      ((_state(username)['verifiedIds'] as List<dynamic>?) ?? const [])
          .map((e) => '$e')
          .toSet();

  Future<void> _saveState(String username, Map<String, dynamic> s) =>
      _prefs.setString(_stateKey(username), jsonEncode(s));

  /// Take ownership of a grievance (Assign).
  Future<void> verify(String username, String issueId) async {
    final s = _state(username);
    final ids = ((s['verifiedIds'] as List<dynamic>?) ?? []).map((e) => '$e').toList();
    if (!ids.contains(issueId)) ids.add(issueId);
    s['verifiedIds'] = ids;
    await _saveState(username, s);
  }

  /// Flag as false: drop ownership, remember the flag.
  Future<void> flagFalse(String username, String issueId) async {
    final s = _state(username);
    final ids = ((s['verifiedIds'] as List<dynamic>?) ?? []).map((e) => '$e').toList()
      ..remove(issueId);
    final falseIds =
        ((s['falsePetitionIds'] as List<dynamic>?) ?? []).map((e) => '$e').toList();
    if (!falseIds.contains(issueId)) falseIds.add(issueId);
    s['verifiedIds'] = ids;
    s['falsePetitionIds'] = falseIds;
    await _saveState(username, s);
  }

  // ── Shared petition-action log ─────────────────────────────────────────

  List<Map<String, dynamic>> actions() {
    final raw = _prefs.getString(_actionsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Latest action per issue (newest first in storage).
  Map<String, String> latestActionKindByIssue() {
    final map = <String, String>{};
    for (final a in actions()) {
      final id = '${a['issueId']}';
      map.putIfAbsent(id, () => '${a['kind']}');
    }
    return map;
  }

  Future<void> addAction({
    required String coordinator,
    required String issueId,
    required String kind,
    Map<String, dynamic> data = const {},
  }) async {
    final list = actions();
    list.insert(0, {
      'issueId': issueId,
      'kind': kind,
      'coordinator': coordinator,
      'timestamp': _now().toIso8601String(),
      'data': data,
    });
    await _prefs.setString(_actionsKey, jsonEncode(list));
  }

  // ── Shared feed (posts + polls) + daily limits ─────────────────────────

  Map<String, dynamic> feed() {
    final raw = _prefs.getString(_feedKey);
    if (raw == null) return {'posts': <dynamic>[], 'polls': <dynamic>[]};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {'posts': <dynamic>[], 'polls': <dynamic>[]};
    }
  }

  bool _hasToday(String listKey, String username) {
    final t = _todayKey();
    return ((feed()[listKey] as List<dynamic>?) ?? const []).any((e) =>
        e is Map && '${e['author']}' == username && '${e['date']}' == t);
  }

  bool canPost(String username) => !_hasToday('posts', username);

  bool canPoll(String username) => !_hasToday('polls', username);

  Future<void> _append(String listKey, Map<String, dynamic> entry) async {
    final f = feed();
    final list = ((f[listKey] as List<dynamic>?) ?? []).toList();
    list.insert(0, entry);
    f[listKey] = list;
    await _prefs.setString(_feedKey, jsonEncode(f));
  }

  /// New posts/polls land as "pending" for admin moderation (mirrors web).
  Future<bool> addPost(String username, Map<String, dynamic> post) async {
    if (!canPost(username)) return false;
    await _append('posts', {
      'id': 'p-${_now().millisecondsSinceEpoch}',
      'author': username,
      'date': _todayKey(),
      'submittedAt': _now().toIso8601String(),
      'status': 'pending',
      ...post,
    });
    return true;
  }

  Future<bool> addPoll(String username, Map<String, dynamic> poll) async {
    if (!canPoll(username)) return false;
    await _append('polls', {
      'id': 'poll-${_now().millisecondsSinceEpoch}',
      'author': username,
      'date': _todayKey(),
      'submittedAt': _now().toIso8601String(),
      'status': 'pending',
      ...poll,
    });
    return true;
  }
}
