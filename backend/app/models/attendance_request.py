import enum
from datetime import datetime, date
from sqlalchemy import Column, Integer, String, DateTime, Date, ForeignKey, Numeric, Float, Enum, LargeBinary
from sqlalchemy.orm import relationship
from app.database import Base

class RequestStatus(str, enum.Enum):
    PENDING = "PENDING"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"

class AttendanceRequest(Base):
    __tablename__ = "attendance_requests"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    request_date = Column(Date, nullable=False, index=True, default=date.today)
    verification_no = Column(Integer, nullable=False, default=1)
    client_request_id = Column(String(128), nullable=True, index=True)
    
    # Server-Authoritative Timestamp (phone clock is never trusted)
    server_timestamp = Column(DateTime, nullable=False, default=datetime.utcnow, index=True)
    device_timestamp = Column(String(64), nullable=True) # Stored for audit / clock skew detection

    # Shift integration
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="SET NULL"), nullable=True, index=True)
    
    # Request status & reason
    status = Column(Enum(RequestStatus), default=RequestStatus.PENDING, nullable=False, index=True)
    rejection_reason_trigger = Column(String(128), nullable=True, default="FACE_MISMATCH") # Why normal punch failed
    
    # GPS & Location Telemetry
    latitude = Column(Numeric(11, 8), nullable=False)
    longitude = Column(Numeric(11, 8), nullable=False)
    gps_accuracy = Column(Float, nullable=True)
    location_name = Column(String(255), nullable=True)
    assigned_location_name = Column(String(255), nullable=True)
    distance_from_location = Column(Float, nullable=False) # In meters, calculated by server
    is_within_geofence = Column(Integer, default=1, nullable=False) # 1 if distance <= radius, 0 otherwise

    # Evidence Selfie with Bottom-Left Watermark Overlay (stored as JPEG bytes)
    evidence_image = Column(LargeBinary, nullable=False)

    # Admin review details
    admin_notes = Column(String(512), nullable=True)
    reviewed_by_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)
    reviewed_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", foreign_keys=[user_id], backref="attendance_requests")
    reviewed_by = relationship("User", foreign_keys=[reviewed_by_user_id])
    shift = relationship("Shift", backref="attendance_requests")
