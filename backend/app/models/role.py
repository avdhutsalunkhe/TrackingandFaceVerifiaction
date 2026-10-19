import enum
from datetime import datetime
from sqlalchemy import Column, Integer, String, Boolean, DateTime
from app.database import Base

class RoleMaster(Base):
    __tablename__ = "role_masters"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    role_code = Column(String(64), unique=True, index=True, nullable=False)
    role_name = Column(String(128), nullable=False)
    description = Column(String(255), nullable=True)
    is_admin = Column(Boolean, default=False, nullable=False)  # True for supervisor/admin roles
    permissions = Column(String(512), default="attendance,reports", nullable=False) # comma-separated permissions
    is_system_role = Column(Boolean, default=False, nullable=False) # Built-in default system role
    is_active = Column(Boolean, default=True, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)
