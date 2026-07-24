import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import 'tamil_nadu_outline.dart';

const _navy = Color(0xFF16324F);
const _gold = Color(0xFFD4A537);

/// Animated government splash: gold particles hold along the Tamil Nadu
/// state outline, then converge into the நம்குரல் wordmark and shimmer
/// until session restore decides the entry screen (citizen home /
/// coordinator console / login).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  static const int particleCount = 360;
  static const Duration holdDuration = Duration(milliseconds: 900);
  static const Duration morphDuration = Duration(milliseconds: 2100);

  /// Dwell on the converged wordmark before navigating away, so it
  /// registers instead of flashing past.
  static const Duration settleDuration = Duration(milliseconds: 600);

  /// Fraction of the main controller spent holding on the outline.
  static final double _holdFraction = holdDuration.inMilliseconds /
      (holdDuration + morphDuration).inMilliseconds;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: holdDuration + morphDuration,
  );
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  List<Offset> _outlineVertices = const [];
  List<Offset> _startPoints = const [];
  List<Offset> _targetPoints = const [];
  bool _initialized = false;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    // The outline geometry is pure math — computed before the first build so
    // the very first Flutter frame already shows the held constellation
    // (no blank-navy beat while the text rasterizes).
    final size = MediaQuery.sizeOf(context);

    // Outline draw box: centered, ~70% of the screen width, capped so the
    // 1.3503-tall box always fits within 80% of the screen height.
    final boxW =
        math.min(size.width * 0.7, size.height * 0.8 / kTamilNaduAspect);
    final boxH = boxW * kTamilNaduAspect;
    final boxOrigin = Offset((size.width - boxW) / 2, (size.height - boxH) / 2);
    Offset place(Offset p) => boxOrigin + Offset(p.dx * boxW, p.dy * boxH);
    _outlineVertices = tamilNaduOutline.map(place).toList(growable: false);
    _startPoints = sampleAlongPolyline(tamilNaduOutline, particleCount)
        .map(place)
        .toList(growable: false);

    _startAfterTargets(size);
  }

  @override
  void dispose() {
    _controller.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  Future<void> _startAfterTargets(Size size) async {
    // Rasterize the wordmark during the visible hold, then run the timeline.
    _targetPoints = await _computeTextTargetPoints(size, particleCount);
    if (!mounted) return;
    setState(() {});

    final converged = Completer<void>();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _shimmer.repeat(reverse: true);
        Future.delayed(settleDuration, () {
          if (!converged.isCompleted) converged.complete();
        });
      }
    });
    _controller.forward();

    // Navigate when BOTH the settled wordmark AND real init are done; a
    // timeout keeps a wedged init from trapping the user on the splash.
    var route = '/login';
    await Future.wait([
      converged.future,
      _runRealAppInit()
          .timeout(const Duration(seconds: 5), onTimeout: () => '/login')
          .then((r) => route = r),
    ]);
    if (!mounted || _navigated) return;
    _navigated = true;
    context.go(route);
  }

  /// Session restore. SharedPreferences is pre-loaded in main(), so today
  /// this resolves instantly — kept async so a real auth check can slot in
  /// without re-wiring the splash.
  Future<String> _runRealAppInit() async {
    if (ref.read(authProvider)) return '/home';
    if (ref.read(coordinatorAuthProvider) != null) return '/coordinator';
    return '/login';
  }

  /// Rasterizes the wordmark once and samples opaque pixels as dot targets,
  /// centered on screen. Never recomputed after init.
  Future<List<Offset>> _computeTextTargetPoints(Size screen, int count) async {
    const style = TextStyle(
      fontSize: 100,
      fontWeight: FontWeight.w900,
      color: _gold,
    );
    final probe = TextPainter(
      text: const TextSpan(text: 'நம்குரல்', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    // Re-lay-out at the size that makes the text span ~85% of the width.
    final scale = (screen.width * 0.85) / probe.width;
    final painter = TextPainter(
      text: TextSpan(
        text: 'நம்குரல்',
        style: style.copyWith(fontSize: 100 * scale),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final w = painter.width.ceil();
    final h = painter.height.ceil();
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), Offset.zero);
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();

    final candidates = <Offset>[];
    if (bytes != null) {
      final data = bytes.buffer.asUint8List();
      for (var y = 0; y < h; y += 2) {
        for (var x = 0; x < w; x += 2) {
          if (data[(y * w + x) * 4 + 3] > 150) {
            candidates.add(Offset(x.toDouble(), y.toDouble()));
          }
        }
      }
    }
    final origin =
        Offset((screen.width - painter.width) / 2, (screen.height - h) / 2);
    if (candidates.isEmpty) {
      // Degenerate fallback (glyphs failed to rasterize): converge on center.
      return List.filled(count, screen.center(Offset.zero));
    }
    // Even index stepping over the row-major candidates spreads the dots
    // uniformly across every glyph, which keeps the wordmark legible —
    // random picks clump and leave gaps.
    final step = candidates.length / count;
    return List.generate(
      count,
      (i) => origin + candidates[(i * step).floor() % candidates.length],
      growable: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _navy,
        body: SizedBox.expand(
          child: CustomPaint(
            painter: _SplashPainter(
              controller: _controller,
              shimmer: _shimmer,
              holdFraction: _holdFraction,
              outlineVertices: _outlineVertices,
              startPoints: _startPoints,
              targetPoints: _targetPoints,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  _SplashPainter({
    required this.controller,
    required this.shimmer,
    required this.holdFraction,
    required this.outlineVertices,
    required this.startPoints,
    required this.targetPoints,
  }) : super(repaint: Listenable.merge([controller, shimmer]));

  final AnimationController controller;
  final AnimationController shimmer;
  final double holdFraction;
  final List<Offset> outlineVertices;
  final List<Offset> startPoints;
  final List<Offset> targetPoints;

  /// 0..1 linear progress within the morph phase (0 during the hold).
  double get _morphLinear {
    final t = controller.value;
    if (t <= holdFraction) return 0;
    return ((t - holdFraction) / (1 - holdFraction)).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _navy);

    final morph = _morphLinear;
    final eased = Curves.easeOutCubic.transform(morph);

    // Faint state outline behind the dots; fades as the dots leave it.
    final outlineOpacity = 0.38 * (1 - morph);
    if (outlineOpacity > 0.01) {
      final outlinePaint = Paint()
        ..color = _gold.withValues(alpha: outlineOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawPath(Path()..addPolygon(outlineVertices, true), outlinePaint);
    }

    // Converged dots pulse 1.0 ↔ 0.85 (shimmer runs repeat(reverse: true)).
    final shimmerOpacity = controller.isCompleted
        ? 1 - 0.15 * Curves.easeInOut.transform(shimmer.value)
        : 1.0;
    final dotPaint = Paint()..color = _gold.withValues(alpha: shimmerOpacity);
    if (targetPoints.isEmpty) {
      // Targets still rasterizing — the hold state needs only start points.
      for (final p in startPoints) {
        canvas.drawCircle(p, 2.2, dotPaint);
      }
      return;
    }
    for (var i = 0; i < targetPoints.length; i++) {
      final pos = Offset.lerp(startPoints[i], targetPoints[i], eased)!;
      canvas.drawCircle(pos, 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) =>
      old.startPoints != startPoints || old.targetPoints != targetPoints;
}
