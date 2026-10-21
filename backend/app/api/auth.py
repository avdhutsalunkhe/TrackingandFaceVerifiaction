from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User, UserRole
from app.schemas.auth import LoginRequest, TokenResponse, ChangePasswordRequest
from app.schemas.user import UserResponse, GeofenceSummary, AttendanceWindowSummary
from app.services.auth_service import authenticate_user, create_user_token
from app.services.audit_service import log_audit_event
from app.security.hashing import verify_password, get_password_hash
from app.dependencies import get_current_user

router = APIRouter(prefix="/api/auth", tags=["Authentication"])

@router.post("/login", response_model=TokenResponse)
def login(login_data: LoginRequest, request: Request, db: Session = Depends(get_db)):
    """Authenticate user with Employee ID and Password, enforcing platform-specific access rules:
    - Administrators (ADMIN, TIME_OFFICE): Permitted to log in ONLY via the Web / PC portal.
    - Field Staff / Employees (USER): Permitted to log in ONLY via the registered mobile phone application.
    """
    user = authenticate_user(db, employee_id=login_data.employee_id, password=login_data.password)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid employee ID or password",
        )
    
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Employee account is deactivated. Please contact your administrator.",
        )

    # Detect client platform via request payload, custom header, or User-Agent
    client_type = None
    if login_data.client_type:
        client_type = login_data.client_type.strip().upper()
    elif request.headers.get("x-client-type"):
        client_type = request.headers.get("x-client-type").strip().upper()
    else:
        ua = (request.headers.get("user-agent") or "").lower()
        if any(keyword in ua for keyword in ("dart", "flutter", "okhttp", "android", "cfnetwork", "mobile")):
            client_type = "MOBILE"
        else:
            client_type = "WEB"

    # Enforce role-based platform restrictions:
    # - TIME_OFFICE: Restricted strictly to Web / PC portal.
    # - ADMIN: Permitted on Web / PC (full administration) AND on Mobile (dedicated employee face registration).
    # - USER: Restricted strictly to the mobile phone application.
    if user.role == UserRole.TIME_OFFICE:
        if client_type == "MOBILE":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Time Office login is restricted to the Web portal. Please log in using the Time Office web or PC application.",
            )
    elif user.role == UserRole.ADMIN:
        # Admin is allowed to log in via Mobile specifically for employee face registration
        pass
    elif user.role == UserRole.USER:
        if client_type == "WEB":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Employee login is restricted to the mobile phone application. Web access is reserved for administrators.",
            )

        incoming_device_id = (login_data.device_id or request.headers.get("x-device-id") or "").strip()

        # Step 1: Enforce device UUID ownership across all active employees.
        # A device actively registered to any other employee must NEVER be accepted.
        if incoming_device_id:
            other_owner = db.query(User).filter(
                User.device_id == incoming_device_id,
                User.id != user.id,
                User.is_active == True
            ).first()
            if other_owner:
                log_audit_event(
                    db=db,
                    action="DEVICE_LOGIN_CONFLICT_REJECTED",
                    actor_user_id=user.id,
                    target_user_id=user.id,
                    details={
                        "attempted_device_id": incoming_device_id,
                        "registered_owner_employee_id": other_owner.employee_id,
                        "registered_owner_name": other_owner.full_name,
                        "reason": "Device is registered to another employee"
                    },
                    ip_address=request.client.host if request.client else None
                )
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="This device is registered to another employee. Please use your assigned device.",
                )

        # Step 2: Enforce per-employee Device Binding toggle
        # ON: Employee must use their assigned registered device.
        # OFF: Employee may use an unregistered device (not assigned to another employee).
        binding_enabled = getattr(user, "device_binding_enabled", True)
        user_assigned_device = (user.device_id or "").strip()

        if binding_enabled:
            if not user_assigned_device or incoming_device_id != user_assigned_device:
                log_audit_event(
                    db=db,
                    action="DEVICE_LOGIN_MISMATCH_REJECTED",
                    actor_user_id=user.id,
                    target_user_id=user.id,
                    details={
                        "expected_device_id": user_assigned_device or "NONE",
                        "received_device_id": incoming_device_id or "NONE",
                        "binding_enabled": True
                    },
                    ip_address=request.client.host if request.client else None
                )
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="This device is not registered for your account. Please contact your administrator.",
                )

    log_audit_event(
        db=db,
        action="USER_LOGIN_SUCCESS",
        actor_user_id=user.id,
        target_user_id=user.id,
        ip_address=request.client.host if request.client else None
    )

    token_info = create_user_token(user, client_type=client_type)
    return TokenResponse(**token_info)

@router.post("/change-password")
def change_password(
    req: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Change current user password. Clears must_change_password flag upon success."""
    if not verify_password(req.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password does not match",
        )
    
    current_user.password_hash = get_password_hash(req.new_password)
    current_user.must_change_password = False
    db.commit()

    log_audit_event(
        db=db,
        action="PASSWORD_CHANGED",
        actor_user_id=current_user.id,
        target_user_id=current_user.id,
    )

    return {"message": "Password changed successfully"}

@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Get current authenticated user profile."""
    geofence_summary = None
    if current_user.geofence:
        geofence_summary = GeofenceSummary(
            location_name=current_user.geofence.location_name,
            latitude=float(current_user.geofence.latitude),
            longitude=float(current_user.geofence.longitude),
            radius_meters=float(current_user.geofence.radius_meters)
        )
    
    window_summary = None
    if current_user.attendance_window:
        window_summary = AttendanceWindowSummary(
            start_time=current_user.attendance_window.start_time.strftime("%H:%M"),
            end_time=current_user.attendance_window.end_time.strftime("%H:%M"),
            timezone=current_user.attendance_window.timezone
        )

    return UserResponse(
        id=current_user.id,
        employee_id=current_user.employee_id,
        full_name=current_user.full_name,
        role=current_user.role,
        is_active=current_user.is_active,
        must_change_password=current_user.must_change_password,
        has_face_enrolled=current_user.face_template is not None,
        geofence=geofence_summary,
        attendance_window=window_summary,
        face_enabled=getattr(current_user, "face_enabled", True),
        geofence_enabled=getattr(current_user, "geofence_enabled", True),
        shift_enabled=getattr(current_user, "shift_enabled", True),
        travel_map_enabled=getattr(current_user, "travel_map_enabled", True),
        device_binding_enabled=getattr(current_user, "device_binding_enabled", True),
        device_id=current_user.device_id,
        is_device_registered=bool(current_user.device_id and len(current_user.device_id.strip()) > 0),
        device_registered_at=current_user.device_registered_at,
        device_model=current_user.device_model,
        created_at=current_user.created_at,
        updated_at=current_user.updated_at
    )
