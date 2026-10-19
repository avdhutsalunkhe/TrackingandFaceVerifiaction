from datetime import datetime, time
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Numeric, Float, Time, JSON
from sqlalchemy.orm import relationship
from app.database import Base

class Geofence(Base):
    __tablename__ = "geofences"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    location_name = Column(String(128), nullable=False)
    latitude = Column(Numeric(11, 8), nullable=False)
    longitude = Column(Numeric(11, 8), nullable=False)
    radius_meters = Column(Float, nullable=False, default=100.0)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="geofence")

class AttendanceWindow(Base):
    __tablename__ = "attendance_windows"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    start_time = Column(Time, nullable=False, default=time(9, 0)) # e.g. 09:00:00
    end_time = Column(Time, nullable=False, default=time(18, 0))   # e.g. 18:00:00
    timezone = Column(String(64), nullable=False, default="Asia/Kolkata")
    allowed_days = Column(JSON, nullable=True) # e.g. [1, 2, 3, 4, 5, 6] (Mon-Sat)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="attendance_window")
