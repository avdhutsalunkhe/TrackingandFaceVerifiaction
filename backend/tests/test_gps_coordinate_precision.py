import pytest
from decimal import Decimal
from app.schemas.coordinate import CoordinatePoint
from app.models.geofence import Geofence
from app.models.attendance import Attendance, AttendanceAttempt
from app.models.attendance_request import AttendanceRequest

def test_coordinate_point_schema_precision():
    """Verify CoordinatePoint schema retains full decimal precision."""
    lat = 18.52043033
    lon = 73.85674377
    point = CoordinatePoint(latitude=lat, longitude=lon)

    assert point.latitude == 18.52043033
    assert point.longitude == 73.85674377
    assert point.to_coordinates_tuple() == (18.52043033, 73.85674377)
    assert str(point) == "18.52043033, 73.85674377"

def test_models_decimal_precision_column_types():
    """Verify ORM models use Numeric(11, 8) columns."""
    assert Geofence.latitude.property.columns[0].type.precision == 11
    assert Geofence.latitude.property.columns[0].type.scale == 8
    assert Geofence.longitude.property.columns[0].type.precision == 11
    assert Geofence.longitude.property.columns[0].type.scale == 8

    assert Attendance.verified_latitude.property.columns[0].type.precision == 11
    assert Attendance.verified_latitude.property.columns[0].type.scale == 8
    assert Attendance.verified_longitude.property.columns[0].type.precision == 11
    assert Attendance.verified_longitude.property.columns[0].type.scale == 8

    assert AttendanceAttempt.latitude.property.columns[0].type.precision == 11
    assert AttendanceAttempt.latitude.property.columns[0].type.scale == 8
    assert AttendanceAttempt.longitude.property.columns[0].type.precision == 11
    assert AttendanceAttempt.longitude.property.columns[0].type.scale == 8

    assert AttendanceRequest.latitude.property.columns[0].type.precision == 11
    assert AttendanceRequest.latitude.property.columns[0].type.scale == 8
    assert AttendanceRequest.longitude.property.columns[0].type.precision == 11
    assert AttendanceRequest.longitude.property.columns[0].type.scale == 8
