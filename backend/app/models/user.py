import enum
from datetime import datetime
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Enum
from sqlalchemy.orm import relationship
from app.database import Base

class UserRole(str, enum.Enum):
    ADMIN = "ADMIN"
    USER = "USER"
    TIME_OFFICE = "TIME_OFFICE"

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    employee_id = Column(String(64), unique=True, index=True, nullable=False)
    full_name = Column(String(128), nullable=False)
    password_hash = Column(String(255), nullable=False)
    role = Column(Enum(UserRole), default=UserRole.USER, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    must_change_password = Column(Boolean, default=True, nullable=False)
    department = Column(String(128), nullable=True)
    department_id = Column(Integer, nullable=True)
    unit_number = Column(Integer, nullable=True)
    designation = Column(String(128), nullable=True)

    # Feature Toggles (Independent per-employee controls)
    face_enabled = Column(Boolean, default=True, nullable=False)
    geofence_enabled = Column(Boolean, default=True, nullable=False)
    shift_enabled = Column(Boolean, default=True, nullable=False)
    travel_map_enabled = Column(Boolean, default=True, nullable=False)
    device_binding_enabled = Column(Boolean, default=True, nullable=False)

    # Device ID Registration (Hardware binding)
    device_id = Column(String(128), nullable=True, unique=True, index=True)
    device_registered_at = Column(DateTime, nullable=True)
    device_model = Column(String(128), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)


    # Relationships
    face_template = relationship("FaceTemplate", back_populates="user", uselist=False, cascade="all, delete-orphan")
    enrollment_samples = relationship("FaceEnrollmentSample", back_populates="user", cascade="all, delete-orphan")
    geofence = relationship("Geofence", back_populates="user", uselist=False, cascade="all, delete-orphan")
    attendance_window = relationship("AttendanceWindow", back_populates="user", uselist=False, cascade="all, delete-orphan")
    attendances = relationship("Attendance", back_populates="user", cascade="all, delete-orphan")
    attendance_attempts = relationship("AttendanceAttempt", back_populates="user", cascade="all, delete-orphan")
    devices = relationship("Device", back_populates="user", cascade="all, delete-orphan")
