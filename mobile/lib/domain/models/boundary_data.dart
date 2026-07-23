import 'package:latlong2/latlong.dart';

/// One boundary feature (a GCC zone or ward) parsed from the GeoJSON served
/// by GET /api/boundaries. Polygon + MultiPolygon are flattened into a list of
/// parts; each part's first ring is the outer ring, the rest are holes.
class BoundaryFeature {
  const BoundaryFeature({
    this.zone,
    this.zoneName,
    this.ward,
    required this.parts,
  });

  final String? zone;
  final String? zoneName;
  final String? ward;
  final List<List<List<LatLng>>> parts;

  /// Centroid of all outer-ring points — mirrors the web's jumpToEgmore math.
  LatLng centroid() {
    var lat = 0.0, lng = 0.0, n = 0;
    for (final part in parts) {
      if (part.isEmpty) continue;
      for (final p in part.first) {
        lat += p.latitude;
        lng += p.longitude;
        n++;
      }
    }
    if (n == 0) return const LatLng(13.0827, 80.2081);
    return LatLng(lat / n, lng / n);
  }
}

class BoundaryData {
  const BoundaryData({required this.zones, required this.wards});

  final List<BoundaryFeature> zones;
  final List<BoundaryFeature> wards;

  static List<List<LatLng>> _rings(List<dynamic> rings) => rings
      .map<List<LatLng>>(
        (ring) => (ring as List<dynamic>)
            .map<LatLng>(
              (pt) => LatLng(
                ((pt as List<dynamic>)[1] as num).toDouble(),
                (pt[0] as num).toDouble(),
              ),
            )
            .toList(),
      )
      .toList();

  static BoundaryFeature _feature(Map<String, dynamic> f) {
    final props = (f['properties'] as Map<String, dynamic>?) ?? const {};
    final geometry = (f['geometry'] as Map<String, dynamic>?) ?? const {};
    final type = geometry['type'];
    final coords = geometry['coordinates'] as List<dynamic>? ?? const [];
    final parts = <List<List<LatLng>>>[];
    if (type == 'Polygon') {
      parts.add(_rings(coords));
    } else if (type == 'MultiPolygon') {
      for (final poly in coords) {
        parts.add(_rings(poly as List<dynamic>));
      }
    }
    return BoundaryFeature(
      zone: props['zone']?.toString(),
      zoneName: props['zone_name']?.toString(),
      ward: props['ward']?.toString(),
      parts: parts,
    );
  }

  static List<BoundaryFeature> _collection(Map<String, dynamic>? fc) =>
      ((fc?['features'] as List<dynamic>?) ?? const [])
          .map((f) => _feature(f as Map<String, dynamic>))
          .toList();

  factory BoundaryData.fromJson(Map<String, dynamic> json) => BoundaryData(
        zones: _collection(json['zones'] as Map<String, dynamic>?),
        wards: _collection(json['wards'] as Map<String, dynamic>?),
      );
}
