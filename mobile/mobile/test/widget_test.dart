import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fieldstaff_attendance/core/services/offline_attendance_service.dart';
import 'package:fieldstaff_attendance/core/services/tracking_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineAttendanceService Unit Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TrackingDatabase.instance.isTestMode = true;
    });

    test('Initializes with empty pending queue', () async {
      final service = OfflineAttendanceService.instance;
      final queue = await service.loadPendingQueue();
      expect(queue, isEmpty);
      expect(service.pendingQueueNotifier.value, isEmpty);
      expect(service.pendingCountNotifier.value, 0);
    });

    test('Throws Exception when attempting to enqueue attendance offline', () async {
      final service = OfflineAttendanceService.instance;

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

    test('Enqueues offline selfie request with binary BLOB image into SQLite storage', () async {
      final service = OfflineAttendanceService.instance;
      final dummyBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);

      final saved = await service.enqueueOfflineSelfieRequest(
        clientRequestId: 'req_test_1001',
        userId: 64,
        employeeId: 'EMP_10001',
        latitude: 18.5204,
        longitude: 73.8567,
        accuracy: 4.2,
        locationName: 'Headquarters Pune',
        reason: 'Network outage during selfie punch',
        verificationNo: 2,
        includeData: true,
        imageBytes: dummyBytes,
      );

      expect(saved, isTrue);

      final pending = await TrackingDatabase.instance.getPendingAttendanceRequests();
      expect(pending.length, 1);

      final firstReq = pending.first;
      expect(firstReq['client_request_id'], 'req_test_1001');
      expect(firstReq['user_id'], 64);
      expect(firstReq['include_data'], 1);
      expect(firstReq['latitude'], 18.5204);
      expect(firstReq['sync_status'], 'PENDING');
      expect(firstReq['image_blob'], isA<Uint8List>());
      expect((firstReq['image_blob'] as Uint8List).length, dummyBytes.length);

      // Verify marking synced
      await TrackingDatabase.instance.markAttendanceRequestSynced('req_test_1001', 9988);
      final remaining = await TrackingDatabase.instance.getPendingAttendanceRequests();
      expect(remaining, isEmpty);
    });

    test('Enqueues offline selfie request without data when includeData is false', () async {
      final service = OfflineAttendanceService.instance;
      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      final saved = await service.enqueueOfflineSelfieRequest(
        clientRequestId: 'req_test_1002',
        userId: 65,
        employeeId: 'EMP_30566',
        latitude: 18.5204,
        longitude: 73.8567,
        includeData: false, // User selected NO
        imageBytes: dummyBytes,
      );

      expect(saved, isTrue);

      final pending = await TrackingDatabase.instance.getPendingAttendanceRequests();
      final req = pending.firstWhere((r) => r['client_request_id'] == 'req_test_1002');
      expect(req['include_data'], 0);
      expect(req['latitude'], 0.0);
      expect(req['longitude'], 0.0);
      expect(req['image_blob'], dummyBytes);
    });
  });
}
