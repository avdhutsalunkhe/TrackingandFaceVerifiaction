import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'gps_distance_calculator.dart';

/// Point representation used during route simplification and chunk encoding
class RouteVertex {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double accuracyMeters;
  final double? speedMps;
  final double? bearingDegrees;
  final bool isGap;

  const RouteVertex({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracyMeters,
    this.speedMps,
    this.bearingDegrees,
    this.isGap = false,
  });

  LatLng toLatLng() => LatLng(latitude, longitude);

  /// Serializes into a compact array: [lat, lng, epochSeconds, accuracy, speed, bearing, isGap]
  List<dynamic> toCompactList() {
    return [
      double.parse(latitude.toStringAsFixed(7)),
      double.parse(longitude.toStringAsFixed(7)),
      (timestamp.millisecondsSinceEpoch / 1000).round(),
      double.parse(accuracyMeters.toStringAsFixed(1)),
      speedMps != null ? double.parse(speedMps!.toStringAsFixed(1)) : null,
      bearingDegrees != null ? double.parse(bearingDegrees!.toStringAsFixed(1)) : null,
      isGap ? 1 : 0,
    ];
  }

  /// Deserializes from a compact array
  factory RouteVertex.fromCompactList(List<dynamic> list) {
    final epochSec = (list[2] as num).toInt();
    return RouteVertex(
      latitude: (list[0] as num).toDouble(),
      longitude: (list[1] as num).toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(epochSec * 1000, isUtc: true),
      accuracyMeters: (list[3] as num).toDouble(),
      speedMps: list[4] != null ? (list[4] as num).toDouble() : null,
      bearingDegrees: list[5] != null ? (list[5] as num).toDouble() : null,
      isGap: list[6] == 1 || list[6] == true,
    );
  }

  Map<String, dynamic> toMap({required String sessionUuid, required int sequenceNumber}) {
    return {
      'session_uuid': sessionUuid,
      'sequence_number': sequenceNumber,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy_meters': accuracyMeters,
      'altitude_meters': 0.0,
      'speed_mps': speedMps,
      'bearing_degrees': bearingDegrees,
      'recorded_at': timestamp.toIso8601String(),
      'is_gap': isGap ? 1 : 0,
    };
  }

  factory RouteVertex.fromMap(Map<String, dynamic> map) {
    DateTime ts;
    final recordedAt = map['recorded_at'] ?? map['captured_at'];
    if (recordedAt != null) {
      final str = '$recordedAt'.trim();
      ts = str.endsWith('Z') || str.contains('+')
          ? DateTime.parse(str).toUtc()
          : DateTime.parse('${str}Z').toUtc();
    } else {
      ts = DateTime.now().toUtc();
    }

    return RouteVertex(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      timestamp: ts,
      accuracyMeters: map['accuracy_meters'] != null
          ? (map['accuracy_meters'] as num).toDouble()
          : (map['accuracy'] != null ? (map['accuracy'] as num).toDouble() : 5.0),
      speedMps: map['speed_mps'] != null ? (map['speed_mps'] as num).toDouble() : (map['speed'] != null ? (map['speed'] as num).toDouble() : null),
      bearingDegrees: map['bearing_degrees'] != null ? (map['bearing_degrees'] as num).toDouble() : (map['bearing'] != null ? (map['bearing'] as num).toDouble() : null),
      isGap: map['is_gap'] == 1 || map['is_gap'] == true,
    );
  }
}

/// Configuration options for hybrid route simplification pipeline
class RouteSimplifierOptions {
  /// Base perpendicular distance tolerance for Douglas-Peucker (in meters).
  /// Recommended initial value: 0.5 - 1.0 meters.
  final double baseEpsilonMeters;

  /// Stricter perpendicular tolerance applied near turns, curves, and junctions (in meters).
  final double turnEpsilonMeters;

  /// Aggressive perpendicular tolerance applied along nearly straight segments (in meters).
  final double straightEpsilonMeters;

  /// Radial distance threshold (in meters) for Stage A pre-filtering.
  final double radialPreFilterMeters;

  /// Minimum angular direction change (in degrees) to classify a corner/turn (Stage C).
  final double minTurnAngleDegrees;

  /// Maximum permitted cross-track deviation (in meters) for Stage D validation.
  final double maxAllowedDeviationMeters;

  /// Minimum segment length (in meters) to evaluate bearing, resisting sensor noise.
  final double minTurnSegmentDistanceMeters;

  /// Maximum elapsed seconds without fixes before treating as a gap boundary (default: 900s = 15m).
  final int gapDurationSeconds;

  /// Protect directional reversals and small loops from collapsing.
  final bool preserveLoops;

  const RouteSimplifierOptions({
    this.baseEpsilonMeters = 0.8,
    this.turnEpsilonMeters = 0.4,
    this.straightEpsilonMeters = 1.2,
    this.radialPreFilterMeters = 1.0,
    this.minTurnAngleDegrees = 15.0,
    this.maxAllowedDeviationMeters = 2.5,
    this.minTurnSegmentDistanceMeters = 2.5,
    this.gapDurationSeconds = 900,
    this.preserveLoops = true,
  });

  RouteSimplifierOptions copyWith({
    double? baseEpsilonMeters,
    double? turnEpsilonMeters,
    double? straightEpsilonMeters,
    double? radialPreFilterMeters,
    double? minTurnAngleDegrees,
    double? maxAllowedDeviationMeters,
    double? minTurnSegmentDistanceMeters,
    int? gapDurationSeconds,
    bool? preserveLoops,
  }) {
    return RouteSimplifierOptions(
      baseEpsilonMeters: baseEpsilonMeters ?? this.baseEpsilonMeters,
      turnEpsilonMeters: turnEpsilonMeters ?? this.turnEpsilonMeters,
      straightEpsilonMeters: straightEpsilonMeters ?? this.straightEpsilonMeters,
      radialPreFilterMeters: radialPreFilterMeters ?? this.radialPreFilterMeters,
      minTurnAngleDegrees: minTurnAngleDegrees ?? this.minTurnAngleDegrees,
      maxAllowedDeviationMeters: maxAllowedDeviationMeters ?? this.maxAllowedDeviationMeters,
      minTurnSegmentDistanceMeters: minTurnSegmentDistanceMeters ?? this.minTurnSegmentDistanceMeters,
      gapDurationSeconds: gapDurationSeconds ?? this.gapDurationSeconds,
      preserveLoops: preserveLoops ?? this.preserveLoops,
    );
  }
}

/// Result of hybrid route simplification
class HybridSimplificationResult {
  /// The simplified vertices to be rendered on the map
  final List<RouteVertex> simplifiedVertices;

  /// 0-indexed indices of the retained vertices within the original list
  final List<int> originalIndices;

  /// Original number of GPS points
  final int originalPointCount;

  /// Simplified number of GPS points
  final int simplifiedPointCount;

  /// Point reduction percentage (0.0% to 100.0%)
  final double reductionPercentage;

  /// Maximum measured geometric cross-track deviation across the entire route (in meters)
  final double maxDeviationMeters;

  /// Set of indices identifying all protected anchors (start, end, gaps, sharp turns, loops)
  final Set<int> protectedIndices;

  const HybridSimplificationResult({
    required this.simplifiedVertices,
    required this.originalIndices,
    required this.originalPointCount,
    required this.simplifiedPointCount,
    required this.reductionPercentage,
    required this.maxDeviationMeters,
    required this.protectedIndices,
  });

  List<LatLng> toLatLngList() =>
      simplifiedVertices.map((v) => LatLng(v.latitude, v.longitude)).toList();
}

/// Production implementation of Hybrid Route Simplification Pipeline
/// Stage A: Radial Distance Pre-Filter
/// Stage B: Adaptive Ramer-Douglas-Peucker (RDP)
/// Stage C: Turning-Point & Anchor Protection
/// Stage D: Maximum-Deviation Validation
class RouteSimplifier {
  /// Default perpendicular distance tolerance (in meters).
  final double epsilonMeters;

  /// Minimum angular direction change (in degrees) to force vertex retention.
  final double minTurnAngleDegrees;

  /// Configurable options
  final RouteSimplifierOptions options;

  const RouteSimplifier({
    this.epsilonMeters = 3.5,
    this.minTurnAngleDegrees = 12.0,
    this.options = const RouteSimplifierOptions(),
  });

  /// Backward-compatible simplification entry point.
  /// Simplifies a candidate list of vertices, preserving start, end, road turns, and gaps.
  List<RouteVertex> simplify(List<RouteVertex> points) {
    if (points.length <= 2) return List.from(points);
    final effectiveOptions = options.copyWith(
      baseEpsilonMeters: epsilonMeters,
      minTurnAngleDegrees: minTurnAngleDegrees,
    );
    return simplifyHybrid(points, effectiveOptions).simplifiedVertices;
  }

  /// Full 4-stage hybrid route simplification pipeline
  static HybridSimplificationResult simplifyHybrid(
    List<RouteVertex> points, [
    RouteSimplifierOptions? options,
  ]) {
    final opts = options ?? const RouteSimplifierOptions();
    final int n = points.length;

    if (n == 0) {
      return const HybridSimplificationResult(
        simplifiedVertices: [],
        originalIndices: [],
        originalPointCount: 0,
        simplifiedPointCount: 0,
        reductionPercentage: 0.0,
        maxDeviationMeters: 0.0,
        protectedIndices: {},
      );
    }

    if (n <= 2) {
      return HybridSimplificationResult(
        simplifiedVertices: List.from(points),
        originalIndices: List.generate(n, (i) => i),
        originalPointCount: n,
        simplifiedPointCount: n,
        reductionPercentage: 0.0,
        maxDeviationMeters: 0.0,
        protectedIndices: Set.from(List.generate(n, (i) => i)),
      );
    }

    // =========================================================================
    // STAGE C: Turning-Point and Anchor Protection
    // Identify mandatory anchors before simplification:
    // 1. Start and End of the entire journey
    // 2. Gap boundaries (isGap flag or time difference > gapDurationSeconds)
    // 3. Significant heading changes (noise-resistant windowed analysis)
    // 4. Directional reversals and small loops
    // =========================================================================
    final protectedIndices = <int>{0, n - 1};

    // 1. Detect gap boundaries
    for (int i = 0; i < n; i++) {
      if (points[i].isGap) {
        protectedIndices.add(i);
        if (i > 0) protectedIndices.add(i - 1);
      } else if (i > 0) {
        final elapsed = points[i].timestamp.difference(points[i - 1].timestamp).inSeconds.abs();
        if (elapsed >= opts.gapDurationSeconds) {
          protectedIndices.add(i);
          protectedIndices.add(i - 1);
        }
      }
    }

    // 2. Noise-resistant turn and junction detection
    // Uses a multi-point spatial lookback/lookahead to prevent GPS sensor jitter from triggering false turns
    final turnIndices = <int>{};
    for (int i = 1; i < n - 1; i++) {
      if (protectedIndices.contains(i)) continue;

      // Find preceding point at least minTurnSegmentDistanceMeters away (or up to 3 points back)
      int prevIdx = i - 1;
      while (prevIdx > 0 &&
          (i - prevIdx) < 3 &&
          GpsDistanceCalculator.haversineDistanceMeters(
                points[prevIdx].latitude,
                points[prevIdx].longitude,
                points[i].latitude,
                points[i].longitude,
              ) < opts.minTurnSegmentDistanceMeters) {
        prevIdx--;
      }

      // Find succeeding point at least minTurnSegmentDistanceMeters away (or up to 3 points ahead)
      int nextIdx = i + 1;
      while (nextIdx < n - 1 &&
          (nextIdx - i) < 3 &&
          GpsDistanceCalculator.haversineDistanceMeters(
                points[i].latitude,
                points[i].longitude,
                points[nextIdx].latitude,
                points[nextIdx].longitude,
              ) < opts.minTurnSegmentDistanceMeters) {
        nextIdx++;
      }

      final distIn = GpsDistanceCalculator.haversineDistanceMeters(
        points[prevIdx].latitude,
        points[prevIdx].longitude,
        points[i].latitude,
        points[i].longitude,
      );
      final distOut = GpsDistanceCalculator.haversineDistanceMeters(
        points[i].latitude,
        points[i].longitude,
        points[nextIdx].latitude,
        points[nextIdx].longitude,
      );

      // Requires physical movement on both sides to eliminate sensor jitter
      if (distIn >= opts.minTurnSegmentDistanceMeters && distOut >= opts.minTurnSegmentDistanceMeters) {
        final bearing1 = _calculateBearing(
          points[prevIdx].latitude,
          points[prevIdx].longitude,
          points[i].latitude,
          points[i].longitude,
        );
        final bearing2 = _calculateBearing(
          points[i].latitude,
          points[i].longitude,
          points[nextIdx].latitude,
          points[nextIdx].longitude,
        );

        final turnAngle = _angularDifference(bearing1, bearing2);
        if (turnAngle >= opts.minTurnAngleDegrees) {
          protectedIndices.add(i);
          turnIndices.add(i);
        }
      }
    }

    // 3. Loop and reversal protection (preserving routes that retrace paths)
    if (opts.preserveLoops) {
      for (int i = 1; i < n - 1; i++) {
        if (protectedIndices.contains(i)) continue;
        final curr = points[i];
        final prev = points[i - 1];
        final next = points[i + 1];
        final distIn = GpsDistanceCalculator.haversineDistanceMeters(prev.latitude, prev.longitude, curr.latitude, curr.longitude);
        final distOut = GpsDistanceCalculator.haversineDistanceMeters(curr.latitude, curr.longitude, next.latitude, next.longitude);
        if (distIn >= opts.minTurnSegmentDistanceMeters && distOut >= opts.minTurnSegmentDistanceMeters) {
          final inBearing = _calculateBearing(prev.latitude, prev.longitude, curr.latitude, curr.longitude);
          final outBearing = _calculateBearing(curr.latitude, curr.longitude, next.latitude, next.longitude);
          if (_angularDifference(inBearing, outBearing) >= 120.0) {
            protectedIndices.add(i);
            turnIndices.add(i);
          }
        }
      }
    }

    // =========================================================================
    // STAGE A: Radial Distance Pre-filter
    // Filters redundant stationary/near-duplicate coordinates,
    // ensuring protected anchors are NEVER removed.
    // =========================================================================
    final candidateIndices = <int>[0];
    for (int i = 1; i < n - 1; i++) {
      if (protectedIndices.contains(i)) {
        candidateIndices.add(i);
      } else {
        final lastIdx = candidateIndices.last;
        final dist = GpsDistanceCalculator.haversineDistanceMeters(
          points[lastIdx].latitude,
          points[lastIdx].longitude,
          points[i].latitude,
          points[i].longitude,
        );
        if (dist >= opts.radialPreFilterMeters) {
          candidateIndices.add(i);
        }
      }
    }
    candidateIndices.add(n - 1);
    final candidateSet = Set<int>.from(candidateIndices);

    // Set of candidate indices to retain
    final retainedIndicesSet = Set<int>.from(protectedIndices);

    // =========================================================================
    // STAGE B: Adaptive Ramer-Douglas-Peucker (RDP)
    // Runs Douglas-Peucker between adjacent protected anchors.
    // Uses turnEpsilon near curves and straightEpsilon on straight stretches.
    // =========================================================================
    final sortedAnchors = protectedIndices.toList()..sort();

    for (int a = 0; a < sortedAnchors.length - 1; a++) {
      final startIdx = sortedAnchors[a];
      final endIdx = sortedAnchors[a + 1];

      // Check if this segment contains a protected turn or curve
      final isCurvedSegment = turnIndices.contains(startIdx) || turnIndices.contains(endIdx);
      final segmentEpsilon = isCurvedSegment ? opts.turnEpsilonMeters : opts.straightEpsilonMeters;

      _adaptiveRdpRecursive(
        points: points,
        startIdx: startIdx,
        endIdx: endIdx,
        epsilon: segmentEpsilon,
        candidateSet: candidateSet,
        retainedIndices: retainedIndicesSet,
      );
    }

    // =========================================================================
    // STAGE D: Maximum-Deviation Validation
    // Validates simplified segments against all original points.
    // If any original point deviates by > maxAllowedDeviationMeters,
    // restore the worst-violating point and re-validate iteratively.
    // =========================================================================
    double maxDeviationMeasured = 0.0;
    var currentRetainedList = retainedIndicesSet.toList()..sort();

    int maxValidationPasses = 50; // Safety guard against infinite loops
    while (maxValidationPasses-- > 0) {
      double worstDeviation = 0.0;
      int? worstViolatorIndex;

      for (int i = 0; i < currentRetainedList.length - 1; i++) {
        final sIdx = currentRetainedList[i];
        final eIdx = currentRetainedList[i + 1];

        // Evaluate all original points between sIdx and eIdx
        for (int p = sIdx + 1; p < eIdx; p++) {
          final dev = _perpendicularDistanceMeters(
            points[p].latitude,
            points[p].longitude,
            points[sIdx].latitude,
            points[sIdx].longitude,
            points[eIdx].latitude,
            points[eIdx].longitude,
          );

          if (dev > worstDeviation) {
            worstDeviation = dev;
            worstViolatorIndex = p;
          }
        }
      }

      if (worstDeviation > maxDeviationMeasured) {
        maxDeviationMeasured = worstDeviation;
      }

      // If worst deviation exceeds permitted threshold, restore violator
      if (worstDeviation > opts.maxAllowedDeviationMeters && worstViolatorIndex != null) {
        retainedIndicesSet.add(worstViolatorIndex);
        currentRetainedList = retainedIndicesSet.toList()..sort();
      } else {
        break; // Within permitted error bound
      }
    }

    final finalIndices = retainedIndicesSet.toList()..sort();
    final simplifiedVertices = finalIndices.map((idx) => points[idx]).toList();

    final reduction = n > 0 ? ((n - simplifiedVertices.length) / n) * 100.0 : 0.0;

    return HybridSimplificationResult(
      simplifiedVertices: simplifiedVertices,
      originalIndices: finalIndices,
      originalPointCount: n,
      simplifiedPointCount: simplifiedVertices.length,
      reductionPercentage: reduction,
      maxDeviationMeters: maxDeviationMeasured,
      protectedIndices: protectedIndices,
    );
  }

  /// Adaptive Ramer-Douglas-Peucker recursive worker
  static void _adaptiveRdpRecursive({
    required List<RouteVertex> points,
    required int startIdx,
    required int endIdx,
    required double epsilon,
    required Set<int> candidateSet,
    required Set<int> retainedIndices,
  }) {
    if (endIdx <= startIdx + 1) return;

    double maxDistance = 0.0;
    int indexFarthest = startIdx;

    final startPt = points[startIdx];
    final endPt = points[endIdx];

    for (int i = startIdx + 1; i < endIdx; i++) {
      if (!candidateSet.contains(i)) continue;
      final dist = _perpendicularDistanceMeters(
        points[i].latitude,
        points[i].longitude,
        startPt.latitude,
        startPt.longitude,
        endPt.latitude,
        endPt.longitude,
      );

      if (dist > maxDistance) {
        maxDistance = dist;
        indexFarthest = i;
      }
    }

    if (maxDistance > epsilon) {
      retainedIndices.add(indexFarthest);
      _adaptiveRdpRecursive(
        points: points,
        startIdx: startIdx,
        endIdx: indexFarthest,
        epsilon: epsilon,
        candidateSet: candidateSet,
        retainedIndices: retainedIndices,
      );
      _adaptiveRdpRecursive(
        points: points,
        startIdx: indexFarthest,
        endIdx: endIdx,
        epsilon: epsilon,
        candidateSet: candidateSet,
        retainedIndices: retainedIndices,
      );
    }
  }

  /// Convenience method to simplify a list of [LatLng] coordinates
  static HybridSimplificationResult simplifyLatLngs(
    List<LatLng> latLngs, {
    RouteSimplifierOptions? options,
    List<bool>? isGapList,
    List<DateTime>? timestamps,
  }) {
    final now = DateTime.now().toUtc();
    final vertices = List.generate(latLngs.length, (i) {
      return RouteVertex(
        latitude: latLngs[i].latitude,
        longitude: latLngs[i].longitude,
        timestamp: timestamps != null && i < timestamps.length
            ? timestamps[i]
            : now.add(Duration(seconds: i * 5)),
        accuracyMeters: 5.0,
        isGap: isGapList != null && i < isGapList.length ? isGapList[i] : false,
      );
    });

    return simplifyHybrid(vertices, options);
  }

  /// Convenience method to simplify raw database coordinate maps
  static HybridSimplificationResult simplifyRawMaps(
    List<Map<String, dynamic>> rawMaps, [
    RouteSimplifierOptions? options,
  ]) {
    final vertices = rawMaps.map((m) => RouteVertex.fromMap(m)).toList();
    return simplifyHybrid(vertices, options);
  }

  /// Returns directly simplified display [LatLng] coordinates from raw database maps
  static List<LatLng> getSimplifiedDisplayPoints(
    List<Map<String, dynamic>> rawMaps, [
    RouteSimplifierOptions? options,
  ]) {
    if (rawMaps.isEmpty) return [];
    return simplifyRawMaps(rawMaps, options).toLatLngList();
  }

  /// Calculates perpendicular cross-track distance from point P to segment AB in meters
  static double _perpendicularDistanceMeters(
    double pLat,
    double pLng,
    double aLat,
    double aLng,
    double bLat,
    double bLng,
  ) {
    final distAB = GpsDistanceCalculator.haversineDistanceMeters(aLat, aLng, bLat, bLng);
    if (distAB < 0.2) {
      return GpsDistanceCalculator.haversineDistanceMeters(pLat, pLng, aLat, aLng);
    }

    final distAP = GpsDistanceCalculator.haversineDistanceMeters(aLat, aLng, pLat, pLng);
    final distBP = GpsDistanceCalculator.haversineDistanceMeters(bLat, bLng, pLat, pLng);

    // Semiperimeter of triangle ABP
    final s = (distAB + distAP + distBP) / 2.0;
    final areaSq = s * (s - distAB) * (s - distAP) * (s - distBP);

    if (areaSq <= 0.0) return 0.0;

    // Height = 2 * Area / Base
    return (2.0 * math.sqrt(areaSq)) / distAB;
  }

  /// Calculates initial bearing in degrees from point 1 to point 2
  static double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final dLon = _degToRad(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(_degToRad(lat2));
    final x = math.cos(_degToRad(lat1)) * math.sin(_degToRad(lat2)) -
        math.sin(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.cos(dLon);

    final brng = math.atan2(y, x);
    return (_radToDeg(brng) + 360.0) % 360.0;
  }

  static double _angularDifference(double angle1, double angle2) {
    double diff = (angle1 - angle2).abs() % 360.0;
    if (diff > 180.0) diff = 360.0 - diff;
    return diff;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);

  /// Compact JSON serialization of route vertices
  static String encodeVertices(List<RouteVertex> vertices) {
    return jsonEncode(vertices.map((v) => v.toCompactList()).toList());
  }

  /// Deserialization of compact JSON route vertices
  static List<RouteVertex> decodeVertices(String jsonStr) {
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((item) => RouteVertex.fromCompactList(item as List<dynamic>)).toList();
  }

  /// Static convenience method for RDP simplification with optional epsilon tolerance
  static List<RouteVertex> simplifyVertices(
    List<RouteVertex> points, {
    double epsilon = 3.5,
    double minTurnAngleDegrees = 12.0,
  }) {
    final simplifier = RouteSimplifier(
      epsilonMeters: epsilon,
      minTurnAngleDegrees: minTurnAngleDegrees,
    );
    return simplifier.simplify(points);
  }

  /// Static convenience method for RDP simplification with optional epsilon tolerance
  static List<RouteVertex> simplifyRoute(
    List<RouteVertex> points, {
    double epsilon = 3.5,
    double minTurnAngleDegrees = 12.0,
  }) {
    return simplifyVertices(points, epsilon: epsilon, minTurnAngleDegrees: minTurnAngleDegrees);
  }
}
