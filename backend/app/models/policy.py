import enum
from datetime import datetime, time, date
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Date, Time, ForeignKey, Text, Float, Enum, JSON, LargeBinary
from sqlalchemy.orm import relationship
from app.database import Base

class DayType(str, enum.Enum):
    NORMAL = "NORMAL"
    HOLIDAY = "HOLIDAY"
    WEEK_OFF = "WEEK_OFF"
    SPECIAL_WORKING_DAY = "SPECIAL_WORKING_DAY"

class EventType(str, enum.Enum):
    IN = "IN"
    OUT = "OUT"

class PunchWindowMode(str, enum.Enum):
    STRICT = "STRICT"
    FLEXIBLE = "FLEXIBLE"
    BLOCKED = "BLOCKED"

class AttendancePolicy(Base):
    __tablename__ = "attendance_policies"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    name = Column(String(128), nullable=False, unique=True)
    description = Column(Text, nullable=True)
    
    # Missed Punch Config
    missed_punch_enabled = Column(Boolean, default=True, nullable=False)
    missed_punch_requires_face = Column(Boolean, default=True, nullable=False)
    missed_punch_requires_liveness = Column(Boolean, default=True, nullable=False)
    missed_punch_requires_gps = Column(Boolean, default=True, nullable=False)
    missed_punch_requires_approval = Column(Boolean, default=True, nullable=False)
    
    # Rules & Enforcement
    allow_out_of_sequence = Column(Boolean, default=False, nullable=False)
    duplicate_punch_policy = Column(String(64), default="REJECT", nullable=False) # REJECT, IGNORE
    absence_calculation_mode = Column(String(64), default="SESSION_BASED", nullable=False)
    half_day_enabled = Column(Boolean, default=True, nullable=False)
    full_day_absence_enabled = Column(Boolean, default=True, nullable=False)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    shifts = relationship("Shift", back_populates="attendance_policy")

class DayTypePolicy(Base):
    __tablename__ = "day_type_policies"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    day_type = Column(Enum(DayType), default=DayType.NORMAL, nullable=False)
    punch_window_mode = Column(Enum(PunchWindowMode), default=PunchWindowMode.STRICT, nullable=False)
    face_required = Column(Boolean, default=True, nullable=False)
    liveness_required = Column(Boolean, default=True, nullable=False)
    gps_required = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    shifts = relationship("Shift", back_populates="day_type_policy")

class ShiftEvent(Base):
    __tablename__ = "shift_events"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="CASCADE"), nullable=False, index=True)
    sequence_no = Column(Integer, nullable=False) # 1, 2, 3, ... N
    session_id = Column(Integer, default=1, nullable=False) # Session 1, Session 2 ...
    event_type = Column(Enum(EventType), nullable=False) # IN or OUT
    event_name = Column(String(128), nullable=True) # e.g. "IN #1", "OUT #1"
    
    window_start = Column(Time, nullable=False)
    window_end = Column(Time, nullable=False)
    grace_period_seconds = Column(Integer, default=300, nullable=False) # default 5 mins
    is_required = Column(Boolean, default=True, nullable=False)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    shift = relationship("Shift", back_populates="events")

class MissedPunchRequest(Base):
    __tablename__ = "missed_punch_requests"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="SET NULL"), nullable=True)
    shift_event_id = Column(Integer, ForeignKey("shift_events.id", ondelete="CASCADE"), nullable=False, index=True)
    attendance_date = Column(Date, nullable=False, index=True, default=date.today)
    requested_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    reason = Column(Text, nullable=False)
    
    face_status = Column(String(32), default="PASSED", nullable=False)
    liveness_status = Column(String(32), default="PASSED", nullable=False)
    gps_status = Column(String(32), default="PASSED", nullable=False)
    
    approval_status = Column(String(32), default="PENDING", nullable=False) # PENDING, APPROVED, REJECTED
    approved_by = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    approved_at = Column(DateTime, nullable=True)
    admin_notes = Column(Text, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", foreign_keys=[user_id], backref="missed_punch_requests")
    approver = relationship("User", foreign_keys=[approved_by])
    shift_event = relationship("ShiftEvent")

class AttendanceDailySummary(Base):
    __tablename__ = "attendance_daily_summary"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    attendance_date = Column(Date, nullable=False, index=True)
    day_type = Column(Enum(DayType), default=DayType.NORMAL, nullable=False)
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="SET NULL"), nullable=True)
    
    total_expected_events = Column(Integer, default=0, nullable=False)
    completed_events = Column(Integer, default=0, nullable=False)
    missed_events = Column(Integer, default=0, nullable=False)
    approved_missed_events = Column(Integer, default=0, nullable=False)
    
    attendance_status = Column(String(64), default="ABSENT", nullable=False) # FULL_DAY_PRESENT, HALF_DAY, FULL_DAY_ABSENT, HOLIDAY
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", backref="daily_summaries")
    shift = relationship("Shift")

class Holiday(Base):
    __tablename__ = "holidays"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    name = Column(String(128), nullable=False)
    holiday_date = Column(Date, nullable=False, unique=True, index=True)
    description = Column(Text, nullable=True)
    is_optional = Column(Boolean, default=False, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

class WeeklyOffConfig(Base):
    __tablename__ = "weekly_off_configs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    day_of_week = Column(Integer, nullable=False) # 0=Monday, 6=Sunday
    day_name = Column(String(32), nullable=False)
    is_weekly_off = Column(Boolean, default=True, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

class ExtraWorkRequest(Base):
    __tablename__ = "extra_work_requests"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    work_date = Column(Date, nullable=False, index=True)
    start_time = Column(String(16), nullable=False)
    end_time = Column(String(16), nullable=False)
    hours = Column(Float, default=0.0, nullable=False)
    location_name = Column(String(255), nullable=True)
    remarks = Column(Text, nullable=True)
    status = Column(String(32), default="PENDING", nullable=False) # PENDING, APPROVED, REJECTED
    evidence_image = Column(LargeBinary, nullable=True)
    reviewed_by_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    admin_notes = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", foreign_keys=[user_id], backref="extra_work_requests")
    reviewer = relationship("User", foreign_keys=[reviewed_by_id])

