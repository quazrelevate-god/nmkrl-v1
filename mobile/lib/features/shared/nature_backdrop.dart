import 'package:flutter/material.dart';

import 'wave_mark.dart';

/// The banner behind the masthead: a navy Chennai skyline — the Kapaleeshwarar
/// gopuram, the Bandra-style cable bridge, Ripon Building and the Thiruvalluvar
/// statue — under gold swooshes.
const String kBannerAsset = 'assets/scenery/appbar_banner.webp';

/// The asset's proportions (1600 x 875). The masthead is sized from this
/// rather than the other way round, so the artwork is never stretched or
/// cropped to fit a box it does not belong in.
///
/// The lower third of the asset is a DISSOLVE: the scene's bottom edge faded
/// to full transparency. It exists so the banner does not meet the map at a
/// hard horizontal cut. The band is laid out so that dissolve happens behind
/// the floating story panel — the join is simply never visible.
const double kBannerAspect = 1600 / 875;

/// How much of the asset is the scene proper, before the dissolve begins.
const double kBannerSolidFraction = 595 / 875;

/// Vertical band reserved for the wordmark, measured from under the status
/// bar. The app bar is parked directly below it, so the mark is never clipped
/// however tall the device's status bar is — which is exactly what went wrong
/// when the bar's position was derived from the banner height alone.
const double kWordmarkBand = 52;

/// Height of the wordmark itself, centred in that band.
const double kWordmarkHeight = 38;

/// What the whole asset occupies at [width], dissolve included, at its true
/// proportions — never cropped and never stretched.
double bannerHeight(double width) => width / kBannerAspect;

/// Where the scene's bottom edge falls — the point the dissolve starts from.
/// The app bar is placed against THIS, not against [bannerHeight]: hanging it
/// off the asset's foot would park it in the middle of the fade.
double bannerSolidHeight(double width) =>
    bannerHeight(width) * kBannerSolidFraction;

/// The banner, with the wordmark centred on it.
///
/// It replaced a pale sky plate. That one had to be bright because the app bar
/// sat ON it and needed contrast; this one carries the brand mark instead, so
/// it can be the deep navy the rest of the identity uses, and the bar floats
/// clear of it below.
class NatureBackdrop extends StatelessWidget {
  const NatureBackdrop({super.key, required this.height, this.topInset = 0});

  /// Painted height. Normally [bannerHeight] of the screen width; a caller
  /// may pass LESS to stop the band spilling below the story panel on a very
  /// wide screen. Anything over the limit is clipped off the bottom of the
  /// dissolve, where the artwork is already transparent.
  final double height;

  /// Status-bar inset, so the wordmark centres in the space actually visible
  /// below the clock rather than in the raw rectangle.
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // fitWidth + top alignment inside a ClipRect, NOT cover: cover would
          // crop the gopuram and the statue off the sides to fill a short box.
          // This keeps the scene whole at its true proportions and takes any
          // shortfall off the bottom of the fade instead.
          ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: Image.asset(
            kBannerAsset,
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            // Decoration; a screen reader announcing it would only get between
            // the user and the bar's own controls.
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF092B54)),
              ),
            ),
          ),
          // The wordmark, centred in the band below the status bar. The dark
          // variant of the asset: this banner is navy, and the light one is
          // cut for a white bar.
          // Centred in [kWordmarkBand] directly under the status bar, NOT at
          // a fraction of the banner: a fraction moves with the artwork while
          // the app bar does not, which is how the mark ended up half under
          // the bar on a phone with a tall status bar.
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            height: kWordmarkBand,
            child: const Center(child: BrandLogo(height: kWordmarkHeight)),
          ),
        ],
      ),
    );
  }
}
