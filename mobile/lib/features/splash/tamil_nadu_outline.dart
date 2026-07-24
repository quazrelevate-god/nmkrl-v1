import 'dart:ui';

/// Height/width aspect ratio of the outline's bounding box — multiply a
/// chosen draw-box width by this to preserve the state's true proportions.
const double kTamilNaduAspect = 1.3503;

/// Normalized (0-1) Tamil Nadu outline points, traced from source artwork
/// via OpenCV contour detection (findContours + approxPolyDP,
/// epsilon = 0.002 × perimeter). Multiply by the target draw box size at
/// render time; the box must keep the [kTamilNaduAspect] ratio.
const List<Offset> tamilNaduOutline = [
  Offset(0.9159, 0.0),
  Offset(0.9019, 0.0324),
  Offset(0.8564, 0.0428),
  Offset(0.8546, 0.061),
  Offset(0.7723, 0.0389),
  Offset(0.7758, 0.0623),
  Offset(0.7461, 0.0804),
  Offset(0.7268, 0.0726),
  Offset(0.7128, 0.096),
  Offset(0.669, 0.0843),
  Offset(0.6445, 0.0947),
  Offset(0.6427, 0.0817),
  Offset(0.6007, 0.0882),
  Offset(0.5394, 0.1686),
  Offset(0.4781, 0.1569),
  Offset(0.4816, 0.1427),
  Offset(0.4413, 0.1271),
  Offset(0.387, 0.1245),
  Offset(0.3625, 0.1595),
  Offset(0.331, 0.1608),
  Offset(0.3363, 0.2114),
  Offset(0.2995, 0.2361),
  Offset(0.3678, 0.2542),
  Offset(0.3468, 0.2918),
  Offset(0.3047, 0.2944),
  Offset(0.289, 0.3256),
  Offset(0.2452, 0.3178),
  Offset(0.2119, 0.3333),
  Offset(0.1909, 0.3178),
  Offset(0.1611, 0.3217),
  Offset(0.1471, 0.358),
  Offset(0.0788, 0.3528),
  Offset(0.0648, 0.3372),
  Offset(0.0, 0.3606),
  Offset(0.0035, 0.3787),
  Offset(0.0753, 0.4008),
  Offset(0.0525, 0.4293),
  Offset(0.1191, 0.4254),
  Offset(0.1313, 0.4578),
  Offset(0.1016, 0.4773),
  Offset(0.1629, 0.5045),
  Offset(0.1559, 0.5318),
  Offset(0.1401, 0.5331),
  Offset(0.1436, 0.5927),
  Offset(0.1804, 0.607),
  Offset(0.2382, 0.5837),
  Offset(0.2557, 0.6083),
  Offset(0.2329, 0.6291),
  Offset(0.2504, 0.655),
  Offset(0.2242, 0.7185),
  Offset(0.2697, 0.7211),
  Offset(0.2837, 0.7393),
  Offset(0.2189, 0.8288),
  Offset(0.2469, 0.856),
  Offset(0.2259, 0.882),
  Offset(0.2522, 0.9144),
  Offset(0.2102, 0.9598),
  Offset(0.2609, 0.9896),
  Offset(0.3205, 0.9987),
  Offset(0.4448, 0.9455),
  Offset(0.4781, 0.8755),
  Offset(0.4729, 0.8457),
  Offset(0.5254, 0.8106),
  Offset(0.7145, 0.7782),
  Offset(0.6813, 0.773),
  Offset(0.648, 0.7406),
  Offset(0.7356, 0.6394),
  Offset(0.7268, 0.6213),
  Offset(0.7461, 0.5979),
  Offset(0.7951, 0.5875),
  Offset(0.8494, 0.5966),
  Offset(0.8179, 0.5927),
  Offset(0.8249, 0.5837),
  Offset(0.8862, 0.5927),
  Offset(0.8792, 0.4994),
  Offset(0.8424, 0.4747),
  Offset(0.8792, 0.4669),
  Offset(0.8564, 0.3658),
  Offset(0.8669, 0.3165),
  Offset(0.8406, 0.3074),
  Offset(0.8284, 0.2815),
  Offset(0.8529, 0.2815),
  Offset(0.8529, 0.297),
  Offset(0.8757, 0.2905),
  Offset(0.9527, 0.1958),
  Offset(0.9982, 0.048),
  Offset(0.9947, 0.0195),
];

/// Walks [path] (treated as a CLOSED polygon — the segment from the last
/// vertex back to the first is included) by cumulative arc length and
/// returns [count] evenly-spaced points along it.
List<Offset> sampleAlongPolyline(List<Offset> path, int count) {
  assert(path.length >= 2 && count > 0);
  final segments = <({Offset a, Offset b, double length})>[];
  var total = 0.0;
  for (var i = 0; i < path.length; i++) {
    final a = path[i];
    final b = path[(i + 1) % path.length];
    final len = (b - a).distance;
    segments.add((a: a, b: b, length: len));
    total += len;
  }
  if (total == 0) return List.filled(count, path.first);

  final out = <Offset>[];
  final step = total / count;
  var seg = 0;
  var segStart = 0.0;
  for (var i = 0; i < count; i++) {
    final d = i * step;
    while (seg < segments.length - 1 && d > segStart + segments[seg].length) {
      segStart += segments[seg].length;
      seg++;
    }
    final s = segments[seg];
    final t = s.length == 0 ? 0.0 : ((d - segStart) / s.length).clamp(0.0, 1.0);
    out.add(Offset.lerp(s.a, s.b, t)!);
  }
  return out;
}
