/// A citizen grievance, as serialized by the FastAPI backend
/// (serialize_issue in backend/utils.py).
class Issue {
  const Issue({
    required this.id,
    required this.title,
    this.imageUrl,
    this.audioUrl,
    this.transcript,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.upvotes = 0,
    this.createdAt,
    this.areaName,
    this.wardNo,
    this.zone,
    this.coordinatorMessage,
    this.summaryHighlights = const [],
    this.distanceM,
  });

  final String id;
  final String title;
  final String? imageUrl;
  final String? audioUrl;
  final String? transcript;
  final double latitude;
  final double longitude;
  final String status;
  final int upvotes;
  final DateTime? createdAt;
  final String? areaName;
  final int? wardNo;
  final String? zone;
  final String? coordinatorMessage;
  final List<String> summaryHighlights;

  /// Present only on /nearby responses.
  final double? distanceM;

  static double _toDouble(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static int? _toInt(Object? v) =>
      v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));

  factory Issue.fromJson(Map<String, dynamic> json) {
    final rawHighlights = json['summary_highlights'];
    return Issue(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? 'Street Issue'}',
      imageUrl: json['image_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      transcript: json['transcript'] as String?,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      status: '${json['status'] ?? 'ACTIVE'}',
      upvotes: _toInt(json['upvotes']) ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse('${json['created_at']}')
          : null,
      areaName: (json['area_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['area_name'] as String).trim(),
      wardNo: _toInt(json['ward_no']),
      zone: json['zone']?.toString(),
      coordinatorMessage: json['coordinator_message'] as String?,
      summaryHighlights: rawHighlights is List
          ? rawHighlights.map((e) => '$e').toList()
          : const [],
      distanceM:
          json['distance_m'] == null ? null : _toDouble(json['distance_m']),
    );
  }
}

/// Result of POST /api/issues/report: either the created issue, or a nearby
/// duplicate to confirm against (when force=false).
class ReportOutcome {
  const ReportOutcome({this.issue, this.duplicate});

  final Issue? issue;
  final Issue? duplicate;

  bool get isDuplicate => duplicate != null;

  factory ReportOutcome.fromJson(Map<String, dynamic> json) {
    if (json['duplicate_exists'] == true && json['existing_issue'] != null) {
      return ReportOutcome(
        duplicate:
            Issue.fromJson(json['existing_issue'] as Map<String, dynamic>),
      );
    }
    return ReportOutcome(issue: Issue.fromJson(json));
  }
}
