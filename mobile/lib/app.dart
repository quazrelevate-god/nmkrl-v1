import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'features/home/home_screen.dart';
import 'features/login/login_screen.dart';
import 'features/splash/splash_screen.dart';
import 'state/providers.dart';

class NammaKuralApp extends ConsumerWidget {
  const NammaKuralApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: 'நம் குரல்',
      debugShowCheckedModeBanner: false,
      theme: buildNkTheme(),
      routerConfig: router,
    );
  }
}

final _routerProvider = Provider<GoRouter>((ref) {
  // Rebuild redirects when the auth flag flips.
  final authed = ValueNotifier(ref.read(authProvider));
  ref.listen(authProvider, (_, next) => authed.value = next);
  ref.onDispose(authed.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authed,
    redirect: (context, state) {
      final isAuthed = authed.value;
      final loc = state.matchedLocation;
      if (loc == '/splash') return null; // splash decides for itself
      if (!isAuthed && loc != '/login') return '/login';
      if (isAuthed && loc == '/login') return '/home';
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
    ],
  );
});
