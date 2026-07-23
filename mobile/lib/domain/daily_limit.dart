import 'package:shared_preferences/shared_preferences.dart';

/// Port of lib/dailyLimit.js — tiny per-day fair-use quota ("1 grievance/day",
/// "5 supports/day"). Display-only in the demo: never blocks the action.
/// Resets automatically at midnight (keyed on the local date string).
const kGrievanceLimitKey = 'nk_grievance_quota';
const kSupportLimitKey = 'nk_support_quota';

class DailyState {
  const DailyState({required this.used, required this.remaining, required this.max});

  final int used;
  final int remaining;
  final int max;
}

class DailyLimit {
  DailyLimit(this._prefs, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  String _todayKey() {
    final d = _now();
    return '${d.year}-${d.month}-${d.day}';
  }

  DailyState state(String key, int max) {
    final date = _prefs.getString('$key.date');
    final used = date == _todayKey() ? (_prefs.getInt('$key.used') ?? 0) : 0;
    return DailyState(used: used, remaining: (max - used).clamp(0, max), max: max);
  }

  /// Consume one unit and return the new state (no-op past the limit).
  Future<DailyState> consume(String key, int max) async {
    final s = state(key, max);
    if (s.remaining <= 0) return s;
    final used = s.used + 1;
    await _prefs.setString('$key.date', _todayKey());
    await _prefs.setInt('$key.used', used);
    return DailyState(used: used, remaining: (max - used).clamp(0, max), max: max);
  }
}
