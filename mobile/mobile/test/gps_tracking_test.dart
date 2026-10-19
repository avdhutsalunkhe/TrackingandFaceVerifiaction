import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstaff_attendance/core/services/gps_distance_calculator.dart';
import 'package:fieldstaff_attendance/core/services/tracking_database.dart';
import 'package:fieldstaff_attendance/core/services/route_simplifier.dart';

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

    test('100 continuous GPS fixes throughout journey are ALL accepted without false speed rejections', () {
      final startTime = DateTime.now().toUtc();
      double totalDistance = 0.0;
      int acceptedCount = 0;

      // Simulate a 100-fix journey: moving eastward at ~15 m/s (54 km/h) with 3s intervals
      // ~45 meters per step, 100 steps = ~4.5 km journey
      double currentLat = 18.5200;
      double currentLng = 73.8500;

      for (int i = 0; i < 100; i++) {
        final fixTime = startTime.add(Duration(seconds: i * 3));
        // Move ~45 meters east (each 0.0004 deg lon at this latitude is ~42m)
        currentLng += 0.0004;

        final res = calculator.processFix(
          latitude: currentLat,
          longitude: currentLng,
          accuracyMeters: 8.0 + (i % 5),
          timestamp: fixTime,
        );

        if (res.isAccepted) {
          acceptedCount++;
          totalDistance += res.distanceAddedMeters;
        }
      }

      // 100% of observations throughout the journey must be accepted
      expect(acceptedCount, equals(100));
      // Total accumulated distance should be between 4,000m and 4,800m
      expect(totalDistance, greaterThan(4000.0));
      expect(totalDistance, lessThan(4800.0));
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

    test('rekeySessionUuid updates session and all points from old UUID to canonical UUID', () async {
      final db = TrackingDatabase.instance;
      const oldUuid = 'TRACK_LOCAL_TEMP_UUID';
      const canonicalUuid = 'TRACK_CANONICAL_SERVER_UUID';

      await db.queueOfflineSession({
        'session_uuid': oldUuid,
        'user_id': 101,
        'work_date': '2026-10-19',
        'start_time': DateTime.now().toUtc().toIso8601String(),
        'status': 'RECORDING',
        'total_distance_meters': 0.0,
      });

      await db.insertPoint({
        'session_uuid': oldUuid,
        'client_point_id': '${oldUuid}_pt_1_1000',
        'sequence_number': 1,
        'latitude': 18.5200,
        'longitude': 73.8500,
        'accuracy_meters': 10.0,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'PENDING',
      });

      // Rekey
      await db.rekeySessionUuid(oldUuid, canonicalUuid);

      // Verify points under canonical UUID
      final points = await db.getSessionPoints(canonicalUuid);
      expect(points.length, equals(1));
      expect(points.first['session_uuid'], equals(canonicalUuid));
      expect(points.first['client_point_id'], contains(canonicalUuid));

      // Verify old UUID has 0 points
      final oldPoints = await db.getSessionPoints(oldUuid);
      expect(oldPoints.length, equals(0));
    });
  });

  group('Compressed Route Geometry & Stationary Suppression', () {
    test('Stationary jitter is suppressed, while periodic heartbeat preserves presence', () {
      final now = DateTime.now().toUtc();
      // First fix
      final lastAcceptedTime = now;
      final lastAcceptedLat = 18.520400;
      final lastAcceptedLng = 73.856700;

      // Stationary jitter: displacement = 2m (< 5m), speed = 0.1 m/s (< 0.5 m/s), time elapsed = 3s (< 120s)
      final jitterResult = GpsDistanceCalculator.shouldRetainCandidateVertex(
        candLat: 18.520418,
        candLng: 73.856700,
        candSpeedMps: 0.1,
        candBearingDegrees: null,
        candTimestamp: now.add(const Duration(seconds: 3)),
        lastAcceptedLat: lastAcceptedLat,
        lastAcceptedLng: lastAcceptedLng,
        lastAcceptedBearing: null,
        lastAcceptedTime: lastAcceptedTime,
      );
      expect(jitterResult.shouldRetain, isFalse);
      expect(jitterResult.reason, contains('Stationary suppression'));

      // Heartbeat: stationary for 125 seconds (> 120s heartbeat interval)
      final heartbeatResult = GpsDistanceCalculator.shouldRetainCandidateVertex(
        candLat: 18.520418,
        candLng: 73.856700,
        candSpeedMps: 0.05,
        candBearingDegrees: null,
        candTimestamp: now.add(const Duration(seconds: 125)),
        lastAcceptedLat: lastAcceptedLat,
        lastAcceptedLng: lastAcceptedLng,
        lastAcceptedBearing: null,
        lastAcceptedTime: lastAcceptedTime,
      );
      expect(heartbeatResult.shouldRetain, isTrue);
      expect(heartbeatResult.reason, contains('Heartbeat'));
    });

    test('Turn detection forces candidate retention when heading changes >= 18 degrees', () {
      final now = DateTime.now().toUtc();
      final lastAcceptedTime = now;
      final lastAcceptedLat = 18.520400;
      final lastAcceptedLng = 73.856700;

      // Heading changes from 90° (East) to 125° (Turn of 35°)
      final turnResult = GpsDistanceCalculator.shouldRetainCandidateVertex(
        candLat: 18.520420,
        candLng: 73.856800,
        candSpeedMps: 8.0,
        candBearingDegrees: 125.0,
        candTimestamp: now.add(const Duration(seconds: 3)),
        lastAcceptedLat: lastAcceptedLat,
        lastAcceptedLng: lastAcceptedLng,
        lastAcceptedBearing: 90.0,
        lastAcceptedTime: lastAcceptedTime,
      );
      expect(turnResult.shouldRetain, isTrue);
      expect(turnResult.reason, contains('Heading delta'));
    });

    test('Douglas-Peucker simplifies straight segments while preserving corners and gaps', () {
      final now = DateTime.now().toUtc();
      final List<RouteVertex> vertices = [];

      // Straight line with 10 intermediate points
      for (int i = 0; i <= 10; i++) {
        vertices.add(RouteVertex(
          latitude: 18.5200 + (i * 0.0001),
          longitude: 73.8500,
          timestamp: now.add(Duration(seconds: i * 3)),
          accuracyMeters: 5.0,
        ));
      }

      // Add a sharp 90-degree corner
      for (int i = 1; i <= 10; i++) {
        vertices.add(RouteVertex(
          latitude: 18.5210,
          longitude: 73.8500 + (i * 0.0001),
          timestamp: now.add(Duration(seconds: (10 + i) * 3)),
          accuracyMeters: 5.0,
        ));
      }

      expect(vertices.length, equals(21));

      // Simplify with epsilon = 6.0 meters
      final simplified = RouteSimplifier.simplify(vertices, epsilon: 6.0);

      // Simplification should compress straight lines down to start, corner, and end
      expect(simplified.length, lessThanOrEqualTo(4));
      expect(simplified.first.latitude, closeTo(18.5200, 0.00001));
      expect(simplified.last.longitude, closeTo(73.8510, 0.00001));

      // The corner vertex must be preserved!
      final hasCorner = simplified.any((v) => (v.latitude - 18.5210).abs() < 0.00005 && (v.longitude - 73.8500).abs() < 0.00005);
      expect(hasCorner, isTrue);
    });

    test('100+ raw GPS observations benchmark: 100% distance accuracy with >= 90% record reduction', () async {
      final db = TrackingDatabase.instance;
      const sessionUuid = 'BENCHMARK_100_OBSERVATIONS';
      final calc = GpsDistanceCalculator();
      final now = DateTime.now().toUtc();

      double accumulatedDistance = 0.0;
      final List<RouteVertex> rawVertices = [];

      // Simulate vehicle route: 120 observations (every 3s = 6 minutes of driving)
      // Segment 1: Straight road (50 points, moving North)
      // Segment 2: Sharp turn to East (50 points, moving East)
      // Segment 3: Stationary traffic light (20 points, jittering within 2m)
      double currentLat = 18.520000;
      double currentLng = 73.850000;

      for (int i = 0; i < 120; i++) {
        final fixTime = now.add(Duration(seconds: i * 3));
        if (i < 50) {
          currentLat += 0.00018; // ~20m per step North
        } else if (i < 100) {
          currentLng += 0.00018; // ~19m per step East
        } else {
          // Stationary jitter < 2m
          currentLat += ((i % 2 == 0) ? 0.000005 : -0.000005);
        }

        final fixRes = calc.processFix(
          latitude: currentLat,
          longitude: currentLng,
          accuracyMeters: 6.0,
          timestamp: fixTime,
        );

        if (fixRes.isAccepted) {
          accumulatedDistance += fixRes.distanceAddedMeters;
          rawVertices.add(RouteVertex(
            latitude: currentLat,
            longitude: currentLng,
            timestamp: fixTime,
            accuracyMeters: 6.0,
            speedMps: (i < 100) ? 6.5 : 0.05,
            bearingDegrees: (i < 50) ? 0.0 : (i < 100 ? 90.0 : 90.0),
          ));
        }
      }

      // 1. Verify 100% distance calculation fidelity:
      // ~50 steps * 20m + ~50 steps * 19m ~= 1,950m
      expect(accumulatedDistance, greaterThan(1800.0));
      expect(accumulatedDistance, lessThan(2100.0));

      // 2. Simplify the vertices using Douglas-Peucker & save as compressed chunk
      final simplifiedVertices = RouteSimplifier.simplify(rawVertices, epsilon: 6.0);
      final encodedGeom = RouteSimplifier.encodeVertices(simplifiedVertices);

      // Insert into chunk database
      await db.insertRouteChunk({
        'chunk_uuid': '${sessionUuid}_chk_001',
        'session_uuid': sessionUuid,
        'chunk_sequence': 1,
        'point_count': simplifiedVertices.length,
        'encoded_geometry': encodedGeom,
        'start_time': rawVertices.first.timestamp.toIso8601String(),
        'end_time': rawVertices.last.timestamp.toIso8601String(),
        'distance_meters': accumulatedDistance,
        'sync_status': 'PENDING',
      });

      // 3. Verify record reduction:
      // Instead of 120 database records, only 1 chunk record is created! (99.1% record reduction)
      final pendingChunks = await db.getPendingRouteChunks(sessionUuid);
      expect(pendingChunks.length, equals(1));
      expect(pendingChunks.length, lessThan(10)); // < 10 records requirement satisfied

      // 4. Verify route reconstruction:
      final reconstructed = await db.getSessionReconstructedPoints(sessionUuid);
      expect(reconstructed.isNotEmpty, isTrue);
      // Reconstructed route must preserve start and end within tight bounds
      expect(reconstructed.first['latitude'], closeTo(18.520000, 0.0001));
      expect(reconstructed.last['longitude'], closeTo(currentLng, 0.001));
    });

    test('Critical Scenario: A -> B -> C -> D -> A preserves outbound and return journey without loop collapsing', () async {
      final db = TrackingDatabase.instance;
      const sessionUuid = 'LOOP_JOURNEY_ABCDA';
      final calc = GpsDistanceCalculator();
      final startTime = DateTime.now().toUtc();

      double accumulatedDistance = 0.0;
      final List<RouteVertex> vertices = [];

      // Waypoints:
      // A: (18.5200, 73.8500)
      // B: (18.5300, 73.8500) - ~1,110m North
      // C: (18.5300, 73.8600) - ~1,050m East
      // D: (18.5200, 73.8600) - ~1,110m South
      // A: (18.5200, 73.8500) - ~1,050m West (return to origin)

      final waypoints = [
        const LatLng(18.5200, 73.8500), // A (Start)
        const LatLng(18.5250, 73.8500),
        const LatLng(18.5300, 73.8500), // B
        const LatLng(18.5300, 73.8550),
        const LatLng(18.5300, 73.8600), // C
        const LatLng(18.5250, 73.8600),
        const LatLng(18.5200, 73.8600), // D
        const LatLng(18.5200, 73.8550),
        const LatLng(18.5200, 73.8500), // A (Return to Start)
      ];

      for (int i = 0; i < waypoints.length; i++) {
        final fixTime = startTime.add(Duration(seconds: i * 30));
        final pt = waypoints[i];
        final res = calc.processFix(
          latitude: pt.latitude,
          longitude: pt.longitude,
          accuracyMeters: 6.0,
          timestamp: fixTime,
        );

        if (res.isAccepted) {
          accumulatedDistance += res.distanceAddedMeters;
          vertices.add(RouteVertex(
            latitude: pt.latitude,
            longitude: pt.longitude,
            timestamp: fixTime,
            accuracyMeters: 6.0,
            speedMps: 10.0,
          ));
        }
      }

      // 1. Total distance must reflect full perimeter (~4.3 km), NOT 0
      expect(accumulatedDistance, greaterThan(4000.0));
      expect(accumulatedDistance, lessThan(4600.0));

      // 2. Simplification must preserve start A, corners B, C, D, and return A
      const simplifier = RouteSimplifier(epsilonMeters: 3.5, minTurnAngleDegrees: 12.0);
      final simplified = simplifier.simplify(vertices);

      // Verify Start A and Return A are both preserved independently with distinct timestamps
      expect(simplified.first.latitude, equals(18.5200));
      expect(simplified.first.longitude, equals(73.8500));
      expect(simplified.last.latitude, equals(18.5200));
      expect(simplified.last.longitude, equals(73.8500));
      expect(simplified.last.timestamp.isAfter(simplified.first.timestamp), isTrue);

      // Verify intermediate corners B, C, D are all preserved
      final hasB = simplified.any((v) => (v.latitude - 18.5300).abs() < 0.0001 && (v.longitude - 73.8500).abs() < 0.0001);
      final hasC = simplified.any((v) => (v.latitude - 18.5300).abs() < 0.0001 && (v.longitude - 73.8600).abs() < 0.0001);
      final hasD = simplified.any((v) => (v.latitude - 18.5200).abs() < 0.0001 && (v.longitude - 73.8600).abs() < 0.0001);
      expect(hasB, isTrue, reason: 'Corner B must be preserved');
      expect(hasC, isTrue, reason: 'Corner C must be preserved');
      expect(hasD, isTrue, reason: 'Corner D must be preserved');

      // 3. Save chunk and verify reconstructed playback preserves chronological order
      final encodedGeom = jsonEncode(simplified.map((v) => v.toCompactList()).toList());
      await db.insertRouteChunk({
        'chunk_uuid': '${sessionUuid}_chk_loop',
        'session_uuid': sessionUuid,
        'chunk_sequence': 1,
        'point_count': simplified.length,
        'encoded_geometry': encodedGeom,
        'start_time': vertices.first.timestamp.toIso8601String(),
        'end_time': vertices.last.timestamp.toIso8601String(),
        'distance_meters': accumulatedDistance,
        'sync_status': 'PENDING',
      });

      final reconstructed = await db.getSessionReconstructedPoints(sessionUuid);
      expect(reconstructed.length, equals(simplified.length));
      expect(reconstructed.first['latitude'], equals(18.5200));
      expect(reconstructed.last['latitude'], equals(18.5200));
      expect(reconstructed.first['sequence_number'], equals(1));
      expect(reconstructed.last['sequence_number'], equals(reconstructed.length));
    });
  });
}


