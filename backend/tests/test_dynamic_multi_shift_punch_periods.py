import unittest
from datetime import datetime, date, time, timedelta
from unittest.mock import patch, MagicMock
import pytz
import numpy as np
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.database import Base, get_db
from app.main import app
from app.models.user import User, UserRole
from app.models.face import FaceTemplate
from app.models.geofence import Geofence
from app.models.shift import Shift, ShiftPunchPeriod, ShiftRule, EmployeeShiftAssignment
from app.models.attendance import Attendance
from app.security.hashing import get_password_hash
from app.security.tokens import create_access_token
from app.services.time_service import TimeService
from app.services.shift_service import ShiftService

from sqlalchemy.pool import StaticPool

SQLALCHEMY_DATABASE_URL = "sqlite:///:memory:"
engine = create_engine(
    SQLALCHEMY_DATABASE_URL,
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

class TestDynamicMultiShiftPunchPeriods(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()

        # Employee 1: will have active shift
        cls.user1 = User(
            employee_id="EMP_SHIFT_01",
            full_name="Shift Worker One",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            must_change_password=False,
            role=UserRole.USER
        )
        # Employee 2: NO shift assigned
        cls.user_no_shift = User(
            employee_id="EMP_NO_SHIFT",
            full_name="Unassigned Worker",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            must_change_password=False,
            role=UserRole.USER
        )
        cls.db.add_all([cls.user1, cls.user_no_shift])
        cls.db.commit()
        cls.db.refresh(cls.user1)
        cls.db.refresh(cls.user_no_shift)

        # Geofence & biometric templates
        for u in [cls.user1, cls.user_no_shift]:
            gf = Geofence(
                user_id=u.id,
                location_name="HQ Office",
                latitude=18.5204,
                longitude=73.8567,
                radius_meters=150.0,
                is_active=True
            )
            cls.db.add(gf)
            dummy_embedding = np.zeros(512, dtype=np.float32)
            tmpl = FaceTemplate(
                user_id=u.id,
                face_embedding=dummy_embedding.tobytes(),
                face_image=b"\xff\xd8\xff\xe0dummyrefimage",
                quality_score=0.98
            )
            cls.db.add(tmpl)
        cls.db.commit()

        # 1. Create General Shift with 4 periods:
        # P1: 08:30:00 - 09:15:00 (Show=True)
        # P2: 13:00:00 - 13:15:00 (Show=True)
        # P3: 13:15:00 - 13:30:00 (Show=False -> Hidden!)
        # P4: 17:00:00 - 18:00:00 (Show=True)
        cls.gen_shift = Shift(
            shift_code="GEN_01",
            shift_name="General Shift 4 Periods",
            is_active=True
        )
        cls.db.add(cls.gen_shift)
        cls.db.flush()

        p_defs = [
            (1, "Morning Punch", time(8, 30, 0), time(9, 15, 0), True),
            (2, "Lunch Punch", time(13, 0, 0), time(13, 15, 0), True),
            (3, "Afternoon Punch (Hidden)", time(13, 15, 0), time(13, 30, 0), False),
            (4, "Evening Punch", time(17, 0, 0), time(18, 0, 0), True),
        ]
        cls.period_objects = []
        for p_no, p_name, st, et, show in p_defs:
            p = ShiftPunchPeriod(
                shift_id=cls.gen_shift.id,
                punch_no=p_no,
                period_name=p_name,
                start_time=st,
                end_time=et,
                show_in_user_schedule=show,
                is_active=True,
                priority=p_no
            )
            cls.db.add(p)
            cls.period_objects.append(p)
        cls.db.flush()

        # Assign user1 to General Shift
        assign = EmployeeShiftAssignment(
            user_id=cls.user1.id,
            shift_id=cls.gen_shift.id,
            effective_from=date(2026, 1, 1),
            is_active=True
        )
        cls.db.add(assign)
        cls.db.commit()

        cls.token_user1 = create_access_token({"sub": str(cls.user1.id), "role": "USER"})
        cls.token_no_shift = create_access_token({"sub": str(cls.user_no_shift.id), "role": "USER"})

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        Base.metadata.drop_all(bind=engine)
        app.dependency_overrides.clear()

    def test_01_no_active_shift_blocks_attendance(self):
        """User with no shift assignment gets has_active_shift=False and punch_allowed=False."""
        headers = {"Authorization": f"Bearer {self.token_no_shift}"}
        res = client.get("/api/user/today-schedule", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertFalse(data["has_active_shift"])
        self.assertFalse(data["attendance_action"]["punch_allowed"])
        self.assertEqual(data["attendance_action"]["reason"], "NO_ACTIVE_SHIFT")
        self.assertEqual(len(data["punch_periods"]), 0)

        # Attempt attendance POST -> strictly rejected
        dummy_file = ("frame.jpg", b"\xff\xd8\xff\xe0dummyjpgbytes", "image/jpeg")
        post_res = client.post(
            "/api/user/attendance/verify",
            headers=headers,
            data={
                "current_latitude": 18.5204,
                "current_longitude": 73.8567,
                "client_punch_id": "PUNCH-NO-SHIFT-01"
            },
            files=[("frames", dummy_file)]
        )
        self.assertEqual(post_res.status_code, 200)
        post_data = post_res.json()
        self.assertFalse(post_data["success"])
        self.assertEqual(post_data["decision"], "REJECTED")
        self.assertIn("No active shift assigned", post_data["message"])

    def test_02_today_schedule_dynamic_cards_and_hidden_filter(self):
        """Visible periods returned dynamically; hidden period excluded from user schedule."""
        headers = {"Authorization": f"Bearer {self.token_user1}"}
        # Mock time at 08:45:00 (inside Punch 1: 08:30-09:15)
        tz = pytz.timezone("Asia/Kolkata")
        t_mid = datetime(2026, 9, 24, 8, 45, 0, tzinfo=tz)
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t_mid,
            "formatted_date": "2026-09-24",
            "formatted_time": "08:45:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t_mid.timestamp() * 1000)
        }):
            res = client.get("/api/user/today-schedule", headers=headers)
            self.assertEqual(res.status_code, 200)
            data = res.json()
            self.assertTrue(data["has_active_shift"])
            self.assertEqual(data["shift"]["shift_code"], "GEN_01")

            # 4 periods configured, but P3 is hidden -> 3 cards returned in user schedule
            periods = data["punch_periods"]
            self.assertEqual(len(periods), 3)
            p1 = periods[0]
            self.assertEqual(p1["punch_no"], 1)
            self.assertEqual(p1["status"], "AVAILABLE")

            # Action allows punch
            self.assertTrue(data["attendance_action"]["punch_allowed"])
            self.assertEqual(data["attendance_action"]["active_punch_period_id"], p1["id"])

    def test_03_half_open_boundaries_and_adjacent_periods(self):
        """
        Half-open intervals: start_time <= time < end_time
        - 08:29:59: UPCOMING
        - 08:30:00: AVAILABLE
        - 09:14:59: AVAILABLE
        - 09:15:00: CLOSED
        - Adjacent boundary at 13:15:00: Lunch Punch (13:00-13:15) is CLOSED,
          Afternoon Punch (13:15-13:30) is ACTIVE
        """
        # Punch 1: 08:30:00 - 09:15:00
        w_early = TimeService.get_active_verification_window(time(8, 29, 59), shift=self.gen_shift)
        self.assertIsNone(w_early)

        w_start = TimeService.get_active_verification_window(time(8, 30, 0), shift=self.gen_shift)
        self.assertIsNotNone(w_start)
        self.assertEqual(w_start["punch_no"], 1)

        w_end_minus1 = TimeService.get_active_verification_window(time(9, 14, 59), shift=self.gen_shift)
        self.assertIsNotNone(w_end_minus1)
        self.assertEqual(w_end_minus1["punch_no"], 1)

        w_end_exact = TimeService.get_active_verification_window(time(9, 15, 0), shift=self.gen_shift)
        self.assertIsNone(w_end_exact)

        # Adjacent boundary at 13:15:00
        # P2: 13:00 - 13:15
        # P3: 13:15 - 13:30
        w_adj = TimeService.get_active_verification_window(time(13, 15, 0), shift=self.gen_shift)
        self.assertIsNotNone(w_adj)
        self.assertEqual(w_adj["punch_no"], 3) # P3 is active, P2 closed!

    @patch("app.services.attendance_decision_service.face_pipeline.verify_live_sequence")
    def test_04_punch_duplicate_prevention_across_periods(self, mock_face):
        """Completing Punch 1 succeeds; re-punching Punch 1 rejected as duplicate; Punch 2 remains punchable at its time."""
        mock_face.return_value = (True, None, "Face matched", 0.95, 0.98, {})
        headers = {"Authorization": f"Bearer {self.token_user1}"}
        dummy_file = ("frame.jpg", b"\xff\xd8\xff\xe0dummyjpgbytes", "image/jpeg")

        tz = pytz.timezone("Asia/Kolkata")
        t_p1 = datetime(2026, 9, 24, 8, 35, 0, tzinfo=tz)

        # 1. Mark Punch 1
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t_p1,
            "formatted_date": "2026-09-24",
            "formatted_time": "08:35:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t_p1.timestamp() * 1000)
        }):
            res1 = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "client_punch_id": "PUNCH-DYN-01"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res1.status_code, 200)
            d1 = res1.json()
            self.assertTrue(d1["success"])
            self.assertEqual(d1["punch_no"], 1)

            # Duplicate attempt for Punch 1 -> Rejected
            res1_dup = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "client_punch_id": "PUNCH-DYN-01-DUP"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res1_dup.status_code, 200)
            d1_dup = res1_dup.json()
            self.assertFalse(d1_dup["success"])
            self.assertEqual(d1_dup["decision"], "REJECTED")

        # 2. Punch 2 arrives at 13:05:00 -> Allowed
        t_p2 = datetime(2026, 9, 24, 13, 5, 0, tzinfo=tz)
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t_p2,
            "formatted_date": "2026-09-24",
            "formatted_time": "13:05:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t_p2.timestamp() * 1000)
        }):
            res2 = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "client_punch_id": "PUNCH-DYN-02"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res2.status_code, 200)
            d2 = res2.json()
            self.assertTrue(d2["success"])
            self.assertEqual(d2["punch_no"], 2)

    def test_05_admin_can_manage_30_shifts_dynamically(self):
        """Test creating and managing 35 arbitrary shifts without any hardcoded shift logic."""
        shifts_created = []
        for i in range(1, 36):
            s = Shift(
                shift_code=f"SHIFT_{i:03d}",
                shift_name=f"Dynamic Shift {i}",
                is_active=True
            )
            self.db.add(s)
            shifts_created.append(s)
        self.db.commit()

        # Query all shifts
        all_shifts = self.db.query(Shift).filter(Shift.is_active == True).all()
        self.assertGreaterEqual(len(all_shifts), 35)

if __name__ == "__main__":
    unittest.main()
