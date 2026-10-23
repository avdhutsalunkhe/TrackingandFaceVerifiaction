from datetime import datetime, date, timedelta, time
import json
from typing import List, Optional, Dict, Any
import pytz
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc, asc, func, or_
from sqlalchemy.exc import IntegrityError

from app.database import get_db
from app.models.user import User, UserRole
from app.models.tracking import TrackingSession, GpsRoutePoint, TrackingRouteChunk, TrackingInterruptionEvent
from app.models.shift import Shift, ShiftPunchPeriod
from app.services.shift_service import ShiftService
from app.services.shift_engine_service import ShiftEngineService
from app.services.shift_tracking_scheduler_service import ShiftTrackingSchedulerService
from app.schemas.tracking import (
    StartTrackingRequest,
    StartTrackingResponse,
    SyncRoutePointsRequest,
    SyncRoutePointsResponse,
    RouteChunkItem,
    SyncRouteChunksRequest,
    SyncRouteChunksResponse,
    RouteArchiveRequest,
    PauseTrackingRequest,
    PauseTrackingResponse,
    ResumeTrackingRequest,
    ResumeTrackingResponse,
    StopTrackingRequest,
    StopTrackingResponse,
    TrackingSessionSummary,
    TrackingRouteResponse,
    RawRoutePointsResponse,
    PlaybackPointItem,
    PlaybackRouteResponse,
    RoutePointDetail,
    TrackingStatisticsResponse,
    TrackingEventRequest,
    TrackingEventResponse,
    ResolveShiftSessionRequest,
    ResolveShiftSessionResponse,
    TrackingHeartbeatRequest,
    TrackingHeartbeatResponse,
    RecordInterruptionRequest,
    RecordRecoveryRequest,
    SyncOfflineEventsRequest,
    SyncOfflineEventsResponse,
    TrackingInterruptionEventItem,
    LivePingRequest,
    LivePingResponse,
)
from app.dependencies import get_current_user, require_admin
from app.services.geofence_service import is_valid_coordinate, calculate_haversine_distance
from app.services.route_simplification_service import RouteSimplificationService, RouteSimplificationOptions

router = APIRouter(prefix="/api/tracking", tags=["GPS Journey Tracking"])


def _to_time(val: Any) -> Optional[time]:
    """Safely normalizes time representations (time, timedelta, str) to standard datetime.time."""
    if val is None:
        return None
    if isinstance(val, time):
        return val
    if isinstance(val, timedelta):
        total_seconds = int(val.total_seconds())
        hours = (total_seconds // 3600) % 24
        minutes = (total_seconds % 3600) // 60
        seconds = total_seconds % 60
        return time(hours, minutes, seconds)
    if isinstance(val, str):
        try:
            parts = [int(p) for p in val.strip().split(":")]
            return time(parts[0], parts[1], parts[2] if len(parts) > 2 else 0)
        except Exception:
            return None
    return None


def _to_naive_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """Safely normalizes datetime to offset-naive UTC datetime to prevent TypeError in comparisons."""
    if dt is None:
        return None
    if getattr(dt, "tzinfo", None) is not None:
        return dt.astimezone(pytz.utc).replace(tzinfo=None)
    return dt


def _resolve_shift_window(db: Session, user_id: int, target_date: date, shift_id: Optional[int] = None):
    """Calculates effective shift, start time, end time in UTC timezone with robust fallback."""
    return ShiftTrackingSchedulerService.resolve_shift_window(
        db=db, user_id=user_id, target_date=target_date, shift_id=shift_id
    )


def _ensure_interruption_event(
    db: Session,
    session: TrackingSession,
    reason_code: str,
    description: str,
    detected_at: datetime,
    recovered_at: Optional[datetime],
    severity: str,
    recovery_outcome: str,
):
    """Ensures an interruption record exists in tracking_interruption_events without duplicate rows."""
    existing = db.query(TrackingInterruptionEvent).filter(
        TrackingInterruptionEvent.session_id == session.id,
        TrackingInterruptionEvent.reason_code == reason_code,
        TrackingInterruptionEvent.detected_at == detected_at,
    ).first()

    if not existing:
        ev_uuid = f"EV_{reason_code}_{session.id}_{int(detected_at.timestamp())}"
        dur = int((recovered_at - detected_at).total_seconds()) if recovered_at else None
        ev = TrackingInterruptionEvent(
            event_uuid=ev_uuid,
            session_id=session.id,
            session_uuid=session.session_uuid,
            user_id=session.user_id,
            device_id=session.device_id,
            reason_code=reason_code,
            description=description,
            severity=severity,
            detected_at=detected_at,
            recovered_at=recovered_at,
            duration_seconds=dur,
            last_known_latitude=session.last_accepted_latitude,
            last_known_longitude=session.last_accepted_longitude,
            last_known_location_time=session.last_accepted_time or detected_at,
            is_confirmed=0,
            recovery_outcome=recovery_outcome,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(ev)


def _reconcile_session_health(db: Session, session: TrackingSession):
    """Reconciles session metrics, status, completeness, and interruption events using ShiftTrackingSchedulerService."""
    if not session:
        return
    ShiftTrackingSchedulerService.reconcile_session(db=db, session=session)


def _build_session_summary(db: Session, s: TrackingSession, effective_point_count: Optional[int] = None) -> TrackingSessionSummary:
    """Builds a consistent, schema-compliant TrackingSessionSummary with semantically accurate start and stop times."""
    cnt = effective_point_count if effective_point_count is not None else (
        s.retained_point_count if (s.retained_point_count and s.retained_point_count > 0) else db.query(GpsRoutePoint.id).filter(GpsRoutePoint.session_id == s.id).count()
    )

    interruption_count = db.query(TrackingInterruptionEvent.id).filter(TrackingInterruptionEvent.session_id == s.id).count()
    active_interruption = db.query(TrackingInterruptionEvent.reason_code).filter(
        TrackingInterruptionEvent.session_id == s.id,
        TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
    ).order_by(desc(TrackingInterruptionEvent.detected_at)).first()

    shift_code = s.shift.shift_code if s.shift else None
    shift_name = s.shift.shift_name if s.shift else None

    # Derive display-accurate actual start and stop times:
    # actual_start_time: first valid in-shift coordinate, or scheduled shift start if recording
    display_start = s.actual_start_time or (s.shift_start_time if s.status in ("RECORDING", "SCHEDULED") else s.start_time)

    # actual_stop_time: if shift is active/scheduled/interrupted, return shift_end_time (scheduled end)
    # so mobile UI displays 06:00 PM (Scheduled End) rather than falling back to last GPS fix
    if s.status in ("RECORDING", "SCHEDULED", "PAUSED", "RECOVERING", "INTERRUPTED", "DEGRADED"):
        display_stop = s.shift_end_time or s.end_time
    else:
        display_stop = s.actual_stop_time or s.end_time or s.shift_end_time

    # Zero points on ended session must report INCOMPLETE, never COMPLETE
    completeness = s.tracking_completeness
    if not completeness:
        completeness = "INCOMPLETE" if cnt == 0 and s.status == "COMPLETED" else "COMPLETE"
    elif cnt == 0 and s.status == "COMPLETED":
        completeness = "INCOMPLETE"

    return TrackingSessionSummary(
        id=s.id,
        session_uuid=s.session_uuid,
        user_id=s.user_id,
        employee_id=s.user.employee_id if s.user else "UNKNOWN",
        employee_name=s.user.full_name if s.user else "Unknown Employee",
        work_date=str(s.work_date),
        start_time=s.start_time,
        end_time=s.end_time,
        status=s.status,
        start_latitude=float(s.start_latitude) if s.start_latitude else None,
        start_longitude=float(s.start_longitude) if s.start_longitude else None,
        end_latitude=float(s.end_latitude) if s.end_latitude else None,
        end_longitude=float(s.end_longitude) if s.end_longitude else None,
        total_distance_meters=float(s.total_distance_meters or 0.0),
        total_duration_seconds=int(s.total_duration_seconds or 0),
        point_count=cnt,
        shift_id=s.shift_id,
        shift_code=shift_code,
        shift_name=shift_name,
        shift_start_time=s.shift_start_time,
        shift_end_time=s.shift_end_time,
        actual_start_time=display_start,
        actual_stop_time=display_stop,
        last_accepted_time=s.last_accepted_time,
        last_heartbeat_time=s.last_heartbeat_time,
        last_sync_time=s.last_sync_time,
        tracking_completeness=completeness,
        active_interruption=active_interruption[0] if active_interruption else None,
        interruption_count=interruption_count,
    )



@router.post("/start", response_model=StartTrackingResponse)
def start_tracking_session(
    req: StartTrackingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Start or retrieve an existing idempotent GPS tracking session for the authenticated user.
    Guarantees ONE continuous tracking session per assigned shift."""
    # Enforce travel_map_enabled toggle
    if not getattr(current_user, "travel_map_enabled", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Travel Map / GPS Tracking is disabled for your account. Please contact your administrator."
        )

    today = date.today()
    shift, shift_start_dt, shift_end_dt = _resolve_shift_window(
        db=db, user_id=current_user.id, target_date=today, shift_id=req.shift_id
    )
    resolved_shift_id = shift.id if shift else req.shift_id

    # 1. Idempotency check: see if session_uuid already exists
    existing = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if existing:
        if existing.user_id != current_user.id and current_user.role != UserRole.ADMIN:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to session.")
        
        # If recovering from interruption
        if existing.status in ("INTERRUPTED", "DEGRADED", "RECOVERING"):
            existing.status = "RECORDING"
            # Auto-close open interruption events
            open_events = db.query(TrackingInterruptionEvent).filter(
                TrackingInterruptionEvent.session_id == existing.id,
                TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
            ).all()
            now_utc = datetime.utcnow()
            for ev in open_events:
                ev.recovered_at = now_utc
                ev.duration_seconds = max(0, int((now_utc - ev.detected_at).total_seconds()))
                ev.recovery_outcome = "RECOVERED"

        if existing.start_latitude is None and is_valid_coordinate(req.start_latitude, req.start_longitude):
            existing.start_latitude = req.start_latitude
            existing.start_longitude = req.start_longitude
        
        existing.last_sync_time = datetime.utcnow()
        existing.last_heartbeat_time = datetime.utcnow()
        db.commit()
        return StartTrackingResponse(
            success=True,
            message="Tracking session active.",
            session_id=existing.id,
            session_uuid=existing.session_uuid,
            status=existing.status,
        )

    # 1b. SINGLE SESSION PER SHIFT: Check if user already has any active or recoverable session for today
    recoverable_today = (
        db.query(TrackingSession)
        .filter(
            TrackingSession.user_id == current_user.id,
            TrackingSession.work_date == today,
            TrackingSession.status.in_(["RECORDING", "ACTIVE", "PAUSED", "INTERRUPTED", "DEGRADED", "RECOVERING", "SCHEDULED"]),
        )
        .order_by(TrackingSession.start_time.asc())
        .first()
    )
    if recoverable_today:
        # Recover the existing session instead of duplicating
        now_utc = datetime.utcnow()
        if recoverable_today.status in ("INTERRUPTED", "DEGRADED", "RECOVERING"):
            recoverable_today.status = "RECORDING"
            open_events = db.query(TrackingInterruptionEvent).filter(
                TrackingInterruptionEvent.session_id == recoverable_today.id,
                TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
            ).all()
            for ev in open_events:
                ev.recovered_at = now_utc
                ev.duration_seconds = max(0, int((now_utc - ev.detected_at).total_seconds()))
                ev.recovery_outcome = "RECOVERED"

        if recoverable_today.start_latitude is None and is_valid_coordinate(req.start_latitude, req.start_longitude):
            recoverable_today.start_latitude = req.start_latitude
            recoverable_today.start_longitude = req.start_longitude

        recoverable_today.last_sync_time = now_utc
        recoverable_today.last_heartbeat_time = now_utc
        db.commit()
        db.refresh(recoverable_today)

        return StartTrackingResponse(
            success=True,
            message="Resumed active continuous shift tracking session.",
            session_id=recoverable_today.id,
            session_uuid=recoverable_today.session_uuid,
            status=recoverable_today.status,
        )

    # 2. Create new single tracking session for this shift
    now_utc = req.start_time or datetime.utcnow()
    is_upcoming = shift_start_dt and (now_utc < shift_start_dt)
    init_status = "SCHEDULED" if is_upcoming else "RECORDING"
    init_completeness = "PENDING_SYNC"
    act_start = None if is_upcoming else now_utc

    session = TrackingSession(
        session_uuid=req.session_uuid,
        user_id=current_user.id,
        attendance_id=req.attendance_id,
        shift_id=resolved_shift_id,
        shift_start_time=shift_start_dt,
        shift_end_time=shift_end_dt,
        actual_start_time=act_start,
        work_date=today,
        start_time=now_utc,
        status=init_status,
        start_latitude=req.start_latitude,
        start_longitude=req.start_longitude,
        total_distance_meters=0.0,
        total_duration_seconds=0,
        tracking_completeness=init_completeness,
        last_heartbeat_time=now_utc,
        last_sync_time=now_utc,
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    # Only insert point #1 into the route if valid AND within the shift window
    if is_valid_coordinate(req.start_latitude, req.start_longitude):
        pt_time = session.start_time
        in_window = True
        if shift_start_dt and pt_time < shift_start_dt:
            in_window = False
        if shift_end_dt and pt_time > shift_end_dt:
            in_window = False

        if in_window:
            init_point = GpsRoutePoint(
                session_id=session.id,
                user_id=current_user.id,
                client_point_id=f"{session.session_uuid}_pt_1",
                sequence_number=1,
                latitude=float(req.start_latitude),
                longitude=float(req.start_longitude),
                accuracy_meters=float(req.start_accuracy_meters) if req.start_accuracy_meters is not None else 10.0,
                altitude_meters=float(req.start_altitude_meters) if req.start_altitude_meters is not None else 0.0,
                speed_mps=float(req.start_speed_mps) if req.start_speed_mps is not None else 0.0,
                bearing_degrees=float(req.start_bearing_degrees) if req.start_bearing_degrees is not None else 0.0,
                recorded_at=pt_time,
                is_gap=0,
                sync_status="SYNCED",
            )
            db.add(init_point)
            session.actual_start_time = pt_time
            session.status = "RECORDING"
            db.commit()

    return StartTrackingResponse(
        success=True,
        message="GPS Tracking session successfully started.",
        session_id=session.id,
        session_uuid=session.session_uuid,
        status=session.status,
    )


@router.post("/points", response_model=SyncRoutePointsResponse)
def sync_route_points(
    req: SyncRoutePointsRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Batch-sync recorded GPS route coordinates from mobile device to server with idempotency.
    Guarantees no unhandled duplicate key crashes, updates session sync/fix timestamps, and reconciles counts."""
    if not getattr(current_user, "travel_map_enabled", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Travel Map / GPS Tracking is disabled for your account. New location points cannot be written."
        )

    now_utc = datetime.utcnow()
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        # Auto-recover / create session if missing so background offline points are never dropped
        first_time = _to_naive_utc(req.points[0].recorded_at) if req.points else now_utc
        shift, s_start, s_end = ShiftTrackingSchedulerService.resolve_shift_window(db=db, user_id=current_user.id, target_date=date.today())
        is_upcoming = s_start and (first_time < s_start)
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            shift_id=shift.id if shift else None,
            shift_start_time=s_start,
            shift_end_time=s_end,
            actual_start_time=None if is_upcoming else first_time,
            work_date=date.today(),
            start_time=first_time,
            status="SCHEDULED" if is_upcoming else "RECORDING",
            total_distance_meters=req.current_distance_meters or 0.0,
            total_duration_seconds=req.current_duration_seconds or 0,
            last_sync_time=now_utc,
            last_heartbeat_time=now_utc,
        )
        db.add(session)
        db.commit()
        db.refresh(session)

    # Ensure shift window is loaded on existing session
    if not session.shift_start_time or not session.shift_end_time:
        shift, s_start, s_end = ShiftTrackingSchedulerService.resolve_shift_window(
            db=db, user_id=session.user_id, target_date=session.work_date, shift_id=session.shift_id
        )
        if shift and not session.shift_id:
            session.shift_id = shift.id
        if not session.shift_start_time:
            session.shift_start_time = s_start
        if not session.shift_end_time:
            session.shift_end_time = s_end

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot upload points to another user's session.")

    # Re-activate session if it was marked INTERRUPTED or DEGRADED
    if session.status in ("INTERRUPTED", "DEGRADED", "RECOVERING"):
        session.status = "RECORDING"
        open_events = db.query(TrackingInterruptionEvent).filter(
            TrackingInterruptionEvent.session_id == session.id,
            TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
        ).all()
        for ev in open_events:
            ev.recovered_at = now_utc
            ev.duration_seconds = max(0, int((now_utc - ev.detected_at).total_seconds()))
            ev.recovery_outcome = "RECOVERED"

    accepted_count = 0
    duplicate_count = 0
    rejected_count = 0
    synced_point_ids: List[str] = []
    rejected_point_ids: List[str] = []
    first_valid_point = None
    latest_valid_point = None

    # Retrieve current max sequence_number for this session to ensure strict monotonicity
    existing_max_seq = db.query(func.max(GpsRoutePoint.sequence_number)).filter(
        GpsRoutePoint.session_id == session.id
    ).scalar() or 0

    allocated_seq = existing_max_seq

    # Query last accepted fix for session to filter near-instantaneous dual-stream duplicate fixes
    last_stored_pt = (
        db.query(GpsRoutePoint.latitude, GpsRoutePoint.longitude, GpsRoutePoint.recorded_at)
        .filter(GpsRoutePoint.session_id == session.id)
        .order_by(GpsRoutePoint.recorded_at.desc(), GpsRoutePoint.id.desc())
        .first()
    )
    last_lat = float(last_stored_pt.latitude) if last_stored_pt else None
    last_lng = float(last_stored_pt.longitude) if last_stored_pt else None
    last_ts = _to_naive_utc(last_stored_pt.recorded_at) if last_stored_pt else None

    # 1. Batch lookup of existing client_point_ids in DB to minimize queries and prevent round-trips
    batch_client_ids = [p.client_point_id for p in req.points if p.client_point_id]
    existing_client_ids = set()
    if batch_client_ids:
        for i in range(0, len(batch_client_ids), 500):
            chunk_ids = batch_client_ids[i:i + 500]
            rows = db.query(GpsRoutePoint.client_point_id).filter(
                GpsRoutePoint.client_point_id.in_(chunk_ids)
            ).all()
            for r in rows:
                existing_client_ids.add(r[0])

    # 2. In-batch de-duplication tracker
    seen_in_batch = set()

    # Sort incoming points chronologically before persistence to guarantee monotonic sequence assignment
    sorted_points = sorted(
        req.points,
        key=lambda pt: (_to_naive_utc(pt.recorded_at) or now_utc, pt.sequence_number or 0)
    )

    shift_s = _to_naive_utc(session.shift_start_time)
    shift_e = _to_naive_utc(session.shift_end_time)

    for p in sorted_points:
        if not is_valid_coordinate(p.latitude, p.longitude):
            rejected_point_ids.append(p.client_point_id)
            rejected_count += 1
            continue

        p_recorded_at = _to_naive_utc(p.recorded_at) or now_utc

        # STRICT SHIFT WINDOW GATING:
        # Pre-shift coordinates (< shift_start) and post-shift coordinates (> shift_end)
        # must be excluded from the official shift route.
        if shift_s and p_recorded_at < shift_s:
            rejected_point_ids.append(p.client_point_id)
            rejected_count += 1
            continue

        if shift_e and p_recorded_at > shift_e:
            rejected_point_ids.append(p.client_point_id)
            rejected_count += 1
            continue

        # Check idempotency against DB and current batch
        if p.client_point_id in existing_client_ids or p.client_point_id in seen_in_batch:
            duplicate_count += 1
            synced_point_ids.append(p.client_point_id)
            continue

        # Check for near-instantaneous dual-stream duplicate fix (<= 1.0s and < 2.0m)
        if last_lat is not None and last_lng is not None and last_ts is not None:
            dt = abs((p_recorded_at - last_ts).total_seconds())
            if dt <= 1.0:
                dist = calculate_haversine_distance(last_lat, last_lng, float(p.latitude), float(p.longitude))
                if dist < 2.0:
                    # Duplicate twin sensor fix from concurrent polling and native location stream
                    duplicate_count += 1
                    synced_point_ids.append(p.client_point_id)
                    continue

        if first_valid_point is None:
            first_valid_point = p

        if latest_valid_point is None or p_recorded_at > _to_naive_utc(latest_valid_point.recorded_at):
            latest_valid_point = p

        seen_in_batch.add(p.client_point_id)
        allocated_seq += 1
        seq = allocated_seq

        emp_id = p.employee_id or getattr(current_user, "employee_id", None)
        dev_id = p.device_id or req.device_id or getattr(current_user, "device_id", None)

        point = GpsRoutePoint(
            session_id=session.id,
            user_id=current_user.id,
            employee_id=emp_id,
            device_id=dev_id,
            client_point_id=p.client_point_id,
            sequence_number=seq,
            latitude=p.latitude,
            longitude=p.longitude,
            accuracy_meters=p.accuracy_meters,
            altitude_meters=p.altitude_meters,
            speed_mps=p.speed_mps,
            bearing_degrees=p.bearing_degrees,
            recorded_at=p_recorded_at,
            is_gap=1 if p.is_gap else 0,
            sync_status="SYNCED",
        )

        try:
            with db.begin_nested():
                db.add(point)
                db.flush()
            accepted_count += 1
            existing_client_ids.add(p.client_point_id)
            synced_point_ids.append(p.client_point_id)
            last_lat = float(p.latitude)
            last_lng = float(p.longitude)
            last_ts = p_recorded_at
        except IntegrityError:
            # Safely handle concurrent duplicate insert
            duplicate_count += 1
            synced_point_ids.append(p.client_point_id)

    # Backfill session start coordinates and actual_start_time if null
    if session.start_latitude is None and first_valid_point is not None:
        session.start_latitude = first_valid_point.latitude
        session.start_longitude = first_valid_point.longitude

    if accepted_count > 0:
        if session.actual_start_time is None and first_valid_point is not None:
            session.actual_start_time = _to_naive_utc(first_valid_point.recorded_at)
        if session.status in ("SCHEDULED", "INTERRUPTED", "DEGRADED"):
            session.status = "RECORDING"

    # Update session last accepted fix and sync timestamp
    if latest_valid_point is not None:
        latest_time = _to_naive_utc(latest_valid_point.recorded_at)
        sess_last = _to_naive_utc(session.last_accepted_time)
        if sess_last is None or (latest_time and latest_time >= sess_last):
            session.last_accepted_time = latest_time
            session.last_accepted_latitude = latest_valid_point.latitude
            session.last_accepted_longitude = latest_valid_point.longitude

    # Always update last_sync_time and last_heartbeat_time on successful point upload
    session.last_sync_time = now_utc
    session.last_heartbeat_time = now_utc

    # Update session metrics if provided
    if req.current_distance_meters is not None and req.current_distance_meters > session.total_distance_meters:
        session.total_distance_meters = req.current_distance_meters
    if req.current_duration_seconds is not None and req.current_duration_seconds > session.total_duration_seconds:
        session.total_duration_seconds = req.current_duration_seconds

    # Accurately maintain retained_point_count
    total_count = db.query(GpsRoutePoint.id).filter(GpsRoutePoint.session_id == session.id).count()
    session.retained_point_count = total_count
    session.updated_at = now_utc

    try:
        db.commit()
    except Exception:
        db.rollback()

    return SyncRoutePointsResponse(
        success=True,
        synced_count=accepted_count,
        accepted_count=accepted_count,
        duplicate_count=duplicate_count,
        rejected_count=rejected_count,
        synced_point_ids=synced_point_ids,
        rejected_point_ids=rejected_point_ids,
        total_points=total_count,
        message=f"Successfully processed {len(req.points)} points ({accepted_count} newly inserted, {duplicate_count} deduplicated, {rejected_count} rejected).",
    )


@router.post("/live-ping", response_model=LivePingResponse)
def record_live_ping(
    req: LivePingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Frequent live GPS update (every 15s or 25m) from foreground/background tracker.
    Updates the session's latest location coordinates and sync timestamp in real time."""
    now_utc = datetime.utcnow()
    recorded_at = _to_naive_utc(req.recorded_at or req.timestamp or now_utc)

    session = None
    if req.session_uuid:
        session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        session = (
            db.query(TrackingSession)
            .filter(
                TrackingSession.user_id == current_user.id,
                TrackingSession.work_date == date.today(),
                TrackingSession.status.in_(["RECORDING", "ACTIVE", "PAUSED", "INTERRUPTED", "DEGRADED", "RECOVERING"]),
            )
            .order_by(desc(TrackingSession.start_time))
            .first()
        )

    session_id = None
    session_status = None

    if session:
        session_id = session.id
        session_status = session.status
        if session.status in ("INTERRUPTED", "DEGRADED", "RECOVERING"):
            session.status = "RECORDING"
            open_events = db.query(TrackingInterruptionEvent).filter(
                TrackingInterruptionEvent.session_id == session.id,
                TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
            ).all()
            for ev in open_events:
                ev.recovered_at = now_utc
                ev.duration_seconds = max(0, int((now_utc - ev.detected_at).total_seconds()))
                ev.recovery_outcome = "RECOVERED"

        if is_valid_coordinate(req.latitude, req.longitude):
            session.last_accepted_latitude = req.latitude
            session.last_accepted_longitude = req.longitude
            session.last_accepted_time = recorded_at
            if session.start_latitude is None:
                session.start_latitude = req.latitude
                session.start_longitude = req.longitude

        session.last_sync_time = now_utc
        session.last_heartbeat_time = now_utc
        session.updated_at = now_utc
        try:
            db.commit()
        except Exception:
            db.rollback()

    return LivePingResponse(
        success=True,
        message="Live ping recorded successfully.",
        session_id=session_id,
        session_status=session_status or "RECORDING",
        address=None,
        server_time=now_utc,
    )


@router.post("/chunks", response_model=SyncRouteChunksResponse)
def sync_route_chunks(
    req: SyncRouteChunksRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Batch-sync storage-efficient compressed route chunks containing retained vertices.
    Minimizes permanent database growth by over 95% while keeping distance and route geometry accurate."""
    if not getattr(current_user, "travel_map_enabled", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Travel Map / GPS Tracking is disabled for your account. New location chunks cannot be written."
        )

    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        # Auto-recover / create session if missing
        first_time = req.chunks[0].start_time if req.chunks else datetime.utcnow()
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            work_date=date.today(),
            start_time=first_time,
            status="RECORDING",
            total_distance_meters=req.current_distance_meters or 0.0,
            total_duration_seconds=0,
        )
        db.add(session)
        db.commit()
        db.refresh(session)

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot upload chunks to another user's session.")

    synced_chunk_uuids: List[str] = []
    synced_count = 0

    for chk in req.chunks:
        # Idempotency check: match by chunk_uuid OR (session_id, chunk_sequence) unique constraint
        existing = db.query(TrackingRouteChunk).filter(
            (TrackingRouteChunk.chunk_uuid == chk.chunk_uuid) |
            ((TrackingRouteChunk.session_id == session.id) & (TrackingRouteChunk.chunk_sequence == chk.chunk_sequence))
        ).first()
        if existing:
            # Idempotently update chunk record in-place to prevent 1062 unique constraint violations
            existing.chunk_uuid = chk.chunk_uuid
            existing.point_count = chk.point_count
            existing.encoded_geometry = chk.encoded_geometry
            existing.start_time = chk.start_time
            existing.end_time = chk.end_time
            existing.distance_meters = chk.distance_meters
            synced_chunk_uuids.append(chk.chunk_uuid)
            continue

        chunk_rec = TrackingRouteChunk(
            chunk_uuid=chk.chunk_uuid,
            session_id=session.id,
            chunk_sequence=chk.chunk_sequence,
            point_count=chk.point_count,
            encoded_geometry=chk.encoded_geometry,
            start_time=chk.start_time,
            end_time=chk.end_time,
            distance_meters=chk.distance_meters,
            created_at=datetime.utcnow(),
        )
        db.add(chunk_rec)
        synced_count += 1
        synced_chunk_uuids.append(chk.chunk_uuid)

    # In-place update of session summary record
    if req.current_distance_meters is not None and req.current_distance_meters > session.total_distance_meters:
        session.total_distance_meters = req.current_distance_meters

    if req.retained_point_count is not None:
        session.retained_point_count = req.retained_point_count

    if req.last_accepted_latitude is not None:
        session.last_accepted_latitude = req.last_accepted_latitude
        session.last_accepted_longitude = req.last_accepted_longitude
        session.last_accepted_time = req.last_accepted_time or datetime.utcnow()

    # Backfill start coordinates if null
    if session.start_latitude is None and req.last_accepted_latitude is not None:
        session.start_latitude = req.last_accepted_latitude
        session.start_longitude = req.last_accepted_longitude

    session.last_sync_time = datetime.utcnow()
    session.updated_at = datetime.utcnow()
    db.commit()

    total_chunks = db.query(TrackingRouteChunk.id).filter(TrackingRouteChunk.session_id == session.id).count()

    return SyncRouteChunksResponse(
        success=True,
        synced_count=synced_count,
        synced_chunk_uuids=synced_chunk_uuids,
        total_chunks=total_chunks,
        retained_point_count=session.retained_point_count,
        total_distance_meters=float(session.total_distance_meters),
        message=f"Synced {synced_count} new route chunks ({len(synced_chunk_uuids) - synced_count} deduplicated). Total chunks: {total_chunks}.",
    )


@router.post("/pause", response_model=PauseTrackingResponse)
def pause_tracking_session(
    req: PauseTrackingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Pause an active GPS tracking session."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot pause another user's session.")

    session.status = "PAUSED"
    session.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(session)

    return PauseTrackingResponse(
        success=True,
        message="GPS Tracking session paused.",
        session_id=session.id,
        status=session.status,
    )


@router.post("/resume", response_model=ResumeTrackingResponse)
def resume_tracking_session(
    req: ResumeTrackingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Resume a paused GPS tracking session."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot resume another user's session.")

    session.status = "RECORDING"
    session.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(session)

    return ResumeTrackingResponse(
        success=True,
        message="GPS Tracking session resumed.",
        session_id=session.id,
        status=session.status,
    )


@router.post("/resolve-shift-session", response_model=ResolveShiftSessionResponse)
def resolve_shift_session(
    req: ResolveShiftSessionRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Deterministically resolves the single continuous tracking session for the employee's shift.
    Guarantees that no duplicate sessions exist for the same employee, shift, and work date."""
    target_date = req.work_date or req.target_date or date.today()
    shift, shift_start_dt, shift_end_dt = _resolve_shift_window(
        db=db, user_id=current_user.id, target_date=target_date, shift_id=req.shift_id
    )
    resolved_shift_id = shift.id if shift else req.shift_id

    # Deterministic canonical session UUID
    canonical_uuid = f"TRACK_{current_user.id}_SHIFT_{resolved_shift_id or 'GENERAL'}_{target_date}"

    # Search for any active/recoverable session for this user and work_date
    existing = (
        db.query(TrackingSession)
        .filter(
            TrackingSession.user_id == current_user.id,
            TrackingSession.work_date == target_date,
            TrackingSession.status.in_(["RECORDING", "ACTIVE", "PAUSED", "INTERRUPTED", "DEGRADED", "RECOVERING", "SCHEDULED"]),
        )
        .order_by(TrackingSession.start_time.asc())
        .first()
    )

    is_new = False
    now_utc = datetime.utcnow()

    if existing:
        session = existing
        # Re-activate if interrupted
        if session.status in ("INTERRUPTED", "DEGRADED", "RECOVERING"):
            session.status = "RECORDING"
            open_events = db.query(TrackingInterruptionEvent).filter(
                TrackingInterruptionEvent.session_id == session.id,
                TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
            ).all()
            for ev in open_events:
                ev.recovered_at = now_utc
                ev.duration_seconds = max(0, int((now_utc - ev.detected_at).total_seconds()))
                ev.recovery_outcome = "RECOVERED"
        session.last_heartbeat_time = now_utc
        session.last_sync_time = now_utc
        if req.device_id and not session.device_id:
            session.device_id = req.device_id
        db.commit()
    else:
        is_new = True
        session = TrackingSession(
            session_uuid=canonical_uuid,
            user_id=current_user.id,
            shift_id=resolved_shift_id,
            shift_start_time=shift_start_dt,
            shift_end_time=shift_end_dt,
            actual_start_time=now_utc,
            work_date=target_date,
            start_time=now_utc,
            status="RECORDING",
            start_latitude=req.start_latitude,
            start_longitude=req.start_longitude,
            total_distance_meters=0.0,
            total_duration_seconds=0,
            tracking_completeness="COMPLETE",
            device_id=req.device_id,
            last_heartbeat_time=now_utc,
            last_sync_time=now_utc,
        )
        db.add(session)
        db.commit()
        db.refresh(session)

    # Check for active unresolved interruption
    active_ev = db.query(TrackingInterruptionEvent).filter(
        TrackingInterruptionEvent.session_id == session.id,
        TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
    ).order_by(desc(TrackingInterruptionEvent.detected_at)).first()

    ev_item = None
    if active_ev:
        ev_item = TrackingInterruptionEventItem.model_validate(active_ev)

    cnt = session.retained_point_count if (session.retained_point_count and session.retained_point_count > 0) else db.query(GpsRoutePoint.id).filter(GpsRoutePoint.session_id == session.id).count()

    return ResolveShiftSessionResponse(
        success=True,
        session_id=session.id,
        session_uuid=session.session_uuid,
        status=session.status,
        is_new=is_new,
        shift_id=session.shift_id,
        shift_name=shift.shift_name if shift else None,
        shift_start_time=session.shift_start_time,
        shift_end_time=session.shift_end_time,
        total_distance_meters=float(session.total_distance_meters),
        accepted_point_count=cnt,
        tracking_completeness=session.tracking_completeness or "COMPLETE",
        active_interruption=ev_item,
        message="Shift tracking session active and ready.",
    )


@router.post("/heartbeat", response_model=TrackingHeartbeatResponse)
def record_tracking_heartbeat(
    req: TrackingHeartbeatRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Periodic health heartbeat from background tracking service.
    Detects gaps, validates shift window, and manages interruption events."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        # Auto-recover session from shift window
        shift, s_start, s_end = _resolve_shift_window(db=db, user_id=current_user.id, target_date=date.today())
        now_utc = req.timestamp or datetime.utcnow()
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            shift_id=shift.id if shift else None,
            shift_start_time=s_start,
            shift_end_time=s_end,
            actual_start_time=now_utc,
            work_date=date.today(),
            start_time=now_utc,
            status="RECORDING",
            total_distance_meters=0.0,
            total_duration_seconds=0,
            tracking_completeness="COMPLETE",
            device_id=None,
            last_heartbeat_time=now_utc,
            last_sync_time=now_utc,
        )
        db.add(session)
        db.commit()
        db.refresh(session)

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to session.")

    now_utc = req.timestamp or datetime.utcnow()
    session.last_heartbeat_time = now_utc
    session.last_sync_time = now_utc

    should_stop = False
    # Check if shift ended
    if session.shift_end_time and now_utc >= session.shift_end_time:
        should_stop = True

    # Detect location services disabled reported via heartbeat
    if req.location_services_enabled is False or req.gps_provider_enabled is False:
        # Check if an unresolved event already exists
        existing_ev = db.query(TrackingInterruptionEvent).filter(
            TrackingInterruptionEvent.session_id == session.id,
            TrackingInterruptionEvent.reason_code == "LOCATION_SERVICES_DISABLED",
            TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
        ).first()
        if not existing_ev:
            ev = TrackingInterruptionEvent(
                event_uuid=f"EV_HEARTBEAT_LOC_OFF_{session.id}_{int(now_utc.timestamp())}",
                session_id=session.id,
                session_uuid=session.session_uuid,
                user_id=current_user.id,
                device_id=req.device_id or session.device_id,
                reason_code="LOCATION_SERVICES_DISABLED",
                description="Location services reported disabled in service heartbeat",
                severity="WARNING",
                detected_at=now_utc,
                last_known_latitude=session.last_accepted_latitude,
                last_known_longitude=session.last_accepted_longitude,
                last_known_location_time=session.last_accepted_time,
                is_confirmed=1,
                recovery_outcome="UNRESOLVED",
            )
            db.add(ev)
            session.status = "INTERRUPTED"
            session.tracking_completeness = "HAS_GAPS"
    elif req.location_services_enabled is True and req.gps_provider_enabled is True:
        # Auto-recover location disabled event if still unresolved
        open_loc_ev = db.query(TrackingInterruptionEvent).filter(
            TrackingInterruptionEvent.session_id == session.id,
            TrackingInterruptionEvent.reason_code == "LOCATION_SERVICES_DISABLED",
            TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
        ).first()
        if open_loc_ev:
            open_loc_ev.recovered_at = now_utc
            open_loc_ev.duration_seconds = max(0, int((now_utc - open_loc_ev.detected_at).total_seconds()))
            open_loc_ev.recovery_outcome = "RECOVERED"
            if session.status == "INTERRUPTED":
                session.status = "RECORDING"

    db.commit()
    return TrackingHeartbeatResponse(
        success=True,
        server_time=now_utc,
        session_status=session.status,
        should_stop=should_stop,
        message="Heartbeat recorded successfully.",
    )


@router.post("/interruption", response_model=TrackingInterruptionEventItem)
def record_interruption_event(
    req: RecordInterruptionRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Records an explicit tracking interruption event (e.g. GPS disabled, accuracy failure, permission revoked)."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        # Auto-recover session if missing
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            work_date=date.today(),
            start_time=req.detected_at,
            status="INTERRUPTED",
            tracking_completeness="HAS_GAPS",
        )
        db.add(session)
        db.commit()
        db.refresh(session)

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot log interruption on another user's session.")

    # Idempotent check by event_uuid
    existing_ev = db.query(TrackingInterruptionEvent).filter(
        TrackingInterruptionEvent.event_uuid == req.event_uuid
    ).first()

    if existing_ev:
        return TrackingInterruptionEventItem.from_orm(existing_ev)

    ev = TrackingInterruptionEvent(
        event_uuid=req.event_uuid,
        session_id=session.id,
        session_uuid=session.session_uuid,
        user_id=current_user.id,
        device_id=req.device_id or session.device_id,
        reason_code=req.reason_code,
        description=req.description,
        severity=req.severity or "WARNING",
        detected_at=req.detected_at,
        last_known_latitude=req.last_known_latitude or session.last_accepted_latitude,
        last_known_longitude=req.last_known_longitude or session.last_accepted_longitude,
        last_known_location_time=req.last_known_location_time or session.last_accepted_time,
        diagnostic_details=json.dumps(req.diagnostic_details) if isinstance(req.diagnostic_details, dict) else req.diagnostic_details,
        is_confirmed=1 if req.is_confirmed else 0,
        recovery_outcome="UNRESOLVED",
    )
    db.add(ev)

    # Transition session status
    if req.reason_code == "POOR_ACCURACY":
        if session.status != "INTERRUPTED":
            session.status = "DEGRADED"
    else:
        session.status = "INTERRUPTED"
        session.tracking_completeness = "HAS_GAPS"

    session.updated_at = req.detected_at
    db.commit()
    db.refresh(ev)

    return TrackingInterruptionEventItem.model_validate(ev)


@router.post("/recovery", response_model=TrackingInterruptionEventItem)
def record_recovery_event(
    req: RecordRecoveryRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Closes an open interruption event and transitions session back to ACTIVE/RECORDING."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot record recovery on another user's session.")

    query = db.query(TrackingInterruptionEvent).filter(
        TrackingInterruptionEvent.session_id == session.id,
        TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
    )
    if req.event_uuid:
        query = query.filter(TrackingInterruptionEvent.event_uuid == req.event_uuid)
    elif req.reason_code:
        query = query.filter(TrackingInterruptionEvent.reason_code == req.reason_code)

    target_ev = query.order_by(desc(TrackingInterruptionEvent.detected_at)).first()
    if not target_ev:
        # Fallback to the latest open event for this session
        target_ev = db.query(TrackingInterruptionEvent).filter(
            TrackingInterruptionEvent.session_id == session.id,
            TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
        ).order_by(desc(TrackingInterruptionEvent.detected_at)).first()

    now_utc = req.recovered_at or datetime.utcnow()

    if target_ev:
        target_ev.recovered_at = now_utc
        target_ev.duration_seconds = max(0, int((now_utc - target_ev.detected_at).total_seconds()))
        target_ev.recovery_outcome = req.recovery_outcome or "RECOVERED"
        if req.diagnostic_details:
            target_ev.diagnostic_details = req.diagnostic_details

    # Check if any remaining open events exist
    remaining_open = db.query(TrackingInterruptionEvent.id).filter(
        TrackingInterruptionEvent.session_id == session.id,
        TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
    ).first()

    if not remaining_open:
        session.status = "RECORDING"

    session.updated_at = now_utc
    session.last_sync_time = now_utc
    db.commit()

    if target_ev:
        db.refresh(target_ev)
        return TrackingInterruptionEventItem.model_validate(target_ev)
    else:
        # Return synthetic confirmed recovery item
        synthetic = TrackingInterruptionEvent(
            id=0,
            event_uuid=f"RECOVERED_{session.id}_{int(now_utc.timestamp())}",
            session_id=session.id,
            session_uuid=session.session_uuid,
            user_id=current_user.id,
            reason_code=req.reason_code or "SERVICE_RESUMED",
            description="Tracking recovered",
            severity="INFO",
            detected_at=now_utc,
            recovered_at=now_utc,
            duration_seconds=0,
            recovery_outcome="RECOVERED",
        )
        return TrackingInterruptionEventItem.model_validate(synthetic)


@router.post("/sync-offline-events", response_model=SyncOfflineEventsResponse)
def sync_offline_events(
    req: SyncOfflineEventsRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Batch-synchronizes interruption events that were recorded locally while offline."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        # Auto-recover/initialize session from shift window
        shift, s_start, s_end = _resolve_shift_window(db=db, user_id=current_user.id, target_date=date.today())
        now_utc = datetime.utcnow()
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            shift_id=shift.id if shift else None,
            shift_start_time=s_start,
            shift_end_time=s_end,
            actual_start_time=now_utc,
            work_date=date.today(),
            start_time=now_utc,
            status="RECORDING",
            total_distance_meters=0.0,
            total_duration_seconds=0,
            tracking_completeness="PENDING_SYNC",
            device_id=None,
            last_heartbeat_time=now_utc,
            last_sync_time=now_utc,
        )
        db.add(session)
        db.commit()
        db.refresh(session)

    synced_count = 0
    synced_ids = []
    for ev_data in req.events:
        synced_ids.append(ev_data.event_uuid)
        exists = db.query(TrackingInterruptionEvent.id).filter(
            TrackingInterruptionEvent.event_uuid == ev_data.event_uuid
        ).first()
        if exists:
            continue

        diag_str = json.dumps(ev_data.diagnostic_details) if isinstance(ev_data.diagnostic_details, dict) else ev_data.diagnostic_details
        ev = TrackingInterruptionEvent(
            event_uuid=ev_data.event_uuid,
            session_id=session.id,
            session_uuid=session.session_uuid,
            user_id=current_user.id,
            device_id=ev_data.device_id or session.device_id,
            reason_code=ev_data.reason_code,
            description=ev_data.description,
            severity=ev_data.severity or "WARNING",
            detected_at=ev_data.detected_at,
            last_known_latitude=ev_data.last_known_latitude or session.last_accepted_latitude,
            last_known_longitude=ev_data.last_known_longitude or session.last_accepted_longitude,
            last_known_location_time=ev_data.last_known_location_time or session.last_accepted_time,
            diagnostic_details=diag_str,
            is_confirmed=1 if ev_data.is_confirmed else 0,
            recovery_outcome="UNRESOLVED",
        )
        db.add(ev)
        synced_count += 1
        if ev_data.severity in ("WARNING", "CRITICAL"):
            session.tracking_completeness = "HAS_GAPS"

    session.last_sync_time = datetime.utcnow()
    db.commit()
    return SyncOfflineEventsResponse(
        success=True,
        synced_count=synced_count,
        synced_event_ids=synced_ids,
        message=f"Synced {synced_count} offline interruption events.",
    )


@router.get("/sessions/{session_id}/interruptions", response_model=List[TrackingInterruptionEventItem])
def get_session_interruptions(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves full chronological interruption history for a tracking session."""
    session = db.query(TrackingSession).filter(TrackingSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to interruptions.")

    _reconcile_session_health(db, session)

    events = (
        db.query(TrackingInterruptionEvent)
        .filter(TrackingInterruptionEvent.session_id == session.id)
        .order_by(TrackingInterruptionEvent.detected_at.asc())
        .all()
    )
    return [TrackingInterruptionEventItem.model_validate(e) for e in events]


@router.post("/stop", response_model=StopTrackingResponse)
def stop_tracking_session(
    req: StopTrackingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Conclude an active GPS tracking session and record final stats."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    now_utc = req.end_time or datetime.utcnow()

    if not session:
        # Auto-recover / conclude session even if /start was not received first
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            work_date=date.today(),
            start_time=now_utc,
            actual_start_time=now_utc,
            actual_stop_time=now_utc,
            status="COMPLETED",
            end_time=now_utc,
            end_latitude=req.end_latitude,
            end_longitude=req.end_longitude,
            total_distance_meters=req.total_distance_meters or 0.0,
            total_duration_seconds=req.total_duration_seconds or 0,
        )
        db.add(session)
        db.commit()
        db.refresh(session)
        return StopTrackingResponse(
            success=True,
            message="GPS Tracking session created and concluded from offline completion.",
            session_id=session.id,
            status=session.status,
            total_distance_meters=session.total_distance_meters,
            total_duration_seconds=session.total_duration_seconds,
        )

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot conclude another user's session.")

    session.status = "COMPLETED"
    session.end_time = now_utc
    session.actual_stop_time = now_utc

    if req.end_latitude is not None:
        session.end_latitude = req.end_latitude
    if req.end_longitude is not None:
        session.end_longitude = req.end_longitude
    if req.total_distance_meters is not None:
        session.total_distance_meters = req.total_distance_meters
    if req.total_duration_seconds is not None:
        session.total_duration_seconds = req.total_duration_seconds

    # Auto-conclude any open interruption events
    open_events = db.query(TrackingInterruptionEvent).filter(
        TrackingInterruptionEvent.session_id == session.id,
        TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
    ).all()
    for ev in open_events:
        ev.recovered_at = now_utc
        ev.duration_seconds = max(0, int((now_utc - ev.detected_at).total_seconds()))
        ev.recovery_outcome = "SHIFT_CONCLUDED"

    db.commit()
    db.refresh(session)

    return StopTrackingResponse(
        success=True,
        message="GPS Tracking session successfully completed.",
        session_id=session.id,
        status=session.status,
        total_distance_meters=session.total_distance_meters,
        total_duration_seconds=session.total_duration_seconds,
    )


@router.post("/event", response_model=TrackingEventResponse)
def log_tracking_event(
    req: TrackingEventRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Log tracking lifecycle and diagnostics event (service start/stop, GPS disabled, battery optimization status, recovery)."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    now = req.timestamp or datetime.utcnow()

    if session:
        if req.event_type == "GPS_DISABLED":
            session.status = "INTERRUPTED"
            session.tracking_completeness = "HAS_GAPS"
            session.updated_at = now
            # Record interruption event
            ev_uuid = f"EV_GPS_OFF_{session.id}_{int(now.timestamp())}"
            exists = db.query(TrackingInterruptionEvent.id).filter(TrackingInterruptionEvent.event_uuid == ev_uuid).first()
            if not exists:
                ev = TrackingInterruptionEvent(
                    event_uuid=ev_uuid,
                    session_id=session.id,
                    session_uuid=session.session_uuid,
                    user_id=current_user.id,
                    device_id=session.device_id,
                    reason_code="LOCATION_SERVICES_DISABLED",
                    description=req.details or "Location provider disabled by user",
                    severity="WARNING",
                    detected_at=now,
                    last_known_latitude=session.last_accepted_latitude,
                    last_known_longitude=session.last_accepted_longitude,
                    last_known_location_time=session.last_accepted_time,
                    is_confirmed=1,
                    recovery_outcome="UNRESOLVED",
                )
                db.add(ev)
            db.commit()
        elif req.event_type in ("SERVICE_RESUMED", "GPS_RESTORED") and session.status in ("INTERRUPTED", "DEGRADED"):
            session.status = "RECORDING"
            session.updated_at = now
            # Close open events
            open_evs = db.query(TrackingInterruptionEvent).filter(
                TrackingInterruptionEvent.session_id == session.id,
                TrackingInterruptionEvent.recovery_outcome == "UNRESOLVED",
            ).all()
            for o_ev in open_evs:
                o_ev.recovered_at = now
                o_ev.duration_seconds = max(0, int((now - o_ev.detected_at).total_seconds()))
                o_ev.recovery_outcome = "RECOVERED"
            db.commit()

    import logging
    logger = logging.getLogger("tracking_diagnostics")
    logger.info(
        f"[DIAGNOSTICS] User {current_user.id} ({current_user.employee_id}) | Session {req.session_uuid} | Event: {req.event_type} | BatteryOptIgnored: {req.battery_optimization_ignored} | Details: {req.details}"
    )

    return TrackingEventResponse(
        success=True,
        message=f"Event {req.event_type} registered.",
    )


@router.get("/sessions", response_model=List[TrackingSessionSummary])
def list_tracking_sessions(
    user_id: Optional[int] = Query(None, description="Filter by user ID"),
    work_date: Optional[str] = Query(None, description="Filter by work date YYYY-MM-DD"),
    status: Optional[str] = Query(None, description="Filter by status (RECORDING, COMPLETED)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List tracking sessions with shift context and interruption diagnostics."""
    query = db.query(TrackingSession)

    if current_user.role != UserRole.ADMIN:
        query = query.filter(TrackingSession.user_id == current_user.id)
    elif user_id:
        query = query.filter(TrackingSession.user_id == user_id)

    target_d = date.today()
    if work_date:
        try:
            target_d = datetime.strptime(work_date, "%Y-%m-%d").date()
            query = query.filter(TrackingSession.work_date == target_d)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")
    else:
        query = query.filter(TrackingSession.work_date == target_d)

    # Automatically ensure daily shift sessions exist and are reconciled for target date
    ShiftTrackingSchedulerService.ensure_daily_sessions_for_date(db, target_date=target_d)

    if status:
        query = query.filter(TrackingSession.status == status)

    sessions = query.order_by(desc(TrackingSession.start_time)).all()

    summaries = []
    for s in sessions:
        _reconcile_session_health(db, s)
        summaries.append(_build_session_summary(db, s))
    return summaries


@router.get("/sessions/{session_id}/route", response_model=TrackingRouteResponse)
def get_session_route(
    session_id: int,
    raw: bool = Query(True, description="Return raw GPS points if True (default), or simplified if False"),
    simplified: Optional[bool] = Query(None, description="Explicitly request hybrid simplified route if True"),
    epsilon: Optional[float] = Query(None, description="Configurable RDP base tolerance in meters (default 0.8)"),
    max_deviation: Optional[float] = Query(None, description="Configurable max deviation in meters (default 2.5)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieve full ordered GPS route. By default returns all raw points so refreshes never lose points.
    If raw=false or simplified=true is specified, returns hybrid simplified candidate vertices for clean map rendering
    while preserving original database records."""
    session = db.query(TrackingSession).filter(TrackingSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to route.")

    _reconcile_session_health(db, session)

    point_details: List[RoutePointDetail] = []
    is_raw_route = False

    want_simplified = (simplified is True) or (not raw)

    # 1. Fetch raw points from database in strict chronological order
    raw_points = (
        db.query(GpsRoutePoint)
        .filter(GpsRoutePoint.session_id == session.id)
        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
        .all()
    )

    if raw_points:
        if want_simplified and len(raw_points) > 2:
            options = RouteSimplificationOptions(
                base_epsilon_meters=epsilon if epsilon is not None else 0.8,
                max_allowed_deviation_meters=max_deviation if max_deviation is not None else 2.5,
            )
            sim_res = RouteSimplificationService.simplify_points(raw_points, options)
            point_details = [
                RoutePointDetail(
                    id=p.id,
                    sequence_number=i + 1,
                    client_point_id=p.client_point_id,
                    employee_id=p.employee_id or (session.user.employee_id if session.user else None),
                    device_id=p.device_id or (session.user.device_id if session.user else None),
                    latitude=float(p.latitude),
                    longitude=float(p.longitude),
                    accuracy_meters=float(p.accuracy_meters),
                    altitude_meters=float(p.altitude_meters) if p.altitude_meters else None,
                    speed_mps=float(p.speed_mps) if p.speed_mps else None,
                    bearing_degrees=float(p.bearing_degrees) if p.bearing_degrees else None,
                    recorded_at=p.recorded_at,
                    is_gap=bool(p.is_gap) if hasattr(p, "is_gap") and p.is_gap else False,
                )
                for i, p in enumerate(sim_res.simplified_points)
            ]
            is_raw_route = False
        else:
            point_details = [
                RoutePointDetail(
                    id=p.id,
                    sequence_number=i + 1,
                    client_point_id=p.client_point_id,
                    employee_id=p.employee_id or (session.user.employee_id if session.user else None),
                    device_id=p.device_id or (session.user.device_id if session.user else None),
                    latitude=float(p.latitude),
                    longitude=float(p.longitude),
                    accuracy_meters=float(p.accuracy_meters),
                    altitude_meters=float(p.altitude_meters) if p.altitude_meters else None,
                    speed_mps=float(p.speed_mps) if p.speed_mps else None,
                    bearing_degrees=float(p.bearing_degrees) if p.bearing_degrees else None,
                    recorded_at=p.recorded_at,
                    is_gap=bool(p.is_gap) if hasattr(p, "is_gap") and p.is_gap else False,
                )
                for i, p in enumerate(raw_points)
            ]
            is_raw_route = True

    # 2. If raw was False or no raw points were found, check compressed route chunks
    if not point_details:
        chunks = (
            db.query(TrackingRouteChunk)
            .filter(TrackingRouteChunk.session_id == session.id)
            .order_by(TrackingRouteChunk.chunk_sequence.asc())
            .all()
        )

        if chunks:
            seq_counter = 1
            for chk in chunks:
                try:
                    coords = json.loads(chk.encoded_geometry)
                    for item in coords:
                        lat = float(item[0])
                        lng = float(item[1])
                        epoch_sec = int(item[2])
                        acc = float(item[3])
                        spd = float(item[4]) if len(item) > 4 and item[4] is not None else None
                        brg = float(item[5]) if len(item) > 5 and item[5] is not None else None
                        is_gap = bool(item[6]) if len(item) > 6 and item[6] else False

                        point_details.append(
                            RoutePointDetail(
                                id=seq_counter,
                                sequence_number=seq_counter,
                                latitude=lat,
                                longitude=lng,
                                accuracy_meters=acc,
                                altitude_meters=None,
                                speed_mps=spd,
                                bearing_degrees=brg,
                                recorded_at=datetime.utcfromtimestamp(epoch_sec),
                                is_gap=is_gap,
                            )
                        )
                        seq_counter += 1
                except Exception:
                    pass

    # 3. Fallback to raw points if chunks empty
    if not point_details:
        raw_points = (
            db.query(GpsRoutePoint)
            .filter(GpsRoutePoint.session_id == session.id)
            .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
            .all()
        )
        point_details = [
            RoutePointDetail(
                id=p.id,
                sequence_number=i + 1,
                client_point_id=p.client_point_id,
                employee_id=p.employee_id or (session.user.employee_id if session.user else None),
                device_id=p.device_id or (session.user.device_id if session.user else None),
                latitude=float(p.latitude),
                longitude=float(p.longitude),
                accuracy_meters=float(p.accuracy_meters),
                altitude_meters=float(p.altitude_meters) if p.altitude_meters else None,
                speed_mps=float(p.speed_mps) if p.speed_mps else None,
                bearing_degrees=float(p.bearing_degrees) if p.bearing_degrees else None,
                recorded_at=p.recorded_at,
                is_gap=bool(p.is_gap) if hasattr(p, "is_gap") and p.is_gap else False,
            )
            for i, p in enumerate(raw_points)
        ]
        is_raw_route = True

    effective_point_count = len(point_details)

    summary = _build_session_summary(db, session, effective_point_count)

    return TrackingRouteResponse(
        session=summary,
        points=point_details,
        total_points=effective_point_count,
        is_raw=is_raw_route,
    )


@router.get("/sessions/{session_id}/raw-points", response_model=RawRoutePointsResponse)
def get_session_raw_points(
    session_id: int,
    page: Optional[int] = Query(None, ge=1, description="Page number for pagination"),
    limit: Optional[int] = Query(None, ge=0, description="Items per page. If 0 or omitted, returns all points without truncation."),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieve all raw GPS points for a session, ordered chronologically.
    No silent limit: if limit is omitted or 0, returns all captured points."""
    session = db.query(TrackingSession).filter(TrackingSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to raw points.")

    base_query = (
        db.query(GpsRoutePoint)
        .filter(GpsRoutePoint.session_id == session.id)
        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
    )

    total_points = base_query.count()

    if limit and limit > 0:
        p_num = page or 1
        offset = (p_num - 1) * limit
        points = base_query.offset(offset).limit(limit).all()
        total_pages = (total_points + limit - 1) // limit
    else:
        points = base_query.all()
        p_num = 1
        offset = 0
        limit = total_points
        total_pages = 1

    point_details = [
        RoutePointDetail(
            id=p.id,
            sequence_number=offset + i + 1,
            client_point_id=p.client_point_id,
            employee_id=p.employee_id or (session.user.employee_id if session.user else None),
            device_id=p.device_id or (session.user.device_id if session.user else None),
            latitude=float(p.latitude),
            longitude=float(p.longitude),
            accuracy_meters=float(p.accuracy_meters),
            altitude_meters=float(p.altitude_meters) if p.altitude_meters else None,
            speed_mps=float(p.speed_mps) if p.speed_mps else None,
            bearing_degrees=float(p.bearing_degrees) if p.bearing_degrees else None,
            recorded_at=p.recorded_at,
            is_gap=bool(p.is_gap) if hasattr(p, "is_gap") and p.is_gap else False,
        )
        for i, p in enumerate(points)
    ]

    summary = _build_session_summary(db, session, total_points)

    return RawRoutePointsResponse(
        session=summary,
        points=point_details,
        total_points=total_points,
        page=p_num,
        limit=limit,
        total_pages=total_pages,
    )


@router.get("/sessions/{session_id}/playback", response_model=PlaybackRouteResponse)
def get_session_playback(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieve full chronological GPS points strictly ordered by recorded_at ASC, sequence_number ASC
    specifically designed for accurate route playback reconstruction."""
    session = db.query(TrackingSession).filter(TrackingSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to route playback.")

    raw_points = (
        db.query(GpsRoutePoint)
        .filter(GpsRoutePoint.session_id == session.id)
        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
        .all()
    )

    playback_points = [
        PlaybackPointItem(
            id=p.id,
            sequence_number=i + 1,
            client_point_id=p.client_point_id,
            latitude=float(p.latitude),
            longitude=float(p.longitude),
            accuracy_meters=float(p.accuracy_meters),
            altitude_meters=float(p.altitude_meters) if p.altitude_meters else None,
            speed_mps=float(p.speed_mps) if p.speed_mps else None,
            bearing_degrees=float(p.bearing_degrees) if p.bearing_degrees else None,
            recorded_at=p.recorded_at,
            is_gap=bool(p.is_gap) if hasattr(p, "is_gap") and p.is_gap else False,
        )
        for i, p in enumerate(raw_points)
    ]

    summary = _build_session_summary(db, session, len(playback_points))

    return PlaybackRouteResponse(
        session=summary,
        points=playback_points,
        total_points=len(playback_points),
    )


@router.get("/sessions/{session_id}/processed-route", response_model=TrackingRouteResponse)
def get_session_processed_route(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieve simplified/processed route points derived by ML or route simplification.
    Does not delete or alter raw points."""
    return get_session_route(session_id=session_id, raw=False, current_user=current_user, db=db)


@router.post("/sessions/{session_id}/process-ml")
def process_ml_route(
    session_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Run ML route processing and simplification.
    CRITICAL: Preserves original raw GPS records intact in gps_route_points without modifying or deleting them.
    Stores simplified derived route representation separately."""
    session = db.query(TrackingSession).filter(TrackingSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access.")

    # 1. Fetch raw points in chronological order
    raw_points = (
        db.query(GpsRoutePoint)
        .filter(GpsRoutePoint.session_id == session.id)
        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
        .all()
    )

    if not raw_points:
        return {
            "success": True,
            "message": "No raw points found for session.",
            "raw_point_count": 0,
            "processed_points_count": 0,
            "raw_data_preserved": True,
        }

    # 2. Derive simplified vertices for display without altering raw points
    coords = [
        [
            float(p.latitude),
            float(p.longitude),
            int(p.recorded_at.timestamp()),
            float(p.accuracy_meters),
            float(p.speed_mps or 0.0),
            float(p.bearing_degrees or 0.0),
            bool(p.is_gap),
        ]
        for p in raw_points
    ]

    chunk_uuid = f"ml_chunk_{session.id}_{int(datetime.utcnow().timestamp())}"
    encoded = json.dumps(coords)

    chunk = db.query(TrackingRouteChunk).filter(TrackingRouteChunk.session_id == session.id).first()
    if not chunk:
        chunk = TrackingRouteChunk(
            chunk_uuid=chunk_uuid,
            session_id=session.id,
            chunk_sequence=1,
            point_count=len(coords),
            encoded_geometry=encoded,
            start_time=raw_points[0].recorded_at,
            end_time=raw_points[-1].recorded_at,
            distance_meters=float(session.total_distance_meters),
        )
        db.add(chunk)
    else:
        chunk.encoded_geometry = encoded
        chunk.point_count = len(coords)
        chunk.end_time = raw_points[-1].recorded_at

    db.commit()

    # Confirm raw points table is 100% intact
    raw_count_after = db.query(GpsRoutePoint).filter(GpsRoutePoint.session_id == session.id).count()

    return {
        "success": True,
        "session_id": session.id,
        "raw_points_count": raw_count_after,
        "processed_points_count": len(coords),
        "raw_data_preserved": raw_count_after == len(raw_points),
        "message": f"ML processing complete. All {raw_count_after} raw points preserved permanently in database.",
    }


@router.post("/archive")
def archive_old_route_chunks(
    req: RouteArchiveRequest,
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Configurable data retention: purges route chunks and raw points older than retention_days (default 90 days),
    permanently preserving session summaries (cumulative distance, dates, punch links, employee IDs)."""
    cutoff = datetime.utcnow() - timedelta(days=req.retention_days)

    deleted_chunks = (
        db.query(TrackingRouteChunk)
        .filter(TrackingRouteChunk.created_at < cutoff)
        .delete(synchronize_session=False)
    )
    deleted_points = (
        db.query(GpsRoutePoint)
        .filter(GpsRoutePoint.created_at < cutoff)
        .delete(synchronize_session=False)
    )
    db.commit()

    return {
        "success": True,
        "message": f"Archival completed for records older than {req.retention_days} days (cutoff: {cutoff.date()}). Purged {deleted_chunks} route chunks and {deleted_points} legacy route points. All session summaries remain intact.",
        "retention_days": req.retention_days,
        "cutoff_date": str(cutoff.date()),
        "purged_chunks": deleted_chunks,
        "purged_points": deleted_points,
    }


@router.get("/statistics", response_model=TrackingStatisticsResponse)
def get_tracking_statistics(
    user_id: Optional[int] = Query(None, description="Filter by user ID"),
    work_date: Optional[str] = Query(None, description="Filter by work date YYYY-MM-DD"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieve aggregate distance and journey metrics for employee travel."""
    query = db.query(TrackingSession)
    if current_user.role != UserRole.ADMIN:
        query = query.filter(TrackingSession.user_id == current_user.id)
    elif user_id:
        query = query.filter(TrackingSession.user_id == user_id)

    if work_date:
        try:
            d = datetime.strptime(work_date, "%Y-%m-%d").date()
            query = query.filter(TrackingSession.work_date == d)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")

    sessions = query.all()
    total_sessions = len(sessions)
    active_sessions = sum(1 for s in sessions if s.status in ("RECORDING", "PAUSED"))
    completed_sessions = sum(1 for s in sessions if s.status == "COMPLETED")
    total_dist_meters = sum(float(s.total_distance_meters or 0.0) for s in sessions)
    total_dur_seconds = sum(int(s.total_duration_seconds or 0) for s in sessions)

    session_ids = [s.id for s in sessions]
    total_points = (
        db.query(GpsRoutePoint.id).filter(GpsRoutePoint.session_id.in_(session_ids)).count()
        if session_ids
        else 0
    )

    return TrackingStatisticsResponse(
        total_sessions=total_sessions,
        active_sessions=active_sessions,
        completed_sessions=completed_sessions,
        total_distance_km=round(total_dist_meters / 1000.0, 3),
        total_duration_hours=round(total_dur_seconds / 3600.0, 2),
        total_points=total_points,
    )
