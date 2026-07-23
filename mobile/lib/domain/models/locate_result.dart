/// Result of POST /api/locate — the real GCC zone + ward for a coordinate,
/// resolved via point-in-polygon over the KML boundaries.
class LocateResult {
  const LocateResult({
    this.zone,
    this.zoneName,
    this.region,
    this.ward,
    this.constituencies = const [],
    required this.inside,
  });

  final String? zone;
  final String? zoneName;
  final String? region;
  final String? ward;
  final List<String> constituencies;
  final bool inside;

  int? get wardNumber => ward == null ? null : int.tryParse(ward!);

  factory LocateResult.fromJson(Map<String, dynamic> json) => LocateResult(
        zone: json['zone']?.toString(),
        zoneName: json['zone_name']?.toString(),
        region: json['region']?.toString(),
        ward: json['ward']?.toString(),
        constituencies: (json['detected_constituencies'] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .toList(),
        inside: json['inside'] == true,
      );
}
