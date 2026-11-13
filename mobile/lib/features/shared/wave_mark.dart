import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme.dart';

/// The supplied நம்குரல் wordmark, rendered from its ORIGINAL vector assets.
/// Never redraw this with text/fonts: the assets are the source of truth for
/// the brand mark.
///
/// Two authored variants, picked by the surface it sits on:
///   • default — cream lettering + `#004AAD` arcs, for navy backgrounds
///     (splash, login, the report sheet).
///   • [onLight] — navy `#1A2744` lettering + gold `#C8963E` arcs, for white
///     surfaces. The dark-background mark washes out on white, which is why
///     the coordinator bar had to draw its own text instead of using this.
///
/// On navy the lettering comes from the SVG and the signal wave is drawn by
/// [WaveMark] in Flutter. The arcs used to live in the SVG too, as filled
/// ribbons inside a chain of masks and per-arc clipPaths cut to their original
/// size. Moving or thickening them left the outermost one truncated part way
/// through its sweep, and widening every clip, swapping the arc command for
/// cubics and removing the mask outright all failed to free it. Drawing them
/// here instead gives exact control over radius, weight and cap, and there is
/// nothing left that can crop them.
///
/// The light variant still uses its own artwork: it sits on white, it was
/// never touched, and it does not have the fault.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 30, this.onLight = false});

  /// Height of the WHOLE mark, arcs included.
  final double height;
  final bool onLight;

  // Proportions measured off the original artwork before the arcs were taken
  // out of it: word 699.96 x 188.02; arcs 119.33 tall, their foot 105.2 above
  // the word's, their outer radius 105.33 with a 14-unit stroke.
  static const double _wordAspect = 699.957 / 188.016;
  static const double _arcToWord = 119.33 / 188.016;   // 0.635
  static const double _footLift = 105.2 / 188.016;     // 0.560
  static const double _overhang = _arcToWord + _footLift - 1.0; // above word
  static const double _gap = 0.04;

  @override
  Widget build(BuildContext context) {
    if (onLight) {
      return SvgPicture.asset(
        'assets/brand/nammakural_wordmark_light.svg',
        height: height,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
      );
    }
    // The arcs rise above the lettering, so `height` is the whole lockup and
    // the word takes the rest.
    final word = height / (1 + _overhang);
    final arc = word * _arcToWord;
    return SizedBox(
      height: height,
      width: word * _wordAspect + word * _gap + arc,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: SvgPicture.asset(
              'assets/brand/nammakural_wordmark.svg',
              height: word,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),
          Positioned(
            right: 0,
            bottom: word * _footLift,
            child: CustomPaint(
              size: Size.square(arc),
              painter: _SignalArcsPainter(color: const Color(0xFFFFEEBF)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three signal arcs, drawn tight to their box.
///
/// They used to be filled ribbons inside the wordmark SVG, wrapped in masks
/// and per-arc clipPaths cut to their original size. Moving or thickening them
/// left the outermost one truncated part way through its sweep, and widening
/// every clip, swapping the arc command for cubics and dropping the mask all
/// failed to free it. Here there is nothing that can crop them.
class _SignalArcsPainter extends CustomPainter {
  const _SignalArcsPainter({required this.color});

  final Color color;

  /// Radii as fractions of the outermost, and the stroke, from the artwork.
  static const List<double> _radii = [43.30 / 105.33, 74.33 / 105.33, 1.0];
  static const double _stroke = 14.0 / 105.33;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final w = _stroke * s;
    final rOuter = s - w / 2;
    // Centre at the bottom-left, so the arcs open up and to the right.
    final c = Offset(w / 2, s - w / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    for (final f in _radii) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: f * rOuter),
          -math.pi / 2, math.pi / 2, false, paint);
    }
  }

  @override
  bool shouldRepaint(_SignalArcsPainter old) => old.color != color;
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
