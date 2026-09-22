/// A citizen grievance, as serialized by the FastAPI backend
/// (serialize_issue in backend/utils.py).
class Issue {
  const Issue({
    required this.id,
    required this.title,
    this.imageUrl,
    this.audioUrl,
    this.closureImageUrl,
    this.closureAudioUrl,
    this.transcript,
    this.transcriptTa,
    this.ticketNo,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.upvotes = 0,
    this.createdAt,
    this.areaName,
    this.wardNo,
    this.zone,
    this.constituencies,
    this.mergedFromTicket,
    this.department,
    this.coordinatorMessage,
    this.assignedCoordinator,
    this.escalatedAt,
    this.rejectedAt,
    this.summaryHighlights = const [],
    this.distanceM,
    this.processing = false,
    this.possibleDuplicateId,
    this.duplicateDecision = '',
    this.mergedIntoId,
    this.processingError = '',
  });

  final String id;
  final String title;
  final String? imageUrl;
  final String? audioUrl;

  /// Proof of work captured when the grievance was closed — the live photo and
  /// voice note the coordinator app requires. Shown to the citizen with the
  /// verify prompt, so they are approving something they can actually see.
  final String? closureImageUrl;
  final String? closureAudioUrl;
  final String? transcript;

  /// Tamil translation of the transcript (Gemini returns both). Shown in
  /// Tamil mode; falls back to [transcript] when empty.
  final String? transcriptTa;

  /// Stored, human-friendly tracking id (FMS-XXXXXXXX) from the DB. Falls
  /// back to the deterministic derivation when absent.
  final String? ticketNo;
  final double latitude;
  final double longitude;
  final String status;
  final int upvotes;
  final DateTime? createdAt;
  final String? areaName;
  final int? wardNo;
  final String? zone;

  /// The ward's assembly constituencies, worked out by the server within the
  /// grievance's own corporation (Chennai and Tambaram share ward numbers).
  /// Null from an older backend; then the app's live table is the fallback.
  final List<String>? constituencies;

  /// Set when this card is the grievance the citizen's own report was merged
  /// into: their original ticket number. My Reports shows the surviving
  /// grievance in its place, so the card must say why the ticket differs —
  /// and the confirm prompt belongs to that grievance's own reporter.
  final String? mergedFromTicket;

  /// AI-routed municipal department (used by the coordinator transfer flow).
  final String? department;
  final String? coordinatorMessage;

  /// Username of the coordinator who took ownership (empty/null = unassigned).
  final String? assignedCoordinator;

  /// Non-null when a coordinator escalated the issue — mobile groups these
  /// under a dedicated Escalated tab.
  final DateTime? escalatedAt;

  /// Non-null when the citizen rejected a coordinator's closure — the
  /// coordinator app shows an alert card and keeps it in Assigned.
  final DateTime? rejectedAt;
  final List<String> summaryHighlights;

  /// Present only on /nearby responses.
  final double? distanceM;

  /// True while the backend is still transcribing/routing/de-duplicating a
  /// freshly-submitted report.
  ///
  /// The citizen is NOT shown this. It used to drive a "Reviewing…" pill on
  /// their own card, which meant a slow Gemini call looked like their report
  /// had not gone through; the report is saved either way.
  final bool processing;

  /// Set when the background duplicate check thinks this report duplicates an
  /// existing grievance.
  ///
  /// Staff-facing only. Ruling on it belongs to admin and the ward coordinator
  /// — the citizen cannot know whether a stranger's grievance is the same as
  /// theirs, and used to be asked anyway.
  final String? possibleDuplicateId;

  /// '' until someone rules, then 'merged' or 'separate'.
  final String duplicateDecision;

  /// Set on a report that was folded INTO another grievance.
  final String? mergedIntoId;

  /// Why the background half failed, for the admin console's retry. Never
  /// surfaced in the citizen app.
  final String processingError;

  /// Flagged by detection and nobody has ruled yet.
  bool get awaitingDuplicateReview =>
      (possibleDuplicateId ?? '').isNotEmpty && duplicateDecision.isEmpty;

  /// Empty strings and nulls both mean "not set" here — SQLite columns added
  /// by migration default to '' while fresh rows carry NULL.
  static String? _blankToNull(Object? v) {
    final s = (v ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

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
      closureImageUrl: json['closure_image_url'] as String?,
      closureAudioUrl: json['closure_audio_url'] as String?,
      transcript: json['transcript'] as String?,
      transcriptTa: (json['transcript_ta'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['transcript_ta'] as String).trim(),
      ticketNo: (json['ticket_number'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['ticket_number'] as String).trim(),
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
      constituencies: json['constituencies'] is List
          ? [for (final c in json['constituencies'] as List) '$c']
          : null,
      mergedFromTicket: _blankToNull(json['merged_from_ticket']),
      department: json['department'] as String?,
      coordinatorMessage: json['coordinator_message'] as String?,
      assignedCoordinator: json['assigned_coordinator'] as String?,
      escalatedAt: () {
        final raw = json['escalated_at'];
        if (raw == null || raw == '') return null;
        return DateTime.tryParse('$raw');
      }(),
      rejectedAt: () {
        final raw = json['rejected_at'];
        if (raw == null || raw == '') return null;
        return DateTime.tryParse('$raw');
      }(),
      summaryHighlights: rawHighlights is List
          ? rawHighlights.map((e) => '$e').toList()
          : const [],
      distanceM:
          json['distance_m'] == null ? null : _toDouble(json['distance_m']),
      processing: json['processing'] == true,
      possibleDuplicateId: _blankToNull(json['possible_duplicate_id']),
      duplicateDecision: (json['duplicate_decision'] ?? '').toString(),
      mergedIntoId: _blankToNull(json['merged_into_id']),
      processingError: (json['processing_error'] ?? '').toString(),
    );
  }
}

/// Result of POST /api/issues/report: either the created issue, or a nearby
/// duplicate to confirm against (when force=false).
/// What came back from submitting a report.
///
/// Always a saved grievance now. Reporting used to answer synchronously with
/// `{duplicate_exists, existing_issue}` so the app could put a duplicate
/// dialog in the reporter's way; submission is fire-and-forget and duplicates
/// are settled by staff, so there is no longer a second outcome to represent.
class ReportOutcome {
  const ReportOutcome({this.issue});

  final Issue? issue;

  factory ReportOutcome.fromJson(Map<String, dynamic> json) =>
      ReportOutcome(issue: Issue.fromJson(json));
}
