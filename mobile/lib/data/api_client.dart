import 'dart:io';

import '../domain/models/boundary_data.dart';
import '../domain/models/issue.dart';
import '../domain/models/locate_result.dart';

/// Abstract seam over the FastAPI backend (mirrors frontend/lib/api.js
/// 1:1). Widget/unit tests inject a fake; the app wires [DioApiClient].
abstract class ApiClient {
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
}

/// Friendly error carrying the FastAPI `detail` message when present.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
