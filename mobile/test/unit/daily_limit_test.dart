import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/domain/daily_limit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DailyLimit', () {
    test('starts full, consumes down to zero, then no-ops', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final limit = DailyLimit(prefs, now: () => DateTime(2026, 7, 23, 10));

      expect(limit.state('q', 1).remaining, 1);
      final s1 = await limit.consume('q', 1);
      expect(s1.used, 1);
      expect(s1.remaining, 0);
      final s2 = await limit.consume('q', 1); // past the limit → no-op
      expect(s2.used, 1);
      expect(s2.remaining, 0);
    });

    test('resets automatically on the next day', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 7, 23, 23);
      final limit = DailyLimit(prefs, now: () => now);

      await limit.consume(kGrievanceLimitKey, 1);
      expect(limit.state(kGrievanceLimitKey, 1).remaining, 0);

      now = DateTime(2026, 7, 24, 0, 5); // past midnight
      expect(limit.state(kGrievanceLimitKey, 1).remaining, 1);
    });

    test('support quota tracks 5/day independently', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final limit = DailyLimit(prefs, now: () => DateTime(2026, 7, 23));

      for (var i = 0; i < 3; i++) {
        await limit.consume(kSupportLimitKey, 5);
      }
      expect(limit.state(kSupportLimitKey, 5).remaining, 2);
      expect(limit.state(kGrievanceLimitKey, 1).remaining, 1);
    });
  });
}
