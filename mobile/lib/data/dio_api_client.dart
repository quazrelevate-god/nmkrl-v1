import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../core/env.dart';
import '../domain/coordinator_data.dart';
import '../domain/models/boundary_data.dart';
import '../domain/models/citizen_user.dart';
import '../domain/models/issue.dart';
import '../domain/models/locate_result.dart';
import 'api_client.dart';

/// Dio-backed [ApiClient]. Maps DioExceptions to friendly [ApiException]s
/// (surfacing FastAPI's {detail} when present) and retries idempotent GETs
/// once on connection hiccups — field networks are flaky.
class DioApiClient implements ApiClient {
  DioApiClient({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl ?? Env.apiBase,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  Never _friendly(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] != null) {
        throw ApiException('${data['detail']}',
            statusCode: error.response?.statusCode);
      }
      throw ApiException(
        switch (error.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.receiveTimeout ||
          DioExceptionType.sendTimeout =>
            'The server is taking too long. Check your connection and retry.',
          DioExceptionType.connectionError =>
            'Could not reach the server. Are you online?',
          _ => 'Request failed. Please try again.',
        },
        statusCode: error.response?.statusCode,
      );
    }
    throw ApiException('Something went wrong. Please try again.');
  }

  Future<T> _get<T>(String path,
      {Map<String, dynamic>? query,
      required T Function(dynamic data) parse}) async {
    for (var attempt = 0;; attempt++) {
      try {
        final res = await _dio.get<dynamic>(path, queryParameters: query);
        return parse(res.data);
      } on DioException catch (e) {
        final transient = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout;
        if (attempt == 0 && transient) continue; // one silent retry
        _friendly(e);
      }
    }
  }

  static List<Issue> _issueList(dynamic data) =>
      ((data as Map<String, dynamic>)['issues'] as List<dynamic>? ?? const [])
          .map((e) => Issue.fromJson(e as Map<String, dynamic>))
          .toList();

  @override
  Future<String?> requestCitizenOtp(String phone) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/auth/request-otp',
        data: FormData.fromMap({'phone': phone}),
      );
      final d = res.data ?? const {};
      return d['dev_otp'] as String?; // non-null only in dummy mode
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<CitizenUser> citizenLogin({
    required String name,
    required String phone,
    required String otp,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: FormData.fromMap({'name': name, 'phone': phone, 'otp': otp}),
      );
      return CitizenUser.fromJson(res.data!);
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<BoundaryData> fetchBoundaries() => _get(
        '/api/boundaries',
        parse: (d) => BoundaryData.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<LocateResult> locate(double lat, double lng) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/locate',
        data: {'latitude': lat, 'longitude': lng},
      );
      return LocateResult.fromJson(res.data!);
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<List<Issue>> fetchWardIssues(int wardNo) =>
      _get('/api/issues/ward/$wardNo', parse: _issueList);

  @override
  Future<List<Issue>> fetchNearby(double lat, double lng,
          {int radius = 1500}) =>
      _get(
        '/api/issues/nearby',
        query: {'lat': lat, 'lng': lng, 'radius': radius},
        parse: _issueList,
      );

  @override
  Future<List<Issue>> fetchHistory(String userId) =>
      _get('/api/issues/history/$userId', parse: _issueList);

  @override
  Future<List<Issue>> fetchSupported(String userId) =>
      _get('/api/issues/supported/$userId', parse: _issueList);

  @override
  Future<({int reports, int upvotes, int resolved, int open})> fetchUserStats(
          String userId) =>
      _get('/api/issues/stats/$userId', parse: (d) {
        final m = d as Map<String, dynamic>;
        int n(String k) => (m[k] as num?)?.toInt() ?? 0;
        return (
          reports: n('reports'),
          upvotes: n('upvotes'),
          resolved: n('resolved'),
          open: n('open'),
        );
      });

  @override
  Future<ReportOutcome> reportIssue({
    required double latitude,
    required double longitude,
    required String userId,
    String title = 'Street Issue',
    bool force = false,
    File? image,
    File? audio,
    String? audioMime,
  }) async {
    try {
      final form = FormData.fromMap({
        'latitude': '$latitude',
        'longitude': '$longitude',
        'user_id': userId,
        'title': title,
        'force': '$force',
        if (image != null)
          'image': await MultipartFile.fromFile(
            image.path,
            filename: image.uri.pathSegments.last,
          ),
        if (audio != null)
          'audio': await MultipartFile.fromFile(
            audio.path,
            filename: 'voice-note.m4a',
            // Native recordings are AAC in an MP4 container; the backend maps
            // audio/mp4 straight through to Gemini.
            contentType: MediaType.parse(audioMime ?? 'audio/mp4'),
          ),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/issues/report',
        data: form,
      );
      return ReportOutcome.fromJson(res.data!);
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<Issue> upvoteIssue(String issueId, String userId,
      {String name = ''}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/issues/$issueId/upvote',
        data: FormData.fromMap({
          'user_id': userId,
          if (name.isNotEmpty) 'name': name,
        }),
      );
      return Issue.fromJson(res.data!);
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> verifyIssue(
      String issueId, String userId, String response) async {
    try {
      await _dio.post<dynamic>(
        '/api/issues/$issueId/verify',
        data: FormData.fromMap({'user_id': userId, 'response': response}),
      );
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> confirmIssue(String issueId, String phone,
      {String name = ''}) async {
    try {
      await _dio.post<dynamic>(
        '/api/issues/$issueId/confirm',
        data: FormData.fromMap({
          'phone': phone,
          if (name.isNotEmpty) 'name': name,
        }),
      );
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<Coordinator> coordinatorLogin(
      {required String username, required String password}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/auth/coordinator/login',
        data: FormData.fromMap({'username': username, 'password': password}),
      );
      return Coordinator.fromJson(res.data!);
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<List<Issue>> fetchCoordinatorWardIssues(int wardNo,
          {required String coordinator, String sort = 'recent'}) =>
      _get('/api/coordinator/ward/$wardNo?coordinator=$coordinator&sort=$sort',
          parse: _issueList);

  @override
  Future<List<Issue>> fetchCoordinatorMine(String coordinator) =>
      _get('/api/coordinator/mine/$coordinator', parse: _issueList);

  Future<Issue> _coordPost(String path, [Map<String, dynamic>? fields]) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        path,
        data: fields == null ? null : FormData.fromMap(fields),
      );
      return Issue.fromJson(res.data!);
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<Issue> coordinatorVerify(String issueId, String coordinator) =>
      _coordPost('/api/coordinator/issues/$issueId/verify',
          {'coordinator': coordinator});

  @override
  Future<Issue> coordinatorTransfer(String issueId, String department,
          {String notes = '', String officer = '', String coordinator = ''}) =>
      _coordPost('/api/coordinator/issues/$issueId/transfer', {
        'department': department,
        if (notes.isNotEmpty) 'notes': notes,
        if (officer.isNotEmpty) 'officer': officer,
        // Identifies the actor so the backend can reject an action on a
        // grievance owned by a different coordinator.
        if (coordinator.isNotEmpty) 'coordinator': coordinator,
      });

  @override
  Future<Issue> coordinatorEscalate(String issueId,
          {required String description, String coordinator = ''}) =>
      _coordPost('/api/coordinator/issues/$issueId/escalate', {
        'description': description,
        if (coordinator.isNotEmpty) 'coordinator': coordinator,
      });

  @override
  Future<Issue> coordinatorClose(String issueId,
          {String notes = '', String coordinator = ''}) =>
      _coordPost('/api/coordinator/issues/$issueId/close', {
        if (notes.isNotEmpty) 'notes': notes,
        if (coordinator.isNotEmpty) 'coordinator': coordinator,
      });

  @override
  Future<Issue> coordinatorMarkFalse(String issueId, String reason,
          {String details = '', String coordinator = ''}) =>
      _coordPost('/api/coordinator/issues/$issueId/mark_false', {
        'reason': reason,
        if (details.isNotEmpty) 'details': details,
        if (coordinator.isNotEmpty) 'coordinator': coordinator,
      });

  @override
  Future<Map<String, dynamic>> fetchDepartmentsTree() => _get(
        '/api/departments/tree',
        parse: (d) => (d as Map<String, dynamic>)['departments'] as Map<String, dynamic>,
      );

  @override
  Future<({List<Map<String, dynamic>> items, String serverTime})>
      fetchNotifications({
    required String recipientType,
    required String recipientId,
    String since = '',
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/api/notifications',
        queryParameters: {
          'recipient_type': recipientType,
          'recipient_id': recipientId,
          if (since.isNotEmpty) 'since': since,
        },
      );
      final data = res.data!;
      final raw = (data['notifications'] as List<dynamic>);
      return (
        items: raw.map((e) => (e as Map).cast<String, dynamic>()).toList(),
        serverTime: '${data['server_time'] ?? ''}',
      );
    } catch (e) {
      _friendly(e);
    }
  }

  @override
  Future<void> registerDeviceToken({
    required String token,
    required String recipientType,
    required String recipientId,
    String platform = 'android',
  }) async {
    // Push is a best-effort extra on top of polling — never surface a failure
    // here to the user or block the sign-in that triggered it.
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/notifications/register',
        data: {
          'token': token,
          'recipient_type': recipientType,
          'recipient_id': recipientId,
          'platform': platform,
        },
      );
    } catch (_) {}
  }

  @override
  Future<void> unregisterDeviceToken(String token) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        '/api/notifications/unregister',
        data: {'token': token},
      );
    } catch (_) {}
  }

  @override
  Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {'lat': lat, 'lon': lng, 'format': 'json', 'zoom': 16},
        options: Options(headers: {
          'User-Agent': 'NammaKural/1.0 (civic grievance app)',
        }),
      );
      final a = (res.data?['address'] as Map<String, dynamic>?) ?? const {};
      for (final k in [
        'suburb',
        'neighbourhood',
        'city_district',
        'city',
        'town',
        'village',
      ]) {
        final v = a[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return '';
    } catch (_) {
      return ''; // never crash the caller — mirrors the web helper
    }
  }
}
