import 'package:latlong2/latlong.dart';

/// The municipal corporation the app is serving — GET /api/corporation.
///
/// The MLA office's console switches the live corporation (Tambaram or
/// Chennai), so the app carries no city of its own: the map centre, the name
/// shown to people and the ward -> constituency table all come from here.
class Corporation {
  const Corporation({
    required this.id,
    required this.name,
    required this.shortName,
    required this.center,
    this.zoom = 12.5,
    this.constituencies = const {},
  });

  /// 'tambaram' | 'chennai'.
  final String id;

  /// "Tambaram City Municipal Corporation".
  final String name;

  /// "Tambaram".
  final String shortName;

  /// Where the map opens when there is no GPS fix.
  final LatLng center;
  final double zoom;

  /// Constituency -> its ward numbers. A ward on a boundary is under both.
  final Map<String, List<String>> constituencies;

  factory Corporation.fromJson(Map<String, dynamic> json) {
    final c = json['center'];
    final center = (c is List && c.length == 2)
        ? LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble())
        : kDefaultCorporationCenter;
    final raw = json['constituencies'];
    return Corporation(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      shortName: '${json['short_name'] ?? json['name'] ?? ''}',
      center: center,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 12.5,
      constituencies: raw is Map
          ? {
              for (final e in raw.entries)
                '${e.key}': [for (final w in (e.value as List? ?? const [])) '$w'],
            }
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'short_name': shortName,
        'center': [center.latitude, center.longitude],
        'zoom': zoom,
        'constituencies': constituencies,
      };
}

/// Middle of Tambaram, the pilot — used only before the app has ever heard
/// from the server which corporation is live.
const kDefaultCorporationCenter = LatLng(12.9376, 80.1355);
