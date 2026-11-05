import 'package:flutter/material.dart';

/// Asset behind the masthead: a clean sky-blue wash with a sliver of sea at
/// the lower left and green foliage at the upper right.
const String kAppBarSkyAsset = 'assets/scenery/appbar_sky.webp';

/// The asset's own proportions (2000 x 500). Everything that positions the
/// masthead works back from this, so the picture is never scaled to fit a box
/// it does not belong in — and because the band's height IS the image's height
/// at the screen's width, a wider plate is a shorter band. The source was
/// 2000x667; the top quarter was plain gradient above both the sea and the
/// foliage, so trimming it cost nothing and bought ~34dp of map.
const double kSkyAspect = 2000 / 500;

/// The sky band behind the floating app bar.
///
/// The home used to run the pale basemap straight up under the status bar, so
/// the white app-bar capsule floated on grey tiles and the top of the screen
/// said nothing. This gives it a ground.
///
/// It replaced a coastal photograph — temple, palms, ocean — which, at the
/// width of a phone, had to be tall enough to hold a recognisable subject and
/// was taking a third of the screen before the map began. This asset carries
/// the same idea at a third of the height: sky, a hint of sea, a little green.
/// There is no subject to clear, so the app bar sits back at the top of the
/// screen where it belongs.
///
/// The image is drawn at its NATURAL proportions — [BoxFit.fitWidth], aligned
/// to the top — so it spans the full width and takes whatever height that
/// implies. Nothing is cropped or stretched. Below it the band is plain white,
/// and the wash lands the image into that white before its last row, so there
/// is no edge where one ends and the other starts.
///
/// Both apps float the same masthead: the citizen home and the coordinator
/// home.
class NatureBackdrop extends StatelessWidget {
  const NatureBackdrop({super.key, required this.height});

  /// Full masthead height — status-bar inset, app-bar capsule, spill and the
  /// story rail together.
  final double height;

  /// What the asset occupies at [width], untouched.
  static double imageHeight(double width) => width / kSkyAspect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final imgH = imageHeight(constraints.maxWidth);
          // The ramp that lands the image in the white beneath it.
          // Proportional, so it is the same gesture on a small phone and a
          // large one.
          //
          // Short (0.22, not 0.34): it begins at roughly the capsule's bottom
          // edge, so the blue holds its colour behind the bar and then
          // resolves cleanly into the white the stories sit on — one crisp
          // transition, as in the reference, rather than a long haze that
          // drains the colour out of the band it is supposed to be showing.
          final ramp = (imgH * 0.22).clamp(18.0, 60.0);
          return Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.white),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: imgH,
                child: Image.asset(
                  kAppBarSkyAsset,
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topCenter,
                  // Decoration; a screen reader announcing it would only get
                  // between the user and the app bar's own controls.
                  excludeFromSemantics: true,
                  // A missing or undecodable asset falls back to the sky's own
                  // blue rather than a grey box under the capsule.
                  errorBuilder: (_, __, ___) =>
                      const ColoredBox(color: Color(0xFF9DD8FD)),
                ),
              ),
              // The wash: the image losing its colour just before it ends, so
              // its last row and the white beneath are the same and there is
              // no seam to see.
              Positioned(
                top: imgH - ramp,
                left: 0,
                right: 0,
                height: ramp,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x59FFFFFF),
                        Color(0xE6FFFFFF),
                        Color(0xFFFFFFFF),
                      ],
                      stops: [0, 0.34, 0.76, 1],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The masthead block — the sky band with the story rail under it — drawn as
/// one card tucked over the map.
///
/// Rounding the BOTTOM corners (the same 22 the bottom sheet rounds its top
/// by) and casting a soft shadow onto the map makes the relationship explicit:
/// one layer tucked under another, the map visible in both corners, bookending
/// the sheet at the other end of the screen.
class MastheadCard extends StatelessWidget {
  const MastheadCard({super.key, required this.child});

  final Widget child;

  /// Matches the bottom sheet's corner, the one radius in the composition.
  static const double radius = 22;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(radius),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),
            blurRadius: 18,
            offset: const Offset(0, 5),
            spreadRadius: -3,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}
