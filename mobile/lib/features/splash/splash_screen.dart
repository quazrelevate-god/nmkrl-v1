import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/providers.dart';
import 'tamil_nadu_outline.dart';

/// The splash navy is the app's authoritative brand navy — it now lives in the
/// theme as [NkColors.navyPrimary] so every other surface can match it exactly.
const _navy = NkColors.navyPrimary;
const _gold = Color(0xFFD4A537);
// Light-beige palette for the solid wordmark gradient.
const _beigeLight = Color(0xFFFBF3DC);
const _beigeMid = Color(0xFFE7CE96);

/// Animated government splash. Gold particles hold along the Tamil Nadu state
/// outline, then swarm along randomized curved paths and settle into the shape
/// of the நம்குரல் wordmark. As they arrive, the particles dissolve and the
/// SOLID wordmark (light-beige gradient) fades in over a soft background glow —
/// then the whole scene fades out before navigating to the entry screen.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  static const int particleCount = 380;
  static const String _wordmark = 'நம்குரல்';

  // Phase boundaries as fractions of the main controller.
  static const double _holdEnd = 0.18; // particles resting on the outline
  static const double _morphEnd = 0.60; // particles have reached the wordmark
  static const double _revealStart = 0.54; // solid text starts fading in
  static const double _revealEnd = 0.76; // solid text fully in, dots gone
  static const double _fadeStart = 0.90; // whole scene begins to fade out

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );
  // Independent slow pulse for the background glow.
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  List<Offset> _outlineVertices = const [];
  List<Offset> _startPoints = const [];
  List<Offset> _targetPoints = const [];
  // Per-particle curve control point + arrival stagger (precomputed once so the
  // paths stay stable frame-to-frame — the "randomness" is fixed, not jittery).
  List<Offset> _controlPoints = const [];
  List<double> _delays = const [];
  static const double _textWidthFrac = 0.85;

  bool _initialized = false;
  bool _navigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final size = MediaQuery.sizeOf(context);
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
    _glow.dispose();
    super.dispose();
  }

  Future<void> _startAfterTargets(Size size) async {
    _targetPoints = await _computeTextTargetPoints(size, particleCount);
    _buildParticlePaths();
    if (!mounted) return;
    setState(() {});

    final done = Completer<void>();
    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed && !done.isCompleted) done.complete();
    });
    _controller.forward();

    var route = '/login';
    await Future.wait([
      done.future,
      _runRealAppInit()
          .timeout(const Duration(seconds: 5), onTimeout: () => '/login')
          .then((r) => route = r),
    ]);
    if (!mounted || _navigated) return;
    _navigated = true;
    context.go(route);
  }

  /// Give every particle a randomized quadratic-bezier control point (so it
  /// arcs, rather than sliding straight in) and a small arrival delay (so the
  /// cloud swarms in over a window instead of snapping in lockstep).
  void _buildParticlePaths() {
    final rnd = math.Random(7);
    final n = math.min(_startPoints.length, _targetPoints.length);
    final ctrl = <Offset>[];
    final delays = <double>[];
    for (var i = 0; i < n; i++) {
      final s = _startPoints[i];
      final t = _targetPoints[i];
      final mid = Offset.lerp(s, t, 0.5)!;
      final d = t - s;
      final dist = d.distance == 0 ? 1 : d.distance;
      // Unit perpendicular to the start→target line.
      final perp = Offset(-d.dy / dist, d.dx / dist);
      // Random sideways bow (both directions) + a little along-line wander.
      final bow = (rnd.nextDouble() - 0.5) * 2 * dist * 0.55;
      final along = (rnd.nextDouble() - 0.5) * dist * 0.25;
      final tangent = Offset(d.dx / dist, d.dy / dist);
      ctrl.add(mid + perp * bow + tangent * along);
      delays.add(rnd.nextDouble() * 0.35); // 0..0.35 of the morph window
    }
    _controlPoints = ctrl;
    _delays = delays;
  }

  Future<String> _runRealAppInit() async {
    if (ref.read(authProvider)) return '/home';
    if (ref.read(coordinatorAuthProvider) != null) return '/coordinator';
    return '/login';
  }

  Future<List<Offset>> _computeTextTargetPoints(Size screen, int count) async {
    const style = TextStyle(fontSize: 100, fontWeight: FontWeight.w900);
    final probe = TextPainter(
      text: const TextSpan(text: _wordmark, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final scale = (screen.width * _textWidthFrac) / probe.width;
    final painter = TextPainter(
      text: TextSpan(
        text: _wordmark,
        style: style.copyWith(fontSize: 100 * scale, color: _gold),
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
      return List.filled(count, screen.center(Offset.zero));
    }
    final step = candidates.length / count;
    return List.generate(
      count,
      (i) => origin + candidates[(i * step).floor() % candidates.length],
      growable: false,
    );
  }

  double _phase(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _navy,
        body: AnimatedBuilder(
          animation: Listenable.merge([_controller, _glow]),
          builder: (context, _) {
            final t = _controller.value;
            final morph = _phase(t, _holdEnd, _morphEnd);
            final reveal =
                Curves.easeOut.transform(_phase(t, _revealStart, _revealEnd));
            final sceneFade = _phase(t, _fadeStart, 1.0);
            final glowPulse = Curves.easeInOut.transform(_glow.value);

            return Opacity(
              opacity: (1 - sceneFade).clamp(0.0, 1.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: _navy),

                  // Soft background glow behind the wordmark (fades in with
                  // the reveal, then breathes via the glow pulse).
                  Center(
                    child: Opacity(
                      opacity: reveal * (0.55 + 0.45 * glowPulse),
                      child: Container(
                        width: size.width * 0.9,
                        height: size.width * 0.9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              _gold.withValues(alpha: 0.28),
                              _gold.withValues(alpha: 0.10),
                              _gold.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Particle field (dissolves as the solid text arrives).
                  Opacity(
                    opacity: (1 - reveal).clamp(0.0, 1.0),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _ParticlePainter(
                        morph: morph,
                        outlineVertices: _outlineVertices,
                        startPoints: _startPoints,
                        controlPoints: _controlPoints,
                        targetPoints: _targetPoints,
                        delays: _delays,
                      ),
                    ),
                  ),

                  // Solid wordmark with a light-beige gradient + soft glow.
                  Center(
                    child: Opacity(
                      opacity: reveal,
                      child: Transform.scale(
                        scale: 0.96 + 0.04 * reveal,
                        child: SizedBox(
                          width: size.width * _textWidthFrac,
                          child: ShaderMask(
                            shaderCallback: (rect) => const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_beigeLight, _beigeMid, _beigeLight],
                              stops: [0.0, 0.5, 1.0],
                            ).createShader(rect),
                            blendMode: BlendMode.srcIn,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              child: Text(
                                _wordmark,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  height: 1.0,
                                  shadows: [
                                    Shadow(
                                      color: _gold.withValues(
                                          alpha: 0.55 * glowPulse),
                                      blurRadius: 28,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.morph,
    required this.outlineVertices,
    required this.startPoints,
    required this.controlPoints,
    required this.targetPoints,
    required this.delays,
  });

  final double morph; // 0..1 within the morph phase
  final List<Offset> outlineVertices;
  final List<Offset> startPoints;
  final List<Offset> controlPoints;
  final List<Offset> targetPoints;
  final List<double> delays;

  static Offset _quad(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return a * (u * u) + c * (2 * u * t) + b * (t * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Faint outline behind the particles; fades as the swarm departs.
    final outlineOpacity = 0.32 * (1 - morph);
    if (outlineOpacity > 0.01 && outlineVertices.isNotEmpty) {
      canvas.drawPath(
        Path()..addPolygon(outlineVertices, true),
        Paint()
          ..color = _gold.withValues(alpha: outlineOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final dot = Paint()..color = _gold;
    if (targetPoints.isEmpty || controlPoints.isEmpty) {
      for (final p in startPoints) {
        canvas.drawCircle(p, 2.2, dot);
      }
      return;
    }

    const window = 0.35; // max per-particle stagger
    for (var i = 0; i < targetPoints.length; i++) {
      final delay = delays[i];
      final local =
          ((morph - delay) / (1 - window)).clamp(0.0, 1.0);
      final e = Curves.easeInOutCubic.transform(local);
      final pos = _quad(startPoints[i], controlPoints[i], targetPoints[i], e);
      // Particles are a touch brighter/larger in flight, tightening on arrival.
      final r = 2.6 - 0.6 * e;
      dot.color = _gold.withValues(alpha: 0.55 + 0.45 * (1 - e));
      canvas.drawCircle(pos, r, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.morph != morph ||
      old.startPoints != startPoints ||
      old.targetPoints != targetPoints;
}
