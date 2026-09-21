import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
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

final apiClientProvider = Provider<ApiClient>(
  // The token reader is called per request, so it always reflects the latest
  // sign-in/out without rebuilding the client.
  (ref) => DioApiClient(
    sessionToken: () => ref.read(prefsProvider).sessionToken,
    // Session rejected by the server: clear both roles' local session and let
    // the router redirects (which watch these providers) fall back to /login.
    onUnauthorized: () {
      Future.microtask(() async {
        await ref.read(prefsProvider).clearSession();
        await ref.read(coordinatorStoreProvider).clearSession();
        ref.invalidate(authProvider);
        ref.invalidate(coordinatorAuthProvider);
      });
    },
  ),
);

/// The signed-in citizen's account id.
///
/// Watches [authProvider] so it is recomputed on every sign-in and sign-out.
/// It used to read prefs once and cache that string for the life of the
/// process, while the token reader above runs fresh on every request — so
/// after an account switch the app asked for the PREVIOUS account's history
/// holding the NEW account's token, and the server refused every such call.
/// That surfaced as a permanent "That belongs to another account" pill and,
/// less visibly, an empty report list.
final userIdProvider = Provider<String>((ref) {
  ref.watch(authProvider);
  return ref.read(prefsProvider).userId;
});

/// The citizen's local profile picture (a file path), or null. Reactive so the
/// avatar in the app bar and the profile screen update the moment it is set.
/// Local only — the image is copied into app storage and never uploaded.
class AvatarNotifier extends Notifier<String?> {
  @override
  String? build() {
    final p = ref.read(prefsProvider).avatarPath;
    return (p != null && p.isNotEmpty && File(p).existsSync()) ? p : null;
  }

  /// Copy [sourcePath] into the app's own storage and remember it.
  Future<void> setFromFile(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/nk_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(sourcePath).copy(dest);
    // Drop any previous avatar file so they don't pile up.
    final old = state;
    await ref.read(prefsProvider).setAvatarPath(dest);
    state = dest;
    if (old != null && old != dest) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    final old = state;
    await ref.read(prefsProvider).clearAvatar();
    state = null;
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }
}

final avatarProvider =
    NotifierProvider<AvatarNotifier, String?>(AvatarNotifier.new);

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
    // Persist the session token so it survives a warm start and rides on every
    // later request via the api client's interceptor.
    await ref.read(prefsProvider).setSessionToken(user.token);
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
    ref.invalidate(avatarProvider); // clearSession removed the stored path
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

  /// Re-read this coordinator's profile from the server and cache it.
  ///
  /// The profile is cached at sign-in, so an admin change made afterwards —
  /// the photo above all, but also a moved home ward or a renamed role — used
  /// to stay invisible until the coordinator signed out and back in. Failures
  /// are swallowed: an offline refresh must not sign anybody out (a genuinely
  /// dead session is already handled by the 401 interceptor).
  Future<void> refreshProfile() async {
    final current = state;
    if (current == null) return;
    try {
      final fresh = await ref.read(apiClientProvider).coordinatorMe();
      if (state == null) return; // signed out while we waited
      final merged = current.withServerProfile(fresh);
      await ref.read(coordinatorStoreProvider).saveSession(merged);
      state = merged;
    } catch (_) {}
  }

  /// Sign in with name + mobile + OTP. Throws [ApiException] on a bad code or
  /// a name/number that does not match an admin-created account.
  Future<Coordinator> signIn(
      {required String name, required String phone, required String otp}) async {
    final c = await ref.read(apiClientProvider).coordinatorLogin(
          name: name,
          phone: phone,
          otp: otp,
        );
    await ref.read(coordinatorStoreProvider).saveSession(c);
    // One device acts as one account at a time, and the two roles share a
    // single token slot — so end any citizen session first. Writing the
    // coordinator's token over it while the citizen's "signed in" flag stayed
    // set left the app believing both were active at once.
    await ref.read(prefsProvider).clearSession();
    // Token lives in Prefs (shared with the citizen flow), not the cached
    // coordinator profile, so the interceptor finds it on a warm start too.
    await ref.read(prefsProvider).setSessionToken(c.token);
    ref.invalidate(authProvider);
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
    // Citizen and coordinator share one token slot, so clearing just the token
    // used to leave the citizen's "signed in" flag set with no token behind it:
    // the next cold start routed to the citizen home and every request 401'd.
    await ref.read(prefsProvider).clearSession();
    ref.invalidate(avatarProvider);
    ref.invalidate(authProvider);
    state = null;
  }
}

final coordinatorAuthProvider =
    NotifierProvider<CoordinatorAuthNotifier, Coordinator?>(
        CoordinatorAuthNotifier.new);
