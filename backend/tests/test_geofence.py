import unittest
import sys
import os

# Add backend root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from app.services.geofence_service import calculate_haversine_distance, validate_geofence

class TestGeofence(unittest.TestCase):
    def test_haversine_distance_same_point(self):
        dist = calculate_haversine_distance(16.1234567, 74.1234567, 16.1234567, 74.1234567)
        self.assertEqual(round(dist, 2), 0.0)

    def test_haversine_distance_known_points(self):
        # London (51.5074, -0.1278) to Paris (48.8566, 2.3522) ~ 343 km
        dist = calculate_haversine_distance(51.5074, -0.1278, 48.8566, 2.3522)
        self.assertTrue(340000 < dist < 346000)

    def test_geofence_inside_radius(self):
        # Assigned: 16.1234567, 74.1234567, Radius 100m
        # Slightly offset point (~30m away)
        cur_lat = 16.1237000
        cur_lon = 74.1234567
        is_inside, dist = validate_geofence(cur_lat, cur_lon, 16.1234567, 74.1234567, 100.0)
        self.assertTrue(is_inside)
        self.assertTrue(dist < 100.0)

    def test_geofence_outside_radius_hard_gate(self):
        # Assigned: 16.1234567, 74.1234567, Radius 100m
        # Farther point (~500m away)
        cur_lat = 16.1280000
        cur_lon = 74.1234567
        is_inside, dist = validate_geofence(cur_lat, cur_lon, 16.1234567, 74.1234567, 100.0)
        self.assertFalse(is_inside)
        self.assertTrue(dist > 100.0)

if __name__ == "__main__":
    unittest.main()
