import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme.dart';

/// The supplied நம்குரல் wordmark, rendered from its ORIGINAL vector asset —
/// cream gradient lettering plus the `#004AAD` signal arcs. Never redraw this
/// with text/fonts: the asset is the source of truth for the brand mark.
///
/// The artwork's own aspect ratio is ~782:230, so callers size it by [height]
/// and the width follows.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 30});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/nammakural_wordmark.svg',
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
    );
  }
}

/// The gold "signal wave" brand mark — a dot with three concentric arcs
/// opening up-and-right (port of the WaveMark SVG used on splash/login/home).
/// [progress] (0..1) draws the arcs in sequence for the splash animation.
class WaveMark extends StatelessWidget {
  const WaveMark({
    super.key,
    this.size = 24,
    this.color = NkColors.gold300,
    this.progress = 1.0,
  });

  final double size;
  final Color color;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _WaveMarkPainter(color: color, progress: progress),
    );
  }
}

class _WaveMarkPainter extends CustomPainter {
  _WaveMarkPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64; // designed on a 64×64 viewBox
    final dot = Offset(18 * s, 46 * s);

    // Dot appears first.
    final dotT = (progress / 0.25).clamp(0.0, 1.0);
    if (dotT > 0) {
      canvas.drawCircle(
        dot,
        4.5 * s * Curves.easeOutBack.transform(dotT),
        Paint()..color = color,
      );
    }

    // Three arcs sweep in one after another (each ~90° of arc from the
    // vertical, matching the SVG's quarter-circle paths).
    final radii = [12.0, 22.0, 32.0];
    final widths = [3.0, 2.5, 2.0];
    for (var i = 0; i < 3; i++) {
      final t0 = 0.25 + i * 0.25;
      final t = ((progress - t0) / 0.25).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final r = radii[i] * s;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = widths[i] * s
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: dot, radius: r),
        -math.pi / 2,
        (math.pi / 2) * Curves.easeOut.transform(t),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveMarkPainter old) =>
      old.progress != progress || old.color != color;
}

/// நம்குரல் wordmark + wave, as used in headers (deep navy on light glass).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.fontSize = 22, this.color = NkColors.brand});

  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Text(
          'நம்குரல்',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: color,
            height: 1,
          ),
        ),
        Positioned(
          top: -fontSize * 0.45,
          left: fontSize * 1.72,
          child: WaveMark(size: fontSize * 0.72),
        ),
      ],
    );
  }
}
