import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/coordinator_store.dart';
import '../data/dio_api_client.dart';
import '../data/prefs.dart';
import '../domain/coordinator_data.dart';
import '../domain/daily_limit.dart';
import '../domain/models/citizen_user.dart';

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

/// Citizen auth as reactive state so router redirects respond to sign-in/out.
/// A session only counts when a server-issued account id is present, so
/// pre-auth-era installs are sent back through the new login.
class AuthNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.read(prefsProvider);
    return prefs.authed && (prefs.accountId?.isNotEmpty ?? false);
  }

  /// Phase-1 login: check-or-create the (name, phone) account on the backend.
  /// Throws [ApiException] with a friendly message on rejection (e.g. the
  /// phone is registered under a different name).
  Future<CitizenUser> signIn(
      {required String name, required String phone}) async {
    final user = await ref
        .read(apiClientProvider)
        .citizenLogin(name: name, phone: phone);
    await ref.read(prefsProvider).saveAccount(user);
    state = true;
    return user;
  }

  Future<void> signOut() async {
    await ref.read(prefsProvider).clearSession();
    state = false;
  }
}

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);

// ── Coordinator side ─────────────────────────────────────────────────────

final coordinatorStoreProvider = Provider<CoordinatorStore>(
  (ref) => CoordinatorStore(ref.watch(sharedPreferencesProvider)),
);

/// The signed-in coordinator (null when signed out) as reactive state so the
/// router redirect responds to sign-in/out. Auth hits the admin-managed
/// backend `coordinators` table — the mobile side no longer ships demo seeds.
class CoordinatorAuthNotifier extends Notifier<Coordinator?> {
  @override
  Coordinator? build() => ref.read(coordinatorStoreProvider).session;

  /// Throws [ApiException] on wrong credentials (message is user-friendly).
  Future<Coordinator> signIn(String username, String password) async {
    final c = await ref.read(apiClientProvider).coordinatorLogin(
          username: username,
          password: password,
        );
    await ref.read(coordinatorStoreProvider).saveSession(c);
    state = c;
    return c;
  }

  Future<void> signOut() async {
    await ref.read(coordinatorStoreProvider).clearSession();
    state = null;
  }
}

final coordinatorAuthProvider =
    NotifierProvider<CoordinatorAuthNotifier, Coordinator?>(
        CoordinatorAuthNotifier.new);
