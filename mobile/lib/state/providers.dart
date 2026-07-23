import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/dio_api_client.dart';
import '../data/prefs.dart';
import '../domain/daily_limit.dart';

/// Overridden with the real instance in main() before runApp.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

final prefsProvider = Provider<Prefs>(
  (ref) => Prefs(ref.watch(sharedPreferencesProvider)),
);

final dailyLimitProvider = Provider<DailyLimit>(
  (ref) => DailyLimit(ref.watch(sharedPreferencesProvider)),
);

final apiClientProvider = Provider<ApiClient>((ref) => DioApiClient());

final userIdProvider = Provider<String>((ref) => ref.watch(prefsProvider).userId);

/// Auth flag as reactive state so router redirects respond to sign-in/out.
class AuthNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).authed;

  Future<void> signIn(String name) async {
    final prefs = ref.read(prefsProvider);
    await prefs.setAuthed(true);
    await prefs.setCitizenName(name);
    state = true;
  }

  Future<void> signOut() async {
    await ref.read(prefsProvider).setAuthed(false);
    state = false;
  }
}

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);
