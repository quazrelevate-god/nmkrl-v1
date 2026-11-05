import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' as physics;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// The glowing emerald fill ramp shared by every "swipe to confirm" action:
/// deep emerald at the track's start, brightening toward a luminous tip right
/// where the fill meets the thumb, so the leading edge reads as glowing as it
/// sweeps. Kept here (not at a call site) so both the report sheet and the
/// support sheet stay visually identical.
const LinearGradient kNkEmeraldGlowFill = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  stops: [0.0, 0.72, 1.0],
  colors: [
    NkColors.emerald600,
    NkColors.emerald500,
    Color(0xFF34D399),
  ],
);

/// iOS "slide to answer"-style confirmation (port of SwipeToConfirm.js).
/// Drag the thumb past ~85% and it settles into the end, fires haptics +
/// [onConfirm]; otherwise it eases back to the start. Pass a changing
/// [resetToken] to snap back (e.g. after a failed submit).
///
/// Styling is fully parametrised so the same control serves the navy report
/// sheet (light track + cream thumb) and the emerald upvote sheet.
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({
    super.key,
    required this.label,
    this.busyLabel = 'Submitting…',
    required this.onConfirm,
    this.busy = false,
    this.disabled = false,
    this.emerald = false,
    this.resetToken = 0,
    this.height = 58,
    this.radius = 16,
    this.thumbWidth = 48,
    this.trackColor,
    this.thumbColor = Colors.white,
    this.thumbIconColor = NkColors.brand,
    this.labelColor = Colors.white,
    this.hintColor = Colors.white,
    this.fillColor,
    this.fillGradient,
    this.uppercaseLabel = false,
  });

  final String label;
  final String busyLabel;
  final VoidCallback onConfirm;
  final bool busy;
  final bool disabled;
  final bool emerald;
  final int resetToken;

  final double height;
  final double radius;
  final double thumbWidth;

  /// Flat track colour. When null the track is the navy (or emerald) gradient.
  final Color? trackColor;
  final Color thumbColor;
  final Color thumbIconColor;
  final Color labelColor;
  final Color hintColor;

  /// The soft progress fill that tracks the thumb. Defaults to a translucent
  /// white on dark tracks; pass a darker tint for light tracks.
  final Color? fillColor;

  /// Optional gradient version of the fill — takes precedence over
  /// [fillColor] when set. Only where supplied; every other user of this
  /// widget keeps its flat fill.
  final Gradient? fillGradient;
  final bool uppercaseLabel;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm>
    with TickerProviderStateMixin {
  static const _pad = 4.0;

  double get _thumbW => widget.thumbWidth;
  double get _thumbH => widget.height - _pad * 2;

  /// Thumb offset in px. A ValueNotifier (not setState) so pointer moves
  /// repaint only this control's subtree — 1:1 with the finger, no lag.
  final ValueNotifier<double> _pos = ValueNotifier(0);
  double _maxX = 1;
  bool _confirmed = false;

  late final AnimationController _hint;
  late final AnimationController _settle;
  VoidCallback? _settleTick;

  @override
  void initState() {
    super.initState();
    _hint = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    if (_isLiquid) {
      // Liquid mode listens to the thumb's own notifier — the drag velocity
      // and spring-stretch are pure read-only followers of [widget]'s
      // existing gesture logic.
      _pos.addListener(_trackLiquid);
    }
  }

  @override
  void didUpdateWidget(SwipeToConfirm old) {
    super.didUpdateWidget(old);
    if (old.resetToken != widget.resetToken) {
      _stopSettle();
      _pos.value = 0;
      setState(() => _confirmed = false);
    }
  }

  @override
  void dispose() {
    _liquidTick?.stop();
    _pos.removeListener(_trackLiquid);
    _liquid.dispose();
    _hint.dispose();
    _settle.dispose();
    _pos.dispose();
    super.dispose();
  }

  void _stopSettle() {
    _settle.stop();
    if (_settleTick != null) {
      _settle.removeListener(_settleTick!);
      _settleTick = null;
    }
  }

  void _animateTo(double to,
      {required Duration duration, VoidCallback? onDone}) {
    _stopSettle();
    final from = _pos.value;
    if ((to - from).abs() < 0.5) {
      _pos.value = to;
      onDone?.call();
      return;
    }
    final curved = CurvedAnimation(parent: _settle, curve: Curves.easeOutCubic);
    void tick() => _pos.value = lerpDouble(from, to, curved.value)!;
    _settleTick = tick;
    _settle
      ..duration = duration
      ..addListener(tick);
    _settle.forward(from: 0).then((_) {
      if (_settleTick == tick) _stopSettle();
      onDone?.call();
    });
  }

  void _onRelease() {
    if (_pos.value >= _maxX * 0.85) {
      HapticFeedback.mediumImpact();
      setState(() => _confirmed = true);
      _animateTo(_maxX,
          // Liquid fill snaps to 100% over 250ms.
          duration:
              _isLiquid ? const Duration(milliseconds: 250) : const Duration(milliseconds: 220),
          onDone: widget.onConfirm);
    } else {
      _animateTo(0,
          // Liquid fill sloshes back over 800ms (easeOutCubic in the curve),
          // so the liquid eases home instead of popping back.
          duration:
              _isLiquid ? const Duration(milliseconds: 800) : const Duration(milliseconds: 260));
    }
  }

  double _fillWidth(double pos) {
    if (pos <= 0 && !_confirmed) return 0;
    // Stop at the thumb's right edge. The old `+ _pad * frac` kept pushing
    // the fill past the thumb, so green bled out through the thumb's rounded
    // corner gaps. Ending flush under the thumb lets its own silhouette
    // cover the seam.
    return _pad + pos + _thumbW;
  }

  /// The label text both copies of the label render (base grey + clipped
  /// white twin over the fill).
  String get labelText =>
      (widget.busy
              ? widget.busyLabel
              : _confirmed
                  ? 'Confirmed'
                  : widget.label)
          .let(widget.uppercaseLabel);

  /// Liquid mode: when a [fillGradient] is supplied the green progress band is
  /// drawn by [_LiquidFillPainter] (wavy leading edge + glow + streaks +
  /// droplets) instead of the gradient Container. Everything else — gesture
  /// handling, thumb, labels — is untouched.
  bool get _isLiquid => widget.fillGradient != null;

  /// Read-only liquid state the painter consumes; notified on every frame the
  /// physics is running.
  final _LiquidState _liquid = _LiquidState();

  /// Ticker driving the spring-stretch, ripple clock, pulse and droplets in
  /// liquid mode. Paused whenever nothing is in motion.
  Ticker? _liquidTick;
  final Stopwatch _liquidClock = Stopwatch();
  physics.SpringSimulation? _stretchSim;
  final Stopwatch _simClock = Stopwatch();
  double _stretchVel = 0;
  double _lastP = 0;
  int _lastMs = 0;

  /// Smoothed drag velocity in px/ms, read straight off the thumb notifier.
  void _trackLiquid() {
    final p = _pos.value;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastMs != 0) {
      final dt = (now - _lastMs) / 1000.0;
      if (dt > 0) {
        final v = (p - _lastP) / dt; // px per ms
        _liquid.vel = _liquid.vel * 0.75 + v * 0.25; // smoothed
      }
    }
    _lastP = p;
    _lastMs = now;
    // Edge-stretch spring: rest target is velocity * 22, clamped to motion
    // limits [-10, +26] px. Restart from the current value and velocity so a
    // direction change mid-drag never fights a stale sim.
    _stretchSim = physics.SpringSimulation(
      const physics.SpringDescription(mass: 1, stiffness: 220, damping: 12),
      _liquid.stretch,
      (_liquid.vel * 22).clamp(-10.0, 26.0),
      _stretchVel,
    );
    _simClock
      ..reset()
      ..start();
    _liquidPlay();
  }

  void _liquidPlay() {
    _liquidClock.start();
    _liquidTick ??= createTicker(_onLiquidTick)..start();
  }

  void _onLiquidTick(Duration d) {
    final dt = _liquidClock.elapsed - _liquidElapsed;
    _liquidElapsed = _liquidClock.elapsed;
    _liquid.t += dt.inMicroseconds / 1e6;

    if (_stretchSim != null) {
      final el = _simClock.elapsed.inMicroseconds / 1e6;
      _liquid.stretch = _stretchSim!.x(el).clamp(-10.0, 26.0);
      _stretchVel = _stretchSim!.dx(el);
      if (_stretchSim!.isDone(el)) {
        _stretchSim = null;
      }
    }

    // Idle detection: drag finished, spring settled, thumb at rest → park the
    // ticker. The next pointer move restarts it via _trackLiquid. (The settle
    // animations keep the thumb notifier changing, which keeps this running
    // through the slosh-back / confirm glide.)
    final idle = _stretchSim == null &&
        _liquid.vel.abs() < 0.005 &&
        (_pos.value <= 0 || _confirmed);
    if (idle && _liquid.t > 0) {
      _liquidTick!.stop();
      _liquidTick = null;
      _liquidClock.reset();
    } else {
      _liquid.touch();
    }
  }

  Duration _liquidElapsed = Duration.zero;

  @override
  Widget build(BuildContext context) {
    final fill = widget.fillColor ?? Colors.white.withValues(alpha: 0.14);
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxX = (constraints.maxWidth - _thumbW - _pad * 2)
            .clamp(1.0, double.infinity);
        final active = !widget.disabled && !widget.busy && !_confirmed;

        return Opacity(
          opacity: widget.disabled ? 0.5 : 1,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.trackColor,
              gradient: widget.trackColor != null
                  ? null
                  : (widget.emerald
                      ? const LinearGradient(
                          colors: [NkColors.emerald500, NkColors.emerald600])
                      : nkBrandGradient),
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: ValueListenableBuilder<double>(
                valueListenable: _pos,
                builder: (context, x, _) {
                  final pct = (x / _maxX).clamp(0.0, 1.0);
                  return Stack(
                    children: [
                      // Base label — same "free track" placement as before
                      // (right of the thumb's rest, left of the chevrons;
                      // FittedBox keeps long labels on one line) — but now
                      // UNDERNEATH the fill, so its grey glyphs disappear
                      // beneath the green as it sweeps past.
                      Positioned(
                        left: _thumbW + 10,
                        right: 52,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                labelText,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: widget.uppercaseLabel ? 12 : 13.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing:
                                      widget.uppercaseLabel ? 0.3 : 0.2,
                                  color: widget.labelColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        // Liquid mode (fillGradient supplied): the green
                        // progress band is painted by [_LiquidFillPainter] —
                        // wavy leading edge, glow, streaks, bubbles, droplets
                        // — sized past the thumb so the wobble and droplets
                        // are visible just beyond it (outer ClipRRect keeps
                        // everything inside the track curve). No gradient:
                        // the original flat/gradient Container fill.
                        child: widget.fillGradient == null
                            ? Container(
                                width: _fillWidth(x),
                                decoration: BoxDecoration(
                                  color: fill,
                                  borderRadius: x < _maxX - 0.5
                                      ? BorderRadius.horizontal(
                                          right: Radius.circular(
                                              widget.radius - 4))
                                      : const BorderRadius.horizontal(),
                                ),
                              )
                            : AnimatedBuilder(
                                animation: _liquid,
                                builder: (context, _) => CustomPaint(
                                  size: Size(_fillWidth(x) + 68, widget.height),
                                  painter: _LiquidFillPainter(
                                    base: _fillWidth(x),
                                    state: _liquid,
                                    thumbW: _thumbW,
                                    maxX: _maxX,
                                  ),
                                ),
                              ),
                      ),
                      // The fill's white twin of the label — identical
                      // geometry to the base copy, clipped at the fill's
                      // right edge, so the glyphs swap to white exactly where
                      // the green runs beneath them. Dark grey on the white
                      // track, white on the green: legible the whole way.
                      Positioned(
                        left: _thumbW + 10,
                        right: 52,
                        top: 0,
                        bottom: 0,
                        child: ClipRect(
                          clipper: _FillEdgeClipper(
                              fillRight: _fillWidth(x),
                              labelLeft: _thumbW + 10),
                          child: IgnorePointer(
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  labelText,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: widget.uppercaseLabel ? 12 : 13.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing:
                                        widget.uppercaseLabel ? 0.3 : 0.2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Hint chevrons
                      Positioned(
                        right: 20,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: (active && pct < 0.2) ? 1 : 0,
                            child: AnimatedBuilder(
                              animation: _hint,
                              builder: (context, _) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(3, (i) {
                                  final t = ((_hint.value - i * 0.136) % 1.0);
                                  final wave = (0.5 - (0.5 - t).abs()) * 2;
                                  return Transform.translate(
                                    offset: Offset(3 * wave, 0),
                                    child: Text(
                                      '›',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                        color: widget.hintColor.withValues(
                                            alpha: 0.25 + 0.55 * wave),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Thumb
                      Positioned(
                        key: const ValueKey('swipe-knob'),
                        left: _pad + x,
                        top: _pad,
                        child: GestureDetector(
                          onHorizontalDragStart:
                              active ? (_) => _stopSettle() : null,
                          onHorizontalDragUpdate: active
                              ? (d) => _pos.value =
                                  (_pos.value + d.delta.dx).clamp(0.0, _maxX)
                              : null,
                          onHorizontalDragEnd:
                              active ? (_) => _onRelease() : null,
                          onHorizontalDragCancel: active ? _onRelease : null,
                          child: Container(
                            height: _thumbH,
                            width: _thumbW,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: widget.thumbColor,
                              borderRadius:
                                  BorderRadius.circular(widget.radius - 4),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: widget.busy
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: widget.thumbIconColor,
                                    ),
                                  )
                                : Icon(
                                    _confirmed
                                        ? Icons.check
                                        : Icons.chevron_right,
                                    size: 24,
                                    color: widget.thumbIconColor,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

extension _Upper on String {
  String let(bool up) => up ? toUpperCase() : this;
}

/// Clips to only what the fill currently covers, offset into the label's own
/// coordinates: the white twin of the label shows only where the green has
/// reached it, so the colour switch travels with the thumb.
class _FillEdgeClipper extends CustomClipper<Rect> {
  const _FillEdgeClipper({required this.fillRight, required this.labelLeft});

  /// The fill's right edge in track coordinates.
  final double fillRight;

  /// The label band's left edge in track coordinates (the clip works in the
  /// Positioned's local space, which starts there).
  final double labelLeft;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, (fillRight - labelLeft).clamp(0.0, size.width),
          size.height);

  @override
  bool shouldReclip(_FillEdgeClipper old) =>
      old.fillRight != fillRight || old.labelLeft != labelLeft;
}

/// Mutable liquid simulation state shared between SwipeToConfirm's physics
/// tick and [_LiquidFillPainter]. One instance per control; notifyListeners
/// fires only while the physics is running.
class _LiquidState extends ChangeNotifier {
  /// Wall clock for ripples, streak drift, bubbles and the glow pulse.
  double t = 0;

  /// Smoothed drag velocity, px per ms (positive = dragging right).
  double vel = 0;

  /// Spring-driven edge stretch in px, clamped to [-10, +26].
  double stretch = 0;

  /// Public repaint pump (ChangeNotifier.notifyListeners is protected to the
  /// class; the physics tick lives in the widget's state instead).
  void touch() => notifyListeners();
}

/// The liquid progress fill: from x=0 to a wavy leading edge just ahead of
/// the thumb — a rounded ~9px bulge plus a sine ripple whose amplitude swells
/// with drag velocity — with a blurred #00F5A0 glow behind the solid fill,
/// drifting streak lines and rising bubble outlines clipped inside the fill,
/// and droplets that flick ahead of the edge on fast drags. The CustomPaint
/// runs 68px wider than the base fill so the bulge, ripple and droplets have
/// room without escaping the outer ClipRRect (which clips them at the track
/// edge and keeps everything inside the track curve).
class _LiquidFillPainter extends CustomPainter {
  const _LiquidFillPainter({
    required this.base,
    required this.state,
    required this.thumbW,
    required this.maxX,
  });

  /// Static thumb coverage (pad + thumb travel + thumb width) in
  /// painter-local px.
  final double base;

  final _LiquidState state;

  /// The thumb's full width, so the edge can be placed relative to its centre.
  final double thumbW;

  /// Full-drive thumb offset, for turning coverage into a 0..1 progress.
  final double maxX;

  static const Color _cLime = Color(0xFF7FE0B8);
  static const Color _cGreen = Color(0xFF1FE08F);
  static const Color _cMint = Color(0xFF3DFFD0);
  static const Color _cAqua = Color(0xFF9CFFEA);
  static const Color _cGlow = Color(0xFF00F5A0);
  static const Color _cStreak = Color(0xFFBFFFEF);
  static const Color _cBubble = Color(0xFFE6FFF9);

  /// Progress 0..1 — drive (thumb travel) over the full travel distance.
  double get _prog => maxX > 0
      ? ((base - 4.0).clamp(0.0, maxX) / maxX).clamp(0.0, 1.0)
      : 0.0;

  /// Leading-edge x at a height-fraction [t] (0 = top, 1 = bottom). Rests a
  /// little ahead of the pasted thumb centre so the wobble is visible beyond
  /// the knob; the middle of the edge bulges right by ~9px; a velocity-driven
  /// sine ripple with a 1.5-wave shape wobbles it as the liquid moves.
  double edgeAt(double t) {
    if (base <= 0) return 0;
    final amp = 1.5 + math.min(state.vel.abs() * 2.5, 5.0);
    return base -
        thumbW * 0.30 +
        state.stretch +
        math.sin(math.pi * t) * 9.0 +
        amp * math.sin(t * 2 * math.pi * 1.5 - state.t * 2 * math.pi * 1.2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (base <= 0) return;
    final h = size.height;
    final p = _prog;

    // Fill path: left edge → wavy right edge → bottom-left → close. 24
    // samples of the edge are enough for a ~9px bulge and <=5px ripple.
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(edgeAt(0), 0);
    const steps = 24;
    for (var i = 1; i <= steps; i++) {
      final ty = i / steps;
      path.lineTo(edgeAt(ty), ty * h);
    }
    path
      ..lineTo(0, h)
      ..close();

    // Glow first (blurred outward), solid gradient fill on top afterwards.
    final pulse =
        0.92 + 0.08 * (0.5 + 0.5 * math.sin(state.t * 2 * math.pi * 0.8));
    final glowSigma = (12 + p * 44 / 2) * pulse;
    canvas.drawPath(
      path,
      Paint()
        ..color = _cGlow
        ..style = PaintingStyle.fill
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma),
    );

    // The gradient is sized to the fill (0..edge+bulge), not the track.
    final fillRect = Rect.fromLTWH(0, 0, edgeAt(0.5) + 9, h);
    canvas.drawPath(
      path,
      Paint()
        ..shader =
            const LinearGradient(colors: [_cLime, _cGreen, _cMint, _cAqua])
                .createShader(fillRect)
        ..style = PaintingStyle.fill,
    );

    // Interior detail lives strictly inside the fill path.
    canvas.save();
    canvas.clipPath(path);

    // 4 drifting wavy streak lines, evenly spaced, slowly swimming.
    final streakPaint = Paint()
      ..color = _cStreak
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final right = edgeAt(0.5);
    for (var i = 0; i < 4; i++) {
      final y = h * ((i + 0.5) / 4);
      final streak = Path();
      for (var x = 0.0; x <= right; x += 8) {
        final yy = y + math.sin(x * 0.045 + state.t * 1.1 + i * 1.7) * 3.5;
        if (x == 0) {
          streak.moveTo(x, yy);
        } else {
          streak.lineTo(x, yy);
        }
      }
      canvas.drawPath(streak, streakPaint);
    }

    // ~9 rising bubble outlines.
    final bubblePaint = Paint()
      ..color = _cBubble
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (var j = 0; j < 9; j++) {
      final fx = ((j * 0.618) + state.t * 0.05) % 1.0;
      final fy = (state.t * 0.12 + j * 0.137) % 1.0;
      canvas.drawCircle(
        Offset(fx * (right - 8) + 4, h * (1 - fy)),
        2.2,
        bubblePaint,
      );
    }
    canvas.restore();

    // Droplets: only while the drag is genuinely fast (velocity > 0.15),
    // flick up to 3 droplets ahead of the edge that travel ~34px and shrink
    // to nothing.
    if (state.vel > 0.15) {
      final drop = Paint()
        ..color = _cMint
        ..style = PaintingStyle.fill;
      for (var k = 0; k < 3; k++) {
        const cycle = 0.45;
        final s = ((state.t + k * cycle / 3) % cycle) / cycle; // 0..1
        final r = 3.2 * (1 - s);
        if (r <= 0.3) continue;
        canvas.drawCircle(
          Offset(right + 6 + s * 34, h * (0.30 + 0.22 * k)),
          r,
          drop,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_LiquidFillPainter old) => true;
}

