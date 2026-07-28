import 'package:flutter/material.dart';

import '../../core/i18n.dart';
import '../../domain/status_meta.dart';

/// Small rounded status badge. Statuses in the "pending" family softly pulse
/// (port of the .glow-pending CSS animation).
class StatusChip extends StatefulWidget {
  const StatusChip({super.key, required this.status, this.fontSize = 9});

  final String status;
  final double fontSize;

  @override
  State<StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<StatusChip>
    with SingleTickerProviderStateMixin {
  // Created lazily only for glowing statuses — and never first-touched in
  // dispose() (a late-final field there would crash on non-glowing chips).
  AnimationController? _pulse;

  bool get _glows =>
      widget.status == 'PENDING_VERIFICATION' || widget.status == 'SUBMITTED';

  void _syncController() {
    if (_glows) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2),
      );
      if (!_pulse!.isAnimating) _pulse!.repeat();
    } else {
      _pulse?.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(StatusChip old) {
    super.didUpdateWidget(old);
    _syncController();
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = statusMeta(widget.status);
    final chip = Container(
      padding: EdgeInsets.symmetric(
          horizontal: widget.fontSize * 0.8, vertical: widget.fontSize * 0.28),
      decoration: BoxDecoration(
        color: m.badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: m.badgeBorder),
      ),
      child: Text(
        context.tr(m.label),
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w600,
          color: m.badgeFg,
          height: 1.2,
        ),
      ),
    );
    final pulse = _pulse;
    if (!_glows || pulse == null) return chip;
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        // 0→1→0 breathing glow.
        final t = (0.5 - (0.5 - pulse.value).abs()) * 2;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF64748B)
                    .withValues(alpha: 0.22 + 0.16 * t),
                blurRadius: 8 + 8 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: chip,
    );
  }
}
