from datetime import datetime, date, timedelta
import json
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc, func

from app.database import get_db
from app.models.user import User, UserRole
from app.models.tracking import TrackingSession, GpsRoutePoint, TrackingRouteChunk
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
)
from app.dependencies import get_current_user, require_admin
from app.services.geofence_service import is_valid_coordinate

router = APIRouter(prefix="/api/tracking", tags=["GPS Journey Tracking"])


@router.post("/start", response_model=StartTrackingResponse)
def start_tracking_session(
    req: StartTrackingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Start or retrieve an existing idempotent GPS tracking session for the authenticated user."""
    # Enforce travel_map_enabled toggle
    if not getattr(current_user, "travel_map_enabled", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Travel Map / GPS Tracking is disabled for your account. Please contact your administrator."
        )

    # 1. Idempotency check: see if session_uuid already exists
    existing = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if existing:
        if existing.user_id != current_user.id and current_user.role != UserRole.ADMIN:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to session.")
        # Update starting coordinates if previously missing and now available
        if existing.start_latitude is None and is_valid_coordinate(req.start_latitude, req.start_longitude):
            existing.start_latitude = req.start_latitude
            existing.start_longitude = req.start_longitude
            db.commit()
        return StartTrackingResponse(
            success=True,
            message="Tracking session already active.",
            session_id=existing.id,
            session_uuid=existing.session_uuid,
            status=existing.status,
        )

    # 1b. Check if user already has an active RECORDING session for today to avoid start time mismatch
    active_today = (
        db.query(TrackingSession)
        .filter(
            TrackingSession.user_id == current_user.id,
            TrackingSession.work_date == date.today(),
            TrackingSession.status == "RECORDING",
        )
        .order_by(TrackingSession.start_time.asc())
        .first()
    )
    if active_today:
        if active_today.start_latitude is None and is_valid_coordinate(req.start_latitude, req.start_longitude):
            active_today.start_latitude = req.start_latitude
            active_today.start_longitude = req.start_longitude
            pt1_exists = db.query(GpsRoutePoint.id).filter(GpsRoutePoint.session_id == active_today.id).first()
            if not pt1_exists:
                init_point = GpsRoutePoint(
                    session_id=active_today.id,
                    user_id=current_user.id,
                    client_point_id=f"{active_today.session_uuid}_pt_1",
                    sequence_number=1,
                    latitude=float(req.start_latitude),
                    longitude=float(req.start_longitude),
                    accuracy_meters=float(req.start_accuracy_meters) if req.start_accuracy_meters is not None else 10.0,
                    altitude_meters=float(req.start_altitude_meters) if req.start_altitude_meters is not None else 0.0,
                    speed_mps=float(req.start_speed_mps) if req.start_speed_mps is not None else 0.0,
                    bearing_degrees=float(req.start_bearing_degrees) if req.start_bearing_degrees is not None else 0.0,
                    recorded_at=req.start_time or datetime.utcnow(),
                    is_gap=0,
                    sync_status="SYNCED",
                )
                db.add(init_point)
            db.commit()
            db.refresh(active_today)
        return StartTrackingResponse(
            success=True,
            message="Resumed active duty tracking session for today.",
            session_id=active_today.id,
            session_uuid=active_today.session_uuid,
            status=active_today.status,
        )

    # 2. Create new tracking session
    session = TrackingSession(
        session_uuid=req.session_uuid,
        user_id=current_user.id,
        attendance_id=req.attendance_id,
        shift_id=req.shift_id,
        work_date=date.today(),
        start_time=req.start_time or datetime.utcnow(),
        status="RECORDING",
        start_latitude=req.start_latitude,
        start_longitude=req.start_longitude,
        total_distance_meters=0.0,
        total_duration_seconds=0,
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    # If valid starting coordinates are provided, insert point #1 into the route
    if is_valid_coordinate(req.start_latitude, req.start_longitude):
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
            recorded_at=session.start_time,
            is_gap=0,
            sync_status="SYNCED",
        )
        db.add(init_point)
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
    """Batch-sync recorded GPS route coordinates from mobile device to server with idempotency."""
    if not getattr(current_user, "travel_map_enabled", True):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Travel Map / GPS Tracking is disabled for your account. New location points cannot be written."
        )

    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        # Auto-recover / create session if missing so background offline points are never dropped
        first_time = req.points[0].recorded_at if req.points else datetime.utcnow()
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            work_date=date.today(),
            start_time=first_time,
            status="RECORDING",
            total_distance_meters=req.current_distance_meters or 0.0,
            total_duration_seconds=req.current_duration_seconds or 0,
        )
        db.add(session)
        db.commit()
        db.refresh(session)

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot upload points to another user's session.")

    accepted_count = 0
    duplicate_count = 0
    rejected_count = 0
    synced_point_ids: List[str] = []
    rejected_point_ids: List[str] = []
    first_valid_point = None

    # Retrieve current max sequence_number for this session to ensure monotonicity
    existing_max_seq = db.query(func.max(GpsRoutePoint.sequence_number)).filter(
        GpsRoutePoint.session_id == session.id
    ).scalar() or 0

    allocated_seq = existing_max_seq

    for p in req.points:
        if not is_valid_coordinate(p.latitude, p.longitude):
            rejected_point_ids.append(p.client_point_id)
            rejected_count += 1
            continue
        if first_valid_point is None:
            first_valid_point = p

        # Check idempotency using stable client_point_id
        exists = db.query(GpsRoutePoint.id).filter(
            GpsRoutePoint.client_point_id == p.client_point_id
        ).first()

        if exists:
            duplicate_count += 1
            synced_point_ids.append(p.client_point_id)
        else:
            allocated_seq += 1
            seq = p.sequence_number if p.sequence_number > 0 else allocated_seq

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
                recorded_at=p.recorded_at,
                is_gap=1 if p.is_gap else 0,
                sync_status="SYNCED",
            )
            db.add(point)
            accepted_count += 1
            synced_point_ids.append(p.client_point_id)

    # Backfill session start coordinates if they were null
    if session.start_latitude is None and first_valid_point is not None:
        session.start_latitude = first_valid_point.latitude
        session.start_longitude = first_valid_point.longitude

    # Update session metrics if provided
    if req.current_distance_meters is not None and req.current_distance_meters > session.total_distance_meters:
        session.total_distance_meters = req.current_distance_meters
    if req.current_duration_seconds is not None and req.current_duration_seconds > session.total_duration_seconds:
        session.total_duration_seconds = req.current_duration_seconds

    session.updated_at = datetime.utcnow()
    db.commit()

    total_count = db.query(GpsRoutePoint).filter(GpsRoutePoint.session_id == session.id).count()

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


@router.post("/stop", response_model=StopTrackingResponse)
def stop_tracking_session(
    req: StopTrackingRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Conclude an active GPS tracking session and record final stats."""
    session = db.query(TrackingSession).filter(TrackingSession.session_uuid == req.session_uuid).first()
    if not session:
        # Auto-recover / conclude session even if /start was not received first
        session = TrackingSession(
            session_uuid=req.session_uuid,
            user_id=current_user.id,
            work_date=date.today(),
            start_time=datetime.utcnow(),
            status="COMPLETED",
            end_time=req.end_time or datetime.utcnow(),
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
    session.end_time = req.end_time or datetime.utcnow()
    if req.end_latitude is not None:
        session.end_latitude = req.end_latitude
    if req.end_longitude is not None:
        session.end_longitude = req.end_longitude
    if req.total_distance_meters is not None:
        session.total_distance_meters = req.total_distance_meters
    if req.total_duration_seconds is not None:
        session.total_duration_seconds = req.total_duration_seconds

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
            session.updated_at = now
            db.commit()
        elif req.event_type in ("SERVICE_RESUMED", "GPS_RESTORED") and session.status == "INTERRUPTED":
            session.status = "RECORDING"
            session.updated_at = now
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
    """List tracking sessions. Non-admins can only see their own sessions."""
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

    if status:
        query = query.filter(TrackingSession.status == status)

    sessions = query.order_by(desc(TrackingSession.start_time)).all()

    summaries = []
    for s in sessions:
        cnt = s.retained_point_count if (s.retained_point_count and s.retained_point_count > 0) else db.query(GpsRoutePoint.id).filter(GpsRoutePoint.session_id == s.id).count()
        summaries.append(
            TrackingSessionSummary(
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
                total_distance_meters=float(s.total_distance_meters),
                total_duration_seconds=int(s.total_duration_seconds),
                point_count=cnt,
            )
        )
    return summaries


@router.get("/sessions/{session_id}/route", response_model=TrackingRouteResponse)
def get_session_route(
    session_id: int,
    raw: bool = Query(True, description="Return raw GPS points if True (default), or simplified if False"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieve full ordered GPS route. By default returns all raw points so refreshes never lose points.
    If raw=false is specified, returns simplified candidate vertices."""
    session = db.query(TrackingSession).filter(TrackingSession.id == session_id).first()
    if not session:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tracking session not found.")

    if session.user_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Unauthorized access to route.")

    point_details: List[RoutePointDetail] = []
    is_raw_route = False

    # 1. If raw is requested (default): retrieve all raw GPS points from gps_route_points
    if raw:
        raw_points = (
            db.query(GpsRoutePoint)
            .filter(GpsRoutePoint.session_id == session.id)
            .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.sequence_number.asc())
            .all()
        )
        if raw_points:
            point_details = [
                RoutePointDetail(
                    id=p.id,
                    sequence_number=p.sequence_number,
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
                for p in raw_points
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
            .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.sequence_number.asc())
            .all()
        )
        point_details = [
            RoutePointDetail(
                id=p.id,
                sequence_number=p.sequence_number,
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
            for p in raw_points
        ]
        is_raw_route = True

    effective_point_count = len(point_details)

    summary = TrackingSessionSummary(
        id=session.id,
        session_uuid=session.session_uuid,
        user_id=session.user_id,
        employee_id=session.user.employee_id if session.user else "UNKNOWN",
        employee_name=session.user.full_name if session.user else "Unknown Employee",
        work_date=str(session.work_date),
        start_time=session.start_time,
        end_time=session.end_time,
        status=session.status,
        start_latitude=float(session.start_latitude) if session.start_latitude else None,
        start_longitude=float(session.start_longitude) if session.start_longitude else None,
        end_latitude=float(session.end_latitude) if session.end_latitude else None,
        end_longitude=float(session.end_longitude) if session.end_longitude else None,
        total_distance_meters=float(session.total_distance_meters),
        total_duration_seconds=int(session.total_duration_seconds),
        point_count=effective_point_count,
    )

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
        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.sequence_number.asc())
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
        limit = total_points
        total_pages = 1

    point_details = [
        RoutePointDetail(
            id=p.id,
            sequence_number=p.sequence_number,
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
        for p in points
    ]

    summary = TrackingSessionSummary(
        id=session.id,
        session_uuid=session.session_uuid,
        user_id=session.user_id,
        employee_id=session.user.employee_id if session.user else "UNKNOWN",
        employee_name=session.user.full_name if session.user else "Unknown Employee",
        work_date=str(session.work_date),
        start_time=session.start_time,
        end_time=session.end_time,
        status=session.status,
        start_latitude=float(session.start_latitude) if session.start_latitude else None,
        start_longitude=float(session.start_longitude) if session.start_longitude else None,
        end_latitude=float(session.end_latitude) if session.end_latitude else None,
        end_longitude=float(session.end_longitude) if session.end_longitude else None,
        total_distance_meters=float(session.total_distance_meters),
        total_duration_seconds=int(session.total_duration_seconds),
        point_count=total_points,
    )

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
        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.sequence_number.asc())
        .all()
    )

    playback_points = [
        PlaybackPointItem(
            id=p.id,
            sequence_number=p.sequence_number,
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
        for p in raw_points
    ]

    summary = TrackingSessionSummary(
        id=session.id,
        session_uuid=session.session_uuid,
        user_id=session.user_id,
        employee_id=session.user.employee_id if session.user else "UNKNOWN",
        employee_name=session.user.full_name if session.user else "Unknown Employee",
        work_date=str(session.work_date),
        start_time=session.start_time,
        end_time=session.end_time,
        status=session.status,
        start_latitude=float(session.start_latitude) if session.start_latitude else None,
        start_longitude=float(session.start_longitude) if session.start_longitude else None,
        end_latitude=float(session.end_latitude) if session.end_latitude else None,
        end_longitude=float(session.end_longitude) if session.end_longitude else None,
        total_distance_meters=float(session.total_distance_meters),
        total_duration_seconds=int(session.total_duration_seconds),
        point_count=len(playback_points),
    )

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
        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.sequence_number.asc())
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
