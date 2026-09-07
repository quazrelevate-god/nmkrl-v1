import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api_client.dart';
import '../data/coordinator_store.dart';
import '../data/dio_api_client.dart';
import '../data/prefs.dart';
import '../data/push_service.dart';
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
    final signedIn = prefs.authed && (prefs.accountId?.isNotEmpty ?? false);
    // Re-bind the push token on a warm start. signIn() only runs on a fresh
    // login, so without this an already-signed-in user would never register a
    // token and would silently receive no push at all.
    if (signedIn) {
      Future.microtask(() => PushService.instance.bind(
            api: ref.read(apiClientProvider),
            recipientType: 'citizen',
            recipientId: prefs.userId,
          ));
    }
    return signedIn;
  }

  /// Phase-1 login: verify [otp], then check-or-create the (name, phone)
  /// account on the backend. Throws [ApiException] with a friendly message on
  /// rejection (wrong OTP, or phone registered under a different name).
  Future<CitizenUser> signIn({
    required String name,
    required String phone,
    required String otp,
  }) async {
    final user = await ref
        .read(apiClientProvider)
        .citizenLogin(name: name, phone: phone, otp: otp);
    await ref.read(prefsProvider).saveAccount(user);
    // A fresh sign-in IS the authentication; the PIN gate is for later opens.
    ref.read(pinLockProvider.notifier).unlock();
    state = true;
    await PushService.instance.bind(
      api: ref.read(apiClientProvider),
      recipientType: 'citizen',
      recipientId: ref.read(prefsProvider).userId,
    );
    return user;
  }

  Future<void> signOut() async {
    // Release the device first — once prefs are cleared we lose the identity
    // this token is bound to, and the next account here would inherit alerts.
    await PushService.instance.unbind(ref.read(apiClientProvider));
    await ref.read(prefsProvider).clearSession();
    ref.read(pinLockProvider.notifier).lock();
    state = false;
  }
}

final authProvider = NotifierProvider<AuthNotifier, bool>(AuthNotifier.new);

/// Whether the app-open PIN has been satisfied in THIS run of the app.
///
/// Deliberately not persisted: the lock exists to be met on every cold start,
/// so it resets when the process does. Signing in fresh, or setting a PIN,
/// unlocks it for the rest of the run.
class PinLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() => state = false;
}

final pinLockProvider =
    NotifierProvider<PinLockNotifier, bool>(PinLockNotifier.new);

/// Ids of the grievances this account has already supported.
///
/// Held app-wide so any surface showing a Support button can disable it BEFORE
/// the user swipes — previously the only feedback was the backend's 409 after
/// a confirmed submit, which read as the action failing.
class SupportedIssuesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // Signed-out builds resolve to an empty set; refresh is a no-op then.
    Future.microtask(refresh);
    return const <String>{};
  }

  Future<void> refresh() async {
    final userId = ref.read(userIdProvider);
    if (userId.isEmpty) return;
    try {
      final list = await ref.read(apiClientProvider).fetchSupported(userId);
      state = {for (final i in list) i.id};
    } catch (_) {
      // Leave the last known set — a failed refresh must not re-enable a
      // button the user has already used.
    }
  }

  /// Optimistic local mark, so the button flips the moment the upvote lands
  /// without waiting for a round trip.
  void markSupported(String issueId) {
    if (state.contains(issueId)) return;
    state = {...state, issueId};
  }

  /// Adopt a set a caller already fetched (the home's "My Supports" scope
  /// loads the same list), instead of issuing a second identical request.
  void setAll(Iterable<String> issueIds) => state = {...issueIds};
}

final supportedIssuesProvider =
    NotifierProvider<SupportedIssuesNotifier, Set<String>>(
        SupportedIssuesNotifier.new);

/// True when [issueId] has already been supported by this account.
bool hasSupported(WidgetRef ref, String issueId) =>
    ref.watch(supportedIssuesProvider).contains(issueId);

// ── Coordinator side ─────────────────────────────────────────────────────

final coordinatorStoreProvider = Provider<CoordinatorStore>(
  (ref) => CoordinatorStore(ref.watch(sharedPreferencesProvider)),
);

/// The signed-in coordinator (null when signed out) as reactive state so the
/// router redirect responds to sign-in/out. Auth hits the admin-managed
/// backend `coordinators` table — the mobile side no longer ships demo seeds.
class CoordinatorAuthNotifier extends Notifier<Coordinator?> {
  @override
  Coordinator? build() {
    final session = ref.read(coordinatorStoreProvider).session;
    // Same warm-start rebind as the citizen side — see AuthNotifier.build().
    if (session != null) {
      Future.microtask(() => PushService.instance.bind(
            api: ref.read(apiClientProvider),
            recipientType: 'coordinator',
            recipientId: session.username,
          ));
    }
    return session;
  }

  /// Throws [ApiException] on wrong credentials (message is user-friendly).
  Future<Coordinator> signIn(String username, String password) async {
    final c = await ref.read(apiClientProvider).coordinatorLogin(
          username: username,
          password: password,
        );
    await ref.read(coordinatorStoreProvider).saveSession(c);
    state = c;
    await PushService.instance.bind(
      api: ref.read(apiClientProvider),
      recipientType: 'coordinator',
      recipientId: c.username,
    );
    return c;
  }

  Future<void> signOut() async {
    await PushService.instance.unbind(ref.read(apiClientProvider));
    await ref.read(coordinatorStoreProvider).clearSession();
    state = null;
  }
}

final coordinatorAuthProvider =
    NotifierProvider<CoordinatorAuthNotifier, Coordinator?>(
        CoordinatorAuthNotifier.new);
