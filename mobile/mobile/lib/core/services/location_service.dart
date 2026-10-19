import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../../models/coordinate_point_model.dart';

enum LocationStatusType {
  granted,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
}

class LocationService {
  static final KalmanLatLongFilter _kalmanFilter = KalmanLatLongFilter();

  static Future<LocationStatusType> checkDetailedStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationStatusType.serviceDisabled;
    }

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      return LocationStatusType.permissionDenied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationStatusType.permissionDeniedForever;
    }

    return LocationStatusType.granted;
  }

  static Future<bool> handlePermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  static Future<Position?> getCurrentPosition() async {
    final hasPermission = await handlePermission();
    if (!hasPermission) return null;

    try {
      // 1. Try High Accuracy (GNSS/GPS Satellites) with 8s timeout
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } catch (_) {
      try {
        // 2. Fallback to Medium Accuracy (Wi-Fi / Cell tower triangulation - works indoors!)
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 6),
        );
      } catch (_) {
        // 3. Fallback to Last Known Cached Position
        return await Geolocator.getLastKnownPosition();
      }
    }
  }

  /// Captures position and wraps in a CoordinatePoint preserving complete decimal precision.
  static Future<CoordinatePoint?> getCurrentCoordinatePoint({bool applyKalmanFilter = false}) async {
    final pos = await getCurrentPosition();
    if (pos == null) return null;

    final rawPoint = CoordinatePoint(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      speed: pos.speed,
      timestamp: pos.timestamp,
    );

    if (applyKalmanFilter) {
      return _kalmanFilter.process(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: pos.accuracy,
        timestampMs: pos.timestamp.millisecondsSinceEpoch,
        altitude: pos.altitude,
        speed: pos.speed,
      );
    }

    return rawPoint;
  }

  /// Haversine spherical distance calculation in meters using full-precision coordinates
  static double calculateDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000.0;
    final double phi1 = lat1 * pi / 180.0;
    final double phi2 = lat2 * pi / 180.0;
    final double deltaPhi = (lat2 - lat1) * pi / 180.0;
    final double deltaLambda = (lon2 - lon1) * pi / 180.0;

    final double a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
        cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// Verifies if a given point is within the geofence radius without reducing coordinate precision
  static bool isWithinGeofence({
    required double currentLat,
    required double currentLon,
    required double centerLat,
    required double centerLon,
    required double radiusMeters,
  }) {
    final distance = calculateDistanceMeters(currentLat, currentLon, centerLat, centerLon);
    return distance <= radiusMeters;
  }
}

