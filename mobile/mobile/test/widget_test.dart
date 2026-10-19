import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fieldstaff_attendance/core/services/offline_attendance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineAttendanceService Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with empty pending queue', () async {
      final service = OfflineAttendanceService();
      final queue = await service.loadPendingQueue();
      expect(queue, isEmpty);
      expect(service.pendingQueueNotifier.value, isEmpty);
    });

    test('Throws Exception when attempting to enqueue attendance offline', () async {
      final service = OfflineAttendanceService();

      expect(
        () async => await service.enqueueOfflineAttendance(
          userId: 2668,
          attendanceDate: '2026-09-22',
          verificationNo: 1,
          verificationWindow: '08:00:00 - 09:00:00',
          latitude: 18.5204,
          longitude: 73.8567,
          accuracy: 5.5,
          geofenceDistance: 22.1,
          faceResult: 'MATCH',
          livenessResult: 'PASS',
          verificationScore: 0.96,
        ),
        throwsA(isA<Exception>()),
      );

      final queue = await service.loadPendingQueue();
      expect(queue, isEmpty);
    });
  });
}
