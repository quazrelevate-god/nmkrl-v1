import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../core/env.dart';
import '../domain/models/boundary_data.dart';
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
