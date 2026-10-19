import 'dart:math';

/// CoordinatePoint model representing complete, unrounded GPS coordinates.
/// Strictly maintains full captured precision everywhere in the Flutter application.
class CoordinatePoint {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final double? altitude;
  final double? speed;
  final DateTime timestamp;

  const CoordinatePoint({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.altitude,
    this.speed,
    required this.timestamp,
  });

  /// Factory from raw captured position values (e.g. from Geolocator Position)
  factory CoordinatePoint.fromValues({
    required double latitude,
    required double longitude,
    double? accuracy,
    double? altitude,
    double? speed,
    DateTime? timestamp,
  }) {
    return CoordinatePoint(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      speed: speed,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  /// Converts to JSON map preserving complete double precision
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (speed != null) 'speed': speed,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Deserializes from JSON map preserving complete numeric precision
  factory CoordinatePoint.fromJson(Map<String, dynamic> json) {
    return CoordinatePoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }

  /// Full-precision coordinate string (e.g. "18.98273456, 73.12345678")
  @override
  String toString() => '$latitude, $longitude';
}

/// 2D Kalman filter for GPS coordinates that maintains full double precision
/// without rounding, truncation, or shortening of coordinates.
class KalmanLatLongFilter {
  final double qMetersPerSecond; // Process noise
  double? _lat;
  double? _lon;
  double _variance = -1.0; // Error covariance P
  int _timestampMs = 0;

  KalmanLatLongFilter({this.qMetersPerSecond = 3.0});

  /// Resets or explicitly sets the filter state
  void reset([double? lat, double? lon, double? accuracy, int? timestampMs]) {
    _lat = lat;
    _lon = lon;
    _variance = (accuracy != null && accuracy > 0) ? accuracy * accuracy : -1.0;
    _timestampMs = timestampMs ?? 0;
  }

  /// Current filtered latitude, or null if uninitialized
  double? get currentLatitude => _lat;

  /// Current filtered longitude, or null if uninitialized
  double? get currentLongitude => _lon;

  /// Current estimated accuracy in meters
  double? get currentAccuracy => _variance > 0 ? sqrt(_variance) : null;

  /// Processes a newly captured GPS coordinate reading and returns the filtered CoordinatePoint
  /// with complete double-precision coordinates maintained throughout calculation.
  CoordinatePoint process({
    required double latitude,
    required double longitude,
    required double accuracy,
    required int timestampMs,
    double? altitude,
    double? speed,
  }) {
    final double safeAccuracy = accuracy < 1.0 ? 1.0 : accuracy;

    if (_variance < 0 || _lat == null || _lon == null) {
      // First measurement initialization
      _lat = latitude;
      _lon = longitude;
      _variance = safeAccuracy * safeAccuracy;
      _timestampMs = timestampMs;
    } else {
      final double dtSeconds = max(0.0, (timestampMs - _timestampMs) / 1000.0);
      if (dtSeconds > 0) {
        _variance += dtSeconds * qMetersPerSecond * qMetersPerSecond;
        _timestampMs = timestampMs;
      }

      // Kalman Gain K = P / (P + R)
      final double measurementVariance = safeAccuracy * safeAccuracy;
      final double kalmanGain = _variance / (_variance + measurementVariance);

      // State update with full double precision
      _lat = _lat! + kalmanGain * (latitude - _lat!);
      _lon = _lon! + kalmanGain * (longitude - _lon!);
      _variance = (1.0 - kalmanGain) * _variance;
    }

    return CoordinatePoint(
      latitude: _lat!,
      longitude: _lon!,
      accuracy: sqrt(_variance),
      altitude: altitude,
      speed: speed,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
  }
}
