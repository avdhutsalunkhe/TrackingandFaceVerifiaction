import math
from typing import Tuple, Optional

EARTH_RADIUS_METERS = 6371000.0

def is_valid_coordinate(lat: Optional[float], lon: Optional[float]) -> bool:
    """
    Validates latitude and longitude ranges.
    Returns False if either coordinate is None, NaN, out of range,
    or matches the known sentinel pair (0.0, 0.0) representing missing GPS fix (Null Island).
    Note: Individual 0.0 coordinates (e.g., equator with non-zero lon, or prime meridian with non-zero lat)
    are mathematically valid and allowed. Only the sentinel pair (0.0, 0.0) is rejected as uninitialized.
    """
    if lat is None or lon is None:
        return False
    try:
        f_lat = float(lat)
        f_lon = float(lon)
    except (ValueError, TypeError):
        return False

    if math.isnan(f_lat) or math.isnan(f_lon):
        return False

    if not (-90.0 <= f_lat <= 90.0 and -180.0 <= f_lon <= 180.0):
        return False

    # Sentinel detection: exactly 0.0, 0.0 represents uninitialized/default GPS coordinates
    if abs(f_lat) < 1e-7 and abs(f_lon) < 1e-7:
        return False

    return True

def calculate_haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate the great-circle distance between two points on the Earth
    using the Haversine formula on a spherical earth model.
    Returns distance in meters.
    """
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (math.sin(delta_phi / 2.0) ** 2 +
         math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2)
    
    # Avoid numerical instability with float precision
    a = min(1.0, max(0.0, a))
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))

    distance = EARTH_RADIUS_METERS * c
    return float(distance)

def validate_geofence(
    current_lat: Optional[float],
    current_lon: Optional[float],
    assigned_lat: float,
    assigned_lon: float,
    radius_meters: float
) -> Tuple[bool, Optional[float]]:
    """
    Authoritative server-side geofence boundary validation.
    Returns: (is_inside: bool, distance_meters: Optional[float])
    If coordinates are missing, out-of-range, or sentinel (0.0, 0.0), returns (False, None).
    """
    if not is_valid_coordinate(current_lat, current_lon) or not is_valid_coordinate(assigned_lat, assigned_lon):
        return False, None

    distance = calculate_haversine_distance(
        float(current_lat), float(current_lon),
        float(assigned_lat), float(assigned_lon)
    )
    is_inside = distance <= radius_meters
    return is_inside, distance
