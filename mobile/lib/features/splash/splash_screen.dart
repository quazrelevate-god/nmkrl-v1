import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import '../shared/wave_mark.dart';

/// Government splash — port of components/SplashScreen.js with native motion:
/// the நம் குரல் wordmark settles in, the gold signal-wave draws itself, the
/// ornamental rule unfurls, then the state line + pulsing dots. Auto-advances
/// to login/home (auth-aware) after the hold.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final AnimationController _dots = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();
  Timer? _leave;

  @override
  void initState() {
    super.initState();
    // Hold ~1.4s (like the web splash), then fade to the right screen for
    // whichever role is signed in (citizen wins if somehow both are).
    _leave = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      if (ref.read(authProvider)) {
        context.go('/home');
      } else if (ref.read(coordinatorAuthProvider) != null) {
        context.go('/coordinator');
      } else {
        context.go('/login');
      }
    });
  }

  @override
  void dispose() {
    _leave?.cancel();
    _intro.dispose();
    _dots.dispose();
    super.dispose();
  }

  Animation<double> _seg(double begin, double end, [Curve curve = Curves.easeOut]) =>
      CurvedAnimation(parent: _intro, curve: Interval(begin, end, curve: curve));

  @override
  Widget build(BuildContext context) {
    final title = _seg(0.0, 0.45, NkMotion.settle);
    final rule = _seg(0.45, 0.7, NkMotion.settle);
    final caption = _seg(0.6, 0.9);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E3A5F), Color(0xFF0F1F36)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Wordmark + animated wave
                  AnimatedBuilder(
                    animation: _intro,
                    builder: (context, _) => Opacity(
                      opacity: title.value,
                      child: Transform.translate(
                        offset: Offset(0, 14 * (1 - title.value)),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Text(
                              'நம் குரல்',
                              style: TextStyle(
                                fontSize: 56,
                                height: 0.95,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                                color: NkColors.gold100,
                              ),
                            ),
                            Positioned(
                              right: -34,
                              top: -8,
                              child: WaveMark(
                                size: 40,
                                progress: _seg(0.25, 0.85).value,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Ornamental rule: line — diamond — line
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: rule,
                    builder: (context, _) => Opacity(
                      opacity: rule.value,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 1,
                            width: 64 * rule.value,
                            color: NkColors.gold300.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 8),
                          Transform.rotate(
                            angle: 0.785398, // 45°
                            child: Container(
                              height: 6,
                              width: 6,
                              color: NkColors.gold300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            height: 1,
                            width: 64 * rule.value,
                            color: NkColors.gold300.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: caption,
                    child: Column(
                      children: [
                        Text(
                          'TAMIL NADU GOVERNMENT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 3.1,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Civic Grievance Redressal Platform',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.40),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Loading dots
                  const SizedBox(height: 32),
                  AnimatedBuilder(
                    animation: _dots,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final t =
                            ((_dots.value - i * 0.2) % 1.0).clamp(0.0, 1.0);
                        final wave = (0.5 - (0.5 - t).abs()) * 2; // 0→1→0
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 3),
                          child: Transform.scale(
                            scale: 0.8 + 0.4 * wave,
                            child: Container(
                              height: 8,
                              width: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white
                                    .withValues(alpha: 0.3 + 0.7 * wave),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
