from datetime import datetime, date, time, timezone
from typing import List, Optional
import pytz
import numpy as np
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form, Response, Query, Header
from app.security.tokens import decode_access_token
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.database import get_db
from app.models.user import User, UserRole
from app.models.face import FaceTemplate, FaceEnrollmentSample
from app.models.geofence import Geofence, AttendanceWindow
from app.models.attendance import Attendance, AttendanceStatus, AttendanceAttempt, AttemptStatus
from app.models.attendance_request import AttendanceRequest, RequestStatus
from app.schemas.user import (
    UserCreate,
    UserUpdate,
    UserResponse,
    GeofenceSummary,
    AttendanceWindowSummary,
    DashboardStatsResponse,
    FeatureToggleRequest,
    EmployeeFeaturesResponse,
    DeviceRegistrationRequest,
    DeviceRegistrationResponse,
)
from app.schemas.geofence import (
    GeofenceCreate,
    GeofenceResponse,
    AttendanceWindowCreate,
    AttendanceWindowResponse,
)
from app.schemas.attendance import (
    AttendanceRecordResponse,
    FaceEnrollmentSampleResponse,
)
from app.schemas.attendance_request import (
    AttendanceRequestResponse,
    AttendanceRequestReview,
)
from app.dependencies import require_admin
from app.config import settings
from app.security.hashing import get_password_hash
from app.services.audit_service import log_audit_event
from app.services.setting_service import SettingService
from app.services.time_service import TimeService
from app.services.shift_service import ShiftService
from app.schemas.setting import BiometricSettingsResponse, BiometricSettingsUpdate
from app.ml.pipeline import face_pipeline
from app.ml.preprocessing import compress_to_jpeg
from app.ml.similarity import aggregate_embeddings, compute_cosine_similarity

router = APIRouter(prefix="/api/admin", tags=["Admin Management"], dependencies=[Depends(require_admin)])

@router.get("/dashboard-stats", response_model=DashboardStatsResponse)
def get_dashboard_stats(db: Session = Depends(get_db)):
    """Retrieve overview metrics for Admin Dashboard."""
    total_employees = db.query(User).filter(User.role == UserRole.USER).count()
    active_employees = db.query(User).filter(User.role == UserRole.USER, User.is_active == True).count()
    
    tz = TimeService.get_server_timezone()
    today_date = datetime.now(tz).date()
    today_present = db.query(Attendance).filter(Attendance.attendance_date == today_date).count()
    
    today_start = datetime.combine(today_date, time.min)
    today_failed = db.query(AttendanceAttempt).filter(
        AttendanceAttempt.timestamp >= today_start,
        AttendanceAttempt.attempt_status == AttemptStatus.REJECTED
    ).count()

    enrolled_faces = db.query(FaceTemplate).count()
    pending_requests = db.query(AttendanceRequest).filter(AttendanceRequest.status == RequestStatus.PENDING).count()

    return DashboardStatsResponse(
        total_employees=total_employees,
        active_employees=active_employees,
        today_present=today_present,
        today_failed_attempts=today_failed,
        enrolled_faces_count=enrolled_faces,
        pending_attendance_requests=pending_requests
    )

@router.post("/users", response_model=UserResponse)
def create_employee(user_in: UserCreate, db: Session = Depends(get_db), admin: User = Depends(require_admin)):
    """Create a new employee with initial password and mandatory password change."""
    existing = db.query(User).filter(User.employee_id == user_in.employee_id).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Employee ID '{user_in.employee_id}' is already registered",
        )

    # Initial password defaults to employee_id if omitted
    init_pwd = user_in.initial_password if user_in.initial_password else user_in.employee_id
    pwd_hash = get_password_hash(init_pwd)

    new_user = User(
        employee_id=user_in.employee_id,
        full_name=user_in.full_name,
        password_hash=pwd_hash,
        role=user_in.role,
        is_active=user_in.is_active,
        must_change_password=True,
        department=user_in.department,
        department_id=user_in.department_id,
        unit_number=user_in.unit_number,
        designation=user_in.designation
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    log_audit_event(
        db=db,
        action="EMPLOYEE_CREATED",
        actor_user_id=admin.id,
        target_user_id=new_user.id,
        details={"employee_id": new_user.employee_id, "full_name": new_user.full_name, "department": new_user.department, "unit_number": new_user.unit_number}
    )

    return UserResponse(
        id=new_user.id,
        employee_id=new_user.employee_id,
        full_name=new_user.full_name,
        role=new_user.role,
        is_active=new_user.is_active,
        must_change_password=new_user.must_change_password,
        department=new_user.department,
        department_id=new_user.department_id,
        unit_number=new_user.unit_number,
        designation=new_user.designation,
        has_face_enrolled=False,
        geofence=None,
        attendance_window=None,
        face_enabled=new_user.face_enabled,
        geofence_enabled=new_user.geofence_enabled,
        shift_enabled=new_user.shift_enabled,
        travel_map_enabled=new_user.travel_map_enabled,
        device_binding_enabled=new_user.device_binding_enabled,
        device_id=new_user.device_id,
        is_device_registered=bool(new_user.device_id and len(new_user.device_id.strip()) > 0),
        device_registered_at=new_user.device_registered_at,
        device_model=new_user.device_model,
        created_at=new_user.created_at,
        updated_at=new_user.updated_at
    )

@router.get("/users", response_model=List[UserResponse])
def list_employees(db: Session = Depends(get_db)):
    """List all registered users with enrollment & geofence status."""
    users = db.query(User).order_by(User.id.desc()).all()
    results = []
    for u in users:
        geofence_summary = None
        if u.geofence:
            geofence_summary = GeofenceSummary(
                location_name=u.geofence.location_name,
                latitude=float(u.geofence.latitude),
                longitude=float(u.geofence.longitude),
                radius_meters=float(u.geofence.radius_meters)
            )
        
        window_summary = None
        if u.attendance_window:
            window_summary = AttendanceWindowSummary(
                start_time=u.attendance_window.start_time.strftime("%H:%M"),
                end_time=u.attendance_window.end_time.strftime("%H:%M"),
                timezone=u.attendance_window.timezone
            )

        results.append(
            UserResponse(
                id=u.id,
                employee_id=u.employee_id,
                full_name=u.full_name,
                role=u.role,
                is_active=u.is_active,
                must_change_password=u.must_change_password,
                department=u.department,
                department_id=u.department_id,
                unit_number=u.unit_number,
                designation=u.designation,
                has_face_enrolled=u.face_template is not None,
                geofence=geofence_summary,
                attendance_window=window_summary,
                face_enabled=getattr(u, "face_enabled", True),
                geofence_enabled=getattr(u, "geofence_enabled", True),
                shift_enabled=getattr(u, "shift_enabled", True),
                travel_map_enabled=getattr(u, "travel_map_enabled", True),
                device_binding_enabled=getattr(u, "device_binding_enabled", True),
                device_id=u.device_id,
                is_device_registered=bool(u.device_id and len(u.device_id.strip()) > 0),
                device_registered_at=u.device_registered_at,
                device_model=u.device_model,
                created_at=u.created_at,
                updated_at=u.updated_at
            )
        )
    return results

@router.get("/users/{user_id}", response_model=UserResponse)
def get_employee(user_id: int, db: Session = Depends(get_db)):
    """Retrieve details for a single employee."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    
    geofence_summary = None
    if u.geofence:
        geofence_summary = GeofenceSummary(
            location_name=u.geofence.location_name,
            latitude=float(u.geofence.latitude),
            longitude=float(u.geofence.longitude),
            radius_meters=float(u.geofence.radius_meters)
        )
    
    window_summary = None
    if u.attendance_window:
        window_summary = AttendanceWindowSummary(
            start_time=u.attendance_window.start_time.strftime("%H:%M"),
            end_time=u.attendance_window.end_time.strftime("%H:%M"),
            timezone=u.attendance_window.timezone
        )

    return UserResponse(
        id=u.id,
        employee_id=u.employee_id,
        full_name=u.full_name,
        role=u.role,
        is_active=u.is_active,
        must_change_password=u.must_change_password,
        department=u.department,
        department_id=u.department_id,
        unit_number=u.unit_number,
        designation=u.designation,
        has_face_enrolled=u.face_template is not None,
        geofence=geofence_summary,
        attendance_window=window_summary,
        face_enabled=getattr(u, "face_enabled", True),
        geofence_enabled=getattr(u, "geofence_enabled", True),
        shift_enabled=getattr(u, "shift_enabled", True),
        travel_map_enabled=getattr(u, "travel_map_enabled", True),
        device_binding_enabled=getattr(u, "device_binding_enabled", True),
        device_id=u.device_id,
        is_device_registered=bool(u.device_id and len(u.device_id.strip()) > 0),
        device_registered_at=u.device_registered_at,
        device_model=u.device_model,
        created_at=u.created_at,
        updated_at=u.updated_at
    )

@router.put("/users/{user_id}", response_model=UserResponse)
def update_employee(
    user_id: int,
    user_update: UserUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Update employee details, active status, or reset password."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    if user_update.full_name is not None:
        u.full_name = user_update.full_name
    if user_update.role is not None:
        u.role = user_update.role
    if user_update.is_active is not None:
        u.is_active = user_update.is_active
    if user_update.must_change_password is not None:
        u.must_change_password = user_update.must_change_password
    if user_update.password:
        u.password_hash = get_password_hash(user_update.password)
        u.must_change_password = True
    if user_update.department is not None:
        u.department = user_update.department
    if user_update.department_id is not None:
        u.department_id = user_update.department_id
    if user_update.unit_number is not None:
        u.unit_number = user_update.unit_number
    if user_update.designation is not None:
        u.designation = user_update.designation

    db.commit()
    db.refresh(u)

    log_audit_event(
        db=db,
        action="EMPLOYEE_UPDATED",
        actor_user_id=admin.id,
        target_user_id=u.id,
    )

    return get_employee(user_id=user_id, db=db)


@router.get("/users/{user_id}/features", response_model=EmployeeFeaturesResponse)
def get_employee_features(user_id: int, db: Session = Depends(get_db)):
    """Retrieve current feature toggles and device registration for an employee."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")
    return EmployeeFeaturesResponse(
        user_id=u.id,
        employee_id=u.employee_id,
        full_name=u.full_name,
        face_enabled=getattr(u, "face_enabled", True),
        geofence_enabled=getattr(u, "geofence_enabled", True),
        shift_enabled=getattr(u, "shift_enabled", True),
        travel_map_enabled=getattr(u, "travel_map_enabled", True),
        device_binding_enabled=getattr(u, "device_binding_enabled", True),
        device_id=u.device_id,
        is_device_registered=bool(u.device_id and len(u.device_id.strip()) > 0),
        device_registered_at=u.device_registered_at,
        device_model=u.device_model
    )


@router.post("/users/{user_id}/features/toggle", response_model=EmployeeFeaturesResponse)
def toggle_employee_feature(
    user_id: int,
    req: FeatureToggleRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Independently toggle a single feature (face, geofence, shift, travel_map, device_binding) for an employee."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")

    feature_key = req.feature.strip().lower()
    valid_features = {"face", "geofence", "shift", "travel_map", "device_binding", "device"}
    if feature_key not in valid_features:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid feature '{req.feature}'. Allowed features: {', '.join(sorted(valid_features))}"
        )

    attr_name = "device_binding_enabled" if feature_key in ("device_binding", "device") else f"{feature_key}_enabled"
    old_val = getattr(u, attr_name, True)
    setattr(u, attr_name, req.enabled)
    db.commit()
    db.refresh(u)

    log_audit_event(
        db=db,
        action="EMPLOYEE_FEATURE_TOGGLED",
        actor_user_id=admin.id,
        target_user_id=u.id,
        details={
            "feature": feature_key,
            "attribute": attr_name,
            "old_value": old_val,
            "new_value": req.enabled,
            "employee_id": u.employee_id
        }
    )

    return EmployeeFeaturesResponse(
        user_id=u.id,
        employee_id=u.employee_id,
        full_name=u.full_name,
        face_enabled=u.face_enabled,
        geofence_enabled=u.geofence_enabled,
        shift_enabled=u.shift_enabled,
        travel_map_enabled=u.travel_map_enabled,
        device_binding_enabled=getattr(u, "device_binding_enabled", True),
        device_id=u.device_id,
        is_device_registered=bool(u.device_id and len(u.device_id.strip()) > 0),
        device_registered_at=u.device_registered_at,
        device_model=u.device_model
    )


@router.get("/users/{user_id}/device", response_model=DeviceRegistrationResponse)
def get_employee_device(user_id: int, db: Session = Depends(get_db)):
    """Retrieve current hardware device registration status for an employee."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")
    
    is_registered = bool(u.device_id and len(u.device_id.strip()) > 0)
    return DeviceRegistrationResponse(
        success=True,
        message="Device registration status retrieved successfully" if is_registered else "No device registered",
        employee_id=u.employee_id,
        full_name=u.full_name,
        device_id=u.device_id,
        is_registered=is_registered,
        registered_at=u.device_registered_at,
        device_model=u.device_model
    )


@router.post("/users/{user_id}/device", response_model=DeviceRegistrationResponse)
def register_employee_device(
    user_id: int,
    req: DeviceRegistrationRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Register or update Device ID for an employee.
    Enforces device binding for mobile app logins.
    Rejects duplicate device assignments with HTTP 409 Conflict to preserve explicit ownership.
    """
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")

    clean_device_id = req.device_id.strip()
    if not clean_device_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Device ID cannot be empty")

    # Enforce device UUID ownership: a UUID actively registered to another employee
    # must NOT be silently transferred or reassigned.
    existing_other = db.query(User).filter(
        User.device_id == clean_device_id,
        User.id != u.id
    ).first()
    if existing_other:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"This device is already registered to employee {existing_other.full_name} ({existing_other.employee_id}). Please unbind it first before reassigning."
        )

    u.device_id = clean_device_id
    u.device_registered_at = datetime.utcnow()
    if req.device_model:
        u.device_model = req.device_model.strip()

    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Conflict registering device. This device ID may already be registered to another employee."
        )
    db.refresh(u)

    log_audit_event(
        db=db,
        action="DEVICE_REGISTERED",
        actor_user_id=admin.id,
        target_user_id=u.id,
        details={
            "device_id": clean_device_id,
            "device_model": u.device_model,
            "employee_id": u.employee_id
        }
    )

    return DeviceRegistrationResponse(
        success=True,
        message=f"Device ID successfully registered for {u.full_name}",
        employee_id=u.employee_id,
        full_name=u.full_name,
        device_id=u.device_id,
        is_registered=True,
        registered_at=u.device_registered_at,
        device_model=u.device_model
    )


@router.delete("/users/{user_id}/device", response_model=DeviceRegistrationResponse)
def remove_employee_device(
    user_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Revoke and remove hardware Device ID registration for an employee."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")

    old_device_id = u.device_id
    u.device_id = None
    u.device_registered_at = None
    u.device_model = None

    db.commit()
    db.refresh(u)

    log_audit_event(
        db=db,
        action="DEVICE_REGISTRATION_REVOKED",
        actor_user_id=admin.id,
        target_user_id=u.id,
        details={"old_device_id": old_device_id, "employee_id": u.employee_id}
    )

    return DeviceRegistrationResponse(
        success=True,
        message=f"Device registration revoked for {u.full_name}. Employee account is now unbound.",
        employee_id=u.employee_id,
        full_name=u.full_name,
        device_id=None,
        is_registered=False,
        registered_at=None,
        device_model=None
    )


@router.post("/users/{user_id}/face", response_model=FaceEnrollmentSampleResponse)
async def enroll_face_sample(
    user_id: int,
    sample_index: int = Form(..., description="Sample index (1, 2, 3)"),
    image: UploadFile = File(...),
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Continuous progressive 3-sample face enrollment endpoint (1 of 3, 2 of 3, 3 of 3).
    Validates face quality, SCRFD detection, alignment, ArcFace embedding.
    Performs automatic Same-Face Self Test on sample 3 before biometric profile activation.
    """
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    image_bytes = await image.read()
    if not image_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty image uploaded")

    # If starting fresh from sample 1, clear previous incomplete enrollment samples
    if sample_index == 1:
        db.query(FaceEnrollmentSample).filter(FaceEnrollmentSample.user_id == u.id).delete()
        db.commit()

    # Process frame through ML pipeline with full quality checks
    res = face_pipeline.process_single_frame(image_bytes)
    if not res.success:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=res.error_message or "Sample validation failed"
        )

    # Save individual sample in DB
    existing_sample = db.query(FaceEnrollmentSample).filter(
        FaceEnrollmentSample.user_id == u.id,
        FaceEnrollmentSample.sample_index == sample_index
    ).first()

    embedding_bytes = res.embedding.tobytes()
    best_jpeg_bytes = compress_to_jpeg(res.aligned_face)

    if existing_sample:
        existing_sample.sample_embedding = embedding_bytes
        existing_sample.sample_image = best_jpeg_bytes
        existing_sample.quality_metrics = {"quality_score": res.quality_score}
    else:
        new_sample = FaceEnrollmentSample(
            user_id=u.id,
            sample_index=sample_index,
            sample_embedding=embedding_bytes,
            sample_image=best_jpeg_bytes,
            quality_metrics={"quality_score": res.quality_score}
        )
        db.add(new_sample)
    
    db.commit()

    # Check if we have collected all 3 valid samples
    samples = db.query(FaceEnrollmentSample).filter(
        FaceEnrollmentSample.user_id == u.id
    ).order_by(FaceEnrollmentSample.sample_index.asc()).all()

    if len(samples) >= 3:
        # Aggregate reference template from all 3 samples
        embeddings_list = [np.frombuffer(s.sample_embedding, dtype=np.float32) for s in samples]
        aggregated_ref = aggregate_embeddings(embeddings_list)
        
        # SAME-FACE SELF TEST: Test genuine verification of enrollment image against the aggregated template
        self_test_sim = compute_cosine_similarity(aggregated_ref, embeddings_list[0])
        print(f"[AdminFaceEnrollment] User {u.id} self-test cosine similarity: {self_test_sim:.4f}")
        if self_test_sim < 0.50:
            # Registration verification failed: do not activate template
            db.query(FaceEnrollmentSample).filter(FaceEnrollmentSample.user_id == u.id).delete()
            db.query(FaceTemplate).filter(FaceTemplate.user_id == u.id).delete()
            db.commit()
            from app.services.face_cache_service import FaceCacheService
            FaceCacheService.invalidate(u.id)
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Face registration validation failed (inconsistent samples). Please register the face again."
            )

        # Best sample JPEG (from sample 1)
        best_image = samples[0].sample_image

        template = db.query(FaceTemplate).filter(FaceTemplate.user_id == u.id).first()
        if template:
            template.face_embedding = aggregated_ref.tobytes()
            template.face_image = best_image
            template.sample_count = len(samples)
            template.quality_score = res.quality_score
            template.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        else:
            template = FaceTemplate(
                user_id=u.id,
                face_embedding=aggregated_ref.tobytes(),
                face_image=best_image,
                sample_count=len(samples),
                quality_score=res.quality_score
            )
            db.add(template)
        
        db.commit()
        from app.services.face_cache_service import FaceCacheService
        FaceCacheService.invalidate(u.id)

        log_audit_event(
            db=db,
            action="FACE_TEMPLATE_ENROLLED",
            actor_user_id=admin.id,
            target_user_id=u.id,
            details={"sample_count": len(samples), "self_test_sim": float(self_test_sim)}
        )

        return FaceEnrollmentSampleResponse(
            sample_index=3,
            total_required=3,
            is_valid=True,
            quality_score=res.quality_score,
            message="Face registration complete ✓"
        )

    return FaceEnrollmentSampleResponse(
        sample_index=sample_index,
        total_required=3,
        is_valid=True,
        quality_score=res.quality_score,
        message=f"Sample {sample_index} captured ✓"
    )

@router.post("/users/{user_id}/geofence", response_model=GeofenceResponse)
def assign_geofence(
    user_id: int,
    geofence_in: GeofenceCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Assign or update employee physical attendance location and radius."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    gf = db.query(Geofence).filter(Geofence.user_id == u.id).first()
    if gf:
        gf.location_name = geofence_in.location_name
        gf.latitude = geofence_in.latitude
        gf.longitude = geofence_in.longitude
        gf.radius_meters = geofence_in.radius_meters
        gf.is_active = geofence_in.is_active
        gf.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
    else:
        gf = Geofence(
            user_id=u.id,
            location_name=geofence_in.location_name,
            latitude=geofence_in.latitude,
            longitude=geofence_in.longitude,
            radius_meters=geofence_in.radius_meters,
            is_active=geofence_in.is_active
        )
        db.add(gf)
    
    db.commit()
    db.refresh(gf)

    log_audit_event(
        db=db,
        action="GEOFENCE_ASSIGNED",
        actor_user_id=admin.id,
        target_user_id=u.id,
        details={
            "location_name": gf.location_name,
            "latitude": float(gf.latitude),
            "longitude": float(gf.longitude),
            "radius": gf.radius_meters
        }
    )

    return GeofenceResponse(
        id=gf.id,
        user_id=gf.user_id,
        location_name=gf.location_name,
        latitude=float(gf.latitude),
        longitude=float(gf.longitude),
        radius_meters=float(gf.radius_meters),
        is_active=gf.is_active
    )

@router.post("/users/{user_id}/attendance-window", response_model=AttendanceWindowResponse)
def assign_attendance_window(
    user_id: int,
    window_in: AttendanceWindowCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Assign or update allowed attendance time window and timezone."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # Parse HH:MM or HH:MM:SS
    start_parts = [int(p) for p in window_in.start_time.split(":")]
    end_parts = [int(p) for p in window_in.end_time.split(":")]
    
    st = time(start_parts[0], start_parts[1], start_parts[2] if len(start_parts) > 2 else 0)
    et = time(end_parts[0], end_parts[1], end_parts[2] if len(end_parts) > 2 else 0)

    win = db.query(AttendanceWindow).filter(AttendanceWindow.user_id == u.id).first()
    if win:
        win.start_time = st
        win.end_time = et
        win.timezone = window_in.timezone
        win.allowed_days = window_in.allowed_days
        win.is_active = window_in.is_active
        win.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
    else:
        win = AttendanceWindow(
            user_id=u.id,
            start_time=st,
            end_time=et,
            timezone=window_in.timezone,
            allowed_days=window_in.allowed_days,
            is_active=window_in.is_active
        )
        db.add(win)
    
    db.commit()
    db.refresh(win)

    log_audit_event(
        db=db,
        action="ATTENDANCE_WINDOW_ASSIGNED",
        actor_user_id=admin.id,
        target_user_id=u.id,
        details={"start_time": window_in.start_time, "end_time": window_in.end_time, "timezone": window_in.timezone}
    )

    return AttendanceWindowResponse(
        id=win.id,
        user_id=win.user_id,
        start_time=win.start_time.strftime("%H:%M:%S"),
        end_time=win.end_time.strftime("%H:%M:%S"),
        timezone=win.timezone,
        allowed_days=win.allowed_days,
        is_active=win.is_active
    )

@router.get("/attendance", response_model=List[AttendanceRecordResponse])
def get_attendance_records(
    date_filter: Optional[date] = None,
    user_id: Optional[int] = None,
    db: Session = Depends(get_db)
):
    """Query attendance history across employees."""
    query = db.query(Attendance, User).join(User, Attendance.user_id == User.id)
    
    if date_filter:
        query = query.filter(Attendance.attendance_date == date_filter)
    if user_id:
        query = query.filter(Attendance.user_id == user_id)
        
    records = query.order_by(Attendance.id.desc()).limit(200).all()

    res = []
    for att, usr in records:
        gf_name = usr.geofence.location_name if usr.geofence else None
        res.append(
            AttendanceRecordResponse(
                id=att.id,
                user_id=att.user_id,
                employee_id=usr.employee_id,
                full_name=usr.full_name,
                shift_id=att.shift_id,
                shift_code=att.shift.shift_code if att.shift else None,
                shift_name=att.shift.shift_name if att.shift else None,
                attendance_classification=att.attendance_classification or "ON_TIME",
                attendance_date=att.attendance_date,
                timestamp=att.timestamp,
                status=att.status,
                verified_latitude=float(att.verified_latitude),
                verified_longitude=float(att.verified_longitude),
                verified_distance_meters=float(att.verified_distance_meters),
                face_similarity_score=float(att.face_similarity_score),
                liveness_score=float(att.liveness_score),
                location_name=gf_name
            )
        )
    return res

@router.get("/settings/biometric", response_model=BiometricSettingsResponse)
def get_biometric_settings(
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Retrieve active global biometric settings (similarity threshold, liveness threshold, min face size)."""
    return SettingService.get_biometric_settings(db=db)

@router.put("/settings/biometric", response_model=BiometricSettingsResponse)
def update_biometric_settings(
    settings_in: BiometricSettingsUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Update and persist global biometric settings (similarity threshold).
    Changes take effect immediately across all verification and enrollment requests globally.
    """
    old_threshold = settings.SIMILARITY_THRESHOLD
    updated = SettingService.update_biometric_settings(
        db=db,
        similarity_threshold=settings_in.similarity_threshold,
        liveness_confidence_threshold=settings_in.liveness_confidence_threshold,
        min_face_size=settings_in.min_face_size
    )

    log_audit_event(
        db=db,
        action="BIOMETRIC_SETTINGS_UPDATED",
        actor_user_id=admin.id,
        details={
            "old_similarity_threshold": old_threshold,
            "new_similarity_threshold": updated["similarity_threshold"],
            "liveness_confidence_threshold": updated["liveness_confidence_threshold"],
            "min_face_size": updated["min_face_size"]
        }
    )

    return updated

@router.get("/attendance-requests", response_model=List[AttendanceRequestResponse])
def list_attendance_requests(
    status_filter: Optional[str] = None,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """List attendance requests for admin review (filter by PENDING, APPROVED, REJECTED)."""
    tz = TimeService.get_server_timezone()
    query = db.query(AttendanceRequest)
    if status_filter:
        query = query.filter(AttendanceRequest.status == status_filter.upper())
    requests = query.order_by(AttendanceRequest.id.desc()).limit(200).all()

    results = []
    for req in requests:
        req_local_dt = req.server_timestamp.astimezone(tz) if req.server_timestamp.tzinfo else pytz.utc.localize(req.server_timestamp).astimezone(tz)
        reviewer_name = req.reviewed_by.full_name if req.reviewed_by else None
        shift_name = req.shift.shift_name if req.shift else None
        shift_code = req.shift.shift_code if req.shift else None

        results.append(
            AttendanceRequestResponse(
                id=req.id,
                user_id=req.user_id,
                employee_id=req.user.employee_id,
                full_name=req.user.full_name,
                request_date=req.request_date.strftime("%Y-%m-%d"),
                server_timestamp=req.server_timestamp.isoformat() + "Z",
                server_formatted_date=req_local_dt.strftime("%d %b %Y"),
                server_formatted_time=req_local_dt.strftime("%I:%M:%S %p"),
                device_timestamp=req.device_timestamp,
                shift_id=req.shift_id,
                shift_name=shift_name,
                shift_code=shift_code,
                status=req.status.value,
                rejection_reason_trigger=req.rejection_reason_trigger,
                latitude=float(req.latitude),
                longitude=float(req.longitude),
                gps_accuracy=req.gps_accuracy,
                location_name=req.location_name,
                assigned_location_name=req.assigned_location_name,
                distance_from_location=float(req.distance_from_location),
                is_within_geofence=bool(req.is_within_geofence),
                has_evidence_image=req.evidence_image is not None,
                admin_notes=req.admin_notes,
                reviewed_at=req.reviewed_at,
                reviewed_by_name=reviewer_name,
                created_at=req.created_at
            )
        )
    return results

@router.get("/attendance-requests/{request_id}/image")
def get_attendance_request_evidence_image(
    request_id: int,
    token: Optional[str] = Query(None, description="Auth token for direct image rendering"),
    db: Session = Depends(get_db)
):
    """
    Retrieve raw watermarked selfie evidence image for a specific attendance request.
    Authorized via Bearer header or token query parameter.
    """
    req = db.query(AttendanceRequest).filter(AttendanceRequest.id == request_id).first()
    if not req or not req.evidence_image:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Evidence image not found")
    return Response(content=req.evidence_image, media_type="image/jpeg")

@router.post("/attendance-requests/{request_id}/approve", response_model=AttendanceRequestResponse)
def approve_attendance_request(
    request_id: int,
    review_in: Optional[AttendanceRequestReview] = None,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Approve employee fallback attendance request:
    1. Evaluates punch classification at the authoritative server timestamp
    2. Inserts official Attendance record with verification_mode='REQUEST_APPROVAL'
    3. Updates request status to APPROVED
    4. Logs audit event
    """
    req = db.query(AttendanceRequest).filter(AttendanceRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance request not found")
    if req.status != RequestStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Request is already {req.status.value}")

    tz = TimeService.get_server_timezone()
    req_local_dt = req.server_timestamp.astimezone(tz) if req.server_timestamp.tzinfo else pytz.utc.localize(req.server_timestamp).astimezone(tz)
    punch_time_val = req_local_dt.time()

    # Dynamic Shift Rule Engine Evaluation
    effective_shift = req.shift
    classification = "ON_TIME"
    att_status_str = "PRESENT"
    if effective_shift:
        classification, att_status_str, _ = ShiftService.evaluate_punch_timestamp(
            shift=effective_shift,
            punch_time=punch_time_val
        )

    final_status = AttendanceStatus.LATE if att_status_str == "LATE" else AttendanceStatus.PRESENT

    target_v_no = req.verification_no or 1
    window_def = TimeService.get_window_by_number(target_v_no)
    window_label = window_def["label"] if window_def else f"Verification {target_v_no}"

    # Create official Attendance record
    new_attendance = Attendance(
        user_id=req.user_id,
        attendance_date=req.request_date,
        verification_no=target_v_no,
        verification_window=window_label,
        timestamp=req.server_timestamp,
        status=final_status,
        shift_id=effective_shift.id if effective_shift else None,
        attendance_classification=classification,
        verification_mode="REQUEST_APPROVAL",
        attendance_request_id=req.id,
        verified_latitude=req.latitude,
        verified_longitude=req.longitude,
        verified_distance_meters=req.distance_from_location,
        gps_accuracy=req.gps_accuracy,
        face_similarity_score=1.0,
        liveness_score=1.0,
        device_id="REQUEST_APPROVAL"
    )
    db.add(new_attendance)

    # Update request state
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    req.status = RequestStatus.APPROVED
    req.reviewed_by_user_id = admin.id
    req.reviewed_at = now_utc
    if review_in and review_in.admin_notes:
        req.admin_notes = review_in.admin_notes

    db.commit()
    db.refresh(req)

    log_audit_event(
        db=db,
        action="ATTENDANCE_REQUEST_APPROVED",
        actor_user_id=admin.id,
        target_user_id=req.user_id,
        details={
            "request_id": req.id,
            "status": "APPROVED",
            "attendance_classification": classification,
            "server_timestamp": req.server_timestamp.isoformat()
        }
    )

    return AttendanceRequestResponse(
        id=req.id,
        user_id=req.user_id,
        employee_id=req.user.employee_id,
        full_name=req.user.full_name,
        request_date=req.request_date.strftime("%Y-%m-%d"),
        server_timestamp=req.server_timestamp.isoformat() + "Z",
        server_formatted_date=req_local_dt.strftime("%d %b %Y"),
        server_formatted_time=req_local_dt.strftime("%I:%M:%S %p"),
        device_timestamp=req.device_timestamp,
        shift_id=req.shift_id,
        shift_name=effective_shift.shift_name if effective_shift else None,
        shift_code=effective_shift.shift_code if effective_shift else None,
        status=req.status.value,
        rejection_reason_trigger=req.rejection_reason_trigger,
        latitude=float(req.latitude),
        longitude=float(req.longitude),
        gps_accuracy=req.gps_accuracy,
        location_name=req.location_name,
        assigned_location_name=req.assigned_location_name,
        distance_from_location=float(req.distance_from_location),
        is_within_geofence=bool(req.is_within_geofence),
        has_evidence_image=True,
        admin_notes=req.admin_notes,
        reviewed_at=req.reviewed_at,
        reviewed_by_name=admin.full_name,
        created_at=req.created_at
    )

@router.post("/attendance-requests/{request_id}/reject", response_model=AttendanceRequestResponse)
def reject_attendance_request(
    request_id: int,
    review_in: Optional[AttendanceRequestReview] = None,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Reject employee fallback attendance request with optional rejection notes."""
    req = db.query(AttendanceRequest).filter(AttendanceRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance request not found")
    if req.status != RequestStatus.PENDING:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Request is already {req.status.value}")

    tz = TimeService.get_server_timezone()
    req_local_dt = req.server_timestamp.astimezone(tz) if req.server_timestamp.tzinfo else pytz.utc.localize(req.server_timestamp).astimezone(tz)

    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    req.status = RequestStatus.REJECTED
    req.reviewed_by_user_id = admin.id
    req.reviewed_at = now_utc
    if review_in and review_in.admin_notes:
        req.admin_notes = review_in.admin_notes

    db.commit()
    db.refresh(req)

    log_audit_event(
        db=db,
        action="ATTENDANCE_REQUEST_REJECTED",
        actor_user_id=admin.id,
        target_user_id=req.user_id,
        details={
            "request_id": req.id,
            "status": "REJECTED",
            "admin_notes": req.admin_notes
        }
    )

    return AttendanceRequestResponse(
        id=req.id,
        user_id=req.user_id,
        employee_id=req.user.employee_id,
        full_name=req.user.full_name,
        request_date=req.request_date.strftime("%Y-%m-%d"),
        server_timestamp=req.server_timestamp.isoformat() + "Z",
        server_formatted_date=req_local_dt.strftime("%d %b %Y"),
        server_formatted_time=req_local_dt.strftime("%I:%M:%S %p"),
        device_timestamp=req.device_timestamp,
        shift_id=req.shift_id,
        shift_name=req.shift.shift_name if req.shift else None,
        shift_code=req.shift.shift_code if req.shift else None,
        status=req.status.value,
        rejection_reason_trigger=req.rejection_reason_trigger,
        latitude=float(req.latitude),
        longitude=float(req.longitude),
        gps_accuracy=req.gps_accuracy,
        location_name=req.location_name,
        assigned_location_name=req.assigned_location_name,
        distance_from_location=float(req.distance_from_location),
        is_within_geofence=bool(req.is_within_geofence),
        has_evidence_image=True,
        admin_notes=req.admin_notes,
        reviewed_at=req.reviewed_at,
        reviewed_by_name=admin.full_name,
        created_at=req.created_at
    )
