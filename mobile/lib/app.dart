import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/i18n.dart';
import 'core/theme.dart';
import 'features/coordinator/coordinator_home_screen.dart';
import 'features/home/home_screen.dart';
import 'features/login/login_screen.dart';
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
      // Carry the current language above every route so `context.tr(...)`
      // works anywhere and re-translates the whole tree on toggle.
      builder: (context, child) =>
          AppL10n(lang: lang, child: child ?? const SizedBox.shrink()),
    );
  }
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
      if (loc == '/home' && !citizenAuthed.value) return '/login';
      if (loc == '/coordinator' && !coordAuthed.value) return '/login';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionDuration: const Duration(milliseconds: 400),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        ),
      ),
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HomeScreen(),
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
