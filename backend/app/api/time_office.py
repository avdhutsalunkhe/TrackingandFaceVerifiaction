import io
from datetime import datetime, date, timedelta
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from sqlalchemy import func, desc, or_, and_

from app.database import get_db
from app.dependencies import require_time_office
from app.models.user import User, UserRole
from app.models.attendance import Attendance, AttendanceAttempt, AttendanceStatus, AttemptStatus
from app.models.attendance_request import AttendanceRequest
from app.models.shift import Shift, ShiftPunchPeriod, ShiftRule, EmployeeShiftAssignment
from app.models.geofence import Geofence, AttendanceWindow
from app.models.policy import Holiday, WeeklyOffConfig, ExtraWorkRequest
from app.models.audit import AuditLog
from app.schemas.user import UserCreate, UserUpdate
from app.security.hashing import get_password_hash
from app.services.audit_service import log_audit_event

router = APIRouter(prefix="/api/time-office", tags=["Time Office Router"])

# Request Schemas
class ApprovalActionRequest(BaseModel):
    admin_notes: Optional[str] = Field(None, description="Operator review notes")

class AttendanceCorrectionRequest(BaseModel):
    user_id: int = Field(..., description="Target employee user ID")
    attendance_date: str = Field(..., description="YYYY-MM-DD date")
    verification_no: int = Field(1, description="Verification sequence number")
    status: str = Field("PRESENT", description="PRESENT or LATE")
    reason: str = Field(..., description="Mandatory correction reason")

@router.get("/server-time", response_model=dict)
def get_server_time(current_user: User = Depends(require_time_office)):
    """Return authoritative server clock, date, epoch ms, and Asia/Kolkata timezone."""
    now = datetime.now()
    return {
        "datetime": now.isoformat(),
        "date": now.strftime("%Y-%m-%d"),
        "time": now.strftime("%H:%M:%S"),
        "epoch_ms": int(now.timestamp() * 1000),
        "timezone": "Asia/Kolkata"
    }

@router.get("/dashboard", response_model=dict)
def get_dashboard_summary(
    target_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Retrieve Time Office daily dashboard statistics & shift progress."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()

    total_employees = db.query(func.count(User.id)).filter(User.role == UserRole.USER, User.is_active == True).scalar() or 0
    present_count = db.query(func.count(func.distinct(Attendance.user_id))).filter(Attendance.attendance_date == req_date, Attendance.status == AttendanceStatus.PRESENT).scalar() or 0
    late_count = db.query(func.count(func.distinct(Attendance.user_id))).filter(Attendance.attendance_date == req_date, Attendance.status == AttendanceStatus.LATE).scalar() or 0
    
    pending_requests = db.query(func.count(AttendanceRequest.id)).filter(AttendanceRequest.request_date == req_date, AttendanceRequest.status == "PENDING").scalar() or 0
    rejected_requests = db.query(func.count(AttendanceRequest.id)).filter(AttendanceRequest.request_date == req_date, AttendanceRequest.status == "REJECTED").scalar() or 0
    
    total_marked = db.query(func.count(func.distinct(Attendance.user_id))).filter(Attendance.attendance_date == req_date).scalar() or 0
    not_marked_count = max(0, total_employees - total_marked)

    return {
        "date": req_date.isoformat(),
        "metrics": {
            "scheduled": total_employees,
            "present": present_count,
            "late": late_count,
            "total_marked": total_marked,
            "not_marked": not_marked_count,
            "pending_requests": pending_requests,
            "rejected_requests": rejected_requests
        }
    }

@router.get("/attendance/today", response_model=dict)
def get_today_attendance(
    target_date: Optional[str] = None,
    user_id: Optional[int] = None,
    status_filter: Optional[str] = Query(None, alias="status"),
    page: int = Query(1, ge=1),
    limit: int = Query(50, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Paginated list of attendance records for a specified date with telemetry."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()
    query = db.query(Attendance).join(User).filter(Attendance.attendance_date == req_date)

    if user_id:
        query = query.filter(Attendance.user_id == user_id)
    if status_filter:
        query = query.filter(Attendance.status == status_filter.upper())

    total = query.count()
    records = query.order_by(desc(Attendance.timestamp)).offset((page - 1) * limit).limit(limit).all()

    result = []
    for rec in records:
        u = db.query(User).filter(User.id == rec.user_id).first()
        result.append({
            "id": rec.id,
            "user_id": rec.user_id,
            "employee_id": u.employee_id if u else None,
            "full_name": u.full_name if u else None,
            "attendance_date": rec.attendance_date.isoformat(),
            "verification_no": rec.verification_no,
            "verification_window": rec.verification_window,
            "timestamp": rec.timestamp.isoformat(),
            "status": rec.status.value if hasattr(rec.status, 'value') else str(rec.status),
            "verification_status": rec.verification_status,
            "verified_latitude": float(rec.verified_latitude),
            "verified_longitude": float(rec.verified_longitude),
            "verified_distance_meters": rec.verified_distance_meters,
            "gps_accuracy": rec.gps_accuracy,
            "face_similarity_score": rec.face_similarity_score,
            "liveness_result": rec.liveness_result,
            "device_id": rec.device_id
        })

    return {
        "date": req_date.isoformat(),
        "total": total,
        "page": page,
        "limit": limit,
        "records": result
    }

@router.get("/attendance/present", response_model=dict)
def get_present_employees(
    target_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Get list of employees marked PRESENT for the given date."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()
    records = db.query(Attendance).join(User).filter(Attendance.attendance_date == req_date, Attendance.status == AttendanceStatus.PRESENT).all()
    
    data = []
    for r in records:
        u = db.query(User).filter(User.id == r.user_id).first()
        data.append({
            "user_id": r.user_id,
            "employee_id": u.employee_id if u else None,
            "full_name": u.full_name if u else None,
            "timestamp": r.timestamp.isoformat(),
            "verification_no": r.verification_no
        })
    return {"date": req_date.isoformat(), "count": len(data), "employees": data}

@router.get("/attendance/late", response_model=dict)
def get_late_employees(
    target_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Get list of employees marked LATE for the given date."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()
    records = db.query(Attendance).join(User).filter(Attendance.attendance_date == req_date, Attendance.status == AttendanceStatus.LATE).all()
    
    data = []
    for r in records:
        u = db.query(User).filter(User.id == r.user_id).first()
        data.append({
            "user_id": r.user_id,
            "employee_id": u.employee_id if u else None,
            "full_name": u.full_name if u else None,
            "timestamp": r.timestamp.isoformat(),
            "verification_no": r.verification_no
        })
    return {"date": req_date.isoformat(), "count": len(data), "employees": data}

@router.get("/attendance/not-marked", response_model=dict)
def get_not_marked_employees(
    target_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Missing attendance list (active staff who haven't marked attendance today)."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()
    
    marked_user_ids = [r[0] for r in db.query(Attendance.user_id).filter(Attendance.attendance_date == req_date).distinct().all()]
    
    unmarked_users = db.query(User).filter(
        User.role == UserRole.USER,
        User.is_active == True,
        ~User.id.in_(marked_user_ids) if marked_user_ids else True
    ).all()

    data = [{"user_id": u.id, "employee_id": u.employee_id, "full_name": u.full_name} for u in unmarked_users]
    return {"date": req_date.isoformat(), "count": len(data), "employees": data}

@router.get("/employees", response_model=dict)
def search_employee_directory(
    query: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Searchable employee directory for Time Office staff."""
    q = db.query(User)
    if query:
        q = q.filter(or_(
            User.employee_id.ilike(f"%{query}%"),
            User.full_name.ilike(f"%{query}%"),
            User.department.ilike(f"%{query}%")
        ))
    
    users = q.order_by(desc(User.id)).all()
    result = []
    for u in users:
        geo = db.query(Geofence).filter(Geofence.user_id == u.id).first()
        win = db.query(AttendanceWindow).filter(AttendanceWindow.user_id == u.id).first()
        result.append({
            "id": u.id,
            "employee_id": u.employee_id,
            "full_name": u.full_name,
            "role": u.role.value if hasattr(u.role, 'value') else str(u.role),
            "is_active": u.is_active,
            "department": u.department,
            "department_id": u.department_id,
            "unit_number": u.unit_number,
            "designation": u.designation,
            "geofence": {
                "location_name": geo.location_name if geo else None,
                "latitude": float(geo.latitude) if geo else None,
                "longitude": float(geo.longitude) if geo else None,
                "radius_meters": geo.radius_meters if geo else None
            } if geo else None,
            "window": {
                "start_time": str(win.start_time) if win else None,
                "end_time": str(win.end_time) if win else None
            } if win else None
        })

    return {"count": len(result), "employees": result}

@router.post("/employees", response_model=dict)
def create_employee_time_office(
    user_in: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Create a new employee with department, unit_number, role, and initial password."""
    existing = db.query(User).filter(User.employee_id == user_in.employee_id).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Employee ID '{user_in.employee_id}' is already registered",
        )

    init_pwd = user_in.initial_password if user_in.initial_password else user_in.employee_id
    pwd_hash = get_password_hash(init_pwd)

    new_user = User(
        employee_id=user_in.employee_id,
        full_name=user_in.full_name,
        password_hash=pwd_hash,
        role=user_in.role or UserRole.USER,
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
        actor_user_id=current_user.id,
        target_user_id=new_user.id,
        details={
            "employee_id": new_user.employee_id,
            "full_name": new_user.full_name,
            "department": new_user.department,
            "department_id": new_user.department_id,
            "unit_number": new_user.unit_number
        }
    )

    return {
        "id": new_user.id,
        "employee_id": new_user.employee_id,
        "full_name": new_user.full_name,
        "role": new_user.role.value if hasattr(new_user.role, 'value') else str(new_user.role),
        "is_active": new_user.is_active,
        "department": new_user.department,
        "department_id": new_user.department_id,
        "unit_number": new_user.unit_number,
        "designation": new_user.designation,
        "message": f"Employee {new_user.employee_id} created successfully"
    }

@router.put("/employees/{user_id}", response_model=dict)
def update_employee_time_office(
    user_id: int,
    user_update: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Update employee master details including department, unit number, role, or active status."""
    u = db.query(User).filter(User.id == user_id).first()
    if not u:
        raise HTTPException(status_code=404, detail="Employee not found")

    if user_update.full_name is not None:
        u.full_name = user_update.full_name
    if user_update.role is not None:
        u.role = user_update.role
    if user_update.is_active is not None:
        u.is_active = user_update.is_active
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
        actor_user_id=current_user.id,
        target_user_id=u.id,
        details={
            "employee_id": u.employee_id,
            "full_name": u.full_name,
            "department": u.department,
            "department_id": u.department_id,
            "unit_number": u.unit_number
        }
    )

    return {
        "id": u.id,
        "employee_id": u.employee_id,
        "full_name": u.full_name,
        "role": u.role.value if hasattr(u.role, 'value') else str(u.role),
        "is_active": u.is_active,
        "department": u.department,
        "department_id": u.department_id,
        "unit_number": u.unit_number,
        "designation": u.designation,
        "message": f"Employee {u.employee_id} updated successfully"
    }

@router.get("/employees/{user_id}", response_model=dict)
def get_employee_profile(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Full employee profile with 30-day attendance history and attempts telemetry."""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Employee not found")

    recent_attendance = db.query(Attendance).filter(Attendance.user_id == user_id).order_by(desc(Attendance.attendance_date)).limit(30).all()
    recent_attempts = db.query(AttendanceAttempt).filter(AttendanceAttempt.user_id == user_id).order_by(desc(AttendanceAttempt.timestamp)).limit(30).all()

    geo = db.query(Geofence).filter(Geofence.user_id == user_id).first()

    return {
        "id": user.id,
        "user_id": user.id,
        "employee_id": user.employee_id,
        "full_name": user.full_name,
        "role": user.role.value if hasattr(user.role, 'value') else str(user.role),
        "is_active": user.is_active,
        "department": user.department,
        "department_id": user.department_id,
        "unit_number": user.unit_number,
        "designation": user.designation,
        "geofence": {
            "location_name": geo.location_name,
            "latitude": float(geo.latitude),
            "longitude": float(geo.longitude),
            "radius_meters": geo.radius_meters
        } if geo else None,
        "attendance_history": [
            {
                "id": a.id,
                "date": a.attendance_date.isoformat(),
                "status": a.status.value if hasattr(a.status, 'value') else str(a.status),
                "timestamp": a.timestamp.isoformat(),
                "verification_no": a.verification_no
            } for a in recent_attendance
        ],
        "attempt_history": [
            {
                "id": att.id,
                "timestamp": att.timestamp.isoformat(),
                "status": att.attempt_status.value if hasattr(att.attempt_status, 'value') else str(att.attempt_status),
                "rejection_reason": att.rejection_reason.value if hasattr(att.rejection_reason, 'value') else str(att.rejection_reason) if att.rejection_reason else None
            } for att in recent_attempts
        ]
    }

@router.get("/shifts", response_model=dict)
def get_shifts_list(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Dynamic shifts list and active assignments with complete rules metadata."""
    shifts = db.query(Shift).all()
    result = []
    for s in shifts:
        periods = db.query(ShiftPunchPeriod).filter(ShiftPunchPeriod.shift_id == s.id).order_by(ShiftPunchPeriod.priority.asc(), ShiftPunchPeriod.punch_no.asc()).all()
        rules_list = []
        if periods:
            for p in periods:
                rules_list.append({
                    "id": p.id,
                    "punch_no": p.punch_no,
                    "verification_no": p.punch_no,
                    "period_name": p.period_name,
                    "rule_name": p.period_name,
                    "start_time": str(p.start_time),
                    "end_time": str(p.end_time),
                    "result_code": getattr(p, "result_code", "PRESENT"),
                    "priority": p.priority,
                    "require_face_verification": p.require_face_verification,
                    "show_in_user_schedule": p.show_in_user_schedule,
                    "is_active": p.is_active
                })
        else:
            legacy_rules = db.query(ShiftRule).filter(ShiftRule.shift_id == s.id).order_by(ShiftRule.priority.asc()).all()
            for r in legacy_rules:
                p_no = getattr(r, "verification_no", 1)
                rules_list.append({
                    "id": r.id,
                    "punch_no": p_no,
                    "verification_no": p_no,
                    "period_name": r.rule_name,
                    "rule_name": r.rule_name,
                    "start_time": str(r.start_time),
                    "end_time": str(r.end_time),
                    "result_code": r.result_code,
                    "priority": r.priority,
                    "require_face_verification": True,
                    "show_in_user_schedule": r.show_in_user_schedule,
                    "is_active": r.is_active
                })

        result.append({
            "id": s.id,
            "shift_code": s.shift_code,
            "shift_name": s.shift_name,
            "description": s.description,
            "is_active": s.is_active,
            "punch_periods": rules_list,
            "rules": rules_list
        })
    return {"count": len(result), "shifts": result}

@router.get("/shift-monitoring", response_model=dict)
def monitor_shifts_realtime(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Real-time punch window state tracking (ACTIVE_NOW, UPCOMING, CLOSED)."""
    now_time = datetime.now().time()
    periods = db.query(ShiftPunchPeriod).all()

    monitoring = []
    for p in periods:
        state = "CLOSED"
        if p.start_time <= now_time <= p.end_time:
            state = "ACTIVE_NOW"
        elif now_time < p.start_time:
            state = "UPCOMING"

        shift = db.query(Shift).filter(Shift.id == p.shift_id).first()
        monitoring.append({
            "period_id": p.id,
            "shift_name": shift.shift_name if shift else None,
            "period_name": p.period_name,
            "start_time": str(p.start_time),
            "end_time": str(p.end_time),
            "window_state": state
        })
    return {"current_time": str(now_time), "monitoring": monitoring}

@router.get("/attempts", response_model=dict)
def get_attempts_telemetry(
    target_date: Optional[str] = None,
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Diagnostic telemetry for investigating failed attendance attempts."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()

    start_dt = datetime.combine(req_date, datetime.min.time())
    end_dt = datetime.combine(req_date, datetime.max.time())

    attempts = db.query(AttendanceAttempt).filter(
        AttendanceAttempt.timestamp >= start_dt,
        AttendanceAttempt.timestamp <= end_dt
    ).order_by(desc(AttendanceAttempt.timestamp)).limit(limit).all()

    result = []
    for att in attempts:
        u = db.query(User).filter(User.id == att.user_id).first()
        result.append({
            "id": att.id,
            "user_id": att.user_id,
            "employee_id": u.employee_id if u else None,
            "full_name": u.full_name if u else None,
            "timestamp": att.timestamp.isoformat(),
            "attempt_status": att.attempt_status.value if hasattr(att.attempt_status, 'value') else str(att.attempt_status),
            "rejection_reason": att.rejection_reason.value if hasattr(att.rejection_reason, 'value') else str(att.rejection_reason) if att.rejection_reason else None,
            "latitude": float(att.latitude) if att.latitude else None,
            "longitude": float(att.longitude) if att.longitude else None,
            "calculated_distance_meters": att.calculated_distance_meters,
            "face_similarity_score": att.face_similarity_score,
            "liveness_result": att.liveness_result
        })

    return {"date": req_date.isoformat(), "count": len(result), "attempts": result}

@router.get("/requests", response_model=dict)
def get_attendance_requests(
    status_filter: Optional[str] = Query(None, alias="status"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Fallback attendance requests awaiting review."""
    q = db.query(AttendanceRequest)
    if status_filter:
        q = q.filter(AttendanceRequest.status == status_filter.upper())
    
    requests = q.order_by(desc(AttendanceRequest.created_at)).all()
    result = []
    for r in requests:
        u = db.query(User).filter(User.id == r.user_id).first()
        result.append({
            "id": r.id,
            "user_id": r.user_id,
            "employee_id": u.employee_id if u else None,
            "full_name": u.full_name if u else None,
            "request_date": r.request_date.isoformat(),
            "verification_no": r.verification_no,
            "status": r.status,
            "rejection_reason_trigger": r.rejection_reason_trigger,
            "latitude": float(r.latitude),
            "longitude": float(r.longitude),
            "distance_from_location": r.distance_from_location,
            "location_name": r.location_name,
            "admin_notes": r.admin_notes,
            "created_at": r.created_at.isoformat()
        })
    return {"count": len(result), "requests": result}

@router.get("/requests/{request_id}/image")
def get_request_evidence_image(
    request_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Binary JPEG evidence selfie with burned metadata."""
    req = db.query(AttendanceRequest).filter(AttendanceRequest.id == request_id).first()
    if not req or not req.evidence_image:
        raise HTTPException(status_code=404, detail="Evidence image not found")
    
    return Response(content=req.evidence_image, media_type="image/jpeg")

@router.post("/requests/{request_id}/approve", response_model=dict)
def approve_attendance_request(
    request_id: int,
    payload: Optional[ApprovalActionRequest] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Approve fallback request and generate official attendance record."""
    req = db.query(AttendanceRequest).filter(AttendanceRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Attendance request not found")
    if req.status != "PENDING":
        raise HTTPException(status_code=400, detail=f"Request is already {req.status}")

    req.status = "APPROVED"
    req.admin_notes = payload.admin_notes if payload else "Approved by Time Office"
    req.reviewed_by_user_id = current_user.id
    req.reviewed_at = datetime.utcnow()

    # Create official Attendance record if not already present
    existing_att = db.query(Attendance).filter(
        Attendance.user_id == req.user_id,
        Attendance.attendance_date == req.request_date,
        Attendance.verification_no == req.verification_no
    ).first()

    if not existing_att:
        att = Attendance(
            user_id=req.user_id,
            attendance_date=req.request_date,
            verification_no=req.verification_no,
            verification_window="OFFICE_APPROVED",
            status=AttendanceStatus.PRESENT,
            verification_status="CONFIRMED",
            verification_mode="REQUEST_APPROVAL",
            attendance_request_id=req.id,
            verified_latitude=req.latitude,
            verified_longitude=req.longitude,
            verified_distance_meters=req.distance_from_location,
            gps_accuracy=req.gps_accuracy,
            face_similarity_score=1.0,
            face_result="APPROVED",
            liveness_score=1.0,
            liveness_result="REAL"
        )
        db.add(att)

    # Log Audit
    audit = AuditLog(
        actor_user_id=current_user.id,
        action="APPROVE_ATTENDANCE_REQUEST",
        target_user_id=req.user_id,
        details={"request_id": req.id, "notes": req.admin_notes}
    )
    db.add(audit)
    db.commit()

    return {"status": "SUCCESS", "message": f"Request #{request_id} approved successfully"}

@router.post("/requests/{request_id}/reject", response_model=dict)
def reject_attendance_request(
    request_id: int,
    payload: Optional[ApprovalActionRequest] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Reject fallback request with operator notes."""
    req = db.query(AttendanceRequest).filter(AttendanceRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Attendance request not found")
    if req.status != "PENDING":
        raise HTTPException(status_code=400, detail=f"Request is already {req.status}")

    req.status = "REJECTED"
    req.admin_notes = payload.admin_notes if payload else "Rejected by Time Office"
    req.reviewed_by_user_id = current_user.id
    req.reviewed_at = datetime.utcnow()

    # Log Audit
    audit = AuditLog(
        actor_user_id=current_user.id,
        action="REJECT_ATTENDANCE_REQUEST",
        target_user_id=req.user_id,
        details={"request_id": req.id, "notes": req.admin_notes}
    )
    db.add(audit)
    db.commit()

    return {"status": "SUCCESS", "message": f"Request #{request_id} rejected"}

@router.post("/attendance/correction", response_model=dict)
def make_attendance_correction(
    payload: AttendanceCorrectionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Controlled attendance correction with mandatory audit reason."""
    att_date = date.fromisoformat(payload.attendance_date)
    att = db.query(Attendance).filter(
        Attendance.user_id == payload.user_id,
        Attendance.attendance_date == att_date,
        Attendance.verification_no == payload.verification_no
    ).first()

    old_status = att.status.value if att and hasattr(att.status, 'value') else (str(att.status) if att else "NONE")

    if not att:
        # Create correction record
        geo = db.query(Geofence).filter(Geofence.user_id == payload.user_id).first()
        lat = geo.latitude if geo else 0.0
        lng = geo.longitude if geo else 0.0

        att = Attendance(
            user_id=payload.user_id,
            attendance_date=att_date,
            verification_no=payload.verification_no,
            verification_window="TIME_OFFICE_CORRECTION",
            status=AttendanceStatus[payload.status.upper()],
            verification_status="CORRECTED",
            verification_mode="MANUAL_CORRECTION",
            verified_latitude=lat,
            verified_longitude=lng,
            verified_distance_meters=0.0,
            face_similarity_score=1.0,
            face_result="MANUAL",
            liveness_score=1.0,
            liveness_result="MANUAL"
        )
        db.add(att)
    else:
        att.status = AttendanceStatus[payload.status.upper()]
        att.verification_status = "CORRECTED"

    # Audit Log
    audit = AuditLog(
        actor_user_id=current_user.id,
        action="ATTENDANCE_CORRECTION",
        target_user_id=payload.user_id,
        details={
            "attendance_date": payload.attendance_date,
            "verification_no": payload.verification_no,
            "old_status": old_status,
            "new_status": payload.status.upper(),
            "reason": payload.reason
        }
    )
    db.add(audit)
    db.commit()

    return {"status": "SUCCESS", "message": "Attendance correction applied successfully"}

@router.get("/reports/daily", response_model=dict)
def get_daily_summary_report(
    target_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Daily roll-up report for CSV/Excel export."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()
    users = db.query(User).filter(User.role == UserRole.USER, User.is_active == True).all()

    report = []
    for u in users:
        atts = db.query(Attendance).filter(Attendance.user_id == u.id, Attendance.attendance_date == req_date).order_by(Attendance.verification_no).all()
        status_summary = "NOT_MARKED"
        if atts:
            status_summary = ", ".join([f"V{a.verification_no}:{a.status.value if hasattr(a.status, 'value') else a.status}" for a in atts])

        report.append({
            "employee_id": u.employee_id,
            "full_name": u.full_name,
            "date": req_date.isoformat(),
            "status_summary": status_summary,
            "verification_count": len(atts)
        })

    return {"date": req_date.isoformat(), "total_records": len(report), "report": report}

@router.get("/reports/shift", response_model=dict)
def get_shift_summary_report(
    target_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Shift-wise summary report for CSV/Excel export."""
    req_date = date.fromisoformat(target_date) if target_date else date.today()
    shifts = db.query(Shift).all()

    report = []
    for s in shifts:
        assignments = db.query(EmployeeShiftAssignment).filter(EmployeeShiftAssignment.shift_id == s.id, EmployeeShiftAssignment.is_active == True).all()
        user_ids = [a.user_id for a in assignments]

        marked = db.query(func.count(func.distinct(Attendance.user_id))).filter(
            Attendance.attendance_date == req_date,
            Attendance.user_id.in_(user_ids) if user_ids else False
        ).scalar() or 0

        report.append({
            "shift_code": s.shift_code,
            "shift_name": s.shift_name,
            "total_assigned": len(user_ids),
            "marked_present": marked,
            "absent_count": max(0, len(user_ids) - marked)
        })

    return {"date": req_date.isoformat(), "shift_report": report}

@router.get("/reports/present-first-punch", response_model=dict)
def get_present_first_punch_report(
    date_param: Optional[str] = Query(None, alias="date"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """
    Present Report – 1st Punch:
    Returns employees with a valid successful attendance punch on a selected date and displays ONLY their earliest valid punch of that date.
    """
    from app.services.shift_service import ShiftService

    if date_param:
        try:
            req_date = date.fromisoformat(date_param)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
    else:
        req_date = date.today()

    # Query distinct user_ids with their earliest valid punch timestamp on req_date
    first_punches = (
        db.query(
            Attendance.user_id,
            func.min(Attendance.timestamp).label("min_timestamp")
        )
        .filter(Attendance.attendance_date == req_date)
        .group_by(Attendance.user_id)
        .all()
    )

    data = []
    for user_id, min_timestamp in first_punches:
        u = db.query(User).filter(User.id == user_id, User.is_active == True).first()
        if not u:
            continue

        # Fetch the specific Attendance record corresponding to the earliest punch
        rec = (
            db.query(Attendance)
            .filter(
                Attendance.user_id == user_id,
                Attendance.attendance_date == req_date,
                Attendance.timestamp == min_timestamp
            )
            .first()
        )
        if not rec:
            continue

        # Format first_punch_time from stored authoritative server timestamp
        punch_time_str = rec.timestamp.strftime("%I:%M:%S %p")

        # Resolve Shift Name
        shift_name = "N/A"
        shift_obj = None
        if rec.shift_id:
            shift_obj = db.query(Shift).filter(Shift.id == rec.shift_id).first()
        if not shift_obj:
            shift_obj = ShiftService.get_effective_shift_for_user(db, u.id, req_date)
        if shift_obj:
            shift_name = shift_obj.shift_name

        # Resolve Location Name from Geofence
        geo = db.query(Geofence).filter(Geofence.user_id == u.id).first()
        location_name = geo.location_name if geo else "N/A"

        # Determine Late Status
        rec_status = rec.status.value if hasattr(rec.status, "value") else str(rec.status)
        late_status = "LATE" if rec_status == "LATE" else "ON_TIME"

        if late_status == "ON_TIME" and shift_obj and shift_obj.punch_periods:
            first_period = shift_obj.punch_periods[0]
            if first_period and first_period.start_time:
                if rec.timestamp.time() > first_period.start_time:
                    late_status = "LATE"

        data.append({
            "employee_id": u.employee_id,
            "employee_name": u.full_name,
            "department": "N/A",
            "shift_name": shift_name,
            "attendance_date": req_date.isoformat(),
            "first_punch_time": punch_time_str,
            "attendance_status": "PRESENT",
            "late_status": late_status,
            "location_name": location_name
        })

    data.sort(key=lambda x: x["employee_id"])

    return {
        "success": True,
        "date": req_date.isoformat(),
        "data": data,
        "total": len(data)
    }

@router.get("/reports/absent-first-punch", response_model=dict)
def get_absent_first_punch_report(
    date_param: Optional[str] = Query(None, alias="date"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """
    Absent Report – 1st Punch:
    Identifies active employees scheduled for the selected date who did NOT complete a valid attendance punch during their assigned shift's FIRST punch/verification period.
    """
    from app.services.shift_service import ShiftService

    if date_param:
        try:
            req_date = date.fromisoformat(date_param)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
    else:
        req_date = date.today()

    users = db.query(User).filter(User.role == UserRole.USER, User.is_active == True).all()

    data = []
    for u in users:
        # 1. Resolve active assigned shift
        shift_obj = ShiftService.get_effective_shift_for_user(db, u.id, req_date)
        if not shift_obj or not shift_obj.is_active:
            continue

        # 2. Check Holiday & Weekly Off
        if shift_obj.day_type_policy:
            day_type_val = (
                shift_obj.day_type_policy.day_type.value
                if hasattr(shift_obj.day_type_policy.day_type, 'value')
                else str(shift_obj.day_type_policy.day_type)
            )
            if day_type_val in ["HOLIDAY", "WEEK_OFF"]:
                continue

        win = db.query(AttendanceWindow).filter(AttendanceWindow.user_id == u.id, AttendanceWindow.is_active == True).first()
        if win and win.allowed_days is not None and isinstance(win.allowed_days, list) and len(win.allowed_days) > 0:
            iso_wday = req_date.isoweekday()
            if iso_wday not in win.allowed_days and (iso_wday - 1) not in win.allowed_days:
                continue

        # 3. Resolve the configured FIRST punch period for that shift
        first_period_start = None
        first_period_end = None

        if shift_obj.punch_periods and len(shift_obj.punch_periods) > 0:
            sorted_periods = sorted(shift_obj.punch_periods, key=lambda p: (p.punch_no, p.priority))
            first_p = sorted_periods[0]
            first_period_start = first_p.start_time
            first_period_end = first_p.end_time
        elif shift_obj.rules and len(shift_obj.rules) > 0:
            sorted_rules = sorted(shift_obj.rules, key=lambda r: (r.verification_no, r.priority))
            first_r = sorted_rules[0]
            first_period_start = first_r.start_time
            first_period_end = first_r.end_time

        if not first_period_start or not first_period_end:
            continue

        # 4. Fetch all valid successful attendance punches for employee on req_date
        atts = (
            db.query(Attendance)
            .filter(Attendance.user_id == u.id, Attendance.attendance_date == req_date)
            .order_by(Attendance.timestamp.asc())
            .all()
        )

        # 5. Check if employee completed a valid punch inside the first-punch window
        has_first_window_punch = any(
            first_period_start <= a.timestamp.time() <= first_period_end
            for a in atts
        )

        if has_first_window_punch:
            # Employee successfully punched inside the 1st window -> EXCLUDED
            continue

        # Employee missed the first punch window -> INCLUDED as ABSENT_FIRST_PUNCH
        actual_first_valid_punch = "-"
        punch_timing = "NO_PUNCH"

        if atts and len(atts) > 0:
            # Employee has a valid punch later in the day
            earliest_later_punch = atts[0]
            actual_first_valid_punch = earliest_later_punch.timestamp.strftime("%I:%M:%S %p")
            punch_timing = "PUNCHED_AFTER_WINDOW"

        geo = db.query(Geofence).filter(Geofence.user_id == u.id).first()
        location_name = geo.location_name if geo else "N/A"

        data.append({
            "employee_id": u.employee_id,
            "employee_name": u.full_name,
            "department": "N/A",
            "shift_code": shift_obj.shift_code,
            "shift_name": shift_obj.shift_name,
            "attendance_date": req_date.isoformat(),
            "first_punch_window_start": first_period_start.strftime("%I:%M:%S %p") if hasattr(first_period_start, 'strftime') else str(first_period_start),
            "first_punch_window_end": first_period_end.strftime("%I:%M:%S %p") if hasattr(first_period_end, 'strftime') else str(first_period_end),
            "first_punch_status": "ABSENT_FIRST_PUNCH",
            "actual_first_valid_punch": actual_first_valid_punch,
            "punch_timing": punch_timing,
            "location_name": location_name
        })

    data.sort(key=lambda x: x["employee_id"])

    return {
        "success": True,
        "date": req_date.isoformat(),
        "data": data,
        "total": len(data)
    }

@router.get("/reports/raw-dataset", response_model=dict)
def get_raw_report_dataset(
    date_param: Optional[str] = Query(None, alias="date"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """
    Configuration-Driven Raw Dataset Endpoint:
    Exposes raw employees, shifts, punch periods, employee shift assignments,
    raw attendance punches, and database-driven attendance rule configurations.
    Contains ZERO hardcoded business classification logic.
    """
    if date_param:
        try:
            req_date = date.fromisoformat(date_param)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")
    else:
        req_date = date.today()

    # 1. Raw Employees
    users = db.query(User).filter(User.role == UserRole.USER, User.is_active == True).all()
    employees_data = []
    for u in users:
        geo = db.query(Geofence).filter(Geofence.user_id == u.id).first()
        employees_data.append({
            "id": u.id,
            "employee_id": u.employee_id,
            "full_name": u.full_name,
            "department": u.department or "General / Unassigned",
            "location_name": geo.location_name if geo else "N/A",
            "is_active": u.is_active
        })

    # 2. Raw Shifts with Periods
    shifts = db.query(Shift).filter(Shift.is_active == True).all()
    shifts_data = []
    for s in shifts:
        periods = db.query(ShiftPunchPeriod).filter(
            ShiftPunchPeriod.shift_id == s.id,
            ShiftPunchPeriod.is_active == True
        ).order_by(ShiftPunchPeriod.priority.asc(), ShiftPunchPeriod.punch_no.asc()).all()

        shifts_data.append({
            "id": s.id,
            "shift_code": s.shift_code,
            "shift_name": s.shift_name,
            "is_active": s.is_active,
            "punch_periods": [
                {
                    "id": p.id,
                    "punch_no": p.punch_no,
                    "period_name": p.period_name,
                    "period_type": "FIRST_PUNCH" if p.punch_no == 1 else f"PUNCH_{p.punch_no}",
                    "start_time": str(p.start_time),
                    "end_time": str(p.end_time),
                    "priority": p.priority,
                    "is_active": p.is_active
                } for p in periods
            ]
        })

    # 3. Employee Shift Assignments
    assignments = db.query(EmployeeShiftAssignment).filter(EmployeeShiftAssignment.is_active == True).all()
    assignments_data = [
        {
            "id": a.id,
            "user_id": a.user_id,
            "shift_id": a.shift_id,
            "effective_from": a.effective_from.isoformat() if a.effective_from else None,
            "effective_to": a.effective_to.isoformat() if a.effective_to else None
        } for a in assignments
    ]

    # 4. Raw Attendance Punches for Target Date
    punches = db.query(Attendance).filter(Attendance.attendance_date == req_date).order_by(Attendance.timestamp.asc()).all()
    punches_data = [
        {
            "id": p.id,
            "user_id": p.user_id,
            "attendance_date": p.attendance_date.isoformat(),
            "verification_no": p.verification_no,
            "timestamp": p.timestamp.strftime("%Y-%m-%d %H:%M:%S"),
            "time_str": p.timestamp.strftime("%I:%M:%S %p"),
            "time_24": p.timestamp.strftime("%H:%M:%S"),
            "status": p.status.value if hasattr(p.status, 'value') else str(p.status)
        } for p in punches
    ]

    # 5. Database-Driven Attendance Rule Configuration & Status Metadata
    rule_configuration = {
        "status_definitions": [
            {"code": "PRESENT", "label": "Present", "display_type": "success"},
            {"code": "LATE", "label": "Late", "display_type": "warning"},
            {"code": "ABSENT_FIRST_PUNCH", "label": "Absent – 1st Punch", "display_type": "danger"},
            {"code": "FULL_DAY_ABSENT", "label": "Full-Day Absent", "display_type": "danger"},
            {"code": "HALF_DAY", "label": "Half-Day", "display_type": "warning"},
            {"code": "ON_TIME", "label": "On Time", "display_type": "success"},
            {"code": "NOT_YET_PUNCHED", "label": "Not Yet Punched", "display_type": "neutral"},
            {"code": "HOLIDAY", "label": "Holiday", "display_type": "info"},
            {"code": "WEEK_OFF", "label": "Weekly Off", "display_type": "info"}
        ],
        "rules": [
            {
                "rule_id": "RULE_FIRST_PUNCH_PRESENT",
                "name": "First Punch Present Rule",
                "enabled": True,
                "priority": 10,
                "conditions": [
                    {"field": "is_scheduled", "operator": "EQUAL", "value": True},
                    {"field": "has_first_window_punch", "operator": "EQUAL", "value": True}
                ],
                "actions": [
                    {"field": "attendance_status", "value": "PRESENT"},
                    {"field": "first_punch_status", "value": "PRESENT_FIRST_PUNCH"}
                ]
            },
            {
                "rule_id": "RULE_FIRST_PUNCH_LATE",
                "name": "First Punch Late Rule",
                "enabled": True,
                "priority": 20,
                "conditions": [
                    {"field": "is_scheduled", "operator": "EQUAL", "value": True},
                    {"field": "has_first_window_punch", "operator": "EQUAL", "value": True},
                    {"field": "is_after_period_start", "operator": "EQUAL", "value": True}
                ],
                "actions": [
                    {"field": "attendance_status", "value": "PRESENT"},
                    {"field": "timing_status", "value": "LATE"}
                ]
            },
            {
                "rule_id": "RULE_FIRST_PUNCH_ABSENT",
                "name": "First Punch Absent Rule",
                "enabled": True,
                "priority": 30,
                "conditions": [
                    {"field": "is_scheduled", "operator": "EQUAL", "value": True},
                    {"field": "has_first_window_punch", "operator": "EQUAL", "value": False}
                ],
                "actions": [
                    {"field": "attendance_status", "value": "ABSENT_FIRST_PUNCH"},
                    {"field": "first_punch_status", "value": "ABSENT_FIRST_PUNCH"}
                ]
            },
            {
                "rule_id": "RULE_FULL_DAY_ABSENT",
                "name": "Full Day Absence Evaluation Rule",
                "enabled": True,
                "priority": 40,
                "conditions": [
                    {"field": "is_scheduled", "operator": "EQUAL", "value": True},
                    {"field": "is_holiday", "operator": "EQUAL", "value": False},
                    {"field": "is_weekly_off", "operator": "EQUAL", "value": False},
                    {"field": "completed_periods_count", "operator": "EQUAL", "value": 0}
                ],
                "actions": [
                    {"field": "full_day_status", "value": "FULL_DAY_ABSENT"},
                    {"field": "reason", "value": "No valid punches completed across required shift periods"}
                ]
            },
            {
                "rule_id": "RULE_HALF_DAY_ABSENT",
                "name": "Half Day Evaluation Rule",
                "enabled": True,
                "priority": 35,
                "conditions": [
                    {"field": "is_scheduled", "operator": "EQUAL", "value": True},
                    {"field": "is_holiday", "operator": "EQUAL", "value": False},
                    {"field": "is_weekly_off", "operator": "EQUAL", "value": False},
                    {"field": "completed_periods_count", "operator": "GREATER_THAN", "value": 0},
                    {"field": "completed_periods_count", "operator": "LESS_THAN", "value": "required_periods_count"}
                ],
                "actions": [
                    {"field": "full_day_status", "value": "HALF_DAY"},
                    {"field": "reason", "value": "Partial shift periods completed"}
                ]
            }
        ]
    }


    now = datetime.now()
    return {
        "success": True,
        "server_time": {
            "date": req_date.isoformat(),
            "time": now.strftime("%H:%M:%S"),
            "iso": now.isoformat(),
            "timezone": "Asia/Kolkata"
        },
        "raw_data": {
            "employees": employees_data,
            "shifts": shifts_data,
            "assignments": assignments_data,
            "punches": punches_data
        },
        "configuration": rule_configuration
    }

@router.get("/audit-logs", response_model=dict)
def get_audit_logs(
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Immutable audit trail viewer."""
    logs = db.query(AuditLog).order_by(desc(AuditLog.created_at)).limit(limit).all()
    result = []
    for l in logs:
        actor = db.query(User).filter(User.id == l.actor_user_id).first() if l.actor_user_id else None
        target = db.query(User).filter(User.id == l.target_user_id).first() if l.target_user_id else None
        result.append({
            "id": l.id,
            "actor": actor.employee_id if actor else "SYSTEM",
            "action": l.action,
            "target": target.employee_id if target else None,
            "details": l.details,
            "created_at": l.created_at.isoformat()
        })
    return {"count": len(result), "audit_logs": result}

# Pydantic Schemas & Routes for Holidays, Weekly Offs & Extra Work
class HolidayCreate(BaseModel):
    name: str = Field(..., description="Holiday Name")
    holiday_date: str = Field(..., description="YYYY-MM-DD Date")
    description: Optional[str] = Field(None, description="Optional description")
    is_optional: bool = Field(False)

class WeeklyOffCreate(BaseModel):
    day_of_week: int = Field(..., ge=0, le=6, description="0=Monday, 6=Sunday")
    day_name: str = Field(...)
    is_weekly_off: bool = Field(True)

@router.get("/holidays", response_model=dict)
def get_holidays(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """List all configured holidays from database master."""
    holidays = db.query(Holiday).filter(Holiday.is_active == True).order_by(Holiday.holiday_date.asc()).all()
    res = [{
        "id": h.id,
        "name": h.name,
        "holiday_date": h.holiday_date.isoformat(),
        "description": h.description,
        "is_optional": h.is_optional,
        "is_active": h.is_active
    } for h in holidays]
    return {"count": len(res), "holidays": res}

@router.post("/holidays", response_model=dict)
def create_holiday(
    h_in: HolidayCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Add a new holiday into database master."""
    try:
        h_date = date.fromisoformat(h_in.holiday_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format YYYY-MM-DD")
    
    existing = db.query(Holiday).filter(Holiday.holiday_date == h_date).first()
    if existing:
        raise HTTPException(status_code=400, detail=f"Holiday for date {h_in.holiday_date} already exists.")
    
    h = Holiday(
        name=h_in.name,
        holiday_date=h_date,
        description=h_in.description,
        is_optional=h_in.is_optional,
        is_active=True
    )
    db.add(h)
    db.commit()
    db.refresh(h)
    return {"id": h.id, "name": h.name, "holiday_date": h.holiday_date.isoformat(), "message": "Holiday added"}

@router.delete("/holidays/{holiday_id}", response_model=dict)
def delete_holiday(
    holiday_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Delete or deactivate a holiday."""
    h = db.query(Holiday).filter(Holiday.id == holiday_id).first()
    if not h:
        raise HTTPException(status_code=404, detail="Holiday not found")
    db.delete(h)
    db.commit()
    return {"message": "Holiday deleted"}

@router.get("/weekly-offs", response_model=dict)
def get_weekly_offs(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """List weekly-off day configurations."""
    woffs = db.query(WeeklyOffConfig).filter(WeeklyOffConfig.is_active == True).all()
    if not woffs:
        default_days = [
            {"day_of_week": 6, "day_name": "Sunday", "is_weekly_off": True}
        ]
        return {"count": len(default_days), "weekly_offs": default_days}
    res = [{
        "id": w.id,
        "day_of_week": w.day_of_week,
        "day_name": w.day_name,
        "is_weekly_off": w.is_weekly_off
    } for w in woffs]
    return {"count": len(res), "weekly_offs": res}

@router.get("/extra-work", response_model=dict)
def get_extra_work_report(
    date_param: Optional[str] = Query(None, alias="date"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Retrieve Extra Work / Overtime submissions submitted by mobile employees."""
    q = db.query(ExtraWorkRequest).join(User)
    if date_param:
        try:
            req_d = date.fromisoformat(date_param)
            q = q.filter(ExtraWorkRequest.work_date == req_d)
        except ValueError:
            pass
    items = q.order_by(desc(ExtraWorkRequest.created_at)).all()
    res = []
    for item in items:
        u = item.user
        res.append({
            "id": item.id,
            "user_id": item.user_id,
            "employee_id": u.employee_id if u else None,
            "full_name": u.full_name if u else None,
            "department": u.department if u else None,
            "work_date": item.work_date.isoformat(),
            "start_time": item.start_time,
            "end_time": item.end_time,
            "hours": item.hours,
            "location_name": item.location_name,
            "remarks": item.remarks,
            "status": item.status,
            "admin_notes": item.admin_notes,
            "created_at": item.created_at.isoformat()
        })
    return {"count": len(res), "records": res}

@router.post("/extra-work/{request_id}/approve", response_model=dict)
def approve_extra_work(
    request_id: int,
    action_in: ApprovalActionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    req = db.query(ExtraWorkRequest).filter(ExtraWorkRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Extra work request not found")
    req.status = "APPROVED"
    req.reviewed_by_id = current_user.id
    req.admin_notes = action_in.admin_notes
    db.commit()
    return {"message": "Extra work request approved", "id": req.id, "status": "APPROVED"}

@router.post("/extra-work/{request_id}/reject", response_model=dict)
def reject_extra_work(
    request_id: int,
    action_in: ApprovalActionRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    req = db.query(ExtraWorkRequest).filter(ExtraWorkRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Extra work request not found")
    req.status = "REJECTED"
    req.reviewed_by_id = current_user.id
    req.admin_notes = action_in.admin_notes
    db.commit()
    return {"message": "Extra work request rejected", "id": req.id, "status": "REJECTED"}

@router.get("/reports/multi-location", response_model=dict)
def get_multi_location_report(
    date_param: Optional[str] = Query(None, alias="date"),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office)
):
    """Retrieve raw attendance punches with full GPS location, accuracy, site details, and device ID."""
    req_date = date.fromisoformat(date_param) if date_param else date.today()
    records = db.query(Attendance).join(User).filter(Attendance.attendance_date == req_date).order_by(desc(Attendance.timestamp)).all()
    
    res = []
    for r in records:
        u = db.query(User).filter(User.id == r.user_id).first()
        geo = db.query(Geofence).filter(Geofence.user_id == r.user_id).first()
        res.append({
            "id": r.id,
            "employee_id": u.employee_id if u else None,
            "full_name": u.full_name if u else None,
            "department": u.department if u else "N/A",
            "attendance_date": r.attendance_date.isoformat(),
            "punch_time": r.timestamp.strftime("%I:%M:%S %p"),
            "verification_no": r.verification_no,
            "site_location": geo.location_name if geo else "Field Location",
            "latitude": float(r.verified_latitude),
            "longitude": float(r.verified_longitude),
            "gps_accuracy": r.gps_accuracy,
            "distance_meters": r.verified_distance_meters,
            "device_id": r.device_id,
            "source": r.source or "ONLINE"
        })
    return {"date": req_date.isoformat(), "count": len(res), "records": res}


