from datetime import datetime, date
from sqlalchemy import (
    Column,
    Integer,
    BigInteger,
    String,
    DateTime,
    Date,
    ForeignKey,
    Numeric,
    Float,
    Index,
    Text,
)
from sqlalchemy.orm import relationship, foreign
from app.database import Base


class TrackingSession(Base):
    """Represents a continuous GPS tracking journey associated with an attendance session/shift.
    Updated in-place to maintain journey summary without unnecessary row explosion."""
    __tablename__ = "tracking_sessions"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    session_uuid = Column(String(64), unique=True, index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    attendance_id = Column(BigInteger, nullable=True, index=True)
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="SET NULL"), nullable=True, index=True)
    work_date = Column(Date, nullable=False, index=True, default=date.today)
    
    start_time = Column(DateTime, nullable=False, default=datetime.utcnow)
    end_time = Column(DateTime, nullable=True)
    status = Column(String(32), nullable=False, default="RECORDING")  # RECORDING, PAUSED, COMPLETED, INTERRUPTED
    
    start_latitude = Column(Numeric(11, 8), nullable=True)
    start_longitude = Column(Numeric(11, 8), nullable=True)
    end_latitude = Column(Numeric(11, 8), nullable=True)
    end_longitude = Column(Numeric(11, 8), nullable=True)
    
    total_distance_meters = Column(Float, nullable=False, default=0.0)
    total_duration_seconds = Column(Integer, nullable=False, default=0)
    retained_point_count = Column(Integer, nullable=False, default=0)

    # Minimal recovery & health state
    last_accepted_latitude = Column(Numeric(11, 8), nullable=True)
    last_accepted_longitude = Column(Numeric(11, 8), nullable=True)
    last_accepted_time = Column(DateTime, nullable=True)
    last_sync_time = Column(DateTime, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", backref="tracking_sessions")
    attendance = relationship("Attendance", primaryjoin="foreign(TrackingSession.attendance_id) == Attendance.id", uselist=False, viewonly=True)
    shift = relationship("Shift", backref="tracking_sessions")
    route_points = relationship(
        "GpsRoutePoint",
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="GpsRoutePoint.sequence_number.asc()",
    )
    chunks = relationship(
        "TrackingRouteChunk",
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="TrackingRouteChunk.chunk_sequence.asc()",
    )


class TrackingRouteChunk(Base):
    """Production Storage-Efficient Model: Stores compressed route chunks containing retained vertices.
    Reduces permanent database row count and storage growth by over 95% compared to raw per-point records."""
    __tablename__ = "tracking_route_chunks"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    chunk_uuid = Column(String(64), unique=True, index=True, nullable=False)
    session_id = Column(Integer, ForeignKey("tracking_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    chunk_sequence = Column(Integer, nullable=False)
    point_count = Column(Integer, nullable=False, default=0)
    
    # Compact JSON array of retained vertices: [[lat, lng, epochSec, acc, spd, bearing, is_gap], ...]
    encoded_geometry = Column(Text, nullable=False)
    
    start_time = Column(DateTime, nullable=False)
    end_time = Column(DateTime, nullable=False)
    distance_meters = Column(Float, nullable=False, default=0.0)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    session = relationship("TrackingSession", back_populates="chunks")

    __table_args__ = (
        Index("idx_chunk_session_seq", "session_id", "chunk_sequence", unique=True),
        Index("idx_chunk_created", "created_at"),
    )


class GpsRoutePoint(Base):
    """Legacy/High-Resolution table for storing individual GPS coordinates (diagnostic/backward-compatible)."""
    __tablename__ = "gps_route_points"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("tracking_sessions.id", ondelete="CASCADE"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    employee_id = Column(String(64), nullable=True, index=True)
    device_id = Column(String(128), nullable=True, index=True)
    client_point_id = Column(String(64), unique=True, index=True, nullable=False)
    sequence_number = Column(Integer, nullable=False)
    
    latitude = Column(Numeric(11, 8), nullable=False)
    longitude = Column(Numeric(11, 8), nullable=False)
    accuracy_meters = Column(Float, nullable=False)
    altitude_meters = Column(Float, nullable=True)
    speed_mps = Column(Float, nullable=True)
    bearing_degrees = Column(Float, nullable=True)
    
    recorded_at = Column(DateTime, nullable=False, index=True)
    is_gap = Column(Integer, nullable=False, default=0)
    sync_status = Column(String(32), nullable=False, default="SYNCED")
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    session = relationship("TrackingSession", back_populates="route_points")
    user = relationship("User")

    __table_args__ = (
        Index("idx_tracking_session_seq", "session_id", "sequence_number"),
        Index("idx_tracking_user_recorded", "user_id", "recorded_at"),
    )
