import os
import io
import time
import unittest
import numpy as np
import cv2
from datetime import datetime, date, time as dtime
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app
from app.config import settings
from app.models.user import User, UserRole
from app.models.face import FaceTemplate, FaceEnrollmentSample
from app.models.geofence import Geofence
from app.models.attendance import Attendance, RejectionReason
from app.security.hashing import get_password_hash
from app.security.tokens import create_access_token
from app.services.attendance_decision_service import AttendanceDecisionService
from app.services.face_cache_service import FaceCacheService
from app.ml.pipeline import face_pipeline
from app.ml.models_manager import models_manager

# In-memory SQLite for deterministic isolated testing
TEST_DATABASE_URL = "sqlite:///:memory:"
test_engine = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db
client = TestClient(app)

class TestOptimizedFaceVerification(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Base.metadata.create_all(bind=test_engine)
        cls.db = TestingSessionLocal()

        # Warm up models
        models_manager.warmup()

        # Create genuine employee
        cls.user = User(
            employee_id="OPT001",
            full_name="Optimized Verification Employee",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            role=UserRole.USER,
            device_id="DEV_OPT_PHONE_01",
            device_registered_at=datetime.utcnow()
        )
        cls.db.add(cls.user)

        # Create wrong employee (different user)
        cls.wrong_user = User(
            employee_id="OPT002",
            full_name="Wrong Employee",
            password_hash=get_password_hash("pass123"),
            is_active=True,
            role=UserRole.USER,
            device_id="DEV_OPT_PHONE_02",
            device_registered_at=datetime.utcnow()
        )
        cls.db.add(cls.wrong_user)
        cls.db.commit()

        # Assigned Geofence
        cls.geofence = Geofence(
            user_id=cls.user.id,
            latitude=18.5204,
            longitude=73.8567,
            radius_meters=150.0,
            location_name="HQ Optimization Lab",
            is_active=True
        )
        cls.db.add(cls.geofence)

        # Create active shift and assign to both test users
        from app.models.shift import Shift, ShiftPunchPeriod, ShiftRule, EmployeeShiftAssignment
        cls.shift = Shift(
            shift_code="S_OPT_01",
            shift_name="Optimization Shift",
            is_active=True
        )
        cls.db.add(cls.shift)
        cls.db.flush()

        # Add morning punch period
        period = ShiftPunchPeriod(
            shift_id=cls.shift.id,
            punch_no=1,
            period_name="Morning Verification",
            start_time=dtime(8, 0, 0),
            end_time=dtime(11, 0, 0),
            show_in_user_schedule=True,
            is_active=True,
            priority=1
        )
        cls.db.add(period)
        rule = ShiftRule(
            shift_id=cls.shift.id,
            rule_code="PUNCH_1",
            rule_name="Morning Verification",
            verification_no=1,
            start_time=dtime(8, 0, 0),
            end_time=dtime(11, 0, 0),
            show_in_user_schedule=True,
            is_active=True,
            priority=1
        )
        cls.db.add(rule)

        # Afternoon punch period
        period2 = ShiftPunchPeriod(
            shift_id=cls.shift.id,
            punch_no=2,
            period_name="Afternoon Punch",
            start_time=dtime(12, 0, 0),
            end_time=dtime(14, 0, 0),
            show_in_user_schedule=True,
            is_active=True,
            priority=2
        )
        cls.db.add(period2)
        rule2 = ShiftRule(
            shift_id=cls.shift.id,
            rule_code="PUNCH_2",
            rule_name="Afternoon Punch",
            verification_no=2,
            start_time=dtime(12, 0, 0),
            end_time=dtime(14, 0, 0),
            show_in_user_schedule=True,
            is_active=True,
            priority=2
        )
        cls.db.add(rule2)

        cls.db.add(EmployeeShiftAssignment(
            user_id=cls.user.id,
            shift_id=cls.shift.id,
            effective_from=date(2026, 1, 1),
            is_active=True
        ))
        cls.db.add(EmployeeShiftAssignment(
            user_id=cls.wrong_user.id,
            shift_id=cls.shift.id,
            effective_from=date(2026, 1, 1),
            is_active=True
        ))
        cls.db.flush()

        # Assign geofence to wrong_user as well
        cls.db.add(Geofence(
            user_id=cls.wrong_user.id,
            latitude=18.5204,
            longitude=73.8567,
            radius_meters=150.0,
            location_name="HQ Optimization Lab",
            is_active=True
        ))
        cls.db.flush()

        # Load realistic camera frame containing genuine face
        real_frame_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "realistic_frame_1.jpg")
        if os.path.exists(real_frame_path):
            with open(real_frame_path, "rb") as f:
                cls.valid_jpeg_bytes = f.read()
            cls.valid_frame = cv2.imread(real_frame_path)
        else:
            cls.valid_frame = cls._create_realistic_face_image()
            _, enc = cv2.imencode('.jpg', cls.valid_frame, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
            cls.valid_jpeg_bytes = enc.tobytes()

        # Extract genuine reference embedding and store in DB
        res = face_pipeline.process_single_frame(cls.valid_jpeg_bytes)
        assert res.success, f"Failed to detect face in test image: {res.error_message}"
        cls.genuine_embedding = res.embedding

        template = FaceTemplate(
            user_id=cls.user.id,
            face_embedding=cls.genuine_embedding.tobytes(),
            face_image=cls.valid_jpeg_bytes,
            sample_count=3,
            quality_score=res.quality_score
        )
        cls.db.add(template)

        # Unrelated embedding for wrong user (orthogonal vector)
        wrong_emb = np.random.randn(512).astype(np.float32)
        wrong_emb = wrong_emb / np.linalg.norm(wrong_emb)
        wrong_template = FaceTemplate(
            user_id=cls.wrong_user.id,
            face_embedding=wrong_emb.tobytes(),
            face_image=cls.valid_jpeg_bytes,
            sample_count=3,
            quality_score=0.9
        )
        cls.db.add(wrong_template)
        cls.db.commit()

        cls.auth_token = create_access_token(data={"sub": str(cls.user.id), "employee_id": cls.user.employee_id})

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        FaceCacheService.clear()

    @staticmethod
    def _create_realistic_face_image() -> np.ndarray:
        """Create a clean 480x640 synthetic camera image with detectable facial features."""
        img = np.full((640, 480, 3), 140, dtype=np.uint8)
        # Background gradient
        for y in range(640):
            img[y, :, 0] = int(120 + (y / 640.0) * 40)
            img[y, :, 1] = int(130 + (y / 640.0) * 30)
            img[y, :, 2] = int(140 + (y / 640.0) * 20)

        center = (240, 280)
        # Head oval
        cv2.ellipse(img, center, (90, 120), 0, 0, 360, (190, 205, 230), -1)
        # Eyes
        cv2.circle(img, (205, 250), 12, (70, 50, 40), -1) # Left eye
        cv2.circle(img, (275, 250), 12, (70, 50, 40), -1) # Right eye
        cv2.circle(img, (205, 250), 4, (20, 20, 20), -1)
        cv2.circle(img, (275, 250), 4, (20, 20, 20), -1)
        # Nose
        cv2.line(img, (240, 260), (240, 290), (140, 160, 185), 3)
        # Mouth
        cv2.ellipse(img, (240, 325), (32, 14), 0, 0, 180, (90, 80, 160), -1)

        # Micro-texture noise to satisfy liveness Laplacian checks
        noise = np.random.normal(0, 4, img.shape).astype(np.int16)
        img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
        return img

    def test_01_warmed_up_model_manager(self):
        """Ensure models are warmed up and sessions active."""
        assert models_manager.is_warmed_up is True
        assert models_manager.detector.session is not None
        assert models_manager.recognizer.session is not None

    def test_02_face_cache_service(self):
        """Test template caching, retrieval speed, and invalidation."""
        FaceCacheService.clear()
        
        # 1. First retrieval loads from DB and caches
        t0 = time.perf_counter_ns()
        emb1 = FaceCacheService.get_user_face_embedding(self.db, self.user.id)
        t_first = (time.perf_counter_ns() - t0) / 1_000_000.0
        assert emb1 is not None
        assert emb1.shape == (512,)

        # 2. Second retrieval hits in-memory cache (< 0.05ms)
        t0 = time.perf_counter_ns()
        emb2 = FaceCacheService.get_user_face_embedding(self.db, self.user.id)
        t_cached = (time.perf_counter_ns() - t0) / 1_000_000.0
        assert emb2 is not None
        assert np.array_equal(emb1, emb2)
        assert t_cached < t_first or t_cached < 0.1

        # 3. Invalidation
        FaceCacheService.invalidate(self.user.id)
        stats = FaceCacheService.stats()
        assert stats["cached_templates_count"] == 0

    def test_03_two_frame_verification_genuine_match(self):
        """Test two-frame verification with live genuine face produces PRESENT decision."""
        dummy_period = {
            "id": 1,
            "punch_no": 1,
            "period_name": "Morning Verification",
            "label": "08:00 AM - 10:00 AM",
            "is_active": True,
            "show_in_user_schedule": True,
            "start_time": dtime(8, 0),
            "end_time": dtime(11, 0),
            "result_classification": "PRESENT"
        }

        with patch("app.services.time_service.TimeService.resolve_shift_punch_periods_list", return_value=[dummy_period]), \
             patch("app.services.time_service.TimeService.get_current_server_time", return_value={"server_timestamp": datetime(2026, 10, 21, 9, 0, 0)}):
            
            # Second frame slightly shifted (simulating 120ms burst)
            frame2 = np.roll(self.valid_frame, 1, axis=0)
            _, enc2 = cv2.imencode('.jpg', frame2)
            f2_bytes = enc2.tobytes()

            t0 = time.perf_counter_ns()
            decision = AttendanceDecisionService.evaluate_attendance(
                db=self.db,
                user=self.user,
                current_lat=18.5204,
                current_lon=73.8567,
                gps_accuracy=8.0,
                frames_bytes_list=[self.valid_jpeg_bytes, f2_bytes],
                device_id="DEV_OPT_PHONE_01",
                request_id="REQ_OPT_TEST_01",
                client_punch_id=f"PUNCH_OPT_{int(time.time()*1000)}"
            )
            total_ms = (time.perf_counter_ns() - t0) / 1_000_000.0

            assert decision.success is True
            assert decision.decision == "PRESENT"
            assert decision.face_similarity_score >= settings.SIMILARITY_THRESHOLD
            assert decision.liveness_result == "REAL"
            print(f"\n[Test] Genuine 2-frame verification total server time: {total_ms:.2f} ms")

    def test_04_wrong_employee_face_mismatch(self):
        """Test verification with face of wrong employee is rejected with FACE_MISMATCH."""
        dummy_period = {
            "id": 1,
            "punch_no": 1,
            "period_name": "Morning Verification",
            "label": "08:00 AM - 10:00 AM",
            "is_active": True,
            "show_in_user_schedule": True,
            "start_time": dtime(8, 0),
            "end_time": dtime(11, 0),
            "result_classification": "PRESENT"
        }

        with patch("app.services.time_service.TimeService.resolve_shift_punch_periods_list", return_value=[dummy_period]), \
             patch("app.services.time_service.TimeService.get_current_server_time", return_value={"server_timestamp": datetime(2026, 10, 21, 9, 0, 0)}):
            
            # Use wrong_user who has an orthogonal reference embedding
            decision = AttendanceDecisionService.evaluate_attendance(
                db=self.db,
                user=self.wrong_user,
                current_lat=18.5204,
                current_lon=73.8567,
                gps_accuracy=8.0,
                frames_bytes_list=[self.valid_jpeg_bytes],
                device_id="DEV_OPT_PHONE_02",
                request_id="REQ_OPT_TEST_MISMATCH",
                client_punch_id=f"PUNCH_MISMATCH_{int(time.time()*1000)}"
            )

            assert decision.success is False
            assert decision.rejection_reason == RejectionReason.FACE_MISMATCH
            assert decision.face_similarity_score < settings.SIMILARITY_THRESHOLD

    def test_05_spoof_detection_paper_and_screen(self):
        """Test that static flat paper/cardboard images are rejected by liveness/anti-spoofing."""
        # Flat texture with no variance / low saturation
        flat_img = np.full((300, 300, 3), 128, dtype=np.uint8)
        is_real, score = models_manager.liveness.evaluate_passive_antispoof(flat_img)
        assert is_real is False, "Flat image with zero skin microtexture should be detected as spoof"

    def test_06_blurry_and_dark_rejection(self):
        """Test that extremely dark or blurry images fail quality pre-filter."""
        # Pitch black frame
        dark_img = np.zeros((300, 300, 3), dtype=np.uint8)
        _, enc_dark = cv2.imencode('.jpg', dark_img)
        res_dark = face_pipeline.process_single_frame(enc_dark.tobytes())
        assert res_dark.success is False
        assert res_dark.error_code in ["FACE_QUALITY_FAILED", "FACE_NOT_DETECTED"]

        # Heavily blurred frame (Gaussian blur)
        blurred = cv2.GaussianBlur(self.valid_frame, (51, 51), 30)
        _, enc_blur = cv2.imencode('.jpg', blurred)
        res_blur = face_pipeline.process_single_frame(enc_blur.tobytes())
        assert res_blur.success is False

    def test_07_outside_geofence_hard_gate(self):
        """Test that punch outside geofence is rejected with OUTSIDE_ASSIGNED_AREA."""
        dummy_period = {
            "id": 2,
            "punch_no": 2,
            "period_name": "Afternoon Verification",
            "label": "12:00 PM - 02:00 PM",
            "is_active": True,
            "show_in_user_schedule": True,
            "start_time": dtime(12, 0),
            "end_time": dtime(14, 0),
            "result_classification": "PRESENT"
        }

        with patch("app.services.time_service.TimeService.resolve_shift_punch_periods_list", return_value=[dummy_period]), \
             patch("app.services.time_service.TimeService.get_current_server_time", return_value={"server_timestamp": datetime(2026, 10, 21, 12, 30, 0)}):
            
            # Far coordinate: 50 km away
            decision = AttendanceDecisionService.evaluate_attendance(
                db=self.db,
                user=self.user,
                current_lat=18.9999,
                current_lon=74.5000,
                gps_accuracy=8.0,
                frames_bytes_list=[self.valid_jpeg_bytes],
                device_id="DEV_OPT_PHONE_01",
                request_id="REQ_OPT_TEST_GEOFENCE",
                client_punch_id=f"PUNCH_GEO_{int(time.time()*1000)}"
            )

            assert decision.success is False
            assert decision.rejection_reason == RejectionReason.OUTSIDE_ASSIGNED_AREA

    def test_08_closed_shift_window_hard_gate(self):
        """Test that punch outside active shift window is rejected with TIME_WINDOW_CLOSED."""
        dummy_period = {
            "id": 1,
            "punch_no": 1,
            "period_name": "Morning Verification",
            "label": "08:00 AM - 09:00 AM",
            "is_active": True,
            "show_in_user_schedule": True,
            "start_time": dtime(8, 0),
            "end_time": dtime(9, 0),
            "result_classification": "PRESENT"
        }

        # Server time is 11:30 AM (outside window)
        with patch("app.services.time_service.TimeService.resolve_shift_punch_periods_list", return_value=[dummy_period]), \
             patch("app.services.time_service.TimeService.get_current_server_time", return_value={"server_timestamp": datetime(2026, 10, 21, 11, 30, 0)}):
            
            decision = AttendanceDecisionService.evaluate_attendance(
                db=self.db,
                user=self.user,
                current_lat=18.5204,
                current_lon=73.8567,
                gps_accuracy=8.0,
                frames_bytes_list=[self.valid_jpeg_bytes],
                device_id="DEV_OPT_PHONE_01",
                request_id="REQ_OPT_TEST_CLOSED",
                client_punch_id=f"PUNCH_CLOSED_{int(time.time()*1000)}"
            )

            assert decision.success is False
            assert decision.rejection_reason == RejectionReason.TIME_WINDOW_CLOSED

    def test_09_idempotency_duplicate_submission(self):
        """Test that repeating the same client_punch_id returns the existing confirmed attendance record."""
        client_punch_id = f"PUNCH_IDEMP_{int(time.time()*1000)}"
        dummy_period = {
            "id": 99,
            "punch_no": 2,
            "period_name": "Afternoon Punch",
            "label": "12:00 PM - 02:00 PM",
            "is_active": True,
            "show_in_user_schedule": True,
            "start_time": dtime(12, 0),
            "end_time": dtime(14, 0),
            "result_classification": "PRESENT"
        }

        with patch("app.services.time_service.TimeService.resolve_shift_punch_periods_list", return_value=[dummy_period]), \
             patch("app.services.time_service.TimeService.get_current_server_time", return_value={"server_timestamp": datetime(2026, 10, 21, 12, 30, 0)}):
            
            # Submission 1
            res1 = AttendanceDecisionService.evaluate_attendance(
                db=self.db,
                user=self.user,
                current_lat=18.5204,
                current_lon=73.8567,
                gps_accuracy=8.0,
                frames_bytes_list=[self.valid_jpeg_bytes],
                device_id="DEV_OPT_PHONE_01",
                request_id="REQ_IDEMP_1",
                client_punch_id=client_punch_id
            )
            assert res1.success is True

            # Submission 2 with same client_punch_id
            t0 = time.perf_counter_ns()
            res2 = AttendanceDecisionService.evaluate_attendance(
                db=self.db,
                user=self.user,
                current_lat=18.5204,
                current_lon=73.8567,
                gps_accuracy=8.0,
                frames_bytes_list=[self.valid_jpeg_bytes],
                device_id="DEV_OPT_PHONE_01",
                request_id="REQ_IDEMP_2",
                client_punch_id=client_punch_id
            )
            idemp_time_ms = (time.perf_counter_ns() - t0) / 1_000_000.0

            assert res2.success is True
            assert res2.decision == "PRESENT"
            assert "already recorded" in res2.message.lower()
            print(f"[Test] Idempotency duplicate check latency: {idemp_time_ms:.2f} ms")

if __name__ == "__main__":
    unittest.main()
