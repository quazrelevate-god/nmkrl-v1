import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme.dart';

/// iOS "slide to answer"-style confirmation (port of SwipeToConfirm.js).
/// Drag the knob past ~85% and it locks in, fires haptics + [onConfirm];
/// otherwise it springs back. Pass a changing [resetToken] to snap back
/// (e.g. after a failed submit).
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
    with SingleTickerProviderStateMixin {
  static const _knob = 48.0;
  static const _pad = 4.0;

  double _x = 0;
  bool _dragging = false;
  bool _confirmed = false;

  // Created eagerly in initState — a late-final first touched in dispose()
  // (possible when the control is busy from the first frame) would crash.
  late final AnimationController _hint;

  @override
  void initState() {
    super.initState();
    _hint = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void didUpdateWidget(SwipeToConfirm old) {
    super.didUpdateWidget(old);
    if (old.resetToken != widget.resetToken) {
      setState(() {
        _x = 0;
        _confirmed = false;
        _dragging = false;
      });
    }
  }

  @override
  void dispose() {
    _hint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxX = (constraints.maxWidth - _knob - _pad * 2)
            .clamp(1.0, double.infinity);
        final pct = (_x / maxX).clamp(0.0, 1.0);
        final active = !widget.disabled && !widget.busy && !_confirmed;

        return Opacity(
          opacity: widget.disabled ? 0.5 : 1,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: NkColors.slate100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NkColors.slate200),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Progress fill — collapsed while the knob rests at the start
                // so no colored halo peeks out around it; it sweeps in behind
                // the knob only once the user actually drags.
                AnimatedContainer(
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: NkMotion.settle,
                  width: _x <= 0 && !_confirmed ? 0 : _x + _knob + _pad,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.emerald
                          ? const [NkColors.emerald500, NkColors.emerald600]
                          : const [NkColors.brand, NkColors.brandDark],
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

                // Hint chevrons (idle only)
                if (active && pct < 0.2)
                  Positioned(
                    right: 20,
                    top: 0,
                    bottom: 0,
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

                // Knob
                AnimatedPositioned(
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: NkMotion.settle,
                  left: _pad + _x,
                  top: _pad,
                  child: GestureDetector(
                    onHorizontalDragStart:
                        active ? (_) => setState(() => _dragging = true) : null,
                    onHorizontalDragUpdate: active
                        ? (d) => setState(() =>
                            _x = (_x + d.delta.dx).clamp(0.0, maxX))
                        : null,
                    onHorizontalDragEnd: active
                        ? (_) {
                            setState(() => _dragging = false);
                            if (_x >= maxX * 0.85) {
                              HapticFeedback.mediumImpact();
                              setState(() {
                                _x = maxX;
                                _confirmed = true;
                              });
                              widget.onConfirm();
                            } else {
                              setState(() => _x = 0);
                            }
                          }
                        : null,
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
                              (_confirmed)
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
            ),
          ),
        );
      },
    );
  }
}
