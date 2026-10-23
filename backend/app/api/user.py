import pytz
from datetime import datetime, date, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form, Request
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.models.attendance import Attendance
from app.schemas.attendance import (
    AttendanceConfigResponse,
    AttendanceVerifyResponse,
    AttendanceRecordResponse,
    TodayScheduleResponse,
    OfflineSyncBatchRequest,
    OfflineSyncBatchResponse,
    OfflineSyncItemResult,
)
from app.schemas.attendance_request import (
    ServerTimeResponse,
    AttendanceRequestResponse,
)
from app.models.attendance_request import AttendanceRequest, RequestStatus
from app.models.policy import ExtraWorkRequest
from app.dependencies import require_active_user
from app.services.attendance_decision_service import AttendanceDecisionService
from app.services.time_service import TimeService
from app.services.shift_service import ShiftService
from app.services.geofence_service import validate_geofence, is_valid_coordinate

router = APIRouter(prefix="/api/user", tags=["Field Staff Attendance"])

@router.get("/server-time", response_model=ServerTimeResponse)
def get_authoritative_server_time():
    """
    Authoritative server clock endpoint.
    Phone's own clock is never trusted for attendance decisions.
    Clients re-sync with this endpoint every 30 seconds.
    """
    return TimeService.get_current_server_time()

@router.get("/attendance-config", response_model=AttendanceConfigResponse)
def get_attendance_config(
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """
    Retrieve employee's assigned geofence, allowed radius, 3 daily verification windows,
    authoritative server time, active verification window, and today's verification statuses.
    """
    server_time_info = TimeService.get_current_server_time()

    gf_data = None
    if current_user.geofence:
        gf_data = {
            "location_name": current_user.geofence.location_name,
            "latitude": float(current_user.geofence.latitude),
            "longitude": float(current_user.geofence.longitude),
            "radius_meters": float(current_user.geofence.radius_meters),
            "is_active": current_user.geofence.is_active
        }

    win_data = None
    if current_user.attendance_window:
        win_data = {
            "start_time": current_user.attendance_window.start_time.strftime("%H:%M"),
            "end_time": current_user.attendance_window.end_time.strftime("%H:%M"),
            "timezone": current_user.attendance_window.timezone,
            "allowed_days": current_user.attendance_window.allowed_days,
            "is_active": current_user.attendance_window.is_active
        }

    tz = TimeService.get_server_timezone()
    raw_ts = server_time_info.get("server_timestamp")
    if isinstance(raw_ts, datetime):
        local_now = raw_ts.astimezone(tz) if raw_ts.tzinfo else raw_ts
        today_date = local_now.date()
        current_punch_time = local_now.time()
    else:
        try:
            today_date = datetime.strptime(server_time_info["server_date"], "%Y-%m-%d").date()
            current_punch_time = datetime.strptime(server_time_info["server_time"], "%H:%M:%S").time()
            local_now = datetime.combine(today_date, current_punch_time)
        except Exception:
            local_now = datetime.now(tz)
            today_date = local_now.date()
            current_punch_time = local_now.time()

    today_attendances = db.query(Attendance).filter(
        Attendance.user_id == current_user.id,
        Attendance.attendance_date == today_date
    ).all()

    effective_shift = ShiftService.get_effective_shift_for_user(db=db, user_id=current_user.id, target_date=today_date)

    windows_status_info = TimeService.get_all_windows_status(
        attendances=today_attendances,
        current_time=current_punch_time,
        shift=effective_shift
    )

    shift_data = None
    if effective_shift:
        classification, status_str, matched_rule = ShiftService.evaluate_punch_timestamp(
            shift=effective_shift,
            punch_time=current_punch_time
        )
        shift_data = {
            "id": effective_shift.id,
            "shift_code": effective_shift.shift_code,
            "shift_name": effective_shift.shift_name,
            "name": effective_shift.shift_name,
            "description": effective_shift.description,
            "current_classification": classification,
            "current_status": windows_status_info["verification_status"],
            "matched_rule": matched_rule.rule_name if matched_rule else None,
            "rules": windows_status_info["verification_rules"]
        }

    today_att_list = [
        {
            "id": att.id,
            "verification_no": att.verification_no,
            "verification_rule_id": getattr(att, "verification_rule_id", None),
            "verification_window": att.verification_window,
            "timestamp": att.timestamp.isoformat() if att.timestamp else None,
            "formatted_time": att.timestamp.strftime("%I:%M:%S %p") if att.timestamp else None,
            "status": att.status.value if hasattr(att.status, "value") else str(att.status),
            "verification_status": att.verification_status,
            "source": att.source
        }
        for att in today_attendances
    ]

    has_active_shift = (effective_shift is not None)

    return AttendanceConfigResponse(
        user_id=current_user.id,
        employee_id=current_user.employee_id,
        full_name=current_user.full_name,
        has_face_enrolled=current_user.face_template is not None,
        geofence=gf_data,
        attendance_window=win_data,
        shift=shift_data,
        assigned_shift=shift_data,
        server_time=server_time_info,
        today_status="PRESENT" if len(today_attendances) > 0 else None,
        today_attendance=today_att_list,
        has_active_shift=has_active_shift,
        current_verification=windows_status_info.get("current_verification"),
        verification_status=windows_status_info.get("verification_status", "CLOSED"),
        verification_rules=windows_status_info.get("verification_rules", []),
        verification_windows=windows_status_info.get("verification_windows", []),
        punch_periods=windows_status_info.get("punch_periods", []),
        next_verification=windows_status_info.get("next_verification"),
        attendance_action=windows_status_info.get("attendance_action"),
        face_enabled=getattr(current_user, "face_enabled", True),
        geofence_enabled=getattr(current_user, "geofence_enabled", True),
        shift_enabled=getattr(current_user, "shift_enabled", True),
        travel_map_enabled=getattr(current_user, "travel_map_enabled", True),
        device_binding_enabled=getattr(current_user, "device_binding_enabled", True),
        device_id=current_user.device_id,
        is_device_registered=bool(current_user.device_id and len(current_user.device_id.strip()) > 0)
    )

@router.get("/today-schedule", response_model=TodayScheduleResponse)
def get_today_schedule(
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """
    Authoritative endpoint returning today's punch schedule, active shift,
    server time, and dynamic attendance action state (punch_allowed / active_punch_period_id).
    """
    server_time_info = TimeService.get_current_server_time()
    tz = TimeService.get_server_timezone()
    raw_ts = server_time_info.get("server_timestamp")
    if isinstance(raw_ts, datetime):
        local_now = raw_ts.astimezone(tz) if raw_ts.tzinfo else raw_ts
        today_date = local_now.date()
        current_punch_time = local_now.time()
    else:
        try:
            today_date = datetime.strptime(server_time_info["server_date"], "%Y-%m-%d").date()
            current_punch_time = datetime.strptime(server_time_info["server_time"], "%H:%M:%S").time()
            local_now = datetime.combine(today_date, current_punch_time)
        except Exception:
            local_now = datetime.now(tz)
            today_date = local_now.date()
            current_punch_time = local_now.time()

    effective_shift = ShiftService.get_effective_shift_for_user(db=db, user_id=current_user.id, target_date=today_date)
    today_attendances = db.query(Attendance).filter(
        Attendance.user_id == current_user.id,
        Attendance.attendance_date == today_date
    ).all()

    windows_status_info = TimeService.get_all_windows_status(
        attendances=today_attendances,
        current_time=current_punch_time,
        shift=effective_shift
    )

    if not effective_shift:
        return TodayScheduleResponse(
            has_active_shift=False,
            shift=None,
            server_time=local_now.isoformat(),
            punch_periods=[],
            attendance_action={
                "punch_allowed": False,
                "active_punch_period_id": None,
                "active_punch_period_name": None,
                "reason": "NO_ACTIVE_SHIFT"
            }
        )

    shift_info = {
        "id": effective_shift.id,
        "shift_code": effective_shift.shift_code,
        "shift_name": effective_shift.shift_name,
        "name": effective_shift.shift_name,
        "description": effective_shift.description
    }

    return TodayScheduleResponse(
        has_active_shift=True,
        shift=shift_info,
        server_time=local_now.isoformat(),
        punch_periods=windows_status_info["punch_periods"],
        attendance_action=windows_status_info["attendance_action"]
    )

@router.post("/attendance/verify", response_model=AttendanceVerifyResponse)
async def verify_attendance(
    request: Request,
    current_latitude: float = Form(..., description="GPS Latitude"),
    current_longitude: float = Form(..., description="GPS Longitude"),
    gps_accuracy: Optional[float] = Form(None, description="GPS Accuracy in meters"),
    device_id: Optional[str] = Form(None, description="Client Device Hardware Identifier"),
    request_id: Optional[str] = Form(None, description="Replay Protection UUID/Nonce"),
    client_punch_id: Optional[str] = Form(None, description="Globally Unique Client Punch UUID"),
    punch_period_id: Optional[int] = Form(None, description="Target Punch Period ID"),
    verification_no: Optional[int] = Form(None, description="Target Verification Window Number"),
    verification_rule_id: Optional[int] = Form(None, description="Target Verification Rule ID"),
    device_wall_time: Optional[str] = Form(None, description="Client Wall Clock String for Audit"),
    frames: List[UploadFile] = File(..., description="Multi-frame live front-camera sequence"),
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """
    Authoritative server-side attendance verification endpoint.
    Evaluates dynamic multi-period verification shift rules configured by admin.
    """
    # Read frame bytes
    frames_bytes = []
    for f in frames:
        content = await f.read()
        if content:
            frames_bytes.append(content)

    if not frames_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="No camera frames provided")

    from starlette.concurrency import run_in_threadpool
    try:
        decision = await run_in_threadpool(
            AttendanceDecisionService.evaluate_attendance,
            db=db,
            user=current_user,
            current_lat=current_latitude,
            current_lon=current_longitude,
            gps_accuracy=gps_accuracy,
            frames_bytes_list=frames_bytes,
            device_id=device_id,
            request_id=request_id,
            ip_address=request.client.host if request.client else None,
            client_punch_id=client_punch_id,
            punch_period_id=punch_period_id,
            verification_no=verification_no,
            verification_rule_id=verification_rule_id,
            device_wall_time=device_wall_time
        )
        return decision
    except HTTPException:
        raise
    except Exception as e:
        db.rollback()
        import logging, traceback
        logging.getLogger(__name__).error(f"[verify_attendance] Internal error during verification: {e}\n{traceback.format_exc()}")
        return AttendanceVerifyResponse(
            success=False,
            decision="REJECTED",
            rejection_reason="BIOMETRIC_SERVICE_ERROR",
            message=f"Attendance verification temporarily unavailable: {str(e)}",
            timestamp=datetime.utcnow(),
            client_punch_id=client_punch_id
        )

@router.post("/attendance-request", response_model=AttendanceRequestResponse)
async def submit_attendance_request(
    current_latitude: Optional[float] = Form(None, description="GPS Latitude"),
    latitude: Optional[float] = Form(None, description="GPS Latitude alias"),
    current_longitude: Optional[float] = Form(None, description="GPS Longitude"),
    longitude: Optional[float] = Form(None, description="GPS Longitude alias"),
    gps_accuracy: Optional[float] = Form(None, description="GPS Accuracy in meters"),
    accuracy: Optional[float] = Form(None, description="GPS Accuracy alias"),
    location_name: Optional[str] = Form(None, description="Current location name / landmark"),
    device_timestamp: Optional[str] = Form(None, description="Phone's clock string for audit"),
    reason: Optional[str] = Form("Face verification failed", description="Reason for submitting request"),
    verification_no: Optional[int] = Form(None, description="Requested verification window number"),
    client_request_id: Optional[str] = Form(None, description="Client request UUID for idempotency"),
    image: Optional[UploadFile] = File(None, description="Evidence selfie image"),
    selfie: Optional[UploadFile] = File(None, description="Evidence selfie image alias"),
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """
    Fallback attendance request endpoint when biometric face verification fails.
    Captures live selfie, current GPS position, burns authoritative server evidence watermark,
    and submits request for admin review and approval.
    """
    actual_lat = current_latitude if current_latitude is not None else latitude
    actual_lon = current_longitude if current_longitude is not None else longitude
    actual_acc = gps_accuracy if gps_accuracy is not None else accuracy
    actual_img = image or selfie

    if actual_lat is None or actual_lon is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="GPS coordinates (latitude, longitude) are required")

    if actual_img is None:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Evidence selfie image is required")

    image_bytes = await actual_img.read()
    if not image_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Evidence selfie image is required")

    # Authoritative server timestamps
    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    tz = TimeService.get_server_timezone()
    local_now = datetime.now(tz)
    server_date = local_now.date()
    current_punch_time = local_now.time()

    # Determine requested verification window
    if verification_no is None:
        active_w = TimeService.get_active_verification_window(current_punch_time)
        target_v_no = active_w["verification_no"] if active_w else 1
    else:
        target_v_no = verification_no

    # Idempotency check via client_request_id
    if client_request_id:
        existing_by_client_id = db.query(AttendanceRequest).filter(
            AttendanceRequest.client_request_id == client_request_id
        ).first()
        if existing_by_client_id:
            tz = TimeService.get_server_timezone()
            req_local_dt = existing_by_client_id.server_timestamp.astimezone(tz) if existing_by_client_id.server_timestamp.tzinfo else pytz.utc.localize(existing_by_client_id.server_timestamp).astimezone(tz)
            eff_shift = existing_by_client_id.shift
            return AttendanceRequestResponse(
                id=existing_by_client_id.id,
                user_id=existing_by_client_id.user_id,
                employee_id=existing_by_client_id.user.employee_id,
                full_name=existing_by_client_id.user.full_name,
                request_date=existing_by_client_id.request_date.strftime("%Y-%m-%d"),
                server_timestamp=existing_by_client_id.server_timestamp.isoformat() + "Z",
                server_formatted_date=req_local_dt.strftime("%d %b %Y"),
                server_formatted_time=req_local_dt.strftime("%I:%M:%S %p"),
                device_timestamp=existing_by_client_id.device_timestamp,
                shift_id=existing_by_client_id.shift_id,
                shift_name=eff_shift.shift_name if eff_shift else None,
                shift_code=eff_shift.shift_code if eff_shift else None,
                status=existing_by_client_id.status.value,
                rejection_reason_trigger=existing_by_client_id.rejection_reason_trigger,
                latitude=float(existing_by_client_id.latitude),
                longitude=float(existing_by_client_id.longitude),
                gps_accuracy=existing_by_client_id.gps_accuracy,
                location_name=existing_by_client_id.location_name,
                assigned_location_name=existing_by_client_id.assigned_location_name,
                distance_from_location=float(existing_by_client_id.distance_from_location),
                is_within_geofence=bool(existing_by_client_id.is_within_geofence),
                has_evidence_image=True,
                admin_notes=existing_by_client_id.admin_notes,
                reviewed_at=existing_by_client_id.reviewed_at,
                reviewed_by_name=existing_by_client_id.reviewed_by.full_name if existing_by_client_id.reviewed_by else None,
                created_at=existing_by_client_id.created_at
            )

    # Check if attendance is already confirmed for this verification window today
    if target_v_no is not None:
        existing_attendance = db.query(Attendance).filter(
            Attendance.user_id == current_user.id,
            Attendance.attendance_date == server_date,
            Attendance.verification_no == target_v_no
        ).first()
        if existing_attendance:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Attendance for Verification {target_v_no} has already been completed today."
            )

        # Check if a pending attendance request already exists for this verification window today
        existing_pending_request = db.query(AttendanceRequest).filter(
            AttendanceRequest.user_id == current_user.id,
            AttendanceRequest.request_date == server_date,
            AttendanceRequest.verification_no == target_v_no,
            AttendanceRequest.status == RequestStatus.PENDING
        ).first()
        if existing_pending_request:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"An attendance request for Verification {target_v_no} is already pending admin review."
            )

    # Validate coordinates to distinguish real GPS fix from uninitialized default (0.0, 0.0)
    valid_coords = is_valid_coordinate(actual_lat, actual_lon)
    stored_lat = float(actual_lat) if actual_lat is not None else 0.0
    stored_lon = float(actual_lon) if actual_lon is not None else 0.0
    stored_acc = actual_acc if valid_coords else None

    # Calculate distance from assigned geofence location
    assigned_loc_name = None
    distance_meters = -1.0  # -1.0 indicates distance unavailable / GPS not fixed
    is_within = 0

    if current_user.geofence:
        gf = current_user.geofence
        assigned_loc_name = gf.location_name
        if valid_coords:
            is_inside, dist = validate_geofence(
                current_lat=stored_lat,
                current_lon=stored_lon,
                assigned_lat=float(gf.latitude),
                assigned_lon=float(gf.longitude),
                radius_meters=float(gf.radius_meters)
            )
            is_within = 1 if is_inside else 0
            distance_meters = dist if dist is not None else -1.0

    # Determine assigned shift for today
    effective_shift = ShiftService.get_effective_shift_for_user(db=db, user_id=current_user.id, target_date=server_date)

    # Ensure evidence overlay is burned onto the stored image
    watermarked_bytes = TimeService.burn_evidence_overlay(
        image_bytes=image_bytes,
        location_name=location_name or assigned_loc_name or "Field Location",
        latitude=stored_lat if valid_coords else None,
        longitude=stored_lon if valid_coords else None,
        server_dt=now_utc
    )

    req = AttendanceRequest(
        user_id=current_user.id,
        verification_no=target_v_no,
        client_request_id=client_request_id,
        request_date=server_date,
        server_timestamp=now_utc,
        device_timestamp=device_timestamp,
        shift_id=effective_shift.id if effective_shift else None,
        status=RequestStatus.PENDING,
        rejection_reason_trigger=reason or "Face verification failed",
        latitude=stored_lat,
        longitude=stored_lon,
        gps_accuracy=stored_acc,
        location_name=location_name,
        assigned_location_name=assigned_loc_name,
        distance_from_location=distance_meters,
        is_within_geofence=is_within,
        evidence_image=watermarked_bytes
    )
    db.add(req)
    db.commit()
    db.refresh(req)

    return AttendanceRequestResponse(
        id=req.id,
        user_id=req.user_id,
        employee_id=current_user.employee_id,
        full_name=current_user.full_name,
        request_date=req.request_date.strftime("%Y-%m-%d"),
        server_timestamp=req.server_timestamp.isoformat() + "Z",
        server_formatted_date=local_now.strftime("%d %b %Y"),
        server_formatted_time=local_now.strftime("%I:%M:%S %p"),
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
        reviewed_by_name=None,
        created_at=req.created_at
    )

@router.get("/attendance-requests", response_model=List[AttendanceRequestResponse])
def get_my_attendance_requests(
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """Retrieve all attendance requests submitted by the current employee."""
    tz = TimeService.get_server_timezone()
    requests = db.query(AttendanceRequest).filter(
        AttendanceRequest.user_id == current_user.id
    ).order_by(AttendanceRequest.id.desc()).limit(100).all()

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
                employee_id=current_user.employee_id,
                full_name=current_user.full_name,
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
                has_evidence_image=True,
                admin_notes=req.admin_notes,
                reviewed_at=req.reviewed_at,
                reviewed_by_name=reviewer_name,
                created_at=req.created_at
            )
        )
    return results

@router.post("/attendance/sync-offline", response_model=OfflineSyncBatchResponse)
async def sync_offline_attendance(
    request: Request,
    batch: OfflineSyncBatchRequest,
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """
    Authoritative server revalidation and synchronization endpoint for offline attendance queue.
    Revalidates:
    - User account status
    - Geofence hard gate (Haversine)
    - Verification window timing against estimated server time
    - Server sync age policy against MAX_OFFLINE_SYNC_AGE_SECONDS
    - Timing anomalies & clock drift
    - Duplicate prevention per window
    - Idempotency with client_punch_id
    """
    results = []
    confirmed = 0
    rejected = 0

    for item in batch.items:
        # Parse timing
        try:
            est_server_dt = datetime.fromisoformat(item.estimated_server_time.replace("Z", "+00:00"))
        except Exception:
            try:
                est_server_dt = datetime.strptime(item.estimated_server_time, "%Y-%m-%d %H:%M:%S")
            except Exception:
                est_server_dt = datetime.now(timezone.utc).replace(tzinfo=None)

        try:
            sync_dt = datetime.fromisoformat(item.last_server_sync_time.replace("Z", "+00:00"))
        except Exception:
            sync_dt = datetime.now(timezone.utc).replace(tzinfo=None)

        try:
            att_d = datetime.strptime(item.attendance_date, "%Y-%m-%d").date()
        except Exception:
            att_d = est_server_dt.date()

        img_bytes = None
        if item.image_base64:
            import base64
            try:
                img_bytes = base64.b64decode(item.image_base64)
            except Exception:
                pass

        res = AttendanceDecisionService.revalidate_offline_attendance(
            db=db,
            user=current_user,
            client_punch_id=item.client_punch_id,
            verification_no=item.verification_no or 1,
            attendance_date=att_d,
            estimated_server_time=est_server_dt,
            device_wall_time=item.device_wall_time,
            last_server_sync_time=sync_dt,
            server_time_offset=item.server_time_offset,
            latitude=item.latitude,
            longitude=item.longitude,
            gps_accuracy=item.gps_accuracy,
            face_similarity_score=item.face_similarity_score or 1.0,
            liveness_score=item.liveness_score or 1.0,
            image_bytes=img_bytes,
            punch_period_id=item.punch_period_id,
            device_id=item.device_id,
            ip_address=request.client.host if request.client else None
        )

        item_result = OfflineSyncItemResult(
            client_punch_id=item.client_punch_id,
            punch_period_id=res.get("punch_period_id", item.punch_period_id),
            verification_no=res.get("verification_no", item.verification_no or 1),
            status=res["status"],
            message=res["message"],
            attendance_id=res.get("attendance_id")
        )
        results.append(item_result)
        if res["status"] in ["CONFIRMED", "REVIEW_REQUIRED"]:
            confirmed += 1
        elif res["status"] == "REJECTED":
            rejected += 1

    return OfflineSyncBatchResponse(
        results=results,
        total_processed=len(batch.items),
        confirmed_count=confirmed,
        rejected_count=rejected
    )

@router.get("/attendance", response_model=List[AttendanceRecordResponse])
def get_my_attendance_history(
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """Retrieve personal attendance history for the authenticated employee with 3 verification records per day."""
    records = db.query(Attendance).filter(
        Attendance.user_id == current_user.id
    ).order_by(Attendance.attendance_date.desc(), Attendance.verification_no.desc()).limit(100).all()

    gf_name = current_user.geofence.location_name if current_user.geofence else None
    tz = TimeService.get_server_timezone()
    results = []
    for att in records:
        f_date = str(att.attendance_date)
        f_time = ""
        local_dt = att.timestamp
        if att.timestamp:
            local_dt = att.timestamp.astimezone(tz) if att.timestamp.tzinfo else pytz.utc.localize(att.timestamp).astimezone(tz)
            f_date = local_dt.strftime("%d %b %Y")
            f_time = local_dt.strftime("%I:%M:%S %p")

        results.append(
            AttendanceRecordResponse(
                id=att.id,
                user_id=att.user_id,
                employee_id=current_user.employee_id,
                full_name=current_user.full_name,
                verification_no=att.verification_no,
                verification_window=att.verification_window,
                source=att.source or "ONLINE",
                verification_status=att.verification_status or "CONFIRMED",
                client_punch_id=att.client_punch_id,
                sync_status=att.sync_status or "SYNCED",
                sync_notes=att.sync_notes,
                shift_id=att.shift_id,
                shift_code=att.shift.shift_code if att.shift else None,
                shift_name=att.shift.shift_name if att.shift else None,
                attendance_classification=att.attendance_classification or f"VERIFICATION_{att.verification_no}",
                attendance_date=att.attendance_date,
                timestamp=local_dt or att.timestamp,
                formatted_date=f_date,
                formatted_time=f_time,
                status=att.status,
                verified_latitude=float(att.verified_latitude),
                verified_longitude=float(att.verified_longitude),
                verified_distance_meters=float(att.verified_distance_meters),
                face_similarity_score=float(att.face_similarity_score),
                liveness_score=float(att.liveness_score),
                verification_mode=getattr(att, 'verification_mode', 'FACE') or 'FACE',
                location_name=gf_name
            )
        )
    return results

@router.post("/extra-work", response_model=dict)
async def submit_extra_work_request(
    work_date: str = Form(..., description="YYYY-MM-DD Date"),
    start_time: str = Form(..., description="Start Time HH:MM"),
    end_time: str = Form(..., description="End Time HH:MM"),
    hours: float = Form(..., description="Number of extra hours"),
    location_name: Optional[str] = Form(None, description="Location / site name"),
    remarks: Optional[str] = Form(None, description="Employee remarks"),
    image: Optional[UploadFile] = File(None, description="Evidence image"),
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """Submit Extra Work / Overtime request from mobile application."""
    try:
        w_d = date.fromisoformat(work_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format YYYY-MM-DD")

    img_bytes = None
    if image:
        img_bytes = await image.read()

    req = ExtraWorkRequest(
        user_id=current_user.id,
        work_date=w_d,
        start_time=start_time,
        end_time=end_time,
        hours=hours,
        location_name=location_name,
        remarks=remarks,
        status="PENDING",
        evidence_image=img_bytes
    )
    db.add(req)
    db.commit()
    db.refresh(req)

    return {
        "id": req.id,
        "work_date": req.work_date.isoformat(),
        "hours": req.hours,
        "status": req.status,
        "message": "Extra work request submitted successfully"
    }

@router.get("/extra-work", response_model=List[dict])
def get_my_extra_work(
    current_user: User = Depends(require_active_user),
    db: Session = Depends(get_db)
):
    """Retrieve my extra work requests."""
    items = db.query(ExtraWorkRequest).filter(
        ExtraWorkRequest.user_id == current_user.id
    ).order_by(ExtraWorkRequest.created_at.desc()).all()

    return [{
        "id": i.id,
        "work_date": i.work_date.isoformat(),
        "start_time": i.start_time,
        "end_time": i.end_time,
        "hours": i.hours,
        "location_name": i.location_name,
        "remarks": i.remarks,
        "status": i.status,
        "created_at": i.created_at.isoformat()
    } for i in items]

