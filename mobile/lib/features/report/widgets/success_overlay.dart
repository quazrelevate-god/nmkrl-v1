import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// Full-screen UPI-style acknowledgement (port of SuccessOverlay.js): a navy
/// radial wash sweeps in, the white badge pops with radiating rings and its
/// mark draws in, then title/message/ticket reveal. Auto-dismisses or on tap.
///
/// The wash is the brand navy — the same value as the Support CTA — so the
/// acknowledgement reads as part of the app rather than a stock success screen.
class SuccessOverlay {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? ticket,
    bool handshake = false,
    Duration autoDismiss = const Duration(milliseconds: 2800),
  }) {
    HapticFeedback.heavyImpact();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        pageBuilder: (_, __, ___) => _SuccessScreen(
          title: title,
          message: message,
          ticket: ticket,
          handshake: handshake,
          autoDismiss: autoDismiss,
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 1.04, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _SuccessScreen extends StatefulWidget {
  const _SuccessScreen({
    required this.title,
    required this.message,
    required this.ticket,
    required this.handshake,
    required this.autoDismiss,
  });

  final String title;
  final String message;
  final String? ticket;

  /// Support flow: an animated handshake instead of the submission tick.
  final bool handshake;
  final Duration autoDismiss;

  @override
  State<_SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<_SuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final AnimationController _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  /// Drives the handshake's two-cycle shake, started once the badge has popped.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  Timer? _auto;
  Timer? _shakeStart;

  /// Two damped oscillations — a greeting shake, not a wobble.
  double get _shakeAngle {
    if (_shake.value == 0 || _shake.value == 1) return 0;
    final decay = 1 - _shake.value;
    return math.sin(_shake.value * math.pi * 4) * 0.20 * decay;
  }

  @override
  void initState() {
    super.initState();
    _auto = Timer(widget.autoDismiss, () {
      if (mounted) Navigator.of(context).maybePop();
    });
    if (widget.handshake) {
      _shakeStart = Timer(const Duration(milliseconds: 620), () {
        if (mounted) _shake.forward();
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _shakeStart?.cancel();
    _intro.dispose();
    _rings.dispose();
    _shake.dispose();
    super.dispose();
  }

  Animation<double> _seg(double a, double b, [Curve c = Curves.easeOut]) =>
      CurvedAnimation(parent: _intro, curve: Interval(a, b, curve: c));

  @override
  Widget build(BuildContext context) {
    final badge = _seg(0.1, 0.55, NkMotion.spring);
    final check = _seg(0.4, 0.75);
    final title = _seg(0.2, 0.6);
    final msg = _seg(0.3, 0.7);
    final ticket = _seg(0.4, 0.8);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              // Brand navy, matching the Support CTA.
              gradient: RadialGradient(
                center: Alignment(0, -1),
                radius: 1.6,
                colors: [
                  NkColors.refBlueGlow,
                  NkColors.navyPrimary,
                  NkColors.brandDark,
                ],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: SafeArea(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Rings + badge
                      SizedBox(
                        height: 150,
                        width: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            for (final delay in const [0.0, 0.25])
                              AnimatedBuilder(
                                animation: _rings,
                                builder: (context, _) {
                                  final t =
                                      ((_rings.value + delay) % 1.0);
                                  return Container(
                                    height: 112 * (1 + 2.4 * t),
                                    width: 112 * (1 + 2.4 * t),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(
                                          alpha: 0.22 * (1 - t)),
                                    ),
                                  );
                                },
                              ),
                            ScaleTransition(
                              scale: badge,
                              child: Container(
                                height: 112,
                                width: 112,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.25),
                                      blurRadius: 40,
                                      offset: const Offset(0, 16),
                                    ),
                                  ],
                                ),
                                child: widget.handshake
                                    ? AnimatedBuilder(
                                        animation:
                                            Listenable.merge([check, _shake]),
                                        builder: (context, _) => Opacity(
                                          opacity:
                                              check.value.clamp(0.0, 1.0),
                                          child: Transform.rotate(
                                            // Two quick shakes once the badge
                                            // has popped — the gesture itself,
                                            // not a spinning icon.
                                            angle: _shakeAngle,
                                            child: const Icon(
                                              Icons.handshake_rounded,
                                              size: 56,
                                              color: NkColors.navyPrimary,
                                            ),
                                          ),
                                        ),
                                      )
                                    : AnimatedBuilder(
                                        animation: check,
                                        builder: (context, _) => CustomPaint(
                                          painter: _CheckPainter(
                                              progress: check.value),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      FadeTransition(
                        opacity: title,
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FadeTransition(
                        opacity: msg,
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ),
                      if (widget.ticket != null) ...[
                        const SizedBox(height: 24),
                        FadeTransition(
                          opacity: ticket,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color:
                                      Colors.white.withValues(alpha: 0.25)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.confirmation_number_outlined,
                                        size: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.7)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'TRACKING TICKET',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2,
                                        color: Colors.white
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.ticket!,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Positioned(
                    bottom: 24,
                    child: FadeTransition(
                      opacity: _seg(0.6, 1.0),
                      child: Text(
                        'Tap anywhere to continue',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
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

/// Stroke-drawn checkmark (port of the SVG dash-offset animation).
class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width;
    final path = Path()
      ..moveTo(w * 0.28, w * 0.52)
      ..lineTo(w * 0.44, w * 0.68)
      ..lineTo(w * 0.74, w * 0.36);
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    final draw = Path();
    var remaining = total * progress;
    for (final m in metrics) {
      final take = remaining.clamp(0, m.length).toDouble();
      draw.addPath(m.extractPath(0, take), Offset.zero);
      remaining -= take;
      if (remaining <= 0) break;
    }
    canvas.drawPath(
      draw,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = NkColors.navyPrimary,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
