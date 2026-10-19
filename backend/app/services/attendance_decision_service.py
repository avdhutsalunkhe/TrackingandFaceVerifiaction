from datetime import datetime, date, time, timezone
from typing import List, Optional, Dict, Any, Tuple
import pytz
import numpy as np
from sqlalchemy.orm import Session
from sqlalchemy import or_
from app.config import settings
from app.models.user import User
from app.models.face import FaceTemplate
from app.models.geofence import Geofence, AttendanceWindow
from app.models.attendance import (
    Attendance,
    AttendanceStatus,
    AttendanceAttempt,
    AttemptStatus,
    RejectionReason,
)
from app.schemas.attendance import AttendanceVerifyResponse
from app.services.geofence_service import validate_geofence
from app.services.audit_service import log_audit_event
from app.ml.pipeline import face_pipeline

class AttendanceDecisionService:
    """
    Authoritative server-side attendance decision service enforcing all business rules
    and multi-factor conditions (Active, Location, Time Window, Duplicate, Liveness, Face).
    """

    @staticmethod
    @staticmethod
    def evaluate_attendance(
        db: Session,
        user: User,
        current_lat: float,
        current_lon: float,
        gps_accuracy: Optional[float],
        frames_bytes_list: List[bytes],
        device_id: Optional[str] = None,
        request_id: Optional[str] = None,
        ip_address: Optional[str] = None,
        client_punch_id: Optional[str] = None,
        punch_period_id: Optional[int] = None,
        verification_no: Optional[int] = None,
        verification_rule_id: Optional[int] = None,
        device_wall_time: Optional[str] = None,
    ) -> AttendanceVerifyResponse:
        from app.services.time_service import TimeService
        from app.services.shift_service import ShiftService

        tz = TimeService.get_server_timezone()
        server_info = TimeService.get_current_server_time()
        raw_ts = server_info.get("server_timestamp")
        if isinstance(raw_ts, datetime):
            local_now = raw_ts if raw_ts.tzinfo is not None else tz.localize(raw_ts)
        elif isinstance(raw_ts, str):
            try:
                dt = datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
                local_now = dt.astimezone(tz)
            except Exception:
                local_now = datetime.now(tz)
        else:
            local_now = datetime.now(tz)

        today_date = local_now.date()
        current_time = local_now.time()
        now_utc = local_now.astimezone(pytz.utc).replace(tzinfo=None)

        # Helper to log failed attempt
        def record_failure(
            reason: RejectionReason,
            msg: str,
            distance: Optional[float] = None,
            sim_score: Optional[float] = None,
            live_res: Optional[str] = None,
            live_score: Optional[float] = None,
            details: Optional[Dict[str, Any]] = None,
            v_no: Optional[int] = None,
            v_rule_id: Optional[int] = None,
        ) -> AttendanceVerifyResponse:
            attempt = AttendanceAttempt(
                user_id=user.id,
                punch_period_id=v_rule_id or punch_period_id or verification_rule_id,
                verification_no=v_no or verification_no,
                verification_rule_id=v_rule_id or verification_rule_id or punch_period_id,
                timestamp=now_utc,
                attempt_status=AttemptStatus.REJECTED,
                rejection_reason=reason,
                source="ONLINE",
                latitude=current_lat,
                longitude=current_lon,
                calculated_distance_meters=distance,
                gps_accuracy=gps_accuracy,
                face_similarity_score=sim_score,
                liveness_result=live_res,
                liveness_score=live_score,
                device_id=device_id,
                request_id=request_id,
                client_punch_id=client_punch_id,
                details=details or {"error_message": msg}
            )
            db.add(attempt)
            db.commit()
            
            log_audit_event(
                db=db,
                action="ATTENDANCE_ATTEMPT_REJECTED",
                actor_user_id=user.id,
                target_user_id=user.id,
                details={"reason": reason.value, "message": msg, "distance": distance, "verification_no": v_no, "rule_id": v_rule_id},
                ip_address=ip_address
            )

            geofence = user.geofence
            return AttendanceVerifyResponse(
                success=False,
                decision="REJECTED",
                rejection_reason=reason,
                message=msg,
                verification_no=v_no or verification_no,
                calculated_distance_meters=distance,
                allowed_radius_meters=float(geofence.radius_meters) if geofence else None,
                face_similarity_score=sim_score,
                liveness_result=live_res,
                liveness_score=live_score,
                timestamp=now_utc,
                client_punch_id=client_punch_id
            )

        # 0. Idempotency Check: if client_punch_id was already processed, return existing confirmed record
        if client_punch_id:
            existing_by_id = db.query(Attendance).filter(Attendance.client_punch_id == client_punch_id).first()
            if existing_by_id:
                return AttendanceVerifyResponse(
                    success=True,
                    decision="PRESENT",
                    message="Attendance already recorded (idempotent submission)",
                    verification_no=existing_by_id.verification_no,
                    verification_window=existing_by_id.verification_window,
                    verification_status=existing_by_id.verification_status,
                    attendance_classification=existing_by_id.attendance_classification,
                    calculated_distance_meters=float(existing_by_id.verified_distance_meters),
                    allowed_radius_meters=float(user.geofence.radius_meters) if user.geofence else None,
                    face_similarity_score=float(existing_by_id.face_similarity_score),
                    liveness_result="REAL",
                    liveness_score=float(existing_by_id.liveness_score),
                    timestamp=existing_by_id.timestamp,
                    client_punch_id=existing_by_id.client_punch_id
                )

        # 1. Check User Active
        if not user.is_active:
            return record_failure(RejectionReason.EMPLOYEE_INACTIVE, "Employee account is deactivated")

        # 2. Check Geofence Config
        geofence_enforced = getattr(user, "geofence_enabled", True)
        geofence = db.query(Geofence).filter(Geofence.user_id == user.id, Geofence.is_active == True).first()
        if geofence_enforced and not geofence:
            return record_failure(RejectionReason.NO_GEOFENCE_ASSIGNED, "No attendance geofence assigned to this employee")

        # Calculate location distance for auditing and validation
        if geofence:
            is_inside_location, distance_meters = validate_geofence(
                current_lat=current_lat,
                current_lon=current_lon,
                assigned_lat=float(geofence.latitude),
                assigned_lon=float(geofence.longitude),
                radius_meters=float(geofence.radius_meters)
            )
        else:
            is_inside_location = True
            distance_meters = None

        if not geofence_enforced:
            # Geofence bypassed when disabled for this employee
            is_inside_location = True

        # Resolve Effective Shift & Dynamic Punch Periods
        shift_enforced = getattr(user, "shift_enabled", True)
        effective_shift = ShiftService.get_effective_shift_for_user(db=db, user_id=user.id, target_date=today_date)
        
        if shift_enforced and not effective_shift:
            return record_failure(
                RejectionReason.NO_SHIFT_ASSIGNED,
                "No active shift assigned to this employee. Attendance cannot be recorded.",
                distance=distance_meters
            )

        all_periods = TimeService.resolve_shift_punch_periods_list(effective_shift) if effective_shift else []

        # 3. Punch Period Resolution & Validation
        target_period = None
        target_id = punch_period_id if punch_period_id is not None else verification_rule_id
        if target_id is not None and all_periods:
            target_period = next((p for p in all_periods if p["id"] == target_id), None)
            if not target_period and shift_enforced:
                return record_failure(
                    RejectionReason.TIME_WINDOW_CLOSED,
                    "Selected punch period does not belong to your assigned active shift.",
                    distance=distance_meters
                )
        elif verification_no is not None and all_periods:
            target_period = next((p for p in all_periods if p["punch_no"] == verification_no), None)
        
        if not target_period and all_periods:
            # Pick currently open period for current_time using half-open interval: start_time <= current_time < end_time
            target_period = next((p for p in all_periods if p["is_active"] and p["start_time"] <= current_time < p["end_time"]), None)

        if not target_period:
            if shift_enforced:
                next_win = TimeService.get_next_verification_window(current_time, shift=effective_shift)
                if next_win:
                    msg = f"Attendance punch window is currently closed. Next punch ({next_win['period_name']}) is at {next_win['label']}."
                else:
                    msg = "All punch periods for today have expired/closed."
                return record_failure(RejectionReason.TIME_WINDOW_CLOSED, msg, distance=distance_meters)
            else:
                # Shift disabled: construct direct punch window
                active_v_no = verification_no or 1
                target_period = {
                    "id": None,
                    "punch_no": active_v_no,
                    "period_name": "Direct Attendance",
                    "label": "Direct Punch",
                    "is_active": True,
                    "show_in_user_schedule": True,
                    "start_time": current_time,
                    "end_time": current_time,
                    "result_classification": "PRESENT"
                }

        # Security Checks on Target Period:
        if not target_period.get("is_active", True):
            return record_failure(RejectionReason.TIME_WINDOW_CLOSED, "Punch period is inactive.", distance=distance_meters)

        if not target_period.get("show_in_user_schedule", True):
            return record_failure(RejectionReason.TIME_WINDOW_CLOSED, "This punch period is hidden from employee schedule / not enabled for user verification.", distance=distance_meters)

        # Server Time Window Check (Half-Open Interval: start_time <= current_time < end_time)
        if not (target_period["start_time"] <= current_time < target_period["end_time"]):
            msg = f"Punch '{target_period['period_name']}' window is {target_period['label']}. Current server time ({current_time.strftime('%H:%M:%S')}) is outside this window."
            return record_failure(
                RejectionReason.TIME_WINDOW_CLOSED,
                msg,
                distance=distance_meters,
                v_no=target_period["punch_no"],
                v_rule_id=target_period["id"]
            )

        active_v_no = target_period["punch_no"]
        active_r_id = target_period["id"]

        # 4. Check Duplicate for THIS specific punch period today
        dup_query = db.query(Attendance).filter(
            Attendance.user_id == user.id,
            Attendance.attendance_date == today_date,
            (Attendance.punch_period_id == active_r_id) | (Attendance.verification_rule_id == active_r_id)
        )
        
        existing_window_attendance = dup_query.first()

        if existing_window_attendance:
            return record_failure(
                RejectionReason.DUPLICATE_ATTENDANCE,
                f"Punch '{target_period['period_name']}' (#{active_v_no}) has already been completed today at {existing_window_attendance.timestamp.strftime('%I:%M:%S %p')}.",
                distance=distance_meters,
                v_no=active_v_no,
                v_rule_id=active_r_id
            )

        # 5. Check Haversine Distance Hard Gate (AUTHORITATIVE LOCATION GATE)
        if not is_inside_location:
            if distance_meters is None:
                return record_failure(
                    reason=RejectionReason.OUTSIDE_ASSIGNED_AREA,
                    msg=f"GPS location is unavailable or invalid. Cannot verify presence at '{geofence.location_name}'.",
                    distance=None,
                    v_no=active_v_no
                )
            return record_failure(
                reason=RejectionReason.OUTSIDE_ASSIGNED_AREA,
                msg=f"Outside assigned location '{geofence.location_name}'. Distance: {distance_meters:.1f}m, Allowed: {geofence.radius_meters:.1f}m",
                distance=distance_meters,
                v_no=active_v_no
            )

        # 6. Check GPS Accuracy Threshold
        if gps_accuracy is not None and gps_accuracy > settings.MAX_GPS_ACCURACY_THRESHOLD_METERS:
            return record_failure(
                RejectionReason.GPS_ACCURACY_LOW,
                f"GPS accuracy ({gps_accuracy:.1f}m) is too poor. Required under {settings.MAX_GPS_ACCURACY_THRESHOLD_METERS}m",
                distance=distance_meters,
                v_no=active_v_no
            )

        # 7. Check Registered Face Template & Biometric Verification
        face_enforced = getattr(user, "face_enabled", True)
        if face_enforced:
            face_template = db.query(FaceTemplate).filter(FaceTemplate.user_id == user.id).first()
            if not face_template or not face_template.face_embedding:
                return record_failure(
                    RejectionReason.NO_FACE_ENROLLED,
                    "No face registered for this employee. Please contact admin to enroll face.",
                    distance=distance_meters,
                    v_no=active_v_no
                )

            # 8. PRIMARY BIOMETRIC GATE: Run Deep-Learning Biometric Verification (Face Detection + Liveness + ArcFace)
            ref_embedding = np.frombuffer(face_template.face_embedding, dtype=np.float32)
            
            is_match, ml_err_code, ml_msg, sim_score, live_score, ml_details = face_pipeline.verify_live_sequence(
                frames_bytes_list=frames_bytes_list,
                reference_embedding=ref_embedding
            )

            if not is_match:
                rejection_reason_enum = RejectionReason.FACE_MISMATCH
                if ml_err_code == "LIVENESS_FAILED":
                    rejection_reason_enum = RejectionReason.LIVENESS_FAILED
                elif ml_err_code == "FACE_NOT_DETECTED":
                    rejection_reason_enum = RejectionReason.FACE_NOT_DETECTED
                elif ml_err_code == "MULTIPLE_FACES":
                    rejection_reason_enum = RejectionReason.MULTIPLE_FACES
                elif ml_err_code == "FACE_QUALITY_FAILED":
                    rejection_reason_enum = RejectionReason.FACE_QUALITY_FAILED
                elif ml_err_code == "CAPTURE_NOT_READY":
                    rejection_reason_enum = RejectionReason.CAPTURE_NOT_READY
                elif ml_err_code == "CAMERA_ERROR":
                    rejection_reason_enum = RejectionReason.CAMERA_ERROR

                return record_failure(
                    reason=rejection_reason_enum,
                    msg=ml_msg or "Biometric verification failed",
                    distance=distance_meters,
                    sim_score=sim_score,
                    live_res="SPOOF" if rejection_reason_enum == RejectionReason.LIVENESS_FAILED else "FAILED",
                    live_score=live_score,
                    details=ml_details,
                    v_no=active_v_no,
                    v_rule_id=active_r_id
                )
        else:
            # Face verification bypassed when disabled by administrator
            is_match = True
            sim_score = 1.0
            live_score = 1.0
            live_res = "BYPASSED_DISABLED"
            ml_details = {"face_verification": "disabled_by_admin"}

        # 9. Attendance Classification
        classification = target_period.get("result_classification", "PRESENT")

        # ALL GATES PASSED -> MARK ATTENDANCE AS CONFIRMED!
        new_attendance = Attendance(
            user_id=user.id,
            attendance_date=today_date,
            punch_period_id=active_r_id,
            verification_no=active_v_no,
            verification_rule_id=active_r_id,
            verification_window=target_period["label"],
            timestamp=now_utc,
            server_time=now_utc,
            device_wall_time=device_wall_time,
            status=AttendanceStatus.PRESENT,
            verification_status="CONFIRMED",
            source="ONLINE",
            client_punch_id=client_punch_id,
            sync_status="SYNCED",
            shift_id=effective_shift.id if effective_shift else None,
            attendance_classification=classification,
            verified_latitude=current_lat,
            verified_longitude=current_lon,
            verified_distance_meters=distance_meters,
            gps_accuracy=gps_accuracy,
            face_similarity_score=sim_score,
            face_result="MATCH",
            liveness_score=live_score,
            liveness_result="REAL",
            device_id=device_id
        )
        db.add(new_attendance)

        # Record successful attempt with verification telemetry
        attempt_details = dict(ml_details or {})
        attempt_details["punch_period_id"] = active_r_id
        attempt_details["verification_no"] = active_v_no
        attempt_details["verification_rule_id"] = active_r_id
        attempt_details["window"] = target_period["label"]
        attempt_details["classification"] = classification
        attempt_details["shift_code"] = effective_shift.shift_code if effective_shift else "DYNAMIC_SHIFT"

        attempt = AttendanceAttempt(
            user_id=user.id,
            punch_period_id=active_r_id,
            verification_no=active_v_no,
            verification_rule_id=active_r_id,
            timestamp=now_utc,
            attempt_status=AttemptStatus.SUCCESS,
            source="ONLINE",
            latitude=current_lat,
            longitude=current_lon,
            calculated_distance_meters=distance_meters,
            gps_accuracy=gps_accuracy,
            face_similarity_score=sim_score,
            liveness_result="REAL",
            liveness_score=live_score,
            device_id=device_id,
            request_id=request_id,
            client_punch_id=client_punch_id,
            details=attempt_details
        )
        db.add(attempt)
        db.commit()
        db.refresh(new_attendance)

        log_audit_event(
            db=db,
            action="ATTENDANCE_MARKED_PRESENT",
            actor_user_id=user.id,
            target_user_id=user.id,
            details={
                "attendance_id": new_attendance.id,
                "punch_period_id": active_r_id,
                "verification_no": active_v_no,
                "verification_rule_id": active_r_id,
                "window": target_period["label"],
                "distance_meters": distance_meters,
                "similarity_score": sim_score,
                "liveness_score": live_score,
                "client_punch_id": client_punch_id
            },
            ip_address=ip_address
        )

        return AttendanceVerifyResponse(
            success=True,
            decision="PRESENT",
            rejection_reason=None,
            message=f"Attendance Punch '{target_period['period_name']}' recorded successfully at {geofence.location_name} ({target_period['label']})",
            punch_period_id=active_r_id,
            punch_no=active_v_no,
            verification_no=active_v_no,
            verification_window=target_period["label"],
            verification_status="CONFIRMED",
            shift_id=effective_shift.id if effective_shift else None,
            shift_name=effective_shift.shift_name if effective_shift else "Dynamic Shift",
            attendance_classification=classification,
            calculated_distance_meters=distance_meters,
            allowed_radius_meters=float(geofence.radius_meters),
            face_similarity_score=sim_score,
            liveness_result="REAL",
            liveness_score=live_score,
            timestamp=now_utc,
            client_punch_id=client_punch_id
        )

    @classmethod
    def revalidate_offline_attendance(
        cls,
        db: Session,
        user: User,
        client_punch_id: str,
        verification_no: int,
        attendance_date: date,
        estimated_server_time: datetime,
        device_wall_time: Optional[str],
        last_server_sync_time: datetime,
        server_time_offset: Optional[int],
        latitude: float,
        longitude: float,
        gps_accuracy: Optional[float],
        face_similarity_score: float,
        liveness_score: float,
        image_bytes: Optional[bytes] = None,
        punch_period_id: Optional[int] = None,
        device_id: Optional[str] = None,
        ip_address: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Authoritative server revalidation pipeline for queued offline attendance records:
        1. User status check
        2. Idempotent client_punch_id check
        3. Active shift assignment resolution
        4. Punch period resolution (by punch_period_id or verification_no)
        5. Duplicate check for (user_id, attendance_date, punch_period_id)
        6. Geofence & GPS accuracy check
        7. Punch period timing validation (half-open: start <= time < end)
        8. Server sync age policy validation
        9. Biometric face validation (if image provided)
        """
        now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
        from app.services.time_service import TimeService
        from app.services.shift_service import ShiftService
        from app.models.setting import SystemSetting

        # 1. Idempotency Check
        existing_by_punch_id = db.query(Attendance).filter(Attendance.client_punch_id == client_punch_id).first()
        if existing_by_punch_id:
            return {
                "status": "DUPLICATE",
                "message": f"Verification {existing_by_punch_id.verification_no} already synced (idempotent duplicate)",
                "attendance_id": existing_by_punch_id.id,
                "client_punch_id": client_punch_id,
                "punch_period_id": existing_by_punch_id.punch_period_id,
                "verification_no": existing_by_punch_id.verification_no
            }

        # 2. Check User Active
        if not user.is_active:
            return {
                "status": "REJECTED",
                "message": "Employee account is deactivated",
                "client_punch_id": client_punch_id,
                "punch_period_id": punch_period_id,
                "verification_no": verification_no
            }

        # 3. Resolve Effective Shift
        eff_shift = ShiftService.get_effective_shift_for_user(db=db, user_id=user.id, target_date=attendance_date)
        if not eff_shift:
            return {
                "status": "REJECTED",
                "message": f"Employee is not assigned to an active shift on {attendance_date}",
                "client_punch_id": client_punch_id,
                "punch_period_id": punch_period_id,
                "verification_no": verification_no
            }

        # 4. Resolve Punch Period
        period_def = None
        if punch_period_id:
            period_def = TimeService.get_punch_period_by_id(punch_period_id, shift=eff_shift)
        if not period_def and verification_no:
            period_def = TimeService.get_window_by_number(verification_no, shift=eff_shift)

        if not period_def or not period_def.get("is_active", True):
            return {
                "status": "REJECTED",
                "message": f"Invalid or inactive punch period for shift '{eff_shift.shift_name}'",
                "client_punch_id": client_punch_id,
                "punch_period_id": punch_period_id,
                "verification_no": verification_no
            }

        target_period_id = period_def["id"]
        target_punch_no = period_def["punch_no"]

        # 5. Check Duplicate for this punch period on this date
        dup_query = db.query(Attendance).filter(
            Attendance.user_id == user.id,
            Attendance.attendance_date == attendance_date
        )
        if target_period_id:
            dup_query = dup_query.filter(
                or_(
                    Attendance.punch_period_id == target_period_id,
                    Attendance.verification_no == target_punch_no
                )
            )
        else:
            dup_query = dup_query.filter(Attendance.verification_no == target_punch_no)

        existing_dup = dup_query.first()
        if existing_dup:
            return {
                "status": "DUPLICATE",
                "message": f"Punch '{period_def['period_name']}' for date {attendance_date} has already been confirmed.",
                "attendance_id": existing_dup.id,
                "client_punch_id": client_punch_id,
                "punch_period_id": target_period_id,
                "verification_no": target_punch_no
            }

        # 6. Check Geofence
        geofence = user.geofence
        if not geofence:
            return {
                "status": "REJECTED",
                "message": "No geofence assigned to this employee",
                "client_punch_id": client_punch_id,
                "punch_period_id": target_period_id,
                "verification_no": target_punch_no
            }

        is_inside, dist_meters = validate_geofence(
            current_lat=latitude,
            current_lon=longitude,
            assigned_lat=float(geofence.latitude),
            assigned_lon=float(geofence.longitude),
            radius_meters=float(geofence.radius_meters)
        )

        if not is_inside:
            dist_msg = f"({dist_meters:.1f}m > {geofence.radius_meters:.1f}m)" if dist_meters is not None else "(GPS location unavailable or invalid)"
            return {
                "status": "REJECTED",
                "message": f"Outside assigned geofence location {dist_msg}",
                "client_punch_id": client_punch_id,
                "punch_period_id": target_period_id,
                "verification_no": target_punch_no
            }

        # 7. Check Half-Open Window Timing (Asia/Kolkata timezone)
        tz = TimeService.get_server_timezone()
        if estimated_server_time.tzinfo is not None:
            punch_time_val = estimated_server_time.astimezone(tz).time()
        else:
            punch_time_val = estimated_server_time.time()

        is_in_window = period_def["start_time"] <= punch_time_val < period_def["end_time"]
        if not is_in_window:
            return {
                "status": "REJECTED",
                "message": f"Estimated server time {punch_time_val.strftime('%H:%M:%S')} is outside punch period {period_def['label']}",
                "client_punch_id": client_punch_id,
                "punch_period_id": target_period_id,
                "verification_no": target_punch_no
            }

        # 8. Check Server Sync Age Policy
        setting_rec = db.query(SystemSetting).filter(SystemSetting.key == "MAX_OFFLINE_SYNC_AGE_SECONDS").first()
        max_age_seconds = float(setting_rec.value) if setting_rec else 14400.0 # 4 hours default

        # Normalize last_server_sync_time to naive UTC for safe subtraction against naive now_utc
        norm_sync_time = last_server_sync_time
        if norm_sync_time.tzinfo is not None:
            norm_sync_time = norm_sync_time.astimezone(pytz.utc).replace(tzinfo=None)

        sync_age_seconds = (now_utc - norm_sync_time).total_seconds()
        flag_review = False
        review_reasons = []

        if sync_age_seconds > max_age_seconds:
            flag_review = True
            review_reasons.append(f"Offline sync age ({int(sync_age_seconds)}s) exceeded configured threshold ({int(max_age_seconds)}s)")

        # 7. Check GPS accuracy threshold
        if gps_accuracy is not None and gps_accuracy > settings.MAX_GPS_ACCURACY_THRESHOLD_METERS:
            flag_review = True
            review_reasons.append(f"GPS accuracy ({gps_accuracy:.1f}m) exceeds threshold ({settings.MAX_GPS_ACCURACY_THRESHOLD_METERS}m)")

        # 8. Biometric check if image provided
        final_sim_score = None
        final_live_score = None
        face_res = "MATCH"
        liveness_res = "REAL"

        if image_bytes and user.face_template and user.face_template.face_embedding:
            try:
                ref_emb = np.frombuffer(user.face_template.face_embedding, dtype=np.float32)
                is_match, ml_code, ml_msg, s_score, l_score, ml_details = face_pipeline.verify_live_sequence(
                    frames_bytes_list=[image_bytes],
                    reference_embedding=ref_emb
                )
                liveness_res = "REAL" if (l_score is not None and l_score >= settings.LIVENESS_CONFIDENCE_THRESHOLD) else "SPOOF"

                if not is_match:
                    rej_reason = getattr(RejectionReason, ml_code, RejectionReason.FACE_MISMATCH) if ml_code else RejectionReason.FACE_MISMATCH
                    rej_attempt = AttendanceAttempt(
                        user_id=user.id,
                        verification_no=verification_no,
                        timestamp=now_utc,
                        attempt_status=AttemptStatus.REJECTED,
                        rejection_reason=rej_reason,
                        source="OFFLINE",
                        latitude=latitude,
                        longitude=longitude,
                        calculated_distance_meters=dist_meters,
                        gps_accuracy=gps_accuracy,
                        face_similarity_score=s_score,
                        liveness_result=liveness_res,
                        liveness_score=l_score,
                        device_id=device_id,
                        client_punch_id=client_punch_id,
                        details=ml_details if ml_details else {"error": ml_msg}
                    )
                    db.add(rej_attempt)
                    db.commit()
                    return {
                        "status": "REJECTED",
                        "message": ml_msg or "Biometric face verification rejected.",
                        "client_punch_id": client_punch_id,
                        "verification_no": verification_no
                    }
                else:
                    final_sim_score = s_score
                    final_live_score = l_score
            except Exception as e:
                print(f"[OfflineRevalidation] Biometric recheck error: {e}")
                rej_attempt = AttendanceAttempt(
                    user_id=user.id,
                    verification_no=verification_no,
                    timestamp=now_utc,
                    attempt_status=AttemptStatus.REJECTED,
                    rejection_reason=RejectionReason.BIOMETRIC_SERVICE_ERROR,
                    source="OFFLINE",
                    latitude=latitude,
                    longitude=longitude,
                    calculated_distance_meters=dist_meters,
                    gps_accuracy=gps_accuracy,
                    device_id=device_id,
                    client_punch_id=client_punch_id,
                    details={"error": str(e)}
                )
                db.add(rej_attempt)
                db.commit()
                return {
                    "status": "REJECTED",
                    "message": f"Biometric service error during revalidation: {str(e)}",
                    "client_punch_id": client_punch_id,
                    "verification_no": verification_no
                }
        elif not (user.face_template and user.face_template.face_embedding):
            return {
                "status": "REJECTED",
                "message": "User does not have an enrolled face template.",
                "client_punch_id": client_punch_id,
                "verification_no": verification_no
            }
        elif not image_bytes:
            return {
                "status": "REJECTED",
                "message": "Offline record missing camera biometric image.",
                "client_punch_id": client_punch_id,
                "verification_no": verification_no
            }

        # Final Status determination
        v_status = "REVIEW_REQUIRED" if flag_review else "CONFIRMED"
        sync_notes_str = "; ".join(review_reasons) if review_reasons else "Offline attendance verified and confirmed"

        new_att = Attendance(
            user_id=user.id,
            attendance_date=attendance_date,
            punch_period_id=target_period_id,
            verification_no=target_punch_no,
            verification_window=period_def["label"],
            timestamp=estimated_server_time,
            server_time=now_utc,
            device_wall_time=device_wall_time,
            status=AttendanceStatus.PRESENT,
            verification_status=v_status,
            source="OFFLINE",
            client_punch_id=client_punch_id,
            sync_status="SYNCED",
            sync_notes=sync_notes_str,
            shift_id=eff_shift.id if eff_shift else None,
            attendance_classification=period_def.get("result_classification") or "PRESENT",
            verified_latitude=latitude,
            verified_longitude=longitude,
            verified_distance_meters=dist_meters,
            gps_accuracy=gps_accuracy,
            face_similarity_score=final_sim_score,
            face_result=face_res,
            liveness_score=final_live_score,
            liveness_result=liveness_res,
            device_id=device_id
        )
        db.add(new_att)

        attempt = AttendanceAttempt(
            user_id=user.id,
            punch_period_id=target_period_id,
            verification_no=target_punch_no,
            timestamp=now_utc,
            attempt_status=AttemptStatus.SUCCESS,
            source="OFFLINE",
            latitude=latitude,
            longitude=longitude,
            calculated_distance_meters=dist_meters,
            gps_accuracy=gps_accuracy,
            face_similarity_score=final_sim_score,
            liveness_result=liveness_res,
            liveness_score=final_live_score,
            device_id=device_id,
            client_punch_id=client_punch_id,
            details={
                "sync_mode": "OFFLINE_SYNC",
                "punch_period_id": target_period_id,
                "verification_status": v_status,
                "sync_notes": sync_notes_str,
                "sync_age_seconds": sync_age_seconds
            }
        )
        db.add(attempt)
        db.commit()
        db.refresh(new_att)

        log_audit_event(
            db=db,
            action="OFFLINE_ATTENDANCE_SYNCED",
            actor_user_id=user.id,
            target_user_id=user.id,
            details={
                "attendance_id": new_att.id,
                "verification_no": verification_no,
                "client_punch_id": client_punch_id,
                "verification_status": v_status,
                "sync_notes": sync_notes_str
            },
            ip_address=ip_address
        )

        return {
            "status": v_status,
            "message": "Attendance confirmed" if v_status == "CONFIRMED" else f"Attendance synced ({sync_notes_str})",
            "attendance_id": new_att.id,
            "client_punch_id": client_punch_id,
            "verification_no": verification_no
        }
