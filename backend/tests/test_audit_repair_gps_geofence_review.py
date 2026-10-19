import unittest
import sys
import os
import io
import math
import numpy as np
import cv2
from datetime import datetime, date

# Add backend root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.main import app
from app.database import Base, get_db
from app.models.user import User, UserRole
from app.models.geofence import Geofence
from app.models.shift import Shift, ShiftRule, EmployeeShiftAssignment
from app.models.attendance_request import AttendanceRequest, RequestStatus
from app.models.attendance import Attendance
from app.models.tracking import TrackingSession, GpsRoutePoint
from app.security.hashing import get_password_hash
from app.security.tokens import create_access_token
from app.services.geofence_service import (
    is_valid_coordinate,
    calculate_haversine_distance,
    validate_geofence,
)
from app.services.time_service import TimeService

SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

client = TestClient(app)

class TestAuditRepairGpsGeofenceReview(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()

        # Admin user
        cls.admin = User(
            employee_id="ADM_AUDIT",
            full_name="Audit Administrator",
            password_hash=get_password_hash("admin123"),
            role=UserRole.ADMIN,
            is_active=True
        )
        cls.db.add(cls.admin)

        # Employee 2668
        cls.user = User(
            employee_id="2668",
            full_name="Field Employee 2668",
            password_hash=get_password_hash("pass123"),
            role=UserRole.USER,
            is_active=True
        )
        cls.db.add(cls.user)
        cls.db.commit()
        cls.db.refresh(cls.admin)
        cls.db.refresh(cls.user)

        # Field Area A Geofence (Kolhapur/Pune region, approx 16.7050, 74.2433, radius 150m)
        cls.geofence = Geofence(
            user_id=cls.user.id,
            location_name="Field Area A",
            latitude=16.7050000,
            longitude=74.2433000,
            radius_meters=150.0,
            is_active=True
        )
        cls.db.add(cls.geofence)
        cls.db.commit()
        cls.db.refresh(cls.geofence)
        cls.user.geofence_id = cls.geofence.id
        cls.db.commit()
        cls.db.refresh(cls.user)

        # Standard Shift
        cls.shift = Shift(
            shift_name="General Department",
            shift_code="GEN_01",
            description="General Department Shift",
            is_active=True
        )
        cls.db.add(cls.shift)
        cls.db.commit()
        cls.db.refresh(cls.shift)

        # Assign shift to employee
        assignment = EmployeeShiftAssignment(
            user_id=cls.user.id,
            shift_id=cls.shift.id,
            effective_from=date.today(),
            is_active=True
        )
        cls.db.add(assignment)
        cls.db.commit()
        cls.db.refresh(cls.user)
        cls.db.refresh(cls.shift)

        cls.admin_token = create_access_token({"sub": str(cls.admin.id), "role": "ADMIN"})
        cls.user_token = create_access_token({"sub": str(cls.user.id), "role": "USER"})

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        app.dependency_overrides.clear()

    # --- Unit Tests: Coordinate Validation ---
    def test_01_coordinate_validity_rules(self):
        """Test is_valid_coordinate rejects null, NaN, out of bounds, and sentinel (0,0) while accepting real zeroes"""
        self.assertFalse(is_valid_coordinate(None, 74.123))
        self.assertFalse(is_valid_coordinate(16.123, None))
        self.assertFalse(is_valid_coordinate(float('nan'), 74.123))
        self.assertFalse(is_valid_coordinate(91.0, 74.123)) # Latitude > 90
        self.assertFalse(is_valid_coordinate(-91.0, 74.123)) # Latitude < -90
        self.assertFalse(is_valid_coordinate(16.123, 181.0)) # Longitude > 180
        self.assertFalse(is_valid_coordinate(16.123, -181.0)) # Longitude < -180

        # Sentinel detection: Null Island (0.0, 0.0) is uninitialized/default
        self.assertFalse(is_valid_coordinate(0.0, 0.0))
        self.assertFalse(is_valid_coordinate("0.0", "0.0"))

        # Legitimate coordinates with a single zero
        self.assertTrue(is_valid_coordinate(0.0, 74.2433)) # Equator with valid longitude
        self.assertTrue(is_valid_coordinate(51.5074, 0.0)) # Prime meridian in Greenwich
        self.assertTrue(is_valid_coordinate(16.7050, 74.2433)) # Field Area A

    # --- Unit Tests: Geofence Validation ---
    def test_02_geofence_sentinel_handling(self):
        """Test validate_geofence returns (False, None) for (0,0) sentinel and does NOT compute 8.3 million meters"""
        is_inside, dist = validate_geofence(
            current_lat=0.0,
            current_lon=0.0,
            assigned_lat=16.7050000,
            assigned_lon=74.2433000,
            radius_meters=150.0
        )
        self.assertFalse(is_inside)
        self.assertIsNone(dist, "Distance must be None for sentinel (0.0, 0.0), not 8,339,237.1m")

    def test_03_geofence_inside_and_outside(self):
        """Test validate_geofence inside and outside permitted radius"""
        # Exactly on geofence center
        is_inside, dist = validate_geofence(16.7050000, 74.2433000, 16.7050000, 74.2433000, 150.0)
        self.assertTrue(is_inside)
        self.assertEqual(round(dist, 2), 0.0)

        # 50m offset (within 150m radius)
        is_inside, dist = validate_geofence(16.7054000, 74.2433000, 16.7050000, 74.2433000, 150.0)
        self.assertTrue(is_inside)
        self.assertTrue(dist < 150.0)

        # 500m offset (outside 150m radius)
        is_inside, dist = validate_geofence(16.7100000, 74.2433000, 16.7050000, 74.2433000, 150.0)
        self.assertFalse(is_inside)
        self.assertTrue(dist > 150.0)

    # --- Integration Tests: Attendance Request with Sentinel (0.0, 0.0) ---
    def test_04_submit_attendance_request_with_sentinel_coordinates(self):
        """Test submitting request with 0.0, 0.0 stores distance=-1.0 and is_within=0 without crashing"""
        img = np.zeros((100, 100, 3), dtype=np.uint8)
        _, encoded = cv2.imencode('.jpg', img)
        file_obj = io.BytesIO(encoded.tobytes())

        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.post(
            "/api/user/attendance-request",
            headers=headers,
            data={
                "verification_no": 1,
                "client_request_id": "REQ_TEST_SENTINEL_001",
                "latitude": "0.0",
                "longitude": "0.0",
                "location_name": "Field Area A",
                "reason": "Attendance verification assistance / manual request"
            },
            files={"selfie": ("selfie.jpg", file_obj, "image/jpeg")}
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["latitude"], 0.0)
        self.assertEqual(data["longitude"], 0.0)
        self.assertEqual(data["distance_from_location"], -1.0, "Distance must be -1.0 sentinel indicating unavailable")
        self.assertFalse(data["is_within_geofence"])
        self.assertIsNone(data["gps_accuracy"])
        self.__class__.submitted_req_id = data["id"]

    def test_05_duplicate_request_prevention(self):
        """Test submitting another pending request for same verification window is rejected with 400"""
        img = np.zeros((100, 100, 3), dtype=np.uint8)
        _, encoded = cv2.imencode('.jpg', img)
        file_obj = io.BytesIO(encoded.tobytes())

        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.post(
            "/api/user/attendance-request",
            headers=headers,
            data={
                "verification_no": 1, # Same verification window #1
                "latitude": "16.7050",
                "longitude": "74.2433",
                "reason": "Duplicate attempt"
            },
            files={"selfie": ("selfie.jpg", file_obj, "image/jpeg")}
        )
        self.assertEqual(res.status_code, 400)
        self.assertIn("already pending admin review", res.json()["detail"])

    def test_06_idempotent_submission_with_client_request_id(self):
        """Test submitting with identical client_request_id returns existing record idempotently"""
        img = np.zeros((100, 100, 3), dtype=np.uint8)
        _, encoded = cv2.imencode('.jpg', img)
        file_obj = io.BytesIO(encoded.tobytes())

        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.post(
            "/api/user/attendance-request",
            headers=headers,
            data={
                "verification_no": 1,
                "client_request_id": "REQ_TEST_SENTINEL_001", # Identical UUID from test_04
                "latitude": "0.0",
                "longitude": "0.0",
                "reason": "Network retry"
            },
            files={"selfie": ("selfie.jpg", file_obj, "image/jpeg")}
        )
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["id"], self.submitted_req_id)

    # --- Evidence Image Authentication Tests ---
    def test_07_evidence_image_auth_via_header_and_query_token(self):
        """Test evidence image endpoint supports both Bearer header and ?token= query parameter"""
        req_id = self.submitted_req_id

        # 1. Bearer Header
        res_header = client.get(
            f"/api/admin/attendance-requests/{req_id}/image",
            headers={"Authorization": f"Bearer {self.admin_token}"}
        )
        self.assertEqual(res_header.status_code, 200)
        self.assertEqual(res_header.headers["content-type"], "image/jpeg")

        # 2. Query param ?token= (Flutter Web / Browser <img> tag)
        res_query = client.get(
            f"/api/admin/attendance-requests/{req_id}/image?token={self.admin_token}"
        )
        self.assertEqual(res_query.status_code, 200)
        self.assertEqual(res_query.headers["content-type"], "image/jpeg")

        # 3. Missing auth -> 401
        res_noauth = client.get(f"/api/admin/attendance-requests/{req_id}/image")
        self.assertEqual(res_noauth.status_code, 401)

    # --- GPS Tracking & Route Initial Point Tests ---
    def test_08_start_tracking_session_creates_initial_point(self):
        """Test /api/tracking/start with valid coordinates automatically persists sequence #1 route point"""
        headers = {"Authorization": f"Bearer {self.user_token}"}
        session_uuid = f"TEST_TRACK_SESSION_{datetime.utcnow().timestamp()}"

        res = client.post(
            "/api/tracking/start",
            headers=headers,
            json={
                "session_uuid": session_uuid,
                "start_latitude": 16.7050000,
                "start_longitude": 74.2433000,
            }
        )
        self.assertEqual(res.status_code, 200)
        session_id = res.json()["session_id"]

        # Check route endpoint returns the initial starting point
        route_res = client.get(
            f"/api/tracking/sessions/{session_id}/route",
            headers=headers
        )
        self.assertEqual(route_res.status_code, 200)
        data = route_res.json()
        self.assertEqual(data["session"]["point_count"], 1)
        self.assertEqual(len(data["points"]), 1)
        self.assertEqual(data["points"][0]["sequence_number"], 1)
        self.assertAlmostEqual(data["points"][0]["latitude"], 16.7050000, places=4)
        self.assertAlmostEqual(data["points"][0]["longitude"], 74.2433000, places=4)

if __name__ == "__main__":
    unittest.main()
