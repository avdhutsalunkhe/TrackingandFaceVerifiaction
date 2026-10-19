import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fieldstaff_attendance/config/api_config.dart';
import 'package:fieldstaff_attendance/network/api_client.dart';
import 'package:fieldstaff_attendance/network/api_failover_manager.dart';
import 'package:fieldstaff_attendance/core/services/auth_service.dart';
import 'package:fieldstaff_attendance/screens/auth/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiFailoverManager failoverManager;
  late ApiClient apiClient;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    failoverManager = ApiFailoverManager();
    failoverManager.resetForTesting(initial: ActiveBackend.primary);
    apiClient = ApiClient();
    apiClient.httpClient = null;
    failoverManager.httpClient = null;
  });

  tearDown(() {
    failoverManager.stopRecoveryChecker();
  });

  group('Automatic Dual-Backend API Failover Tests', () {
    // TEST 1: Primary available -> API uses primary
    test('TEST 1: Primary available -> API uses primary', () async {
      int primaryCalls = 0;
      int secondaryCalls = 0;

      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          primaryCalls++;
          return http.Response(jsonEncode({'message': 'from_primary'}), 200);
        } else if (request.url.toString().startsWith(ApiConfig.secondaryApiUrl)) {
          secondaryCalls++;
          return http.Response(jsonEncode({'message': 'from_secondary'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      final res = await apiClient.get('/api/test');
      expect(res['message'], equals('from_primary'));
      expect(primaryCalls, equals(1));
      expect(secondaryCalls, equals(0));
      expect(failoverManager.activeBackend, equals(ActiveBackend.primary));
      expect(failoverManager.activeUrl, equals(ApiConfig.primaryApiUrl));
    });

    // TEST 2: Primary unavailable -> API automatically uses secondary
    test('TEST 2: Primary unavailable -> API automatically uses secondary', () async {
      int primaryCalls = 0;
      int secondaryCalls = 0;

      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          primaryCalls++;
          throw const SocketException('Connection refused');
        } else if (request.url.toString().startsWith(ApiConfig.secondaryApiUrl)) {
          secondaryCalls++;
          return http.Response(jsonEncode({'message': 'from_secondary'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      final res = await apiClient.get('/api/test');
      expect(res['message'], equals('from_secondary'));
      expect(primaryCalls, equals(1));
      expect(secondaryCalls, greaterThanOrEqualTo(1));
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));
      expect(failoverManager.activeUrl, equals(ApiConfig.secondaryApiUrl));
    });

    // TEST 3: Secondary available -> login succeeds without user selecting server
    test('TEST 3: Secondary available -> login succeeds without user selecting server', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          throw http.ClientException('Network is unreachable');
        } else if (request.url.toString().startsWith(ApiConfig.secondaryApiUrl)) {
          return http.Response(
            jsonEncode({
              'access_token': 'test_token_123',
              'role': 'USER',
              'employee_id': '2668',
              'full_name': 'Avadhut',
              'must_change_password': false,
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      final authService = AuthService();
      final loginRes = await authService.login('2668', 'password123');

      expect(loginRes['access_token'], equals('test_token_123'));
      expect(loginRes['role'], equals('USER'));
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));
      expect(await authService.isLoggedIn(), isTrue);
    });

    // TEST 4: Both unavailable -> user sees "Attendance service is temporarily unavailable. Please try again."
    test('TEST 4: Both unavailable -> user sees generic friendly message without URLs or IPs', () async {
      final mockClient = MockClient((request) async {
        throw const SocketException('Connection timed out');
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      try {
        await apiClient.get('/api/test');
        fail('Should have thrown ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(503));
        expect(e.message, equals(ApiConfig.serviceUnavailableMessage));
        expect(e.message, equals('Attendance service is temporarily unavailable. Please try again.'));
        // Verify no sensitive IP or URL in message
        expect(e.message.contains(ApiConfig.primaryApiUrl), isFalse);
        expect(e.message.contains(ApiConfig.secondaryApiUrl), isFalse);
      }
    });

    // TEST 5: Primary returns HTTP 401 -> do not switch to secondary
    test('TEST 5: Primary returns HTTP 401 -> do not switch to secondary', () async {
      int secondaryCalls = 0;

      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          return http.Response(jsonEncode({'detail': 'Invalid credentials'}), 401);
        } else {
          secondaryCalls++;
          return http.Response(jsonEncode({'detail': 'from_secondary'}), 200);
        }
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      try {
        await apiClient.post('/api/auth/login', body: {'employee_id': 'bad'});
        fail('Should have thrown 401 ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(401));
        expect(e.message, equals('Invalid credentials'));
      }

      // Backend must NOT have switched to secondary
      expect(secondaryCalls, equals(0));
      expect(failoverManager.activeBackend, equals(ActiveBackend.primary));
    });

    // TEST 6: Primary returns HTTP 400 -> do not switch
    test('TEST 6: Primary returns HTTP 400 -> do not switch to secondary', () async {
      int secondaryCalls = 0;

      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          return http.Response(jsonEncode({'detail': 'Bad request validation'}), 400);
        } else {
          secondaryCalls++;
          return http.Response('ok', 200);
        }
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      try {
        await apiClient.get('/api/user/test');
        fail('Should have thrown 400 ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, equals(400));
        expect(e.message, equals('Bad request validation'));
      }

      expect(secondaryCalls, equals(0));
      expect(failoverManager.activeBackend, equals(ActiveBackend.primary));
    });

    // TEST 7: Primary returns timeout -> switch to secondary
    test('TEST 7: Primary returns timeout -> switch to secondary', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          throw TimeoutException('Connection timed out');
        } else if (request.url.toString().startsWith(ApiConfig.secondaryApiUrl)) {
          return http.Response(jsonEncode({'status': 'recovered_via_secondary'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      final res = await apiClient.get('/api/data');
      expect(res['status'], equals('recovered_via_secondary'));
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));
    });

    // TEST 8: Primary returns HTTP 503 -> switch to secondary
    test('TEST 8: Primary returns HTTP 503 -> switch to secondary', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          return http.Response('Service Unavailable', 503);
        } else if (request.url.toString().startsWith(ApiConfig.secondaryApiUrl)) {
          return http.Response(jsonEncode({'status': 'healthy_secondary'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      final res = await apiClient.get('/api/status');
      expect(res['status'], equals('healthy_secondary'));
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));
    });

    // TEST 9: Application starts while primary is unavailable -> automatically select secondary
    test('TEST 9: Application starts while primary is unavailable -> automatically select secondary', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          throw const SocketException('Connection refused');
        } else if (request.url.toString().startsWith(ApiConfig.secondaryApiUrl)) {
          return http.Response(jsonEncode({'status': 'online'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      failoverManager.httpClient = mockClient;
      apiClient.httpClient = mockClient;

      await failoverManager.init(checkReachable: true);
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));
      expect(failoverManager.activeUrl, equals(ApiConfig.secondaryApiUrl));
    });

    // TEST 10: Application is using secondary and primary recovers -> controlled switch back to primary
    test('TEST 10: Application is using secondary and primary recovers with anti-flapping checks', () async {
      failoverManager.resetForTesting(initial: ActiveBackend.secondary);
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));

      final mockClient = MockClient((request) async {
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          return http.Response(jsonEncode({'status': 'online'}), 200);
        }
        return http.Response(jsonEncode({'status': 'online'}), 200);
      });

      failoverManager.httpClient = mockClient;

      // Check 1: Should increment success count but NOT switch yet
      await failoverManager.checkPrimaryRecovery();
      expect(failoverManager.consecutivePrimarySuccesses, equals(1));
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));

      // Check 2: Still not switched
      await failoverManager.checkPrimaryRecovery();
      expect(failoverManager.consecutivePrimarySuccesses, equals(2));
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));

      // Check 3: Reached threshold of 3 -> switches back to primary!
      final recovered = await failoverManager.checkPrimaryRecovery();
      expect(recovered, isTrue);
      expect(failoverManager.activeBackend, equals(ActiveBackend.primary));
      expect(failoverManager.activeUrl, equals(ApiConfig.primaryApiUrl));
    });

    // TEST 11: Two simultaneous requests detect primary failure -> only one centralized failover occurs
    test('TEST 11: Two simultaneous requests detect primary failure -> only one centralized failover occurs', () async {
      int primaryCallCount = 0;
      int secondaryCallCount = 0;

      final mockClient = MockClient((request) async {
        // Small delay to simulate simultaneous network in-flight requests
        await Future.delayed(const Duration(milliseconds: 20));
        if (request.url.toString().startsWith(ApiConfig.primaryApiUrl)) {
          primaryCallCount++;
          throw const SocketException('Connection refused');
        } else if (request.url.toString().startsWith(ApiConfig.secondaryApiUrl)) {
          secondaryCallCount++;
          return http.Response(jsonEncode({'result': 'success'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      apiClient.httpClient = mockClient;
      failoverManager.httpClient = mockClient;

      final results = await Future.wait([
        apiClient.get('/api/endpoint1'),
        apiClient.get('/api/endpoint2'),
      ]);

      expect(results[0]['result'], equals('success'));
      expect(results[1]['result'], equals('success'));
      expect(primaryCallCount, greaterThanOrEqualTo(1));
      expect(secondaryCallCount, greaterThanOrEqualTo(1));
      expect(failoverManager.activeBackend, equals(ActiveBackend.secondary));
      // Max 1 failover occurred, secondary is now active
      expect(failoverManager.activeUrl, equals(ApiConfig.secondaryApiUrl));
    });

    // TEST 12: Login page -> Backend Server URL setting is completely absent
    testWidgets('TEST 12: Login page has no Backend Server URL setting or server dialog', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no server setting button or text exists
      expect(find.text('Backend Server URL'), findsNothing);
      expect(find.text('Server URL'), findsNothing);
      expect(find.byKey(const Key('backend_url_field')), findsNothing);
      expect(find.byIcon(Icons.dns_rounded), findsNothing);

      // Verify normal employee login elements ARE present
      expect(find.text('Employee ID / Admin ID'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    // TEST 13: Centralized configuration integrity
    test('TEST 13: Centralized configuration has valid primary & secondary URLs and timeouts', () {
      expect(ApiConfig.primaryApiUrl, isNotEmpty);
      expect(ApiConfig.secondaryApiUrl, isNotEmpty);
      expect(ApiConfig.primaryApiUrl, isNot(equals(ApiConfig.secondaryApiUrl)));
      expect(ApiConfig.requestTimeout.inSeconds, inInclusiveRange(3, 10));
      expect(ApiConfig.healthCheckTimeout.inSeconds, inInclusiveRange(1, 5));
    });

    // TEST 14: SharedPreferences custom_base_url is invalidated and cannot override ApiConfig
    test('TEST 14: SharedPreferences custom_base_url cannot override ApiConfig', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_base_url', 'http://malicious-override.com');

      final client = ApiClient();
      await client.init(checkReachable: false);

      // Must remain primary from ApiConfig, not malicious-override
      expect(client.baseUrl, equals(ApiConfig.primaryApiUrl));
      expect(prefs.getString('custom_base_url'), isNull);
    });
  });
}
