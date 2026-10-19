from datetime import datetime, timedelta, timezone
from typing import Optional, Tuple
from sqlalchemy.orm import Session
from app.models.user import User, UserRole
from app.config import settings
from app.security.hashing import verify_password, get_password_hash
from app.security.tokens import create_access_token
from app.services.audit_service import log_audit_event

def authenticate_user(db: Session, employee_id: str, password: str) -> Optional[User]:
    """Verify employee credentials and return User if valid."""
    user = db.query(User).filter(User.employee_id == employee_id).first()
    if not user:
        return None
    if not verify_password(password, user.password_hash):
        return None
    return user

def create_user_token(user: User) -> dict:
    """Generate JWT access token and session metadata."""
    payload = {
        "sub": str(user.id),
        "user_id": user.id,
        "employee_id": user.employee_id,
        "role": user.role.value
    }
    expires_delta = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(data=payload, expires_delta=expires_delta)
    expire_timestamp = int((datetime.now(timezone.utc) + expires_delta).timestamp())
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        "expires_at": expire_timestamp,
        "user_id": user.id,
        "role": user.role.value,
        "employee_id": user.employee_id,
        "full_name": user.full_name,
        "must_change_password": user.must_change_password,
        "face_enabled": getattr(user, "face_enabled", True),
        "geofence_enabled": getattr(user, "geofence_enabled", True),
        "shift_enabled": getattr(user, "shift_enabled", True),
        "travel_map_enabled": getattr(user, "travel_map_enabled", True),
        "device_binding_enabled": getattr(user, "device_binding_enabled", True),
        "device_id": getattr(user, "device_id", None),
        "is_device_registered": bool(user.device_id and len(user.device_id.strip()) > 0),
    }
