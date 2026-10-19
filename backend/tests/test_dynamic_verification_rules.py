import unittest
import sys
import os
import numpy as np
from datetime import datetime, date, time
import pytz

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
from app.services.shift_service import ShiftService

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

class TestDynamicMultiPeriodVerification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        app.dependency_overrides[get_db] = override_get_db
        Base.metadata.create_all(bind=engine)
        cls.db = TestingSessionLocal()

        # Create user
        cls.user = User(
            employee_id="DYNAMIC01",
            full_name="Dynamic Rule Tester",
            password_hash=get_password_hash("password123"),
            is_active=True,
            must_change_password=False,
            role=UserRole.USER
        )
        cls.db.add(cls.user)
        cls.db.commit()
        cls.db.refresh(cls.user)

        # Face template
        dummy_embedding = np.zeros(512, dtype=np.float32)
        cls.template = FaceTemplate(
            user_id=cls.user.id,
            face_embedding=dummy_embedding.tobytes(),
            face_image=b"\xff\xd8\xff\xe0dummyrefimage",
            quality_score=0.98
        )
        cls.db.add(cls.template)

        # Geofence
        cls.geofence = Geofence(
            user_id=cls.user.id,
            location_name="Field Hub",
            latitude=18.5204,
            longitude=73.8567,
            radius_meters=200.0,
            is_active=True
        )
        cls.db.add(cls.geofence)
        cls.db.commit()

        cls.user_token = create_access_token({"sub": str(cls.user.id), "role": "USER"})

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        Base.metadata.drop_all(bind=engine)
        app.dependency_overrides.clear()

    def test_01_dynamic_6_period_shift_configuration(self):
        """Test a shift configured with 6 verification periods and 1 hidden rule."""
        shift = Shift(
            shift_code="S6P",
            shift_name="6-Period Field Guard Shift",
            description="Shift with 6 face verification checkpoints",
            is_active=True
        )
        self.db.add(shift)
        self.db.flush()

        # Add 6 active user-visible rules + 1 hidden rule
        rule_times = [
            (1, "08:00:00", "08:15:00", "V1_START", "Check-in 1", True),
            (2, "10:00:00", "10:15:00", "V2_MID1", "Check-in 2", True),
            (3, "12:00:00", "12:15:00", "V3_NOON", "Check-in 3", True),
            (4, "14:00:00", "14:15:00", "V4_AFTERNOON", "Check-in 4", True),
            (5, "16:00:00", "16:15:00", "V5_TEA", "Check-in 5", True),
            (6, "18:00:00", "18:15:00", "V6_END", "Check-in 6", True),
            (7, "22:00:00", "23:00:00", "V7_INTERNAL", "Admin Internal Rule", False), # hidden
        ]

        for v_no, st, et, code, name, show in rule_times:
            r = ShiftRule(
                shift_id=shift.id,
                verification_no=v_no,
                rule_code=code,
                rule_name=name,
                start_time=ShiftService.parse_time_str(st),
                end_time=ShiftService.parse_time_str(et),
                result_code="PRESENT",
                result_classification=code,
                show_in_user_schedule=show,
                priority=v_no,
                is_active=True
            )
            self.db.add(r)
        
        # Assign user to shift
        assignment = EmployeeShiftAssignment(
            user_id=self.user.id,
            shift_id=shift.id,
            effective_from=date(2026, 1, 1),
            is_active=True
        )
        self.db.add(assignment)
        self.db.commit()

        # Check API config response
        headers = {"Authorization": f"Bearer {self.user_token}"}
        res = client.get("/api/user/attendance-config", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()

        rules = data["verification_rules"]
        # Only 6 user-visible rules should be returned in user schedule
        self.assertEqual(len(rules), 6)
        self.assertEqual(rules[0]["verification_no"], 1)
        self.assertEqual(rules[0]["rule_code"], "V1_START")
        self.assertEqual(rules[5]["verification_no"], 6)
        self.assertEqual(rules[5]["rule_code"], "V6_END")

    @patch("app.services.attendance_decision_service.face_pipeline.verify_live_sequence")
    def test_02_verify_rule_by_id_and_hidden_rule_block(self, mock_face):
        """Test verifying by rule_id and blocking hidden rules."""
        mock_face.return_value = (True, None, "Face matched", 0.96, 0.99, {})
        headers = {"Authorization": f"Bearer {self.user_token}"}

        shift = self.db.query(Shift).filter(Shift.shift_code == "S6P").first()
        r1 = next(r for r in shift.rules if r.verification_no == 1)
        r_hidden = next(r for r in shift.rules if r.show_in_user_schedule == False)

        dummy_file = ("frame.jpg", b"\xff\xd8\xff\xe0dummyjpgbytes", "image/jpeg")
        
        # Mock time during Window 1: 08:05:00
        t1 = datetime(2026, 9, 24, 8, 5, 0, tzinfo=pytz.timezone("Asia/Kolkata"))
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t1,
            "formatted_date": "2026-09-24",
            "formatted_time": "08:05:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t1.timestamp() * 1000)
        }):
            # Verify for Window 1 using verification_rule_id
            res = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "gps_accuracy": 5.0,
                    "verification_rule_id": r1.id,
                    "client_punch_id": "PUNCH-RULE-1"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res.status_code, 200)
            data = res.json()
            self.assertTrue(data["success"])
            self.assertEqual(data["decision"], "PRESENT")
            self.assertEqual(data["verification_no"], 1)

        # Mock time during hidden rule: 22:30:00
        t_hidden = datetime(2026, 9, 24, 22, 30, 0, tzinfo=pytz.timezone("Asia/Kolkata"))
        with patch.object(TimeService, 'get_current_server_time', return_value={
            "server_timestamp": t_hidden,
            "formatted_date": "2026-09-24",
            "formatted_time": "22:30:00",
            "timezone": "Asia/Kolkata",
            "epoch_ms": int(t_hidden.timestamp() * 1000)
        }):
            # Attempt to verify hidden rule -> MUST BE REJECTED
            res_h = client.post(
                "/api/user/attendance/verify",
                headers=headers,
                data={
                    "current_latitude": 18.5204,
                    "current_longitude": 73.8567,
                    "verification_rule_id": r_hidden.id,
                    "client_punch_id": "PUNCH-HIDDEN-TRY"
                },
                files=[("frames", dummy_file)]
            )
            self.assertEqual(res_h.status_code, 200)
            data_h = res_h.json()
            self.assertFalse(data_h["success"])
            self.assertEqual(data_h["decision"], "REJECTED")
            self.assertIn("not enabled for user verification", data_h["message"].lower())

if __name__ == "__main__":
    unittest.main()
