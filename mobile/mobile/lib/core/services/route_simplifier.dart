import 'dart:convert';
import 'dart:math' as math;
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
}

/// Production implementation of Ramer-Douglas-Peucker (RDP) algorithm with turn and gap protection.
/// Minimizes permanent storage growth by retaining key geometry while omitting redundant linear points.
class RouteSimplifier {
  /// Default perpendicular distance tolerance (in meters).
  /// 3.5m retains high-resolution curvature along winding roads while filtering redundant collinear points.
  final double epsilonMeters;

  /// Minimum angular direction change (in degrees) to force vertex retention (protects street turns).
  final double minTurnAngleDegrees;

  const RouteSimplifier({
    this.epsilonMeters = 3.5,
    this.minTurnAngleDegrees = 12.0,
  });

  /// Simplifies a candidate list of vertices, preserving start, end, road turns, and gaps.
  List<RouteVertex> simplify(List<RouteVertex> points) {
    if (points.length <= 2) return List.from(points);

    // 1. Mark vertices that MUST be preserved (mandatory anchors)
    final preservedIndices = <int>{0, points.length - 1};

    // Mark gap points (pause/resume boundaries)
    for (int i = 0; i < points.length; i++) {
      if (points[i].isGap) {
        preservedIndices.add(i);
        if (i > 0) preservedIndices.add(i - 1);
      }
    }

    // Mark significant direction changes (protect turns at street corners)
    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      final bearing1 = _calculateBearing(prev.latitude, prev.longitude, curr.latitude, curr.longitude);
      final bearing2 = _calculateBearing(curr.latitude, curr.longitude, next.latitude, next.longitude);

      final angleDiff = _angularDifference(bearing1, bearing2);
      if (angleDiff >= minTurnAngleDegrees) {
        preservedIndices.add(i);
      }
    }

    // 2. Run Douglas-Peucker algorithm between adjacent mandatory anchors
    final sortedAnchors = preservedIndices.toList()..sort();
    final resultIndices = <int>{};

    for (int a = 0; a < sortedAnchors.length - 1; a++) {
      final startIdx = sortedAnchors[a];
      final endIdx = sortedAnchors[a + 1];
      _douglasPeuckerRecursive(points, startIdx, endIdx, resultIndices);
    }

    resultIndices.addAll(sortedAnchors);
    final finalSorted = resultIndices.toList()..sort();

    return finalSorted.map((idx) => points[idx]).toList();
  }

  void _douglasPeuckerRecursive(
    List<RouteVertex> points,
    int startIdx,
    int endIdx,
    Set<int> retainedIndices,
  ) {
    if (endIdx <= startIdx + 1) return;

    double maxDistance = 0.0;
    int indexFarthest = startIdx;

    final startPt = points[startIdx];
    final endPt = points[endIdx];

    for (int i = startIdx + 1; i < endIdx; i++) {
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

    if (maxDistance > epsilonMeters) {
      retainedIndices.add(indexFarthest);
      _douglasPeuckerRecursive(points, startIdx, indexFarthest, retainedIndices);
      _douglasPeuckerRecursive(points, indexFarthest, endIdx, retainedIndices);
    }
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
    if (distAB < 1.0) {
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
