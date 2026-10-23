import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../core/constants/api_constants.dart';
import 'api_failover_manager.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  final String? endpoint;
  final dynamic details;

  ApiException(
    this.message, {
    required this.statusCode,
    this.endpoint,
    this.details,
  });

  bool get isAuthFailure => statusCode == 401 || statusCode == 403;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isTimeout => statusCode == 504 || statusCode == 408;
  bool get isNetworkFailure => statusCode == 0;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500 && statusCode < 600;
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  String get userFriendlyMessage {
    if (isUnauthorized) {
      return 'Your session has expired. Please log in again.';
    }
    if (isForbidden) {
      return message.isNotEmpty ? message : 'Access denied. Please contact your administrator.';
    }
    if (isTimeout) {
      return 'The request timed out. Please check your connection and try again.';
    }
    if (isNetworkFailure) {
      return 'Cannot reach the attendance server. Please check your network connection.';
    }
    if (isServerError) {
      return ApiConfig.serviceUnavailableMessage;
    }
    return message;
  }

  @override
  String toString() => 'ApiException(status: $statusCode, endpoint: $endpoint, message: $message)';
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

  // Concurrency Mutex for Token Refresh
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

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
      'X-Client-Type': kIsWeb ? 'WEB' : 'MOBILE',
    };
    if (!isMultipart) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      final cleanToken = token.trim().replaceAll('"', '').replaceAll("'", '');
      headers['Authorization'] = 'Bearer $cleanToken';
    }
    return headers;
  }

  /// Sanitized logger: never logs passwords, access tokens, refresh tokens, or face image bytes.
  void _logRequest(
    String method,
    String endpoint, {
    int? statusCode,
    Duration? duration,
    String? error,
  }) {
    final cleanEndpoint = endpoint.split('?').first;
    final buffer = StringBuffer('[HTTP $method] $cleanEndpoint');
    if (statusCode != null) {
      buffer.write(' -> status: $statusCode');
    }
    if (duration != null) {
      buffer.write(' (${duration.inMilliseconds}ms)');
    }
    if (error != null) {
      buffer.write(' -> error: $error');
    }
    debugPrint(buffer.toString());
  }

  /// Clear stored credentials from persistent storage upon genuine session invalidation
  Future<void> _clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('token_expires_at');
    } catch (e) {
      debugPrint('[ApiClient] Error clearing credentials: $e');
    }
  }

  /// Thread-safe mutex lock for token refresh:
  /// Prevents multiple concurrent requests from triggering independent refresh calls.
  Future<bool> _refreshTokenWithMutex() async {
    if (_isRefreshing && _refreshCompleter != null) {
      debugPrint('[ApiClient] Token refresh already in progress, queuing request...');
      return await _refreshCompleter!.future;
    }

    _isRefreshing = true;
    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');

      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('[ApiClient] No refresh token stored. Session cannot be renewed.');
        _isRefreshing = false;
        completer.complete(false);
        return false;
      }

      final deviceId = prefs.getString('device_id');
      final refreshUrl = Uri.parse('$baseUrl${ApiConstants.refresh}');
      debugPrint('[ApiClient] Refreshing session at $refreshUrl');

      final stopwatch = Stopwatch()..start();
      final response = await _client.post(
        refreshUrl,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Client-Type': kIsWeb ? 'WEB' : 'MOBILE',
        },
        body: jsonEncode({
          'refresh_token': refreshToken,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          'client_type': kIsWeb ? 'WEB' : 'MOBILE',
        }),
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();
      _logRequest('POST', ApiConstants.refresh, statusCode: response.statusCode, duration: stopwatch.elapsed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        final newAccessToken = data['access_token'] as String?;
        final newRefreshToken = data['refresh_token'] as String?;
        final newExpiresAt = data['expires_at'];

        if (newAccessToken != null && newAccessToken.isNotEmpty) {
          await prefs.setString('access_token', newAccessToken);
          if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
            await prefs.setString('refresh_token', newRefreshToken);
          }
          if (newExpiresAt != null) {
            final expiresAtInt = newExpiresAt is int
                ? newExpiresAt
                : int.tryParse(newExpiresAt.toString());
            if (expiresAtInt != null) {
              await prefs.setInt('token_expires_at', expiresAtInt);
            }
          }
          debugPrint('[ApiClient] Token refreshed successfully. Access renewed.');
          _isRefreshing = false;
          completer.complete(true);
          return true;
        }
      }

      debugPrint('[ApiClient] Token refresh rejected with status ${response.statusCode}');
      _isRefreshing = false;
      completer.complete(false);
      return false;
    } catch (e) {
      debugPrint('[ApiClient] Token refresh exception: $e');
      _isRefreshing = false;
      completer.complete(false);
      return false;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  /// Execute an HTTP request with automatic single-hop failover on infrastructure failure
  Future<http.Response> _executeWithFailover(
    Future<http.Response> Function(String currentUrl) action,
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

  /// Universal request runner with:
  /// 1. Automatic failover on server infrastructure outage
  /// 2. Automatic token refresh and single-attempt retry on HTTP 401
  /// 3. Clear session expiration and credential wiping on genuine session expiry
  /// 4. Sanitized request/response logging
  Future<dynamic> _sendRequest({
    required String endpoint,
    required String method,
    required Future<http.Response> Function(String currentUrl) send,
    bool isRetry = false,
  }) async {
    http.Response response;
    final stopwatch = Stopwatch()..start();

    try {
      response = await _executeWithFailover((currentUrl) => send(currentUrl));
      stopwatch.stop();
      _logRequest(method, endpoint, statusCode: response.statusCode, duration: stopwatch.elapsed);
    } on TimeoutException {
      stopwatch.stop();
      _logRequest(method, endpoint, error: 'TIMEOUT (${stopwatch.elapsedMilliseconds}ms)');
      throw ApiException(
        'Request to attendance service timed out.',
        statusCode: 504,
        endpoint: endpoint,
      );
    } catch (e) {
      stopwatch.stop();
      if (e is ApiException) rethrow;

      final errStr = e.toString();
      final isNetworkErr = errStr.contains('SocketException') ||
          errStr.contains('Connection refused') ||
          errStr.contains('Failed host lookup') ||
          errStr.contains('ClientException') ||
          errStr.contains('XMLHttpRequest error') ||
          errStr.contains('Network is unreachable');

      if (isNetworkErr) {
        _logRequest(method, endpoint, error: 'NETWORK_FAILURE: $errStr');
        throw ApiException(
          'Unable to connect to attendance service. Please check your internet connection.',
          statusCode: 0,
          endpoint: endpoint,
        );
      }

      _logRequest(method, endpoint, error: errStr);
      rethrow;
    }

    // Check if 401 Unauthorized occurs on an authenticated route
    final isAuthRoute = endpoint.contains('/auth/login') || endpoint.contains('/auth/refresh');
    if (response.statusCode == 401 && !isAuthRoute) {
      if (!isRetry) {
        debugPrint('[ApiClient] 401 Unauthorized on $endpoint. Attempting automatic token refresh...');
        final refreshed = await _refreshTokenWithMutex();
        if (refreshed) {
          debugPrint('[ApiClient] Token refreshed successfully. Retrying original request to $endpoint at most once...');
          return _sendRequest(
            endpoint: endpoint,
            method: method,
            send: send,
            isRetry: true,
          );
        } else {
          debugPrint('[ApiClient] Token refresh failed. Genuine session expiry.');
          await _clearCredentials();
          onSessionExpired?.call();
          throw ApiException(
            'Your session has expired. Please log in again.',
            statusCode: 401,
            endpoint: endpoint,
          );
        }
      } else {
        // Request failed with 401 even after token refresh
        debugPrint('[ApiClient] Request to $endpoint returned 401 even after token refresh. Clearing session.');
        await _clearCredentials();
        onSessionExpired?.call();
        throw ApiException(
          'Your session has expired. Please log in again.',
          statusCode: 401,
          endpoint: endpoint,
        );
      }
    }

    return _handleResponse(response, endpoint);
  }

  Future<dynamic> get(String endpoint) async {
    return _sendRequest(
      endpoint: endpoint,
      method: 'GET',
      send: (currentUrl) async {
        final url = Uri.parse('$currentUrl$endpoint');
        final headers = await _getHeaders();
        return await _client
            .get(url, headers: headers)
            .timeout(ApiConfig.requestTimeout);
      },
    );
  }

  Future<dynamic> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data;
    final encodedPayload = payload != null ? jsonEncode(payload) : null;

    return _sendRequest(
      endpoint: endpoint,
      method: 'POST',
      send: (currentUrl) async {
        final url = Uri.parse('$currentUrl$endpoint');
        final headers = await _getHeaders();
        return await _client
            .post(
              url,
              headers: headers,
              body: encodedPayload,
            )
            .timeout(ApiConfig.requestTimeout);
      },
    );
  }

  Future<dynamic> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data;
    final encodedPayload = payload != null ? jsonEncode(payload) : null;

    return _sendRequest(
      endpoint: endpoint,
      method: 'PUT',
      send: (currentUrl) async {
        final url = Uri.parse('$currentUrl$endpoint');
        final headers = await _getHeaders();
        return await _client
            .put(
              url,
              headers: headers,
              body: encodedPayload,
            )
            .timeout(ApiConfig.requestTimeout);
      },
    );
  }

  Future<dynamic> delete(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, dynamic>? data,
  }) async {
    final payload = body ?? data;
    final encodedPayload = payload != null ? jsonEncode(payload) : null;

    return _sendRequest(
      endpoint: endpoint,
      method: 'DELETE',
      send: (currentUrl) async {
        final url = Uri.parse('$currentUrl$endpoint');
        final headers = await _getHeaders();
        return await _client
            .delete(
              url,
              headers: headers,
              body: encodedPayload,
            )
            .timeout(ApiConfig.requestTimeout);
      },
    );
  }

  Future<dynamic> postMultipart({
    required String endpoint,
    required Map<String, String> fields,
    required List<MapEntry<String, Uint8List>> files,
  }) async {
    return _sendRequest(
      endpoint: endpoint,
      method: 'POST_MULTIPART',
      send: (currentUrl) async {
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

        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(seconds: 25));
        return await http.Response.fromStream(streamedResponse);
      },
    );
  }

  dynamic _handleResponse(http.Response response, String endpoint) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    }

    String errorMessage = 'Server error (${response.statusCode})';
    dynamic errorDetail;

    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        if (body.containsKey('detail')) {
          errorMessage = body['detail'].toString();
          errorDetail = body['detail'];
        } else if (body.containsKey('message')) {
          errorMessage = body['message'].toString();
          errorDetail = body['message'];
        }
      }
    } catch (_) {
      if (response.body.isNotEmpty && response.body.length < 200) {
        errorMessage = response.body;
      }
    }

    // Never log sensitive payloads or tokens
    debugPrint('[ApiClient] API Response Error: HTTP ${response.statusCode} on $endpoint: $errorMessage');

    if (response.statusCode == 401) {
      throw ApiException(
        errorMessage,
        statusCode: 401,
        endpoint: endpoint,
        details: errorDetail,
      );
    } else if (response.statusCode == 403) {
      throw ApiException(
        errorMessage,
        statusCode: 403,
        endpoint: endpoint,
        details: errorDetail,
      );
    } else if (response.statusCode == 502 ||
        response.statusCode == 503 ||
        response.statusCode == 504) {
      throw ApiException(
        ApiConfig.serviceUnavailableMessage,
        statusCode: response.statusCode,
        endpoint: endpoint,
        details: errorDetail,
      );
    } else if (response.statusCode == 404) {
      throw ApiException(
        'Endpoint not found (404) at $endpoint.',
        statusCode: 404,
        endpoint: endpoint,
        details: errorDetail,
      );
    } else {
      throw ApiException(
        errorMessage,
        statusCode: response.statusCode,
        endpoint: endpoint,
        details: errorDetail,
      );
    }
  }
}
