import 'issue.dart';

/// A grievance offered as the "original" a flagged report may duplicate.
///
/// The server sends these WITHOUT the reporter's name, phone or account id.
/// Detection matches within 100m and pays no attention to ward boundaries, so
/// the original is often in a neighbouring ward or owned by another
/// coordinator — someone the reviewer has no claim over. They get what they
/// need to judge whether it is the same problem, and nothing about the person
/// who reported it.
class DuplicateCandidate {
  const DuplicateCandidate({
    required this.issue,
    required this.distanceM,
    required this.sameWard,
  });

  final Issue issue;

  /// Metres between the two reports.
  final double distanceM;

  /// False when the original sits in a different ward — merging then moves
  /// this report onto another coordinator's ticket, so the UI says so.
  final bool sameWard;

  factory DuplicateCandidate.fromJson(Map<String, dynamic> json) =>
      DuplicateCandidate(
        issue: Issue.fromJson(json),
        distanceM: (json['distance_m'] as num?)?.toDouble() ?? 0,
        sameWard: json['same_ward'] == true,
      );

  /// "40 m away" / "1.2 km away" — distance the way someone standing in the
  /// street would say it.
  String get distanceLabel => distanceM >= 1000
      ? '${(distanceM / 1000).toStringAsFixed(1)} km away'
      : '${distanceM.round()} m away';
}

/// Where a grievance stands with the duplicate check.
class DuplicateInfo {
  const DuplicateInfo({
    required this.awaitingReview,
    required this.decision,
    required this.decidedBy,
    this.mergedIntoId,
    this.parent,
    this.children = const [],
  });

  /// Flagged by detection and nobody has ruled yet — the only state that
  /// should put a decision in front of a coordinator.
  final bool awaitingReview;

  /// '' until someone rules, then 'merged' or 'separate'. First ruling wins,
  /// so a coordinator opening a case admin already settled sees the outcome
  /// rather than a second set of buttons.
  final String decision;
  final String decidedBy;

  /// Set when THIS grievance was folded into another one.
  final String? mergedIntoId;

  /// The suspected original.
  final DuplicateCandidate? parent;

  /// Reports already folded into this one.
  final List<Issue> children;

  bool get isMerged => (mergedIntoId ?? '').isNotEmpty;

  static const empty = DuplicateInfo(
    awaitingReview: false,
    decision: '',
    decidedBy: '',
  );

  factory DuplicateInfo.fromJson(Map<String, dynamic> json) {
    final parent = json['parent'];
    final kids = (json['children'] as List?) ?? const [];
    return DuplicateInfo(
      awaitingReview: json['awaiting_review'] == true,
      decision: (json['decision'] ?? '').toString(),
      decidedBy: (json['decided_by'] ?? '').toString(),
      mergedIntoId: (json['merged_into_id'] ?? '').toString().isEmpty
          ? null
          : json['merged_into_id'].toString(),
      parent: parent is Map<String, dynamic>
          ? DuplicateCandidate.fromJson(parent)
          : null,
      children: kids
          .whereType<Map<String, dynamic>>()
          .map(Issue.fromJson)
          .toList(),
    );
  }
}
