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

  // Maximum physically plausible speed between fixes before flagging jump (45 m/s ≈ 162 km/h)
  final double maxImpliedSpeedMps;

  // Maximum elapsed seconds without fixes before treating subsequent fix as a discontinuous gap (15 min)
  final int gapDurationSeconds;

  LatLng? _distanceReferencePosition;
  DateTime? _lastAcceptedTimestamp;
  LatLng? get lastReferencePosition => _distanceReferencePosition;
  DateTime? get lastAcceptedTimestamp => _lastAcceptedTimestamp;

  GpsDistanceCalculator({
    this.maxAllowedAccuracyMeters = 50.0,
    this.minMovementThresholdMeters = 15.0,
    this.maxImpliedSpeedMps = 45.0,
    this.gapDurationSeconds = 900,
  });

  /// Reset or restore reference state upon session start or recovery
  void restoreReference(LatLng? position, DateTime? timestamp) {
    _distanceReferencePosition = position;
    _lastAcceptedTimestamp = timestamp;
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
  /// Small movements (< minMovementThresholdMeters) are retained in reference so they accumulate
  /// toward total distance rather than being lost.
  GpsFilterResult processFix({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime timestamp,
    bool isResumedAfterPause = false,
  }) {
    if (!isValidCoordinate(latitude, longitude)) {
      return GpsFilterResult.rejected('Invalid coordinate bounds ($latitude, $longitude)');
    }

    if (accuracyMeters > maxAllowedAccuracyMeters) {
      return GpsFilterResult.rejected(
        'Accuracy too low ($accuracyMeters m > $maxAllowedAccuracyMeters m)',
      );
    }

    final currentCoord = LatLng(latitude, longitude);

    // Initial fix for a tracking journey
    if (_distanceReferencePosition == null) {
      _distanceReferencePosition = currentCoord;
      _lastAcceptedTimestamp = timestamp;
      return GpsFilterResult.acceptedNoDistance;
    }

    final displacementFromRef = haversineDistanceMeters(
      _distanceReferencePosition!.latitude,
      _distanceReferencePosition!.longitude,
      currentCoord.latitude,
      currentCoord.longitude,
    );

    int elapsedSeconds = 0;
    if (_lastAcceptedTimestamp != null) {
      elapsedSeconds = timestamp.difference(_lastAcceptedTimestamp!).inSeconds.abs();
    }

    // Gap detection: long interruption (> 15 mins) or resumed after user pause
    if (isResumedAfterPause || elapsedSeconds > gapDurationSeconds) {
      _distanceReferencePosition = currentCoord;
      _lastAcceptedTimestamp = timestamp;
      return GpsFilterResult.acceptedWithDistance(0.0, isGap: true);
    }

    // Teleportation / GPS glitch detection
    if (elapsedSeconds > 0 && displacementFromRef > 50.0) {
      final impliedSpeed = displacementFromRef / elapsedSeconds;
      if (impliedSpeed > maxImpliedSpeedMps) {
        return GpsFilterResult.rejected(
          'Implied speed excessive ($impliedSpeed m/s > $maxImpliedSpeedMps m/s)',
        );
      }
    }

    // Movement threshold check:
    // If movement from the reference position reaches the threshold, commit distance
    // and advance the reference position.
    if (displacementFromRef >= minMovementThresholdMeters) {
      _distanceReferencePosition = currentCoord;
      _lastAcceptedTimestamp = timestamp;
      return GpsFilterResult.acceptedWithDistance(displacementFromRef);
    }

    // Small movement (< 15m): keep the existing reference position so subsequent
    // steps continue accumulating towards the threshold.
    _lastAcceptedTimestamp = timestamp;
    return GpsFilterResult.acceptedNoDistance;
  }
}
