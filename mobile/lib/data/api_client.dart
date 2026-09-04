import 'dart:io';

import '../domain/coordinator_data.dart';
import '../domain/models/boundary_data.dart';
import '../domain/models/citizen_user.dart';
import '../domain/models/issue.dart';
import '../domain/models/locate_result.dart';

/// Abstract seam over the FastAPI backend (mirrors frontend/lib/api.js
/// 1:1). Widget/unit tests inject a fake; the app wires [DioApiClient].
abstract class ApiClient {
  /// Request an SMS OTP for [phone] (POST /api/auth/request-otp). Returns the
  /// dev OTP string when the backend is in dummy mode (no live SMS key), else
  /// null. Throws [ApiException] on a bad number / gateway error.
  Future<String?> requestCitizenOtp(String phone);

  /// Phase-1 citizen login (POST /api/auth/login): verifies [otp], then a
  /// known phone must present its registered name; an unknown phone
  /// auto-registers. Throws [ApiException] on wrong OTP (401), name mismatch
  /// (401) or invalid input (400/422).
  Future<CitizenUser> citizenLogin({
    required String name,
    required String phone,
    required String otp,
  });

  Future<BoundaryData> fetchBoundaries();

  Future<LocateResult> locate(double lat, double lng);

  Future<List<Issue>> fetchWardIssues(int wardNo);

  Future<List<Issue>> fetchNearby(double lat, double lng, {int radius = 1500});

  Future<List<Issue>> fetchHistory(String userId);

  /// Public grievances this user has upvoted — the "My Supports" filter in the
  /// ward feed.
  Future<List<Issue>> fetchSupported(String userId);

  /// Real per-account profile counters (reports / upvotes cast / resolved /
  /// open-unassigned) from GET /api/issues/stats/{userId}.
  Future<({int reports, int upvotes, int resolved, int open})> fetchUserStats(
      String userId);

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

  /// Sign in a constituency-staff account against the admin-managed
  /// `coordinators` table. Throws [ApiException] on invalid credentials.
  Future<Coordinator> coordinatorLogin(
      {required String username, required String password});

  /// Ward grievances scoped for [coordinator] (excludes tickets assigned to
  /// OTHER coordinators; unassigned + own-assigned are returned).
  /// [sort] is 'recent' (default) or 'priority' (upvotes desc).
  Future<List<Issue>> fetchCoordinatorWardIssues(int wardNo,
      {required String coordinator, String sort = 'recent'});

  /// Every grievance the coordinator has taken ownership of (any ward, any
  /// status) — used to compute per-ward "assigned by me" counts in the ward
  /// dropdown.
  Future<List<Issue>> fetchCoordinatorMine(String coordinator);

  /// Take ownership: any → ACTIVE (citizen sees "Assigned"). Passes the
  /// acting coordinator so the row is stamped with them.
  Future<Issue> coordinatorVerify(String issueId, String coordinator);

  /// Dept. Transfer: → FORWARDED with dept + responsible officer.
  ///
  /// [photo] / [voice] are the evidence captured in the action sheet. They are
  /// optional on every action except close, where the sheet will not let the
  /// coordinator submit without both.
  Future<Issue> coordinatorTransfer(String issueId, String department,
      {String notes = '',
      String officer = '',
      String coordinator = '',
      File? photo,
      File? voice});

  /// Escalate: → IN_PROGRESS + escalated_at server-side timestamp.
  Future<Issue> coordinatorEscalate(String issueId,
      {required String description,
      String coordinator = '',
      File? photo,
      File? voice});

  /// Close: → PENDING_VERIFICATION (citizen sees the verify prompt). The
  /// closure photo + voice note are the proof of work the admin console shows.
  Future<Issue> coordinatorClose(String issueId,
      {String notes = '', String coordinator = '', File? photo, File? voice});

  /// Mark false: → FALSE with the coordinator's reason.
  Future<Issue> coordinatorMarkFalse(String issueId, String reason,
      {String details = '',
      String coordinator = '',
      File? photo,
      File? voice});

  /// Fetch the Tamil-Nadu grievance-routing taxonomy (39 Government
  /// Departments → types → sub-types → sub-departments + responsible officers).
  Future<Map<String, dynamic>> fetchDepartmentsTree();

  /// The desk contact configured for one responsible-officer slot, so the
  /// Dept Transfer dispatch can open THAT officer's WhatsApp chat instead of
  /// dropping the coordinator into a contact picker. Returns empty strings
  /// when nothing is configured.
  Future<({String name, String mobile})> fetchOfficerContact({
    required String department,
    required String subDept,
    required String officer,
  });

  // ── Notifications (routers/notifications.py) ──────────────────────────

  /// Poll for unseen notifications strictly newer than [since] (ISO ts).
  /// [recipientType] is 'citizen' or 'coordinator'.
  Future<({List<Map<String, dynamic>> items, String serverTime})>
      fetchNotifications({
    required String recipientType,
    required String recipientId,
    String since = '',
  });

  /// Bind this device's FCM token to the signed-in account so the backend can
  /// push while the app is backgrounded or closed.
  Future<void> registerDeviceToken({
    required String token,
    required String recipientType,
    required String recipientId,
    String platform = 'android',
  });

  /// Drop the token on sign-out, so the next account on this device does not
  /// inherit the previous one's alerts.
  Future<void> unregisterDeviceToken(String token);
}

/// Friendly error carrying the FastAPI `detail` message when present.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
