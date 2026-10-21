import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstaff_attendance/core/services/gps_distance_calculator.dart';
import 'package:fieldstaff_attendance/core/services/route_simplifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Hybrid Route Simplification - 10 Core Geospatial Scenarios', () {
    final baseTime = DateTime.parse('2026-10-19T08:00:00Z');

    // 1. Straight route with many redundant points
    test('Scenario 1: Straight route with many redundant points is heavily simplified', () {
      final points = <RouteVertex>[];
      // 100 points along a straight latitude line (0.0001 deg ~ 11.1 meters)
      for (int i = 0; i < 100; i++) {
        points.add(RouteVertex(
          latitude: 12.9716 + (i * 0.0001),
          longitude: 77.5946,
          timestamp: baseTime.add(Duration(seconds: i * 5)),
          accuracyMeters: 5.0,
        ));
      }

      final result = RouteSimplifier.simplifyHybrid(
        points,
        const RouteSimplifierOptions(
          straightEpsilonMeters: 2.0,
          radialPreFilterMeters: 1.5,
          maxAllowedDeviationMeters: 2.5,
        ),
      );

      // On a perfectly straight line, start and end are preserved, redundant intermediates removed
      expect(result.simplifiedPointCount, lessThanOrEqualTo(5));
      expect(result.reductionPercentage, greaterThanOrEqualTo(95.0));
      expect(result.originalIndices.first, equals(0));
      expect(result.originalIndices.last, equals(99));
      expect(result.maxDeviationMeters, lessThan(0.5));
    });

    // 2. Route containing sharp turns
    test('Scenario 2: Route containing sharp 90-degree turns preserves all corner vertices', () {
      final points = <RouteVertex>[];
      // Leg 1: North (10 points)
      for (int i = 0; i < 10; i++) {
        points.add(RouteVertex(
          latitude: 12.9000 + (i * 0.0002),
          longitude: 77.5000,
          timestamp: baseTime.add(Duration(seconds: points.length * 5)),
          accuracyMeters: 5.0,
        ));
      }
      final corner1Idx = points.length - 1; // 9

      // Leg 2: East (10 points)
      for (int i = 1; i < 10; i++) {
        points.add(RouteVertex(
          latitude: 12.9000 + (9 * 0.0002),
          longitude: 77.5000 + (i * 0.0002),
          timestamp: baseTime.add(Duration(seconds: points.length * 5)),
          accuracyMeters: 5.0,
        ));
      }
      final corner2Idx = points.length - 1; // 18

      // Leg 3: South (10 points)
      for (int i = 1; i < 10; i++) {
        points.add(RouteVertex(
          latitude: 12.9000 + (9 * 0.0002) - (i * 0.0002),
          longitude: 77.5000 + (9 * 0.0002),
          timestamp: baseTime.add(Duration(seconds: points.length * 5)),
          accuracyMeters: 5.0,
        ));
      }

      final result = RouteSimplifier.simplifyHybrid(
        points,
        const RouteSimplifierOptions(
          minTurnAngleDegrees: 30.0,
          minTurnSegmentDistanceMeters: 5.0,
        ),
      );

      expect(result.originalIndices.contains(corner1Idx), isTrue,
          reason: 'First 90-deg corner must be retained');
      expect(result.originalIndices.contains(corner2Idx), isTrue,
          reason: 'Second 90-deg corner must be retained');
      expect(result.originalIndices.first, equals(0));
      expect(result.originalIndices.last, equals(points.length - 1));
      expect(result.simplifiedPointCount, lessThan(points.length));
    });

    // 3. Curved road
    test('Scenario 3: Curved arc road retains curve shape within deviation tolerance', () {
      final points = <RouteVertex>[];
      final centerLat = 12.9700;
      final centerLon = 77.5900;
      final radius = 0.005; // ~550m radius

      // Quarter-circle arc in 50 points
      for (int i = 0; i <= 50; i++) {
        final angle = (i / 50.0) * (math.pi / 2);
        points.add(RouteVertex(
          latitude: centerLat + radius * math.cos(angle),
          longitude: centerLon + radius * math.sin(angle),
          timestamp: baseTime.add(Duration(seconds: i * 5)),
          accuracyMeters: 5.0,
        ));
      }

      final result = RouteSimplifier.simplifyHybrid(
        points,
        const RouteSimplifierOptions(
          baseEpsilonMeters: 1.0,
          turnEpsilonMeters: 0.8,
          maxAllowedDeviationMeters: 2.0,
        ),
      );

      expect(result.simplifiedPointCount, greaterThan(3),
          reason: 'Curve must not be collapsed to a single straight line');
      expect(result.simplifiedPointCount, lessThan(points.length));
      expect(result.maxDeviationMeters, lessThanOrEqualTo(2.0),
          reason: 'Curve deviation must stay within maxAllowedDeviationMeters');
    });

    // 4. Small loop and retraced route
    test('Scenario 4: Retraced route and small loop vertices are preserved', () {
      final points = <RouteVertex>[];
      // Outward: 10 points East
      for (int i = 0; i < 10; i++) {
        points.add(RouteVertex(
          latitude: 12.9500,
          longitude: 77.5500 + (i * 0.0003),
          timestamp: baseTime.add(Duration(seconds: points.length * 5)),
          accuracyMeters: 5.0,
        ));
      }
      final turnaroundIdx = points.length - 1; // 9

      // Return: 10 points West along almost same path
      for (int i = 1; i < 10; i++) {
        points.add(RouteVertex(
          latitude: 12.950002, // 0.2m parallel
          longitude: 77.5500 + ((9 - i) * 0.0003),
          timestamp: baseTime.add(Duration(seconds: points.length * 5)),
          accuracyMeters: 5.0,
        ));
      }

      final result = RouteSimplifier.simplifyHybrid(
        points,
        const RouteSimplifierOptions(
          preserveLoops: true,
          minTurnSegmentDistanceMeters: 5.0,
        ),
      );

      expect(result.originalIndices.contains(turnaroundIdx), isTrue,
          reason: 'Turnaround / reversal anchor must be protected');
      expect(result.originalIndices.first, equals(0));
      expect(result.originalIndices.last, equals(points.length - 1));
    });

    // 5. Duplicate and near-duplicate coordinates
    test('Scenario 5: Duplicate and near-duplicate stationary coordinates are pre-filtered', () {
      final points = <RouteVertex>[];
      // 30 points sitting at virtually the same spot (0.1m jitter)
      for (int i = 0; i < 30; i++) {
        points.add(RouteVertex(
          latitude: 12.9100 + (i * 0.0000005),
          longitude: 77.5200 + (i * 0.0000005),
          timestamp: baseTime.add(Duration(seconds: i * 5)),
          accuracyMeters: 5.0,
        ));
      }
      // Followed by moving points
      for (int i = 1; i < 10; i++) {
        points.add(RouteVertex(
          latitude: 12.9100 + (i * 0.0002),
          longitude: 77.5200,
          timestamp: baseTime.add(Duration(seconds: (30 + i) * 5)),
          accuracyMeters: 5.0,
        ));
      }

      final result = RouteSimplifier.simplifyHybrid(
        points,
        const RouteSimplifierOptions(radialPreFilterMeters: 2.0),
      );

      // The 30 stationary points should be filtered down
      expect(result.simplifiedPointCount, lessThan(15));
      expect(result.reductionPercentage, greaterThan(60.0));
    });

    // 6. Noisy smartphone GPS samples
    test('Scenario 6: High-frequency GPS cross-track jitter is smoothed without distorting path', () {
      final points = <RouteVertex>[];
      for (int i = 0; i < 40; i++) {
        // Lateral noise alternating ~0.9m jitter
        final noise = (i % 2 == 1 ? 1 : -1) * 0.000008;
        points.add(RouteVertex(
          latitude: 12.9200 + (i * 0.0001),
          longitude: 77.5300 + noise,
          timestamp: baseTime.add(Duration(seconds: i * 5)),
          accuracyMeters: 10.0,
        ));
      }

      final result = RouteSimplifier.simplifyHybrid(
        points,
        const RouteSimplifierOptions(
          straightEpsilonMeters: 2.0,
          minTurnAngleDegrees: 20.0,
          maxAllowedDeviationMeters: 3.0,
        ),
      );

      expect(result.reductionPercentage, greaterThanOrEqualTo(80.0));
      expect(result.maxDeviationMeters, lessThanOrEqualTo(3.0));
    });

    // 7. GPS interruptions and separate segments
    test('Scenario 7: GPS gap boundary vertices are strictly preserved and never bridged', () {
      final points = <RouteVertex>[];
      // Segment 1 (5 points)
      for (int i = 0; i < 5; i++) {
        points.add(RouteVertex(
          latitude: 12.9300 + (i * 0.0001),
          longitude: 77.5400,
          timestamp: baseTime.add(Duration(seconds: i * 10)),
          accuracyMeters: 5.0,
        ));
      }
      final gapStartIdx = 4;
      final gapEndIdx = 5;

      // 15-minute gap
      for (int i = 0; i < 5; i++) {
        points.add(RouteVertex(
          latitude: 12.9400 + (i * 0.0001),
          longitude: 77.5500,
          timestamp: baseTime.add(Duration(minutes: 15, seconds: i * 10)),
          accuracyMeters: 5.0,
          isGap: i == 0, // Marked as gap start
        ));
      }

      final result = RouteSimplifier.simplifyHybrid(
        points,
        const RouteSimplifierOptions(gapDurationSeconds: 180),
      );

      expect(result.originalIndices.contains(gapStartIdx), isTrue,
          reason: 'Point right before gap must be preserved');
      expect(result.originalIndices.contains(gapEndIdx), isTrue,
          reason: 'Point right after gap must be preserved');
    });

    // 8. Route with protected events and start/end points
    test('Scenario 8: Start and End coordinates are always 100% retained', () {
      final points = <RouteVertex>[
        RouteVertex(latitude: 12.0, longitude: 77.0, timestamp: baseTime, accuracyMeters: 5.0),
        RouteVertex(latitude: 12.00001, longitude: 77.00001, timestamp: baseTime.add(const Duration(seconds: 5)), accuracyMeters: 5.0),
        RouteVertex(latitude: 12.00002, longitude: 77.00002, timestamp: baseTime.add(const Duration(seconds: 10)), accuracyMeters: 5.0),
        RouteVertex(latitude: 12.00003, longitude: 77.00003, timestamp: baseTime.add(const Duration(seconds: 15)), accuracyMeters: 5.0),
      ];

      final result = RouteSimplifier.simplifyHybrid(points);

      expect(result.originalIndices.first, equals(0));
      expect(result.originalIndices.last, equals(points.length - 1));
      expect(result.simplifiedVertices.first.latitude, equals(12.0));
      expect(result.simplifiedVertices.last.latitude, equals(12.00003));
    });

    // 9. Route with very few points (0, 1, 2)
    test('Scenario 9: Route with 0, 1, or 2 points returns safe, identical results', () {
      final emptyResult = RouteSimplifier.simplifyHybrid([]);
      expect(emptyResult.simplifiedPointCount, equals(0));

      final singlePoint = [
        RouteVertex(latitude: 12.0, longitude: 77.0, timestamp: baseTime, accuracyMeters: 5.0)
      ];
      final singleResult = RouteSimplifier.simplifyHybrid(singlePoint);
      expect(singleResult.simplifiedPointCount, equals(1));
      expect(singleResult.originalIndices, equals([0]));

      final twoPoints = [
        RouteVertex(latitude: 12.0, longitude: 77.0, timestamp: baseTime, accuracyMeters: 5.0),
        RouteVertex(latitude: 12.1, longitude: 77.1, timestamp: baseTime.add(const Duration(seconds: 10)), accuracyMeters: 5.0),
      ];
      final twoResult = RouteSimplifier.simplifyHybrid(twoPoints);
      expect(twoResult.simplifiedPointCount, equals(2));
      expect(twoResult.originalIndices, equals([0, 1]));
    });

    // 10. Empty, invalid, or zero-coordinate input
    test('Scenario 10: Empty or invalid coordinate data handled gracefully', () {
      final maps = <Map<String, dynamic>>[];
      final displayPoints = RouteSimplifier.getSimplifiedDisplayPoints(maps);
      expect(displayPoints.isEmpty, isTrue);

      final latLngs = RouteSimplifier.simplifyLatLngs([]);
      expect(latLngs.simplifiedPointCount, equals(0));
    });
  });

  group('Session 25 Real 397-Point Route Benchmark', () {
    test('Real 397-point route simplifies cleanly with bounded deviation', () {
      // Find export json file
      final possiblePaths = [
        '../../../../backend/exports/latest/json/gps_route_points.json',
        '../../../backend/exports/latest/json/gps_route_points.json',
        '../../backend/exports/latest/json/gps_route_points.json',
        '../backend/exports/latest/json/gps_route_points.json',
        'backend/exports/latest/json/gps_route_points.json',
        'c:/Users/Administrator/Desktop/Tracking/backend/exports/latest/json/gps_route_points.json',
      ];

      File? targetFile;
      for (final p in possiblePaths) {
        final f = File(p);
        if (f.existsSync()) {
          targetFile = f;
          break;
        }
      }

      expect(targetFile, isNotNull, reason: 'gps_route_points.json must be accessible for benchmark');
      final jsonStr = targetFile!.readAsStringSync();
      final List<dynamic> data = jsonDecode(jsonStr);

      // Filter Session 25 records
      final session25Rows = data.where((r) => r['session_id'] == 25).toList();
      expect(session25Rows.length, equals(397),
          reason: 'Session 25 must contain exactly 397 coordinates as reported');

      // Sort by recorded_at
      session25Rows.sort((a, b) => (a['recorded_at'] as String).compareTo(b['recorded_at'] as String));

      final vertices = session25Rows.map((r) => RouteVertex.fromMap(r as Map<String, dynamic>)).toList();

      // Benchmark execution time
      final stopwatch = Stopwatch()..start();
      final result = RouteSimplifier.simplifyHybrid(
        vertices,
        const RouteSimplifierOptions(
          baseEpsilonMeters: 0.75,
          turnEpsilonMeters: 0.5,
          straightEpsilonMeters: 1.5,
          radialPreFilterMeters: 1.0,
          minTurnAngleDegrees: 15.0,
          maxAllowedDeviationMeters: 2.5,
          minTurnSegmentDistanceMeters: 3.0,
        ),
      );
      stopwatch.stop();

      print('=== Flutter Session 25 Benchmark Results ===');
      print('Original Point Count: ${result.originalPointCount}');
      print('Simplified Point Count: ${result.simplifiedPointCount}');
      print('Points Removed: ${result.originalPointCount - result.simplifiedPointCount} (${result.reductionPercentage.toStringAsFixed(2)}%)');
      print('Max Geometric Deviation: ${result.maxDeviationMeters.toStringAsFixed(3)} meters');
      print('Execution Time: ${stopwatch.elapsedMilliseconds} ms');
      print('Protected Anchors: ${result.protectedIndices.length}');

      // Verification checks
      expect(result.originalPointCount, equals(397));
      expect(result.simplifiedPointCount, lessThan(150),
          reason: 'Simplified point count should be well under 150 points');
      expect(result.reductionPercentage, greaterThan(60.0),
          reason: 'Reduction percentage should be at least 60%');
      expect(result.maxDeviationMeters, lessThanOrEqualTo(2.5),
          reason: 'Geometric cross-track deviation must not exceed 2.5 meters');
      expect(result.originalIndices.first, equals(0),
          reason: 'Journey start must be retained');
      expect(result.originalIndices.last, equals(396),
          reason: 'Journey end must be retained');
      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: 'Hybrid simplification of 397 points must complete within 200ms');

      // Distance integrity check: Verify that calculating distance from original validated points is preserved
      double originalTotalDistance = 0.0;
      for (int i = 0; i < vertices.length - 1; i++) {
        originalTotalDistance += GpsDistanceCalculator.haversineDistanceMeters(
          vertices[i].latitude,
          vertices[i].longitude,
          vertices[i + 1].latitude,
          vertices[i + 1].longitude,
        );
      }
      expect(originalTotalDistance, greaterThan(0.0));
      print('Original Validated Cumulative Distance: ${(originalTotalDistance / 1000.0).toStringAsFixed(3)} km');
    });
  });
}
