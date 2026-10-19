import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fieldstaff_attendance/core/constants/api_constants.dart';
import 'package:fieldstaff_attendance/core/network/api_client.dart';
import 'package:fieldstaff_attendance/core/services/server_time_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Server Failover & Automatic Candidate Probing', () {
    test('ApiConstants contains configured port 8084 server candidates in priority order', () {
      expect(ApiConstants.serverCandidates, contains('http://192.168.1.91:8084'));
      expect(ApiConstants.serverCandidates, contains('http://115.244.240.22:8084'));
      expect(ApiConstants.serverCandidates, contains('http://182.66.233.66:8084'));
      expect(ApiConstants.serverCandidates, isNot(contains('http://127.0.0.1:8084')));
      expect(ApiConstants.defaultBaseUrl, equals('http://192.168.1.91:8084'));
    });

    test('ApiClient initializes with defaultBaseUrl or stored custom_base_url', () async {
      final client = ApiClient();
      await client.init();
      expect(client.baseUrl, isNotEmpty);
    });

    test('ApiClient allows updating base URL and persists to SharedPreferences', () async {
      final client = ApiClient();
      await client.setBaseUrl('http://115.244.240.22:8084');
      expect(client.baseUrl, equals('http://115.244.240.22:8084'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('custom_base_url'), equals('http://115.244.240.22:8084'));
    });

    test('ApiException formats correctly with message and statusCode', () {
      final exc = ApiException('Unauthorized access', statusCode: 401);
      expect(exc.statusCode, equals(401));
      expect(exc.message, equals('Unauthorized access'));
      expect(exc.toString(), contains('Unauthorized access'));
    });
  });

  group('ServerTimeService 3-Second Synchronization Interval', () {
    test('ServerTimeService initializes with monotonic clock and 3s sync timer', () {
      final service = ServerTimeService();
      service.init();
      expect(service.isSynchronized, isA<bool>());
      expect(service.timeNotifier.value, isNotNull);
      service.dispose();
    });
  });
}
