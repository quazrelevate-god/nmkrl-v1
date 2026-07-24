import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// iOS "slide to answer"-style confirmation (port of SwipeToConfirm.js).
/// Drag the knob past ~85% and it settles into the end, fires haptics +
/// [onConfirm]; otherwise it eases back to the start. Pass a changing
/// [resetToken] to snap back (e.g. after a failed submit).
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
  });

  final String label;
  final String busyLabel;
  final VoidCallback onConfirm;
  final bool busy;
  final bool disabled;
  final bool emerald;
  final int resetToken;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm>
    with TickerProviderStateMixin {
  static const _knob = 48.0;
  static const _pad = 4.0;
  static const _radius = 16.0;

  /// Knob offset in px. A ValueNotifier (not setState) so pointer moves
  /// repaint only this control's subtree — 1:1 with the finger, no
  /// build-frame lag.
  final ValueNotifier<double> _pos = ValueNotifier(0);
  double _maxX = 1;
  bool _confirmed = false;

  // Created eagerly in initState — a late-final first touched in dispose()
  // (possible when the control is busy from the first frame) would crash.
  late final AnimationController _hint;

  /// Drives release animations (ease back to start / settle into the end).
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

  /// Animate the knob from its current offset to [to] with an ease-out
  /// curve; [onDone] fires only when the run completes uninterrupted.
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
      // Lock in before animating so jittery follow-up motion can't retrigger.
      HapticFeedback.mediumImpact();
      setState(() => _confirmed = true);
      _animateTo(_maxX,
          duration: const Duration(milliseconds: 220),
          onDone: widget.onConfirm);
    } else {
      _animateTo(0, duration: const Duration(milliseconds: 260));
    }
  }

  /// Fill width behind the knob: collapsed at rest, meets the track's inner
  /// right edge exactly at full extension (the trailing pad is blended in
  /// with drag progress so there's no end gap and no overflow).
  double _fillWidth(double pos) {
    if (pos <= 0 && !_confirmed) return 0;
    final frac = (pos / _maxX).clamp(0.0, 1.0);
    return _pad + pos + _knob + _pad * frac;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxX = (constraints.maxWidth - _knob - _pad * 2)
            .clamp(1.0, double.infinity);
        final active = !widget.disabled && !widget.busy && !_confirmed;

        return Opacity(
          opacity: widget.disabled ? 0.5 : 1,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: NkColors.slate100,
              borderRadius: BorderRadius.circular(_radius),
              border: Border.all(color: NkColors.slate200),
            ),
            // Everything that moves is hard-clipped to the pill so the fill
            // can never poke past the rounded corners, mid-drag or settled.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: ValueListenableBuilder<double>(
                valueListenable: _pos,
                builder: (context, x, _) {
                  final pct = (x / _maxX).clamp(0.0, 1.0);
                  return Stack(
                    children: [
                      // Progress fill
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: _fillWidth(x),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: widget.emerald
                                  ? const [
                                      NkColors.emerald500,
                                      NkColors.emerald600
                                    ]
                                  : const [NkColors.brand, NkColors.brandDark],
                            ),
                          ),
                        ),
                      ),

                      // Label
                      Positioned.fill(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 40),
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: (pct > 0.45 || _confirmed)
                                    ? Colors.white
                                    : NkColors.slate500,
                              ),
                              child: Text(
                                widget.busy
                                    ? widget.busyLabel
                                    : _confirmed
                                        ? 'Confirmed'
                                        : widget.label,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Hint chevrons — faded out instead of removed: taking
                      // them out of the Stack mid-drag would shift the knob's
                      // element index and dispose its recognizer, killing the
                      // in-flight gesture (the pointer-up would never arrive).
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
                                        color: NkColors.slate300.withValues(
                                            alpha: 0.25 + 0.65 * wave),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Knob — follows the raw drag delta 1:1; GestureDetector
                      // supplies the platform touch slop so incidental touches
                      // don't start a drag. Keyed so future structural edits
                      // to this Stack can never re-bind (and dispose) the
                      // element that owns the live drag recognizer.
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
                            height: _knob,
                            width: _knob,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: widget.busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: NkColors.brand,
                                    ),
                                  )
                                : Icon(
                                    _confirmed
                                        ? Icons.check
                                        : Icons.keyboard_double_arrow_right,
                                    size: 22,
                                    color: widget.emerald
                                        ? NkColors.emerald600
                                        : NkColors.brand,
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
