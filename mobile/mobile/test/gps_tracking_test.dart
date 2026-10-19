import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstaff_attendance/core/services/gps_distance_calculator.dart';
import 'package:fieldstaff_attendance/core/services/tracking_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TrackingDatabase.instance.isTestMode = true;
  });

  group('GPS Haversine Distance Calculator', () {
    test('Calculates accurate distance between known coordinates (Pune benchmarks)', () {
      // Pune Railway Station to Shaniwar Wada (~2,260 meters)
      const lat1 = 18.5284;
      const lon1 = 73.8744;
      const lat2 = 18.5196;
      const lon2 = 73.8553;

      final dist = GpsDistanceCalculator.haversineDistanceMeters(lat1, lon1, lat2, lon2);
      expect(dist, greaterThan(2200));
      expect(dist, lessThan(2350));
    });

    test('Returns 0.0 for identical coordinates', () {
      final dist = GpsDistanceCalculator.haversineDistanceMeters(18.5204, 73.8567, 18.5204, 73.8567);
      expect(dist, equals(0.0));
    });

    test('Rejects invalid coordinate ranges', () {
      expect(GpsDistanceCalculator.isValidCoordinate(91.0, 73.0), isFalse);
      expect(GpsDistanceCalculator.isValidCoordinate(-90.1, 73.0), isFalse);
      expect(GpsDistanceCalculator.isValidCoordinate(18.0, 181.0), isFalse);
      expect(GpsDistanceCalculator.isValidCoordinate(18.0, -180.1), isFalse);
      expect(GpsDistanceCalculator.isValidCoordinate(0.0, 0.0), isFalse); // Null Island
      expect(GpsDistanceCalculator.isValidCoordinate(18.5, 73.8), isTrue);
    });
  });

  group('GPS Filtering, Drift, and Movement Accumulation', () {
    late GpsDistanceCalculator calculator;

    setUp(() {
      calculator = GpsDistanceCalculator(
        maxAllowedAccuracyMeters: 50.0,
        minMovementThresholdMeters: 15.0,
        maxImpliedSpeedMps: 45.0,
      );
    });

    test('Rejects noisy observations with accuracy > 50m', () {
      final now = DateTime.now().toUtc();
      // First point to initialize
      final init = calculator.processFix(
        latitude: 18.5200,
        longitude: 73.8500,
        accuracyMeters: 10.0,
        timestamp: now,
      );
      expect(init.isAccepted, isTrue);

      // Poor accuracy point (e.g. 75m)
      final noisy = calculator.processFix(
        latitude: 18.5205,
        longitude: 73.8505,
        accuracyMeters: 75.0,
        timestamp: now.add(const Duration(seconds: 10)),
      );
      expect(noisy.isAccepted, isFalse);
      expect(noisy.rejectionReason, contains('Accuracy too low'));
    });

    test('Accumulates small movements (< 15m) so walking distance is not lost', () {
      final now = DateTime.now().toUtc();
      final init = calculator.processFix(
        latitude: 18.520000,
        longitude: 73.850000,
        accuracyMeters: 6.0,
        timestamp: now,
      );
      expect(init.isAccepted, isTrue);
      expect(init.distanceAddedMeters, equals(0.0));

      // Step 1: ~7m move (below 15m threshold, distance committed is 0 but reference remains)
      final step1 = calculator.processFix(
        latitude: 18.520063,
        longitude: 73.850000,
        accuracyMeters: 6.0,
        timestamp: now.add(const Duration(seconds: 10)),
      );
      expect(step1.isAccepted, isTrue);
      expect(step1.distanceAddedMeters, equals(0.0));

      // Step 2: Another ~10m move (total ~17m from reference point, crosses 15m threshold!)
      final step2 = calculator.processFix(
        latitude: 18.520153,
        longitude: 73.850000,
        accuracyMeters: 6.0,
        timestamp: now.add(const Duration(seconds: 20)),
      );
      expect(step2.isAccepted, isTrue);
      expect(step2.distanceAddedMeters, greaterThan(15.0));
      expect(step2.isGap, isFalse);
    });

    test('Filters impossible location jumps (> 45 m/s or 162 km/h)', () {
      final now = DateTime.now().toUtc();
      calculator.processFix(
        latitude: 18.5200,
        longitude: 73.8500,
        accuracyMeters: 10.0,
        timestamp: now,
      );

      // Jump 5 km in 10 seconds (implied speed = 500 m/s)
      final jump = calculator.processFix(
        latitude: 18.5600,
        longitude: 73.8500,
        accuracyMeters: 10.0,
        timestamp: now.add(const Duration(seconds: 10)),
      );
      expect(jump.isAccepted, isFalse);
      expect(jump.rejectionReason, contains('Implied speed excessive'));
    });

    test('Detects tracking gap when resumed from pause', () {
      final now = DateTime.now().toUtc();
      calculator.processFix(
        latitude: 18.5200,
        longitude: 73.8500,
        accuracyMeters: 10.0,
        timestamp: now,
      );

      // Resumed after pause: 50m move with isResumedAfterPause = true
      final resumed = calculator.processFix(
        latitude: 18.5205,
        longitude: 73.8505,
        accuracyMeters: 10.0,
        timestamp: now.add(const Duration(minutes: 30)),
        isResumedAfterPause: true,
      );
      expect(resumed.isAccepted, isTrue);
      expect(resumed.isGap, isTrue);
      // Distance across gap must NOT be added to continuous travel distance
      expect(resumed.distanceAddedMeters, equals(0.0));
    });
  });

  group('Offline SQLite Database & Sequence Number Stability', () {
    test('Database singleton provides non-colliding sequence retrieval', () async {
      final db = TrackingDatabase.instance;
      expect(db, isNotNull);

      const sessionUuid = 'test-session-seq-123';
      final maxSeq = await db.getMaxSequenceNumber(sessionUuid);
      expect(maxSeq, equals(0));

      // Insert point
      await db.insertPoint({
        'session_uuid': sessionUuid,
        'client_point_id': '${sessionUuid}_pt_1',
        'sequence_number': 1,
        'latitude': 18.5204,
        'longitude': 73.8567,
        'accuracy_meters': 8.5,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
        'is_gap': 0,
        'sync_status': 'PENDING',
      });

      final newMaxSeq = await db.getMaxSequenceNumber(sessionUuid);
      expect(newMaxSeq, equals(1));

      // Verify getLastPoint retrieves the inserted point
      final lastPoint = await db.getLastPoint(sessionUuid);
      expect(lastPoint, isNotNull);
      expect(lastPoint!['sequence_number'], equals(1));
      expect(lastPoint['client_point_id'], equals('${sessionUuid}_pt_1'));
    });
  });
}
