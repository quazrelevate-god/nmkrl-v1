import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/features/coordinator/coordinator_home_screen.dart';
import 'package:namma_kural/features/home/home_screen.dart';
import 'package:namma_kural/features/home/widgets/profile_header.dart';
import 'package:namma_kural/features/shared/nature_backdrop.dart';
import 'package:namma_kural/features/stories/story_rail.dart';

/// Geometry the masthead has to hold on EVERY phone, not just the emulator.
/// Both of these were found on a real device (Redmi 15A, tall status bar)
/// after they looked fine at 411dp.
void main() {
  const devices = <String, (double width, double inset)>{
    'emulator 411dp, short inset': (411, 24),
    'Pixel-ish 393dp': (393, 32),
    'Redmi 15A, tall inset': (393, 34),
    'tall inset, narrow screen': (360, 48),
    'punch-hole worst case': (360, 56),
    'small phone': (320, 44),
    'tablet-ish': (600, 28),
  };

  devices.forEach((name, d) {
    final (width, inset) = d;

    // kBackdropHeight is, by construction, the top of the story panel.
    double panelTop(double Function(double, double) backdrop) =>
        backdrop(inset, width);

    group(name, () {
      test('the app bar never rides up over the wordmark', () {
        final wordmarkBottom = inset + kWordmarkBand;
        expect(kAppBarTop(inset, width), greaterThanOrEqualTo(wordmarkBottom));
        expect(kCoordAppBarTop(inset, width),
            greaterThanOrEqualTo(wordmarkBottom));
      });

      test('the banner dissolves away before the story panel ends', () {
        // The band is clamped to the panel's foot, so a hard edge can never
        // show. What this guards is that the clamp is not CUTTING anything
        // worth seeing: on a phone the fade must finish on its own, with the
        // clamp doing nothing.
        if (width > 480) return; // portrait phones only; app is portrait-locked
        for (final backdrop in [kBackdropHeight, kCoordBackdropHeight]) {
          expect(bannerHeight(width),
              lessThanOrEqualTo(panelTop(backdrop) + kStoryRailHeight),
              reason: 'the clamp would bite into a still-visible fade');
        }
      });

      test('the dissolve is well past half way at the panel midpoint', () {
        // This is the look that was asked for: banner and map converge at the
        // middle of the story panel, so the join is never visible.
        final halfFaded =
            bannerSolidHeight(width) + (bannerHeight(width) - bannerSolidHeight(width)) / 2;
        for (final backdrop in [kBackdropHeight, kCoordBackdropHeight]) {
          final midPanel = panelTop(backdrop) + kStoryRailHeight / 2;
          expect(midPanel, greaterThanOrEqualTo(halfFaded),
              reason: 'the banner would still be solid at the panel midpoint');
        }
      });

      test('the app bar still overlaps the scene, never floats under it', () {
        expect(kAppBarTop(inset, width),
            lessThan(bannerSolidHeight(width) + kAppBarHeight));
      });
    });
  });

  test('the banner is never cropped or stretched', () {
    expect(bannerHeight(411), closeTo(411 / (1600 / 875), 0.01));
    expect(bannerSolidHeight(411), closeTo(411 / (1600 / 595), 0.01));
  });

  test('components stayed at the sizes the geometry assumes', () {
    expect(kAppBarHeight, 46);
    expect(kStoryRailHeight, 84);
    expect(kWordmarkBand, 52);
    expect(kWordmarkHeight, 38);
  });
}
