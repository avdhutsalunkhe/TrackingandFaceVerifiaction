from datetime import datetime, time, date
from sqlalchemy import Column, Integer, String, Boolean, DateTime, Date, Time, ForeignKey, Text
from sqlalchemy.orm import relationship
from app.database import Base

class Shift(Base):
    __tablename__ = "shifts"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    shift_code = Column(String(32), unique=True, index=True, nullable=False) # e.g. "S001", "S002", "SPLIT_01"
    shift_name = Column(String(128), nullable=False) # e.g. "General Shift", "Factory Split Shift"
    description = Column(Text, nullable=True)
    timezone = Column(String(64), default="Asia/Kolkata", nullable=False)
    
    day_type_policy_id = Column(Integer, ForeignKey("day_type_policies.id", ondelete="SET NULL"), nullable=True)
    attendance_policy_id = Column(Integer, ForeignKey("attendance_policies.id", ondelete="SET NULL"), nullable=True)
    
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    punch_periods = relationship("ShiftPunchPeriod", back_populates="shift", cascade="all, delete-orphan", order_by="ShiftPunchPeriod.priority")
    rules = relationship("ShiftRule", back_populates="shift", cascade="all, delete-orphan", order_by="ShiftRule.priority")
    events = relationship("ShiftEvent", back_populates="shift", cascade="all, delete-orphan", order_by="ShiftEvent.sequence_no")
    assignments = relationship("EmployeeShiftAssignment", back_populates="shift", cascade="all, delete-orphan")
    attendance_policy = relationship("AttendancePolicy", back_populates="shifts")
    day_type_policy = relationship("DayTypePolicy", back_populates="shifts")

class ShiftPunchPeriod(Base):
    __tablename__ = "shift_punch_periods"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="CASCADE"), nullable=False, index=True)
    punch_no = Column(Integer, nullable=False, default=1)
    period_name = Column(String(128), nullable=False)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    show_in_user_schedule = Column(Boolean, default=True, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    priority = Column(Integer, default=1, nullable=False)
    require_face_verification = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    shift = relationship("Shift", back_populates="punch_periods")

    # Compatibility properties with legacy rule schema
    @property
    def rule_name(self):
        return self.period_name

    @rule_name.setter
    def rule_name(self, value):
        self.period_name = value

    @property
    def rule_code(self):
        return f"PUNCH_{self.punch_no}"

    @property
    def verification_no(self):
        return self.punch_no

    @verification_no.setter
    def verification_no(self, value):
        self.punch_no = value

    @property
    def result_code(self):
        return "PRESENT"

    @property
    def result_classification(self):
        return "PRESENT"

class ShiftRule(Base):
    __tablename__ = "shift_rules"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="CASCADE"), nullable=False, index=True)
    rule_code = Column(String(64), nullable=False) # e.g. "NORMAL_IN", "LATE_IN", "HALF_DAY"
    rule_name = Column(String(128), nullable=False)
    verification_no = Column(Integer, nullable=False, default=1)
    start_time = Column(Time, nullable=False)
    end_time = Column(Time, nullable=False)
    result_code = Column(String(64), nullable=False, default="PRESENT")
    result_classification = Column(String(64), nullable=True)
    show_in_user_schedule = Column(Boolean, default=True, nullable=False)
    priority = Column(Integer, default=1, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    shift = relationship("Shift", back_populates="rules")

class EmployeeShiftAssignment(Base):
    __tablename__ = "employee_shift_assignments"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    shift_id = Column(Integer, ForeignKey("shifts.id", ondelete="RESTRICT"), nullable=False, index=True)
    effective_from = Column(Date, nullable=False, default=date.today)
    effective_to = Column(Date, nullable=True) # None = ongoing indefinitely
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", backref="shift_assignments")
    shift = relationship("Shift", back_populates="assignments")
