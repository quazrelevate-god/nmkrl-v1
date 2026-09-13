import 'package:flutter/material.dart';

/// The நம்குரல் wordmark as the splash reveals it — and, since the login screen
/// now continues straight on from the splash's last frame, as the login screen
/// shows it too. One widget, so the hand-off between the two cannot drift: if
/// the logo differed by a pixel in size, colour or font, the swap would show.
const splashWordmarkText = 'நம்குரல்';

/// Width of the fully revealed wordmark, as a fraction of the screen width.
/// The login screen starts its logo here, so both read the same constant.
const kSplashWordmarkWidthFrac = 0.85;

// Gold palette for the wordmark gradient.
//
// The sheen used to run to #FBF3DC at BOTH ends of the ramp, which is very
// nearly white — so every glyph extremity that landed near the gradient's
// start or finish (the dot on ம், the top of ல், the base of கு) rendered
// white instead of gold, and the wordmark looked half-painted. Both ends are
// unambiguously gold now, and the ramp only varies enough to keep the sheen.
const _goldLight = Color(0xFFF6E3B0);
const _goldMid = Color(0xFFDDBE74);

class SplashWordmark extends StatelessWidget {
  const SplashWordmark({super.key, required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_goldLight, _goldMid, _goldLight],
          stops: [0.0, 0.5, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.srcIn,
        // No text shadow here, deliberately. BlendMode.srcIn paints the shader
        // wherever the CHILD has alpha — and a blurred shadow has alpha all
        // around the glyphs, so the gradient filled the shadow's soft
        // rectangle: the translucent box that appeared under the wordmark
        // whenever the glow pulsed.
        child: FittedBox(
          fit: BoxFit.contain,
          child: Text(
            splashWordmarkText,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              // Gold, not white. A ShaderMask only masks what paints INSIDE
              // its bounds, and Tamil combining marks — the dot on ம், the tail
              // of கு — can sit outside them, escaping the mask and showing
              // this colour raw. That was the white on the glyph tips.
              color: _goldMid,
              // No height: 1.0 either. Forcing the line box to the font size is
              // what pushed those marks outside the bounds in the first place.
            ),
          ),
        ),
      ),
    );
  }

  /// Rendered height at [width]. The login form below the resting logo needs
  /// it to know where to start; measured with the same inherited style the
  /// widget itself renders with, so the two agree.
  static double heightFor(BuildContext context, double width) {
    final style = DefaultTextStyle.of(context)
        .style
        .merge(const TextStyle(fontWeight: FontWeight.w900));
    final tp = TextPainter(
      text: TextSpan(text: splashWordmarkText, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width == 0 ? 0 : width * tp.height / tp.width;
  }
}
