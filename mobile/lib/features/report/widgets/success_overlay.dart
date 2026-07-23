import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// Full-screen UPI-style acknowledgement (port of SuccessOverlay.js): green
/// radial wash sweeps in, the white check badge pops with radiating rings and
/// a stroke-drawn tick, then title/message/ticket reveal. Auto-dismisses or
/// on tap.
class SuccessOverlay {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? ticket,
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
    required this.autoDismiss,
  });

  final String title;
  final String message;
  final String? ticket;
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
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer(widget.autoDismiss, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _intro.dispose();
    _rings.dispose();
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
              gradient: RadialGradient(
                center: Alignment(0, -1),
                radius: 1.6,
                colors: [
                  Color(0xFF12B76A),
                  Color(0xFF059669),
                  Color(0xFF047857),
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
                                child: AnimatedBuilder(
                                  animation: check,
                                  builder: (context, _) => CustomPaint(
                                    painter:
                                        _CheckPainter(progress: check.value),
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
        ..color = NkColors.emerald600,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}
