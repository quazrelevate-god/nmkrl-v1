import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/i18n.dart';
import 'core/theme.dart';
import 'features/coordinator/coordinator_home_screen.dart';
import 'features/home/home_screen.dart';
import 'features/login/login_screen.dart';
import 'features/login/pin_screens.dart';
import 'features/splash/splash_screen.dart';
import 'state/providers.dart';

class NammaKuralApp extends ConsumerWidget {
  const NammaKuralApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final lang = ref.watch(langProvider);
    return MaterialApp.router(
      title: 'நம் குரல்',
      debugShowCheckedModeBanner: false,
      theme: buildNkTheme(),
      routerConfig: router,
      // Rubber-band overscroll everywhere — including pushed routes like the
      // profile and the search overlay — so no list stops dead at its end.
      scrollBehavior: const _NkScrollBehavior(),
      // Carry the current language above every route so `context.tr(...)`
      // works anywhere and re-translates the whole tree on toggle.
      builder: (context, child) =>
          AppL10n(lang: lang, child: child ?? const SizedBox.shrink()),
    );
  }
}

/// App-wide scroll feel: iOS-style rubber band on every platform, and drags
/// that also work from a mouse/trackpad (handy in the simulator and on web).
class _NkScrollBehavior extends MaterialScrollBehavior {
  const _NkScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

final _routerProvider = Provider<GoRouter>((ref) {
  // Rebuild redirects when either role's auth state flips.
  final citizenAuthed = ValueNotifier(ref.read(authProvider));
  final coordAuthed =
      ValueNotifier(ref.read(coordinatorAuthProvider) != null);
  ref.listen(authProvider, (_, next) => citizenAuthed.value = next);
  ref.listen(coordinatorAuthProvider,
      (_, next) => coordAuthed.value = next != null);
  ref.onDispose(citizenAuthed.dispose);
  ref.onDispose(coordAuthed.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: Listenable.merge([citizenAuthed, coordAuthed]),
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (loc == '/splash') return null; // splash decides for itself
      // /login always reachable — it hosts the citizen↔coordinator toggle.
      if (loc == '/coordinator' && !coordAuthed.value) return '/login';
      if (loc == '/home') {
        if (!citizenAuthed.value) return '/login';
        // An account without a PIN — every account created before PINs
        // existed — is sent to set one rather than being let past. The lock
        // itself is not a redirect: home draws it over itself (_LockableHome).
        final prefs = ref.read(prefsProvider);
        if (!prefs.hasPin) return '/set-pin';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) {
          // Arriving from the splash, login continues the splash's last frame
          // — same navy, same wordmark in the same place — so there is nothing
          // to transition between. Any other arrival (signing out) fades in.
          if (state.extra == 'intro') {
            return NoTransitionPage<void>(
              key: state.pageKey,
              child: const LoginScreen(intro: true),
            );
          }
          return CustomTransitionPage(
            key: state.pageKey,
            child: const LoginScreen(),
            transitionDuration: const Duration(milliseconds: 400),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            ),
          );
        },
      ),
      GoRoute(
        path: '/set-pin',
        builder: (context, state) => const SetPinScreen(),
      ),
      // Kept so any stale link still lands somewhere sensible: the lock now
      // lives over home rather than on a page of its own.
      GoRoute(path: '/lock', redirect: (_, __) => '/home'),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const _LockableHome(),
          transitionDuration: const Duration(milliseconds: 450),
          transitionsBuilder: (_, anim, __, child) {
            final curved =
                CurvedAnimation(parent: anim, curve: NkMotion.settle);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      ),
      GoRoute(
        path: '/coordinator',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CoordinatorHomeScreen(),
          transitionDuration: const Duration(milliseconds: 450),
          transitionsBuilder: (_, anim, __, child) {
            final curved =
                CurvedAnimation(parent: anim, curve: NkMotion.settle);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      ),
    ],
  );
});


/// Home, with the app-open lock drawn over it until the PIN is entered.
///
/// The lock was a navy page of its own; it is a veil over home now, so the map
/// and grievances are visibly right there behind the blur. [pinLockProvider]
/// is in-memory only, so the veil is up on a cold start and stays down while
/// the app is merely backgrounded.
class _LockableHome extends ConsumerWidget {
  const _LockableHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(pinLockProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Always wrapped, so unlocking never changes this subtree's shape and
        // home's state survives the veil lifting. While locked the PIN
        // keyboard's inset is withheld, so the map and sheet behind the blur
        // do not reflow every time it opens.
        MediaQuery.removeViewInsets(
          context: context,
          removeBottom: !unlocked,
          child: const HomeScreen(),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 360),
          switchOutCurve: Curves.easeOut,
          child: unlocked
              ? const SizedBox.shrink(key: ValueKey('unlocked'))
              : const PinLockOverlay(key: ValueKey('locked')),
        ),
      ],
    );
  }
}
