import 'dart:io';

import '../domain/models/boundary_data.dart';
import '../domain/models/citizen_user.dart';
import '../domain/models/issue.dart';
import '../domain/models/locate_result.dart';

/// Abstract seam over the FastAPI backend (mirrors frontend/lib/api.js
/// 1:1). Widget/unit tests inject a fake; the app wires [DioApiClient].
abstract class ApiClient {
  /// Phase-1 citizen login (POST /api/auth/login): a known phone must present
  /// its registered name; an unknown phone auto-registers. Throws
  /// [ApiException] on a name mismatch (401) or invalid input (400).
  Future<CitizenUser> citizenLogin({required String name, required String phone});

  Future<BoundaryData> fetchBoundaries();

  Future<LocateResult> locate(double lat, double lng);

  Future<List<Issue>> fetchWardIssues(int wardNo);

  Future<List<Issue>> fetchNearby(double lat, double lng, {int radius = 1500});

  Future<List<Issue>> fetchHistory(String userId);

  Future<ReportOutcome> reportIssue({
    required double latitude,
    required double longitude,
    required String userId,
    String title = 'Street Issue',
    bool force = false,
    File? image,
    File? audio,
    String? audioMime,
  });

  Future<Issue> upvoteIssue(String issueId, String userId, {String name = ''});

  Future<void> verifyIssue(String issueId, String userId, String response);

  Future<void> confirmIssue(String issueId, String phone, {String name = ''});

  /// Reverse geocode via OSM Nominatim (suburb/neighbourhood/city fallback),
  /// mirroring lib/hooks.js. Returns '' on any failure.
  Future<String> reverseGeocode(double lat, double lng);

  // ── Coordinator endpoints (routers/coordinator.py) ─────────────────────

  /// Every grievance in the ward regardless of status (coordinators see
  /// SUBMITTED, which is hidden from citizens).
  Future<List<Issue>> fetchCoordinatorWardIssues(int wardNo);

  /// Take ownership: any → ACTIVE (citizen sees "Assigned").
  Future<Issue> coordinatorVerify(String issueId);

  /// Dept. Transfer: → FORWARDED, routed to a chosen department.
  Future<Issue> coordinatorTransfer(String issueId, String department,
      {String notes = ''});

  /// Close: → PENDING_VERIFICATION (citizen sees the verify prompt).
  Future<Issue> coordinatorClose(String issueId, {String notes = ''});

  /// Mark false: → FALSE with the coordinator's reason.
  Future<Issue> coordinatorMarkFalse(String issueId, String reason,
      {String details = ''});
}

/// Friendly error carrying the FastAPI `detail` message when present.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
