import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

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
          duration: const Duration(milliseconds: 220),
          onDone: widget.onConfirm);
    } else {
      _animateTo(0, duration: const Duration(milliseconds: 260));
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
                        child: Container(
                          width: _fillWidth(x),
                          // Match the thumb's corner radius so the green
                          // trailing edge follows the same curvature as the
                          // knob resting over it — no square corner peeking
                          // out around the thumb's rounded corners.
                          decoration: BoxDecoration(
                            // Gradient fill (when supplied) draws the same
                            // emerald ramp full-strength instead of a tint;
                            // the flat colour stays the default for every
                            // other caller.
                            color: widget.fillGradient == null ? fill : null,
                            gradient: widget.fillGradient,
                            borderRadius: x < _maxX - 0.5
                                ? BorderRadius.horizontal(
                                    // Same value the thumb uses for its own
                                    // corners (radius - 4) so the arcs sit on
                                    // top of each other exactly.
                                    right: Radius.circular(widget.radius - 4),
                                  )
                                : const BorderRadius.horizontal(),
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
