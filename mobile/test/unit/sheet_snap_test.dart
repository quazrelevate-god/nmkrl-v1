import 'package:flutter_test/flutter_test.dart';
import 'package:namma_kural/features/home/home_screen.dart';

/// The sheet's smallest stop is a response to the map, not a drag target.
/// Pulling or scrolling the sheet down must bottom out at the floor; only
/// touching the map may take it below that.
void main() {
  const mini = 0.14, floor = 0.34, max = 0.86;

  test('a drag cannot reach the mini stop', () {
    final stops = sheetSnapStops(
        mini: mini, floor: floor, max: max, allowMini: false);
    expect(stops, [floor, max]);
    expect(stops, isNot(contains(mini)));
    expect(stops.first, floor, reason: 'a downward drag must stop at the floor');
  });

  test('a map gesture opens the mini stop', () {
    expect(
      sheetSnapStops(mini: mini, floor: floor, max: max, allowMini: true),
      [mini, floor, max],
    );
  });

  test('stops stay ascending, which the sheet asserts on', () {
    for (final allow in [true, false]) {
      final stops = sheetSnapStops(
          mini: mini, floor: floor, max: max, allowMini: allow);
      for (var i = 1; i < stops.length; i++) {
        expect(stops[i], greaterThan(stops[i - 1]));
      }
    }
  });
}
