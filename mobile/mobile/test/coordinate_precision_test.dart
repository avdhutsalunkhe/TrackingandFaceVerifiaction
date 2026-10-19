import 'package:flutter_test/flutter_test.dart';
import 'package:fieldstaff_attendance/models/coordinate_point_model.dart';
import 'package:fieldstaff_attendance/core/services/location_service.dart';

void main() {
  group('Full GPS Coordinate Precision Tests', () {
    test('CoordinatePoint retains exact captured decimal values', () {
      const double originalLat = 18.98273456;
      const double originalLon = 73.12345678;

      final point = CoordinatePoint(
        latitude: originalLat,
        longitude: originalLon,
        accuracy: 4.5,
        timestamp: DateTime(2026, 9, 25, 10, 0, 0),
      );

      // Verify exact precision without truncation or rounding
      expect(point.latitude, equals(18.98273456));
      expect(point.longitude, equals(73.12345678));
      expect(point.toString(), equals('18.98273456, 73.12345678'));

      // Test JSON round-trip
      final json = point.toJson();
      expect(json['latitude'], equals(18.98273456));
      expect(json['longitude'], equals(73.12345678));

      final reconstructed = CoordinatePoint.fromJson(json);
      expect(reconstructed.latitude, equals(18.98273456));
      expect(reconstructed.longitude, equals(73.12345678));
    });

    test('KalmanLatLongFilter preserves full double precision during filtering', () {
      final filter = KalmanLatLongFilter();

      // Process initial reading
      final pt1 = filter.process(
        latitude: 18.98273456,
        longitude: 73.12345678,
        accuracy: 5.0,
        timestampMs: 1000,
      );

      expect(pt1.latitude, equals(18.98273456));
      expect(pt1.longitude, equals(73.12345678));

      // Process second reading
      final pt2 = filter.process(
        latitude: 18.98273499,
        longitude: 73.12345699,
        accuracy: 3.0,
        timestampMs: 2000,
      );

      // Filtered coordinates maintain full double precision
      expect(pt2.latitude.toString().length, greaterThanOrEqualTo(10));
      expect(pt2.longitude.toString().length, greaterThanOrEqualTo(10));
    });

    test('Haversine distance calculation operates on full precision coordinates', () {
      const double lat1 = 18.98273456;
      const double lon1 = 73.12345678;
      const double lat2 = 18.98274567; // ~1.2m offset
      const double lon2 = 73.12346789;

      final distance = LocationService.calculateDistanceMeters(lat1, lon1, lat2, lon2);
      expect(distance, greaterThan(0.0));
      expect(distance, lessThan(5.0));

      final isInside = LocationService.isWithinGeofence(
        currentLat: lat1,
        currentLon: lon1,
        centerLat: lat2,
        centerLon: lon2,
        radiusMeters: 10.0,
      );
      expect(isInside, isTrue);
    });
  });
}
