import unittest
import sys
import os
import io
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
from app.security.hashing import get_password_hash
from app.security.tokens import create_access_token
from app.services.time_service import TimeService

# In-memory SQLite for testing
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

class TestServerAuthoritativeAttendanceRequests(unittest.TestCase):
    submitted_req_id = None

    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()

        # Create Admin
        cls.admin = User(
            employee_id="ADM001",
            full_name="Admin User",
            password_hash=get_password_hash("admin123"),
            role=UserRole.ADMIN,
            is_active=True,
            must_change_password=False
        )
        cls.db.add(cls.admin)

        # Create Employee
        cls.user = User(
            employee_id="2668",
            full_name="John Doe",
            password_hash=get_password_hash("user123"),
            role=UserRole.USER,
            is_active=True,
            must_change_password=False
        )
        cls.db.add(cls.user)
        cls.db.commit()
        cls.db.refresh(cls.admin)
        cls.db.refresh(cls.user)

        # Create Geofence for employee
        cls.geofence = Geofence(
            user_id=cls.user.id,
            location_name="Factory Main Gate",
            latitude=16.70500,
            longitude=74.24330,
            radius_meters=150.0,
            is_active=True
        )
        cls.db.add(cls.geofence)

        # Create Shift: Dayin (08:30 AM - 09:10:59 AM)
        cls.shift = Shift(
            shift_code="DAYIN_SHIFT",
            shift_name="Dayin",
            description="Morning Dayin Shift",
            is_active=True
        )
        cls.db.add(cls.shift)
        cls.db.commit()
        cls.db.refresh(cls.shift)

        # Shift Rule
        cls.rule1 = ShiftRule(
            shift_id=cls.shift.id,
            rule_name="Dayin Punch Window",
            rule_code="DAYIN",
            start_time=datetime.strptime("08:30:00", "%H:%M:%S").time(),
            end_time=datetime.strptime("09:10:59", "%H:%M:%S").time(),
            result_code="DAYIN",
            is_active=True,
            priority=10
        )
        cls.rule2 = ShiftRule(
            shift_id=cls.shift.id,
            rule_name="Late Entry Window",
            rule_code="LATE",
            start_time=datetime.strptime("09:11:00", "%H:%M:%S").time(),
            end_time=datetime.strptime("11:00:00", "%H:%M:%S").time(),
            result_code="LATE",
            is_active=True,
            priority=5
        )
        cls.db.add_all([cls.rule1, cls.rule2])

        # Assign Shift to employee
        cls.assignment = EmployeeShiftAssignment(
            user_id=cls.user.id,
            shift_id=cls.shift.id,
            effective_from=date.today(),
            is_active=True
        )
        cls.db.add(cls.assignment)
        cls.db.commit()

        # Auth tokens
        cls.admin_token = create_access_token({"sub": str(cls.admin.id), "role": "ADMIN"})
        cls.user_token = create_access_token({"sub": str(cls.user.id), "role": "USER"})

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        Base.metadata.drop_all(bind=engine)
        app.dependency_overrides.clear()

    def test_01_time_service_and_evidence_overlay(self):
        """Test TimeService server time extraction and OpenCV evidence overlay burning"""
        server_info = TimeService.get_current_server_time()
        self.assertIn("server_timestamp", server_info)
        self.assertIn("formatted_date", server_info)
        self.assertIn("formatted_time", server_info)
        self.assertEqual(server_info["timezone"], "Asia/Kolkata")
        self.assertTrue(server_info["epoch_ms"] > 0)

        # Create dummy test image (400x400 blue square)
        img = np.zeros((400, 400, 3), dtype=np.uint8)
        img[:, :] = (180, 100, 50)
        _, encoded_orig = cv2.imencode('.jpg', img)
        raw_bytes = encoded_orig.tobytes()

        # Burn bottom-left evidence overlay
        overlaid_bytes = TimeService.burn_evidence_overlay(
            image_bytes=raw_bytes,
            location_name="Factory Main Gate",
            latitude=16.70500,
            longitude=74.24330,
            server_dt=datetime(2026, 9, 21, 10, 34, 27)
        )
        self.assertIsNotNone(overlaid_bytes)
        self.assertTrue(len(overlaid_bytes) > 0)

        # Decode stamped image and verify dimensions
        overlaid_np = cv2.imdecode(np.frombuffer(overlaid_bytes, np.uint8), cv2.IMREAD_COLOR)
        self.assertEqual(overlaid_np.shape[0], 400)
        self.assertEqual(overlaid_np.shape[1], 400)

    def test_02_server_time_api(self):
        """Test GET /api/user/server-time returns authoritative server time"""
        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.get("/api/user/server-time", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("server_date", data)
        self.assertIn("server_time", data)
        self.assertIn("epoch_ms", data)
        self.assertEqual(data["timezone"], "Asia/Kolkata")

    def test_03_attendance_config_api(self):
        """Test GET /api/user/attendance-config returns shift & server time info"""
        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.get("/api/user/attendance-config", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("server_time", data)
        self.assertIn("shift", data)
        self.assertEqual(data["shift"]["shift_name"], "Dayin")
        self.assertIn("current_status", data["shift"])
        self.assertEqual(data["geofence"]["location_name"], "Factory Main Gate")

    def test_04_submit_attendance_request(self):
        """Test POST /api/user/attendance-request records live selfie, GPS, and server timestamp"""
        # Create test selfie image
        img = np.zeros((300, 300, 3), dtype=np.uint8)
        _, encoded = cv2.imencode('.jpg', img)
        file_obj = io.BytesIO(encoded.tobytes())

        headers = {"Authorization": f"Bearer {self.user_token}"}
        response = client.post(
            "/api/user/attendance-request",
            headers=headers,
            data={
                "latitude": "16.70510",
                "longitude": "74.24335",
                "location_name": "Factory Main Gate",
                "accuracy": "3.5",
                "device_timestamp": "2026-09-21T08:50:00",  # Manipulated device time
                "reason": "Face verification failed"
            },
            files={"selfie": ("selfie.jpg", file_obj, "image/jpeg")}
        )
        if response.status_code != 200:
            print("422 DETAIL:", response.text)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["employee_id"], "2668")
        self.assertEqual(data["status"], "PENDING")
        self.assertEqual(data["shift_name"], "Dayin")
        self.assertTrue(data["is_within_geofence"])
        self.assertTrue(data["distance_from_location"] < 25.0)
        self.assertIn("server_formatted_date", data)
        self.assertIn("server_formatted_time", data)
        self.__class__.submitted_req_id = data["id"]

    def test_05_get_user_attendance_requests(self):
        """Test GET /api/user/attendance-requests allows employee to view submitted requests"""
        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.get("/api/user/attendance-requests", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertTrue(len(data) >= 1)
        self.assertEqual(data[0]["id"], self.__class__.submitted_req_id)
        self.assertEqual(data[0]["status"], "PENDING")

    def test_06_admin_dashboard_stats_and_request_list(self):
        """Test admin dashboard shows pending attendance requests count & lists requests"""
        headers = {"Authorization": f"Bearer {self.admin_token}"}
        stats_res = client.get("/api/admin/dashboard-stats", headers=headers)
        self.assertEqual(stats_res.status_code, 200)
        stats = stats_res.json()
        self.assertTrue(stats["pending_attendance_requests"] >= 1)

        # List requests
        reqs_res = client.get("/api/admin/attendance-requests?status=PENDING", headers=headers)
        self.assertEqual(reqs_res.status_code, 200)
        reqs = reqs_res.json()
        self.assertTrue(any(r["id"] == self.__class__.submitted_req_id for r in reqs))

    def test_07_admin_view_evidence_image(self):
        """Test GET /api/admin/attendance-requests/{id}/image returns raw watermarked evidence"""
        headers = {"Authorization": f"Bearer {self.admin_token}"}
        img_res = client.get(f"/api/admin/attendance-requests/{self.__class__.submitted_req_id}/image", headers=headers)
        self.assertEqual(img_res.status_code, 200)
        self.assertEqual(img_res.headers["content-type"], "image/jpeg")
        self.assertTrue(len(img_res.content) > 0)

    def test_08_admin_approve_attendance_request(self):
        """Test POST /api/admin/attendance-requests/{id}/approve creates official attendance record using server timestamp"""
        req = self.db.query(AttendanceRequest).filter(AttendanceRequest.status == RequestStatus.PENDING).first()
        if not req:
            img = np.zeros((100, 100, 3), dtype=np.uint8)
            _, enc = cv2.imencode('.jpg', img)
            req = AttendanceRequest(
                user_id=self.user.id,
                request_date=date.today(),
                server_timestamp=datetime.utcnow(),
                shift_id=self.shift.id,
                status=RequestStatus.PENDING,
                rejection_reason_trigger="Face verification failed",
                latitude=16.70500,
                longitude=74.24330,
                distance_from_location=10.0,
                is_within_geofence=True,
                evidence_image=enc.tobytes()
            )
            self.db.add(req)
            self.db.commit()
            self.db.refresh(req)

        headers = {"Authorization": f"Bearer {self.admin_token}"}
        approve_res = client.post(
            f"/api/admin/attendance-requests/{req.id}/approve",
            headers=headers,
            json={"admin_notes": "Verified authentic selfie at factory gate"}
        )
        self.assertEqual(approve_res.status_code, 200)
        data = approve_res.json()
        self.assertEqual(data["status"], "APPROVED")
        self.assertEqual(data["admin_notes"], "Verified authentic selfie at factory gate")

        # Verify attendance record created in database
        att_record = self.db.query(Attendance).filter(
            Attendance.attendance_request_id == req.id
        ).first()
        self.assertIsNotNone(att_record)
        self.assertEqual(att_record.user_id, self.user.id)
        self.assertEqual(att_record.verification_mode, "REQUEST_APPROVAL")
        self.assertEqual(att_record.shift_id, self.shift.id)
        self.assertIsNotNone(att_record.timestamp)
        self.assertIn(att_record.status.value, ["LATE", "DAYIN", "PRESENT", "HALF_DAY"])

    def test_09_admin_reject_attendance_request(self):
        """Test POST /api/admin/attendance-requests/{id}/reject marks request rejected without creating attendance"""
        # Create second request
        img = np.zeros((200, 200, 3), dtype=np.uint8)
        _, encoded = cv2.imencode('.jpg', img)
        file_obj = io.BytesIO(encoded.tobytes())

        user_headers = {"Authorization": f"Bearer {self.user_token}"}
        sub_res = client.post(
            "/api/user/attendance-request",
            headers=user_headers,
            data={
                "verification_no": 2,
                "latitude": "16.90000", # Far outside
                "longitude": "74.50000",
                "location_name": "Unknown Offsite",
                "reason": "Face verification failed"
            },
            files={"selfie": ("selfie2.jpg", file_obj, "image/jpeg")}
        )
        req2_id = sub_res.json()["id"]

        # Admin rejects
        admin_headers = {"Authorization": f"Bearer {self.admin_token}"}
        rej_res = client.post(
            f"/api/admin/attendance-requests/{req2_id}/reject",
            headers=admin_headers,
            json={"admin_notes": "Selfie location 25km away from assigned work site"}
        )
        self.assertEqual(rej_res.status_code, 200)
        data = rej_res.json()
        self.assertEqual(data["status"], "REJECTED")
        self.assertEqual(data["admin_notes"], "Selfie location 25km away from assigned work site")

        # Confirm NO attendance record created
        att_count = self.db.query(Attendance).filter(
            Attendance.attendance_request_id == req2_id
        ).count()
        self.assertEqual(att_count, 0)

if __name__ == "__main__":
    unittest.main()
