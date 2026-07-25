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

/// Particle dots during the scatter/converge phase.
const _gold = Color(0xFFD4A537);

/// Final solid wordmark glyph fill — the cream tone from the real login
/// title (distinct from the gold particle color).
const _cream = Color(0xFFEADFBF);

/// The signal-wave arcs on the final logo lockup — a warmer, more saturated
/// gold than the cream text, matching the real brand mark.
const _waveGold = Color(0xFFC8A04A);

/// Animated government splash: gold particles hold along the Tamil Nadu
/// state outline, then converge — from scattered outline positions, each on
/// its own slightly-staggered path — into the நம்குரல் wordmark, crossfading
/// from the dot swarm into solid vector type before shimmering until session
/// restore decides the entry screen (citizen home / coordinator / login).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  /// Dense enough that the pre-crossfade convergence already reads as text;
  /// the crossfade to solid type then removes any residual dot texture.
  static const int particleCount = 500;
  static const Duration holdDuration = Duration(milliseconds: 900);
  static const Duration morphDuration = Duration(milliseconds: 2100);

  /// Dwell on the converged wordmark before navigating away.
  static const Duration settleDuration = Duration(milliseconds: 600);

  /// Widest per-particle start delay, as a fraction of the morph phase
  /// (~250ms of the 2100ms morph). The most-delayed particle still lands at
  /// morph end, so total elapsed time is unchanged.
  static const double _maxDelayFrac = 0.12;

  /// Fraction of the main controller spent holding on the outline.
  static final double _holdFraction = holdDuration.inMilliseconds /
      (holdDuration + morphDuration).inMilliseconds;

  final math.Random _rng = math.Random();

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
  List<double> _delays = const [];

  // Solid wordmark for the crossfade finish — laid out at the exact origin
  // and size the dot targets were sampled from, so the swap never shifts.
  TextPainter? _solidText;
  Offset _solidOrigin = Offset.zero;
  Size _solidSize = Size.zero;

  // Signal-wave mark geometry, anchored to the text's top-right corner.
  Offset _waveTopLeft = Offset.zero;
  double _waveSize = 0;

  bool _initialized = false;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    // Outline geometry is pure math — computed before the first build so the
    // first frame already shows the scattered constellation.
    final size = MediaQuery.sizeOf(context);

    final boxW =
        math.min(size.width * 0.7, size.height * 0.8 / kTamilNaduAspect);
    final boxH = boxW * kTamilNaduAspect;
    final boxOrigin = Offset((size.width - boxW) / 2, (size.height - boxH) / 2);
    Offset place(Offset p) => boxOrigin + Offset(p.dx * boxW, p.dy * boxH);
    _outlineVertices = tamilNaduOutline.map(place).toList(growable: false);

    // Random (not evenly-spaced) scatter along the outline, re-rolled every
    // launch, so no grid pattern is ever visible.
    _startPoints = randomAlongPolyline(tamilNaduOutline, particleCount, _rng)
        .map(place)
        .toList(growable: false);
    // Per-particle start delay → the formation gathers, it doesn't slide.
    _delays = List.generate(
        particleCount, (_) => _rng.nextDouble() * _maxDelayFrac,
        growable: false);

    _startAfterTargets(size);
  }

  @override
  void dispose() {
    _controller.dispose();
    _shimmer.dispose();
    _solidText?.dispose();
    super.dispose();
  }

  Future<void> _startAfterTargets(Size size) async {
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

  Future<String> _runRealAppInit() async {
    if (ref.read(authProvider)) return '/home';
    if (ref.read(coordinatorAuthProvider) != null) return '/coordinator';
    return '/login';
  }

  /// Lays out the wordmark once: stores the solid [TextPainter] + its origin
  /// for the crossfade, and returns [count] dot targets sampled from the same
  /// rasterized glyphs (shuffled so no particle keeps an index-correspondence
  /// to its start position).
  Future<List<Offset>> _computeTextTargetPoints(Size screen, int count) async {
    // Mirror the real login title lockup exactly: cream fill, w900,
    // letterSpacing -0.5, height 1.
    const style = TextStyle(
      fontSize: 100,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
      height: 1,
      color: _cream,
    );
    final probe = TextPainter(
      text: const TextSpan(text: 'நம்குரல்', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final scale = (screen.width * 0.85) / probe.width;
    final fontSize = 100 * scale;
    final painter = TextPainter(
      text: TextSpan(
        text: 'நம்குரல்',
        style: style.copyWith(fontSize: fontSize, letterSpacing: -0.5 * scale),
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

    // Signal-wave mark uses the real login proportions (WaveMark size 24 at
    // right:-26/top:-8 over a 34px title → scaled by fontSize/34). It hangs
    // ~26k past the text's right edge, so the whole lockup (text + wave) is
    // what gets centered — otherwise the wave crowds/clips the right edge on
    // narrow screens.
    final k = fontSize / 34;
    // The arcs' rightmost point reaches ~21k past the text edge (box is 24k
    // wide but the outer arc only extends to x≈18.75k + stroke); center the
    // lockup on that true extent for balanced margins.
    final waveOverhang = 21 * k;
    final origin = Offset(
      (screen.width - painter.width - waveOverhang) / 2,
      (screen.height - h) / 2,
    );
    // Keep the same painter + origin for the solid crossfade render.
    _solidText = painter;
    _solidOrigin = origin;
    _solidSize = Size(painter.width, h.toDouble());

    _waveSize = 24 * k;
    _waveTopLeft = Offset(
      origin.dx + painter.width + 2 * k, // 2px past the right edge at F=34
      origin.dy - 8 * k, // 8px above the top at F=34
    );

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
    if (candidates.isEmpty) {
      return List.filled(count, screen.center(Offset.zero));
    }
    // Even stepping spreads targets uniformly over every glyph; shuffling the
    // resulting list breaks any residual ordering so the assignment is random.
    final step = candidates.length / count;
    final targets = List.generate(
      count,
      (i) => origin + candidates[(i * step).floor() % candidates.length],
      growable: false,
    );
    targets.shuffle(_rng);
    return targets;
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
              staggerSpan: 1 - _maxDelayFrac,
              outlineVertices: _outlineVertices,
              startPoints: _startPoints,
              targetPoints: _targetPoints,
              delays: _delays,
              solidText: _solidText,
              solidOrigin: _solidOrigin,
              solidSize: _solidSize,
              waveTopLeft: _waveTopLeft,
              waveSize: _waveSize,
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
    required this.staggerSpan,
    required this.outlineVertices,
    required this.startPoints,
    required this.targetPoints,
    required this.delays,
    required this.solidText,
    required this.solidOrigin,
    required this.solidSize,
    required this.waveTopLeft,
    required this.waveSize,
  }) : super(repaint: Listenable.merge([controller, shimmer]));

  final AnimationController controller;
  final AnimationController shimmer;
  final double holdFraction;

  /// Per-particle travel window as a fraction of the morph (1 - maxDelayFrac).
  final double staggerSpan;
  final List<Offset> outlineVertices;
  final List<Offset> startPoints;
  final List<Offset> targetPoints;
  final List<double> delays;
  final TextPainter? solidText;
  final Offset solidOrigin;
  final Size solidSize;
  final Offset waveTopLeft;
  final double waveSize;

  /// Morph progress within the crossfade window [start, 1.0].
  static const double _crossfadeStart = 0.88;

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

    // Faint state outline behind the dots; fades as the dots leave it.
    final outlineOpacity = 0.38 * (1 - morph);
    if (outlineOpacity > 0.01) {
      final outlinePaint = Paint()
        ..color = _gold.withValues(alpha: outlineOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawPath(Path()..addPolygon(outlineVertices, true), outlinePaint);
    }

    // Crossfade: dots dissolve as the solid wordmark fades in.
    final crossfade =
        ((morph - _crossfadeStart) / (1 - _crossfadeStart)).clamp(0.0, 1.0);
    final shimmerMul = controller.isCompleted
        ? 1 - 0.15 * Curves.easeInOut.transform(shimmer.value)
        : 1.0;

    // ── Dots (fading out through the crossfade) ──
    final dotOpacity = 1 - crossfade;
    if (dotOpacity > 0.01) {
      final dotPaint = Paint()..color = _gold.withValues(alpha: dotOpacity);
      if (targetPoints.isEmpty) {
        // Targets still rasterizing — hold state shows the scatter.
        for (final p in startPoints) {
          canvas.drawCircle(p, 2.2, dotPaint);
        }
      } else {
        for (var i = 0; i < targetPoints.length; i++) {
          // Per-particle staggered progress: delayed start, all landing by
          // the end of the morph.
          final local = ((morph - delays[i]) / staggerSpan).clamp(0.0, 1.0);
          final eased = Curves.easeOutCubic.transform(local);
          final pos = Offset.lerp(startPoints[i], targetPoints[i], eased)!;
          canvas.drawCircle(pos, 2.2, dotPaint);
        }
      }
    }

    // ── Solid wordmark + wave (one lockup: fade in through the crossfade,
    //    then shimmer together at the same opacity) ──
    final solidOpacity = crossfade * shimmerMul;
    final text = solidText;
    if (text != null && solidOpacity > 0.01) {
      // Inflate by a full text-height so the opacity layer never clips glyph
      // ink that sits above the font's ascent line — e.g. the pulli dots over
      // ம் and ல் (a tight rect sheared their tops off).
      final rect = (solidOrigin & solidSize).inflate(solidSize.height);
      canvas.saveLayer(
        rect,
        Paint()..color = Color.fromRGBO(255, 255, 255, solidOpacity),
      );
      text.paint(canvas, solidOrigin);
      canvas.restore();
      _paintWave(canvas, solidOpacity);
    }
  }

  /// The signal-wave brand mark: a source dot with three concentric arcs
  /// radiating up-and-right, matching the real [WaveMark] geometry on a
  /// 64-unit viewBox. Drawn at [opacity] so it pulses in lockstep with the
  /// text.
  void _paintWave(Canvas canvas, double opacity) {
    if (waveSize <= 0) return;
    final s = waveSize / 64;
    final dot = waveTopLeft + Offset(18 * s, 46 * s);
    final fill = Paint()..color = _waveGold.withValues(alpha: opacity);

    // Source dot (present in the real brand mark).
    canvas.drawCircle(dot, 4.5 * s, fill);

    const radii = [12.0, 22.0, 32.0];
    const widths = [3.0, 2.5, 2.0];
    for (var i = 0; i < 3; i++) {
      final paint = Paint()
        ..color = _waveGold.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = widths[i] * s
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: dot, radius: radii[i] * s),
        -math.pi / 2,
        math.pi / 2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashPainter old) =>
      old.startPoints != startPoints ||
      old.targetPoints != targetPoints ||
      old.solidText != solidText;
}
