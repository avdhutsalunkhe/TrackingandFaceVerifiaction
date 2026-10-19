import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class GpsFilterResult {
  final bool isAccepted;
  final double distanceAddedMeters;
  final bool isGap;
  final String? rejectionReason;

  const GpsFilterResult({
    required this.isAccepted,
    required this.distanceAddedMeters,
    this.isGap = false,
    this.rejectionReason,
  });

  static const GpsFilterResult acceptedNoDistance = GpsFilterResult(
    isAccepted: true,
    distanceAddedMeters: 0.0,
    isGap: false,
  );

  static GpsFilterResult acceptedWithDistance(double dist, {bool isGap = false}) =>
      GpsFilterResult(
        isAccepted: true,
        distanceAddedMeters: dist,
        isGap: isGap,
      );

  static GpsFilterResult rejected(String reason) => GpsFilterResult(
        isAccepted: false,
        distanceAddedMeters: 0.0,
        rejectionReason: reason,
      );
}

class GpsDistanceCalculator {
  // Mean earth radius in meters (WGS-84 / IUGG standard)
  static const double earthRadiusMeters = 6371000.0;

  // Maximum allowed horizontal accuracy before fix is rejected (meters)
  final double maxAllowedAccuracyMeters;

  // Minimum displacement required from reference position before distance is committed (meters)
  final double minMovementThresholdMeters;

  // Maximum physically plausible speed between consecutive fixes before flagging jump (~198 km/h)
  final double maxImpliedSpeedMps;

  // Maximum elapsed seconds without fixes before treating subsequent fix as a discontinuous gap (15 min)
  final int gapDurationSeconds;

  // Dead-reckoning reference position for accumulating distance without noise drift
  LatLng? _distanceReferencePosition;
  DateTime? _lastReferenceTimestamp;

  // Immediately preceding consecutive accepted GPS fix for accurate point-to-point speed calculation
  LatLng? _lastFixPosition;
  DateTime? _lastFixTimestamp;

  // Last retained candidate vertex position & bearing for adaptive vertex filtering
  LatLng? _lastCandidateVertexPosition;
  DateTime? _lastCandidateVertexTimestamp;
  double? _lastCandidateBearing;

  LatLng? get lastReferencePosition => _distanceReferencePosition;
  DateTime? get lastReferenceTimestamp => _lastReferenceTimestamp;
  LatLng? get lastFixPosition => _lastFixPosition;
  DateTime? get lastAcceptedTimestamp => _lastFixTimestamp ?? _lastReferenceTimestamp;

  GpsDistanceCalculator({
    this.maxAllowedAccuracyMeters = 65.0,
    this.minMovementThresholdMeters = 8.0,
    this.maxImpliedSpeedMps = 55.0, // 55 m/s ≈ 198 km/h covers Indian highways & expressways
    this.gapDurationSeconds = 900,
  });

  /// Reset or restore reference state upon session start or recovery
  void restoreReference(LatLng? position, DateTime? timestamp) {
    _distanceReferencePosition = position;
    _lastReferenceTimestamp = timestamp;
    _lastFixPosition = position;
    _lastFixTimestamp = timestamp;
    _lastCandidateVertexPosition = position;
    _lastCandidateVertexTimestamp = timestamp;
  }

  /// Evaluates whether an accepted observation should be retained as a candidate route vertex.
  /// Suppresses stationary jitter while preserving road turns, distance milestones, and boundaries.
  bool shouldRetainCandidateVertex({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double? speedMps,
    double? bearingDegrees,
    bool isGap = false,
  }) {
    if (isGap) {
      _lastCandidateVertexPosition = LatLng(latitude, longitude);
      _lastCandidateVertexTimestamp = timestamp;
      _lastCandidateBearing = bearingDegrees;
      return true;
    }

    if (_lastCandidateVertexPosition == null || _lastCandidateVertexTimestamp == null) {
      _lastCandidateVertexPosition = LatLng(latitude, longitude);
      _lastCandidateVertexTimestamp = timestamp;
      _lastCandidateBearing = bearingDegrees;
      return true;
    }

    final displacement = haversineDistanceMeters(
      _lastCandidateVertexPosition!.latitude,
      _lastCandidateVertexPosition!.longitude,
      latitude,
      longitude,
    );

    final elapsedSeconds = timestamp.difference(_lastCandidateVertexTimestamp!).inSeconds.abs();

    // Stationary suppression: speed < 0.4 m/s and movement < 4m (suppresses stationary GPS drift)
    final isStationary = (speedMps != null && speedMps < 0.4 && displacement < 4.0) || (displacement < 2.5);
    if (isStationary) {
      // Retain at most 1 stationary checkpoint every 120 seconds to represent dwell time without inflating storage
      if (elapsedSeconds >= 120) {
        _lastCandidateVertexPosition = LatLng(latitude, longitude);
        _lastCandidateVertexTimestamp = timestamp;
        return true;
      }
      return false;
    }

    // Significant turn detection (direction change >= 12 degrees with some movement)
    if (_lastCandidateBearing != null && bearingDegrees != null) {
      double angleDiff = (bearingDegrees - _lastCandidateBearing!).abs() % 360.0;
      if (angleDiff > 180.0) angleDiff = 360.0 - angleDiff;
      if (angleDiff >= 12.0 && displacement >= 4.0) {
        _lastCandidateVertexPosition = LatLng(latitude, longitude);
        _lastCandidateVertexTimestamp = timestamp;
        _lastCandidateBearing = bearingDegrees;
        return true;
      }
    }

    // Movement displacement threshold (8 meters - captures multiple points along journey)
    if (displacement >= 8.0) {
      _lastCandidateVertexPosition = LatLng(latitude, longitude);
      _lastCandidateVertexTimestamp = timestamp;
      _lastCandidateBearing = bearingDegrees;
      return true;
    }

    // Time heartbeat (30 seconds while moving)
    if (elapsedSeconds >= 30 && displacement >= 4.0) {
      _lastCandidateVertexPosition = LatLng(latitude, longitude);
      _lastCandidateVertexTimestamp = timestamp;
      _lastCandidateBearing = bearingDegrees;
      return true;
    }

    return false;
  }

  /// Calculates exact great-circle distance between two coordinates using the Haversine formula
  static double haversineDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    if (lat1 == lat2 && lon1 == lon2) return 0.0;

    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final lat1Rad = _degToRad(lat1);
    final lat2Rad = _degToRad(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) *
            math.sin(dLon / 2) *
            math.cos(lat1Rad) *
            math.cos(lat2Rad);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  /// Validates geographical bounds of coordinates
  static bool isValidCoordinate(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    if (lat.isNaN || lon.isNaN || lat.isInfinite || lon.isInfinite) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lon < -180.0 || lon > 180.0) return false;
    // Sentinel detection: Null Island
    if (lat.abs() < 1e-6 && lon.abs() < 1e-6) return false;
    return true;
  }

  /// Evaluates an incoming GPS fix against accuracy, drift, speed, and gap rules.
  /// Fixes are accepted and stored as valid route observations.
  /// Distance is accumulated cleanly without noise drift or false speed rejections.
  GpsFilterResult processFix({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime timestamp,
    double? speedMps,
    bool isResumedAfterPause = false,
  }) {
    // Stage 1: Boundary & Sentinel Check (NaN, Infinite, out-of-bounds, Null Island)
    if (!isValidCoordinate(latitude, longitude)) {
      return GpsFilterResult.rejected('Invalid coordinate bounds ($latitude, $longitude)');
    }

    // Stage 2: Accuracy Threshold Gate (Discard cell-tower jumps > 65m)
    if (accuracyMeters > maxAllowedAccuracyMeters) {
      return GpsFilterResult.rejected(
        'Accuracy too low (${accuracyMeters.toStringAsFixed(1)}m > ${maxAllowedAccuracyMeters.toStringAsFixed(1)}m)',
      );
    }

    final currentCoord = LatLng(latitude, longitude);

    // Initial fix for a tracking journey
    if (_lastFixPosition == null || _distanceReferencePosition == null) {
      _distanceReferencePosition = currentCoord;
      _lastReferenceTimestamp = timestamp;
      _lastFixPosition = currentCoord;
      _lastFixTimestamp = timestamp;
      return GpsFilterResult.acceptedNoDistance;
    }

    // Measure delta from immediately preceding consecutive fix
    final stepDisplacement = haversineDistanceMeters(
      _lastFixPosition!.latitude,
      _lastFixPosition!.longitude,
      currentCoord.latitude,
      currentCoord.longitude,
    );

    final elapsedMs = timestamp.difference(_lastFixTimestamp!).inMilliseconds.abs();
    final elapsedSeconds = elapsedMs / 1000.0;

    // Stage 3: Discontinuous Gap Detection (> 15 mins or explicit pause resumption)
    if (isResumedAfterPause || elapsedSeconds > gapDurationSeconds) {
      _distanceReferencePosition = currentCoord;
      _lastReferenceTimestamp = timestamp;
      _lastFixPosition = currentCoord;
      _lastFixTimestamp = timestamp;
      return GpsFilterResult.acceptedWithDistance(0.0, isGap: true);
    }

    // Stage 4: Teleportation & Glitch Detection (Implied Speed Check: > 55 m/s ≈ 198 km/h)
    if (elapsedSeconds > 0.5 && stepDisplacement > 40.0) {
      final impliedSpeed = stepDisplacement / elapsedSeconds;
      if (impliedSpeed > maxImpliedSpeedMps) {
        return GpsFilterResult.rejected(
          'Implied speed excessive (${impliedSpeed.toStringAsFixed(1)} m/s > $maxImpliedSpeedMps m/s for ${stepDisplacement.toStringAsFixed(1)}m in ${elapsedSeconds.toStringAsFixed(1)}s)',
        );
      }
    }

    // Update consecutive fix tracker for next fix's speed check
    _lastFixPosition = currentCoord;
    _lastFixTimestamp = timestamp;

    // Stage 5: Stationary Drift Suppression (Dead-Reckoning Threshold)
    final displacementFromRef = haversineDistanceMeters(
      _distanceReferencePosition!.latitude,
      _distanceReferencePosition!.longitude,
      currentCoord.latitude,
      currentCoord.longitude,
    );

    // Suppress stationary wander when speed < 0.4 m/s and displacement < 4.0m
    if (speedMps != null && speedMps < 0.4 && displacementFromRef < 4.0) {
      return GpsFilterResult.acceptedNoDistance;
    }

    // Enforce minimum movement threshold of 8 meters before distance is committed
    if (displacementFromRef >= minMovementThresholdMeters) {
      _distanceReferencePosition = currentCoord;
      _lastReferenceTimestamp = timestamp;
      return GpsFilterResult.acceptedWithDistance(displacementFromRef);
    }

    // Sub-threshold movement (< minMovementThresholdMeters):
    // Accepted as a valid route point so high-fidelity trajectory is maintained,
    // but distance accumulation waits until movement crosses the threshold to avoid stationary jitter.
    return GpsFilterResult.acceptedNoDistance;
  }

  /// Static helper evaluating candidate vertex retention against stationary, turn, and heartbeat criteria
  static VertexRetentionDecision evaluateVertex({
    required double candLat,
    required double candLng,
    required DateTime candTimestamp,
    double? candSpeedMps,
    double? candBearingDegrees,
    required double lastAcceptedLat,
    required double lastAcceptedLng,
    required DateTime lastAcceptedTime,
    double? lastAcceptedBearing,
  }) {
    final displacement = haversineDistanceMeters(lastAcceptedLat, lastAcceptedLng, candLat, candLng);
    final elapsedSeconds = candTimestamp.difference(lastAcceptedTime).inSeconds.abs();

    final isStationary = (candSpeedMps != null && candSpeedMps < 0.4 && displacement < 4.0) || (displacement < 2.5);
    if (isStationary) {
      if (elapsedSeconds >= 120) {
        return const VertexRetentionDecision(true, 'Heartbeat checkpoint (>=120s dwell)');
      }
      return const VertexRetentionDecision(false, 'Stationary suppression (<4m / <0.4m/s)');
    }

    if (lastAcceptedBearing != null && candBearingDegrees != null) {
      double angleDiff = (candBearingDegrees - lastAcceptedBearing).abs() % 360.0;
      if (angleDiff > 180.0) angleDiff = 360.0 - angleDiff;
      if (angleDiff >= 12.0 && displacement >= 4.0) {
        return VertexRetentionDecision(true, 'Turn detected (${angleDiff.toStringAsFixed(1)} deg >= 12 deg)');
      }
    }

    if (displacement >= 8.0) {
      return VertexRetentionDecision(true, 'Movement threshold (${displacement.toStringAsFixed(1)}m >= 8m)');
    }

    return const VertexRetentionDecision(false, 'Sub-threshold movement');
  }
}

class VertexRetentionDecision {
  final bool shouldRetain;
  final String reason;
  const VertexRetentionDecision(this.shouldRetain, this.reason);
}
