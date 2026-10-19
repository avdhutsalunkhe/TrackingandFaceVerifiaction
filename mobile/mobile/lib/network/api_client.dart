import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'api_failover_manager.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, {required this.statusCode});

  @override
  String toString() => 'Exception: $message';
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();

  /// Global callback triggered when an authenticated request receives HTTP 401 Unauthorized
  static void Function()? onSessionExpired;
  factory ApiClient() => _instance;
  ApiClient._internal();

  final ApiFailoverManager _failoverManager = ApiFailoverManager();
  ApiFailoverManager get failoverManager => _failoverManager;

  String? _customOverrideUrl;

  String get baseUrl => _customOverrideUrl ?? _failoverManager.activeUrl;

  http.Client? httpClient;
  http.Client get _client => httpClient ?? _failoverManager.httpClient ?? http.Client();

  /// Initialize failover manager and determine reachable backend
  Future<void> init({bool checkReachable = true}) async {
    _customOverrideUrl = null;
    await _failoverManager.init(checkReachable: checkReachable);
  }

  /// Backward compatible base URL setter
  Future<void> setBaseUrl(String newUrl) async {
    final cleanUrl = newUrl.replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_base_url', cleanUrl);

    if (cleanUrl == ApiConfig.secondaryApiUrl) {
      _failoverManager.setActiveBackend(ActiveBackend.secondary);
      _customOverrideUrl = null;
    } else if (cleanUrl == ApiConfig.primaryApiUrl) {
      _failoverManager.setActiveBackend(ActiveBackend.primary);
      _customOverrideUrl = null;
    } else {
      _customOverrideUrl = cleanUrl;
    }
    debugPrint('[ApiClient] Base URL set to: $baseUrl');
  }

  /// Backward compatible probe server method
  Future<bool> probeServer(String url, {Duration? timeout}) async {
    return await _failoverManager.probeHealth(url, timeout: timeout);
  }

  /// Backward compatible switch active server
  Future<String?> switchActiveServer() async {
    return await _failoverManager.triggerFailover(failedUrl: baseUrl);
  }

  Future<Map<String, String>> _getHeaders({bool isMultipart = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    final headers = <String, String>{
      'Accept': 'application/json',
      'X-Client-Type': 'MOBILE',
    };
    if (!isMultipart) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// Execute an HTTP request with automatic single-hop failover on infrastructure failure
  Future<dynamic> _executeWithFailover(
    Future<dynamic> Function(String currentUrl) action,
  ) async {
    final initialUrl = _failoverManager.activeUrl;

    try {
      return await action(initialUrl);
    } catch (e) {
      // For standard client-side / application errors (e.g. 400, 401, 403, 404),
      // remain on the same server and do not switch.
      if (e is ApiException) {
        if (!ApiFailoverManager.isInfrastructureFailure(e, e.statusCode)) {
          rethrow;
        }
      } else if (!ApiFailoverManager.isInfrastructureFailure(e)) {
        rethrow;
      }

      // Infrastructure failure detected (Timeout, Connection refused, 502/503/504, etc.)
      debugPrint('[ApiClient] Infrastructure failure detected on $initialUrl. Attempting failover...');
      final newUrl = await _failoverManager.triggerFailover(failedUrl: initialUrl);

      // Retry request exactly once on alternate backend
      try {
        debugPrint('[ApiClient] Retrying request on alternate backend: $newUrl');
        return await action(newUrl);
      } catch (retryErr) {
        debugPrint('[ApiClient] Alternate backend retry failed: $retryErr');
        if (retryErr is ApiException &&
            !ApiFailoverManager.isInfrastructureFailure(retryErr, retryErr.statusCode)) {
          rethrow;
        }

        // Both servers failed or infrastructure failure on secondary:
        throw ApiException(
          ApiConfig.serviceUnavailableMessage,
          statusCode: 503,
        );
      }
    }
  }

  Future<dynamic> get(String endpoint) async {
    return _executeWithFailover((currentUrl) async {
      final url = Uri.parse('$currentUrl$endpoint');
      final headers = await _getHeaders();
      try {
        final response = await _client
            .get(url, headers: headers)
            .timeout(ApiConfig.requestTimeout);
        return _handleResponse(response, endpoint);
      } on TimeoutException {
        throw ApiException(
          'Request to attendance service timed out.',
          statusCode: 504,
        );
      }
    });
  }

  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data;
    final encodedPayload = payload != null ? jsonEncode(payload) : null;

    return _executeWithFailover((currentUrl) async {
      final url = Uri.parse('$currentUrl$endpoint');
      final headers = await _getHeaders();
      try {
        final response = await _client
            .post(
              url,
              headers: headers,
              body: encodedPayload,
            )
            .timeout(ApiConfig.requestTimeout);
        return _handleResponse(response, endpoint);
      } on TimeoutException {
        throw ApiException(
          'Request to attendance service timed out.',
          statusCode: 504,
        );
      }
    });
  }

  Future<dynamic> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data;
    final encodedPayload = payload != null ? jsonEncode(payload) : null;

    return _executeWithFailover((currentUrl) async {
      final url = Uri.parse('$currentUrl$endpoint');
      final headers = await _getHeaders();
      try {
        final response = await _client
            .put(
              url,
              headers: headers,
              body: encodedPayload,
            )
            .timeout(ApiConfig.requestTimeout);
        return _handleResponse(response, endpoint);
      } on TimeoutException {
        throw ApiException(
          'Request to attendance service timed out.',
          statusCode: 504,
        );
      }
    });
  }

  Future<dynamic> delete(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data;
    final encodedPayload = payload != null ? jsonEncode(payload) : null;

    return _executeWithFailover((currentUrl) async {
      final url = Uri.parse('$currentUrl$endpoint');
      final headers = await _getHeaders();
      try {
        final response = await _client
            .delete(
              url,
              headers: headers,
              body: encodedPayload,
            )
            .timeout(ApiConfig.requestTimeout);
        return _handleResponse(response, endpoint);
      } on TimeoutException {
        throw ApiException(
          'Request to attendance service timed out.',
          statusCode: 504,
        );
      }
    });
  }

  Future<dynamic> postMultipart({
    required String endpoint,
    required Map<String, String> fields,
    required List<MapEntry<String, Uint8List>> files,
  }) async {
    return _executeWithFailover((currentUrl) async {
      final url = Uri.parse('$currentUrl$endpoint');
      final headers = await _getHeaders(isMultipart: true);

      final request = http.MultipartRequest('POST', url);
      request.headers.addAll(headers);
      request.fields.addAll(fields);

      for (int i = 0; i < files.length; i++) {
        final entry = files[i];
        request.files.add(
          http.MultipartFile.fromBytes(
            entry.key,
            entry.value,
            filename: 'frame_$i.jpg',
          ),
        );
      }

      try {
        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(seconds: 15));
        final response = await http.Response.fromStream(streamedResponse);
        return _handleResponse(response, endpoint);
      } on TimeoutException {
        throw ApiException(
          'Upload to attendance service timed out.',
          statusCode: 504,
        );
      }
    });
  }

  dynamic _handleResponse(http.Response response, String endpoint) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      // Trigger auto-logout if token expired on authenticated API call
      if (!endpoint.contains('/auth/login')) {
        onSessionExpired?.call();
      }
      String errorMessage = 'Session expired. Please log in again.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('detail')) {
          errorMessage = body['detail'].toString();
        } else if (body is Map && body.containsKey('message')) {
          errorMessage = body['message'].toString();
        }
      } catch (_) {}
      throw ApiException(errorMessage, statusCode: 401);
    } else if (response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      throw ApiException(
        ApiConfig.serviceUnavailableMessage,
        statusCode: response.statusCode,
      );
    } else if (response.statusCode == 404) {
      throw ApiException(
        'Endpoint not found (404) at $endpoint.',
        statusCode: 404,
      );
    } else {
      String errorMessage = 'Server error (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body.containsKey('detail')) {
          errorMessage = body['detail'].toString();
        } else if (body is Map && body.containsKey('message')) {
          errorMessage = body['message'].toString();
        }
      } catch (_) {}
      throw ApiException(errorMessage, statusCode: response.statusCode);
    }
  }
}
