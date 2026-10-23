import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fieldstaff_attendance/config/api_config.dart';
import 'package:fieldstaff_attendance/network/api_client.dart';
import 'package:fieldstaff_attendance/network/api_failover_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient apiClient;
  late ApiFailoverManager failoverManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'initial_expired_token',
      'refresh_token': 'valid_refresh_token_xyz',
      'device_id': 'TEST_DEVICE_UUID',
    });
    failoverManager = ApiFailoverManager();
    failoverManager.resetForTesting(initial: ActiveBackend.primary);
    apiClient = ApiClient();
    apiClient.httpClient = null;
    failoverManager.httpClient = null;
    ApiClient.onSessionExpired = null;
  });

  tearDown(() {
    failoverManager.stopRecoveryChecker();
  });

  group('Flutter Attendance & Token Refresh Resiliency Tests', () {
    test('1. Valid session: postMultipart succeeds directly with Bearer header', () async {
      String? sentAuthHeader;
      final mockClient = MockClient((request) async {
        sentAuthHeader = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'success': true,
            'decision': 'PRESENT',
            'message': 'Attendance marked successfully',
            'attendance_classification': 'ON_TIME',
            'client_punch_id': 'PUNCH_123',
          }),
          200,
        );
      });

      apiClient.httpClient = mockClient;

      final res = await apiClient.postMultipart(
        endpoint: '/api/user/attendance/verify',
        fields: {
          'current_latitude': '19.0760',
          'current_longitude': '72.8777',
          'client_punch_id': 'PUNCH_123',
        },
        files: [
          MapEntry('frames', Uint8List.fromList([1, 2, 3])),
        ],
      );

      expect(res['success'], isTrue);
      expect(sentAuthHeader, equals('Bearer initial_expired_token'));
    });

    test('2. Expired access token (401) automatically refreshes and retries attendance verification', () async {
      int attendanceAttempts = 0;
      int refreshAttempts = 0;
      String? lastAttendanceToken;

      final mockClient = MockClient((request) async {
        final path = request.url.path;

        if (path.contains('/api/auth/refresh')) {
          refreshAttempts++;
          final body = jsonDecode(request.body);
          expect(body['refresh_token'], equals('valid_refresh_token_xyz'));
          return http.Response(
            jsonEncode({
              'access_token': 'new_fresh_access_token_abc',
              'refresh_token': 'new_refresh_token_def',
              'token_type': 'bearer',
              'expires_in': 28800,
            }),
            200,
          );
        }

        if (path.contains('/api/user/attendance/verify')) {
          attendanceAttempts++;
          lastAttendanceToken = request.headers['Authorization'];
          if (attendanceAttempts == 1) {
            // First call fails with 401 token expired
            return http.Response(
              jsonEncode({'detail': 'Token expired. Please log in again.'}),
              401,
            );
          } else {
            // Retry succeeds with fresh token
            return http.Response(
              jsonEncode({
                'success': true,
                'decision': 'PRESENT',
                'message': 'Attendance marked after token refresh',
                'client_punch_id': 'PUNCH_TEST_RETRY_1',
              }),
              200,
            );
          }
        }

        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;

      final res = await apiClient.postMultipart(
        endpoint: '/api/user/attendance/verify',
        fields: {
          'current_latitude': '19.0760',
          'current_longitude': '72.8777',
          'client_punch_id': 'PUNCH_TEST_RETRY_1',
        },
        files: [MapEntry('frames', Uint8List.fromList([10, 20, 30]))],
      );

      expect(res['success'], isTrue);
      expect(refreshAttempts, equals(1));
      expect(attendanceAttempts, equals(2));
      expect(lastAttendanceToken, equals('Bearer new_fresh_access_token_abc'));

      // Check that SharedPreferences received the updated token
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('access_token'), equals('new_fresh_access_token_abc'));
    });

    test('3. Concurrency Mutex: Multiple parallel requests hitting 401 trigger only ONE refresh', () async {
      int refreshCalls = 0;
      int apiCalls = 0;

      final mockClient = MockClient((request) async {
        final path = request.url.path;

        if (path.contains('/api/auth/refresh')) {
          refreshCalls++;
          await Future.delayed(const Duration(milliseconds: 50));
          return http.Response(
            jsonEncode({
              'access_token': 'refreshed_mutex_token',
              'refresh_token': 'refreshed_mutex_refresh',
            }),
            200,
          );
        }

        if (path.contains('/api/user/today-schedule') ||
            path.contains('/api/user/server-time') ||
            path.contains('/api/user/attendance-config')) {
          apiCalls++;
          final auth = request.headers['Authorization'];
          if (auth == 'Bearer initial_expired_token') {
            return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
          }
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        }

        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;

      // Launch 3 simultaneous requests
      final results = await Future.wait([
        apiClient.get('/api/user/today-schedule'),
        apiClient.get('/api/user/server-time'),
        apiClient.get('/api/user/attendance-config'),
      ]);

      // All 3 should succeed
      for (final r in results) {
        expect(r['status'], equals('ok'));
      }

      // Exactly ONE refresh call was made despite 3 concurrent 401s
      expect(refreshCalls, equals(1));
      expect(apiCalls, equals(6)); // 3 failed initial + 3 retried successfully
    });

    test('4. Genuinely invalid session: Refresh fails with 401 -> clears credentials and triggers onSessionExpired', () async {
      bool sessionExpiredFired = false;
      ApiClient.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final mockClient = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/api/auth/refresh')) {
          return http.Response(
            jsonEncode({'detail': 'Refresh token expired. Please log in again.'}),
            401,
          );
        }
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      apiClient.httpClient = mockClient;

      expect(
        () async => await apiClient.get('/api/user/attendance/verify'),
        throwsA(predicate((e) =>
            e is ApiException &&
            e.isUnauthorized &&
            e.message.contains('session has expired'))),
      );

      // Wait a microtask
      await Future.delayed(const Duration(milliseconds: 10));
      expect(sessionExpiredFired, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('access_token'), isNull);
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('5. Differentiated error classification matches user requirements', () {
      final auth401 = ApiException('Token expired', statusCode: 401);
      expect(auth401.isAuthFailure, isTrue);
      expect(auth401.isUnauthorized, isTrue);
      expect(auth401.userFriendlyMessage, equals('Your session has expired. Please log in again.'));

      final auth403 = ApiException('Deactivated account', statusCode: 403);
      expect(auth403.isAuthFailure, isTrue);
      expect(auth403.isForbidden, isTrue);

      final timeout504 = ApiException('Gateway Timeout', statusCode: 504);
      expect(timeout504.isTimeout, isTrue);
      expect(timeout504.isAuthFailure, isFalse);

      final net0 = ApiException('No connection', statusCode: 0);
      expect(net0.isNetworkFailure, isTrue);
      expect(net0.isAuthFailure, isFalse);

      final server500 = ApiException('Internal Error', statusCode: 500);
      expect(server500.isServerError, isTrue);
      expect(server500.isAuthFailure, isFalse);
    });

    test('6. Idempotency preservation: Retrying face verification preserves client_punch_id', () async {
      final receivedPunchIds = <String>[];
      int attempts = 0;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/auth/refresh')) {
          return http.Response(
            jsonEncode({'access_token': 'fresh_token'}),
            200,
          );
        }

        if (request.url.path.contains('/api/user/attendance/verify')) {
          attempts++;
          // Parse multipart fields
          final bodyString = request.body;
          if (bodyString.contains('client_punch_id')) {
            final match = RegExp(r'name="client_punch_id"\r?\n\r?\n([^\r\n]+)').firstMatch(bodyString);
            if (match != null) {
              receivedPunchIds.add(match.group(1)!);
            }
          }

          if (attempts == 1) {
            return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
          }
          return http.Response(jsonEncode({'success': true, 'decision': 'PRESENT'}), 200);
        }

        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;

      await apiClient.postMultipart(
        endpoint: '/api/user/attendance/verify',
        fields: {
          'client_punch_id': 'GLOBAL_UUID_9999',
        },
        files: [MapEntry('frames', Uint8List.fromList([1]))],
      );

      expect(receivedPunchIds.length, equals(2));
      expect(receivedPunchIds[0], equals('GLOBAL_UUID_9999'));
      expect(receivedPunchIds[1], equals('GLOBAL_UUID_9999'));
      // The exact same client_punch_id is preserved on the retry
    });
  });
}
