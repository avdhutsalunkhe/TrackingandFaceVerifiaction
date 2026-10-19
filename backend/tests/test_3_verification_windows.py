import unittest
import sys
import os
import io
import numpy as np
from datetime import datetime, date, time, timedelta
import pytz

# Add backend root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from unittest.mock import patch

from app.database import Base, get_db
from app.main import app
from app.models.user import User, UserRole
from app.models.face import FaceTemplate
from app.models.geofence import Geofence
from app.models.attendance import Attendance
from app.models.shift import Shift, ShiftRule, EmployeeShiftAssignment
from app.security.hashing import get_password_hash
from app.security.tokens import create_access_token
from app.services.time_service import TimeService
from app.services.attendance_decision_service import AttendanceDecisionService

TEST_DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

client = TestClient(app)

class TestThreeVerificationWindows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()

        # Create test employee
        cls.user = User(
            employee_id="EMP3WIN",
            full_name="Verification Window Tester",
            password_hash=get_password_hash("password123"),
            is_active=True,
            must_change_password=False,
            role=UserRole.USER
        )
        cls.db.add(cls.user)
        cls.db.commit()
        cls.db.refresh(cls.user)

        # Create FaceTemplate
        dummy_embedding = np.zeros(512, dtype=np.float32)
        cls.template = FaceTemplate(
            user_id=cls.user.id,
            face_embedding=dummy_embedding.tobytes(),
            face_image=b"\xff\xd8\xff\xe0dummyrefimage",
            quality_score=0.98
        )
        cls.db.add(cls.template)

        # Create geofence
        cls.geofence = Geofence(
            user_id=cls.user.id,
            location_name="HQ Office",
            latitude=18.5204,
            longitude=73.8567,
            radius_meters=150.0,
            is_active=True
        )
        cls.db.add(cls.geofence)

        # Create dynamic shift and assign to employee
        from app.models.shift import Shift, ShiftPunchPeriod, ShiftRule, EmployeeShiftAssignment
        cls.shift = Shift(
            shift_code="S_TEST_3WIN",
            shift_name="Test 3 Windows Shift",
            is_active=True
        )
        cls.db.add(cls.shift)
        cls.db.flush()

        periods_def = [
            (1, "Morning Verification", time(8, 0, 0), time(9, 0, 0)),
            (2, "Lunch Verification", time(13, 0, 0), time(13, 20, 0)),
            (3, "Evening Verification", time(17, 0, 0), time(18, 0, 0)),
        ]
        for p_no, p_name, st, et in periods_def:
            p = ShiftPunchPeriod(
                shift_id=cls.shift.id,
                punch_no=p_no,
                period_name=p_name,
                start_time=st,
                end_time=et,
                show_in_user_schedule=True,
                is_active=True,
                priority=p_no
            )
            cls.db.add(p)
            r = ShiftRule(
                shift_id=cls.shift.id,
                rule_code=f"PUNCH_{p_no}",
                rule_name=p_name,
                verification_no=p_no,
                start_time=st,
                end_time=et,
                show_in_user_schedule=True,
                is_active=True,
                priority=p_no
            )
            cls.db.add(r)

        cls.assignment = EmployeeShiftAssignment(
            user_id=cls.user.id,
            shift_id=cls.shift.id,
            effective_from=date(2026, 1, 1),
            is_active=True
        )
        cls.db.add(cls.assignment)
        cls.db.commit()

        cls.user_token = create_access_token({"sub": str(cls.user.id), "role": "USER"})

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        Base.metadata.drop_all(bind=engine)
        app.dependency_overrides.clear()

    def test_01_window_schedule_determination(self):
        """Test TimeService.get_active_verification_window and get_next_verification_window"""
        # Verification 1 window: 08:00 - 09:00
        w1_mid = time(8, 30, 0)
        win1 = TimeService.get_active_verification_window(w1_mid, shift=self.shift)
        self.assertIsNotNone(win1)
        self.assertEqual(win1["verification_no"], 1)

        # Gap between V1 and V2: 09:30 - CLOSED
        gap1 = time(9, 30, 0)
        self.assertIsNone(TimeService.get_active_verification_window(gap1, shift=self.shift))
        next_win = TimeService.get_next_verification_window(gap1, shift=self.shift)
        self.assertIsNotNone(next_win)
        self.assertEqual(next_win["verification_no"], 2)

        # Verification 2 window: 13:00 - 13:20
        w2_mid = time(13, 10, 0)
        win2 = TimeService.get_active_verification_window(w2_mid, shift=self.shift)
        self.assertIsNotNone(win2)
        self.assertEqual(win2["verification_no"], 2)

        # Gap between V2 and V3: 15:00 - CLOSED
        gap2 = time(15, 0, 0)
        self.assertIsNone(TimeService.get_active_verification_window(gap2, shift=self.shift))
        next_win3 = TimeService.get_next_verification_window(gap2, shift=self.shift)
        self.assertIsNotNone(next_win3)
        self.assertEqual(next_win3["verification_no"], 3)

        # Verification 3 window: 17:00 - 18:00
        w3_mid = time(17, 30, 0)
        win3 = TimeService.get_active_verification_window(w3_mid, shift=self.shift)
        self.assertIsNotNone(win3)
        self.assertEqual(win3["verification_no"], 3)

        # After 18:00: CLOSED, no next verification
        after_all = time(18, 5, 0)
        self.assertIsNone(TimeService.get_active_verification_window(after_all, shift=self.shift))
        self.assertIsNone(TimeService.get_next_verification_window(after_all, shift=self.shift))

    def test_02_attendance_config_reflects_3_windows(self):
        """Test GET /api/user/attendance-config returns structured 3-window info"""
        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.get("/api/user/attendance-config", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()

        self.assertIn("verification_windows", data)
        windows = data["verification_windows"]
        self.assertEqual(len(windows), 3)
        self.assertEqual(windows[0]["verification_no"], 1)
        self.assertEqual(windows[0]["start"], "08:00:00")
        self.assertEqual(windows[0]["end"], "09:00:00")
        self.assertEqual(windows[1]["verification_no"], 2)
        self.assertEqual(windows[1]["start"], "13:00:00")
        self.assertEqual(windows[1]["end"], "13:20:00")
        self.assertEqual(windows[2]["verification_no"], 3)
        self.assertEqual(windows[2]["start"], "17:00:00")
        self.assertEqual(windows[2]["end"], "18:00:00")

    @patch("app.services.attendance_decision_service.face_pipeline.verify_live_sequence")
    def test_03_authoritative_attendance_flow_all_3_windows(self, mock_face):
        """Test marking all 3 independent verifications for the same employee on the same date"""
        mock_face.return_value = (True, None, "Face matched successfully", 0.95, 0.98, {})
        headers = {"Authorization": f"Bearer {self.user_token}"}
        today = date(2026, 9, 22)
        dummy_file = ("frame.jpg", b"\xff\xd8\xff\xe0dummyjpgbytes", "image/jpeg")

        # 1. Mark Window 1 (Mock server time: 08:30:00)
        t1 = datetime(2026, 9, 22, 8, 30, 0, tzinfo=pytz.timezone("Asia/Kolkata"))
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t1,
            "formatted_date": "2026-09-22",
            "formatted_time": "08:30:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t1.timestamp() * 1000)
        }):
            # First attempt at Window 1 -> Success
            res1 = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "gps_accuracy": 5.0,
                    "client_punch_id": "PUNCH-W1-001"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res1.status_code, 200)
            data1 = res1.json()
            self.assertTrue(data1["success"])
            self.assertEqual(data1["decision"], "PRESENT")
            self.assertEqual(data1["verification_no"], 1)

            # Duplicate attempt at Window 1 -> Rejected
            res1_dup = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "gps_accuracy": 5.0,
                    "client_punch_id": "PUNCH-W1-DUP"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res1_dup.status_code, 200)
            data1_dup = res1_dup.json()
            self.assertFalse(data1_dup["success"])
            self.assertEqual(data1_dup["decision"], "REJECTED")
            self.assertIn("already been completed", data1_dup["message"].lower())

        # 2. Attempt punch during closed period: 10:00:00 -> Rejected
        t_gap = datetime(2026, 9, 22, 10, 0, 0, tzinfo=pytz.timezone("Asia/Kolkata"))
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t_gap,
            "formatted_date": "2026-09-22",
            "formatted_time": "10:00:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t_gap.timestamp() * 1000)
        }):
            res_gap = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "client_punch_id": "PUNCH-GAP-001"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res_gap.status_code, 200)
            data_gap = res_gap.json()
            self.assertFalse(data_gap["success"])
            self.assertEqual(data_gap["decision"], "REJECTED")
            self.assertIn("closed", data_gap["message"].lower())

        # 3. Mark Window 2 (Mock server time: 13:10:00) -> Allowed! Window 1 completion did NOT lock Window 2
        t2 = datetime(2026, 9, 22, 13, 10, 0, tzinfo=pytz.timezone("Asia/Kolkata"))
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t2,
            "formatted_date": "2026-09-22",
            "formatted_time": "13:10:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t2.timestamp() * 1000)
        }):
            res2 = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "client_punch_id": "PUNCH-W2-001"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res2.status_code, 200)
            data2 = res2.json()
            self.assertTrue(data2["success"])
            self.assertEqual(data2["decision"], "PRESENT")
            self.assertEqual(data2["verification_no"], 2)

        # 4. Mark Window 3 (Mock server time: 17:30:00) -> Allowed!
        t3 = datetime(2026, 9, 22, 17, 30, 0, tzinfo=pytz.timezone("Asia/Kolkata"))
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t3,
            "formatted_date": "2026-09-22",
            "formatted_time": "17:30:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t3.timestamp() * 1000)
        }):
            res3 = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "client_punch_id": "PUNCH-W3-001"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res3.status_code, 200)
            data3 = res3.json()
            self.assertTrue(data3["success"])
            self.assertEqual(data3["decision"], "PRESENT")
            self.assertEqual(data3["verification_no"], 3)

        # Verify that all 3 records exist in the database for the user on this date
        records = self.db.query(Attendance).filter(
            Attendance.user_id == self.user.id,
            Attendance.attendance_date == today
        ).order_by(Attendance.verification_no.asc()).all()

        self.assertEqual(len(records), 3)
        self.assertEqual(records[0].verification_no, 1)
        self.assertEqual(records[1].verification_no, 2)
        self.assertEqual(records[2].verification_no, 3)

    def test_04_offline_batch_sync_and_revalidation(self):
        """Test POST /api/user/attendance/sync-offline with revalidation logic and idempotency"""
        from app.services.attendance_decision_service import face_pipeline
        headers = {"Authorization": f"Bearer {self.user_token}"}
        tomorrow = date.today() + timedelta(days=1)
        now_str = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S")

        # Client submits offline punch for tomorrow Verification 1 (08:15 AM)
        sync_payload = {
            "items": [
                {
                    "client_punch_id": "OFFLINE-SYNC-001",
                    "attendance_date": tomorrow.isoformat(),
                    "verification_no": 1,
                    "estimated_server_time": f"{tomorrow.isoformat()}T08:15:00",
                    "device_wall_time": f"{tomorrow.isoformat()}T08:15:05",
                    "last_server_sync_time": now_str,
                    "server_time_offset": 5.0,
                    "latitude": 18.5204,
                    "longitude": 73.8567,
                    "accuracy": 8.5,
                    "face_result": "MATCH",
                    "liveness_result": "PASS",
                    "verification_score": 0.95,
                    "image_base64": "L2ZmWGQvZmZlMGR1bW15cmVmaW1hZ2U="
                }
            ]
        }

        with patch.object(face_pipeline, 'verify_live_sequence', return_value=(True, None, "Face verified", 0.95, 0.98, {})):
            res = client.post("/api/user/attendance/sync-offline", headers=headers, json=sync_payload)
            self.assertEqual(res.status_code, 200)
            data = res.json()
            self.assertEqual(data["total_processed"], 1)
            self.assertEqual(data["confirmed_count"], 1)
            item_res = data["results"][0]
            self.assertEqual(item_res["client_punch_id"], "OFFLINE-SYNC-001")
            self.assertEqual(item_res["status"], "CONFIRMED")
            self.assertEqual(item_res["verification_no"], 1)

            # Re-sending the same offline payload must return DUPLICATE idempotently without error
            res_dup = client.post("/api/user/attendance/sync-offline", headers=headers, json=sync_payload)
            self.assertEqual(res_dup.status_code, 200)
            data_dup = res_dup.json()
            item_dup = data_dup["results"][0]
            self.assertEqual(item_dup["status"], "DUPLICATE")

if __name__ == "__main__":
    unittest.main()

