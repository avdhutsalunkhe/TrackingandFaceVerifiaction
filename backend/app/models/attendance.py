import enum
from datetime import datetime, date
from sqlalchemy import Column, Integer, String, DateTime, Date, ForeignKey, Numeric, Float, Enum, JSON, Text, UniqueConstraint
from sqlalchemy.orm import relationship
from app.database import Base

class AttendanceStatus(str, enum.Enum):
    PRESENT = "PRESENT"
    LATE = "LATE"

class AttemptStatus(str, enum.Enum):
    SUCCESS = "SUCCESS"
    REJECTED = "REJECTED"

class RejectionReason(str, enum.Enum):
    OUTSIDE_ASSIGNED_AREA = "OUTSIDE_ASSIGNED_AREA"
    FACE_MISMATCH = "FACE_MISMATCH"
    LIVENESS_FAILED = "LIVENESS_FAILED"
    TIME_WINDOW_CLOSED = "TIME_WINDOW_CLOSED"
    DUPLICATE_ATTENDANCE = "DUPLICATE_ATTENDANCE"
    EMPLOYEE_INACTIVE = "EMPLOYEE_INACTIVE"
    LOCATION_UNAVAILABLE = "LOCATION_UNAVAILABLE"
    GPS_ACCURACY_LOW = "GPS_ACCURACY_LOW"
    CAMERA_ERROR = "CAMERA_ERROR"
    FACE_NOT_DETECTED = "FACE_NOT_DETECTED"
    MULTIPLE_FACES = "MULTIPLE_FACES"
    FACE_QUALITY_FAILED = "FACE_QUALITY_FAILED"
    CAPTURE_NOT_READY = "CAPTURE_NOT_READY"
    NO_FACE_ENROLLED = "NO_FACE_ENROLLED"
    NO_GEOFENCE_ASSIGNED = "NO_GEOFENCE_ASSIGNED"
    NO_SHIFT_ASSIGNED = "NO_SHIFT_ASSIGNED"
    BIOMETRIC_SERVICE_ERROR = "BIOMETRIC_SERVICE_ERROR"
    UNAUTHORIZED = "UNAUTHORIZED"
    OFFLINE_SYNC_EXPIRED = "OFFLINE_SYNC_EXPIRED"

class Attendance(Base):
    __tablename__ = "attendance"
    __table_args__ = (
        UniqueConstraint("user_id", "attendance_date", "verification_no", name="uq_user_date_verification"),
    )

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    attendance_date = Column(Date, nullable=False, index=True, default=date.today)
    verification_no = Column(Integer, nullable=False, default=1)
    punch_period_id = Column(Integer, ForeignKey("shift_punch_periods.id", ondelete="SET NULL"), nullable=True, index=True)
    verification_rule_id = Column(Integer, ForeignKey("shift_rules.id", ondelete="SET NULL"), nullable=True, index=True)
    verification_window = Column(String(64), nullable=False, default="08:00:00 - 09:00:00")
    timestamp = Column(DateTime, nullable=False, default=datetime.utcnow)
    server_time = Column(DateTime, nullable=False, default=datetime.utcnow)
    device_wall_time = Column(String(64), nullable=True)
    status = Column(Enum(AttendanceStatus), default=AttendanceStatus.PRESENT, nullable=False)
    verification_status = Column(String(32), nullable=False, default="CONFIRMED") # CONFIRMED, REVIEW_REQUIRED, REJECTED
    source = Column(String(32), nullable=False, default="ONLINE") # ONLINE, OFFLINE
    client_punch_id = Column(String(128), unique=True, index=True, nullable=True)
    sync_status = Column(String(32), nullable=False, default="SYNCED") # SYNCED, PENDING_SYNC
    sync_notes = Column(Text, nullable=True)
    
    # Shift integration
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="SET NULL"), nullable=True, index=True)
    attendance_classification = Column(String(64), nullable=True, default="VERIFICATION_1")

    # Verification Mode: FACE or REQUEST_APPROVAL
    verification_mode = Column(String(32), default="FACE", nullable=False) # FACE or REQUEST_APPROVAL
    attendance_request_id = Column(Integer, ForeignKey("attendance_requests.id", ondelete="SET NULL"), nullable=True, index=True)

    verified_latitude = Column(Numeric(11, 8), nullable=False)
    verified_longitude = Column(Numeric(11, 8), nullable=False)
    verified_distance_meters = Column(Float, nullable=False)
    gps_accuracy = Column(Float, nullable=True)
    
    face_similarity_score = Column(Float, nullable=False, default=1.0)
    face_result = Column(String(32), nullable=False, default="MATCH")
    liveness_score = Column(Float, nullable=False, default=1.0)
    liveness_result = Column(String(32), nullable=False, default="REAL")
    device_id = Column(String(128), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="attendances")
    shift = relationship("Shift", backref="attendance_records")
    punch_period = relationship("ShiftPunchPeriod", backref="attendance_records")
    verification_rule = relationship("ShiftRule", backref="attendance_records")
    attendance_request = relationship("AttendanceRequest", backref="created_attendance")

class AttendanceAttempt(Base):
    __tablename__ = "attendance_attempts"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    punch_period_id = Column(Integer, ForeignKey("shift_punch_periods.id", ondelete="SET NULL"), nullable=True, index=True)
    verification_no = Column(Integer, nullable=True)
    verification_rule_id = Column(Integer, ForeignKey("shift_rules.id", ondelete="SET NULL"), nullable=True, index=True)
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    attempt_status = Column(Enum(AttemptStatus), nullable=False)
    rejection_reason = Column(Enum(RejectionReason), nullable=True)
    source = Column(String(32), nullable=False, default="ONLINE")
    
    latitude = Column(Numeric(11, 8), nullable=True)
    longitude = Column(Numeric(11, 8), nullable=True)
    calculated_distance_meters = Column(Float, nullable=True)
    gps_accuracy = Column(Float, nullable=True)
    
    face_similarity_score = Column(Float, nullable=True)
    liveness_result = Column(String(32), nullable=True) # REAL or SPOOF or FAILED
    liveness_score = Column(Float, nullable=True)
    
    device_id = Column(String(128), nullable=True)
    request_id = Column(String(64), nullable=True, index=True)
    client_punch_id = Column(String(128), nullable=True)
    details = Column(JSON, nullable=True)

    user = relationship("User", back_populates="attendance_attempts")

class Device(Base):
    __tablename__ = "devices"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    device_id = Column(String(128), nullable=False, index=True)
    device_model = Column(String(128), nullable=True)
    os_version = Column(String(64), nullable=True)
    is_trusted = Column(Integer, default=1, nullable=False)
    last_used_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="devices")
