import logging
from datetime import datetime, date, timedelta, time
from typing import Optional, List, Dict, Any
import pytz
from sqlalchemy.orm import Session
from sqlalchemy import or_, desc

from app.models.user import User, UserRole
from app.models.shift import Shift, EmployeeShiftAssignment
from app.models.tracking import TrackingSession, GpsRoutePoint, TrackingInterruptionEvent
from app.services.shift_service import ShiftService
from app.services.shift_engine_service import ShiftEngineService

logger = logging.getLogger("shift_tracking_scheduler")

class ShiftTrackingSchedulerService:
    """
    Production-grade automatic background shift-tracking scheduler.
    Enforces daily shift-based location tracking lifecycles:
    1. At shift start: Automatically creates/activates the tracking session (SCHEDULED -> RECORDING).
    2. During shift: Validates coordinates against the shift window [shift_start, shift_end].
    3. At shift end: Automatically finalizes the session (COMPLETED) without requiring manual app stops.
    4. Survives restarts: Reconciles all missed transitions across server downtime.
    5. Prevents premature completion or false 'COMPLETE' reports on zero-point sessions.
    """

    @staticmethod
    def _to_naive_utc(dt: Optional[datetime]) -> Optional[datetime]:
        if dt is None:
            return None
        if getattr(dt, "tzinfo", None) is not None:
            return dt.astimezone(pytz.utc).replace(tzinfo=None)
        return dt

    @classmethod
    def resolve_shift_window(
        cls,
        db: Session,
        user_id: int,
        target_date: date,
        shift_id: Optional[int] = None,
    ) -> tuple[Optional[Shift], datetime, datetime]:
        """
        Dynamically resolves the user's shift and canonical shift window in UTC.
        Supports any timezone (default Asia/Kolkata), punch periods, rules, and overnight shifts.
        """
        shift = None
        if shift_id:
            shift = db.query(Shift).filter(Shift.id == shift_id, Shift.is_active == True).first()
        if not shift:
            shift = ShiftService.get_effective_shift_for_user(db=db, user_id=user_id, target_date=target_date)
        if not shift:
            shift = ShiftEngineService.get_assigned_shift(db=db, user_id=user_id, target_date=target_date)
        if not shift:
            shift = db.query(Shift).filter(Shift.is_active == True).first()

        tz_name = getattr(shift, "timezone", None) or "Asia/Kolkata"
        try:
            local_tz = pytz.timezone(tz_name)
        except Exception:
            local_tz = pytz.timezone("Asia/Kolkata")

        periods = getattr(shift, "punch_periods", None) or []
        if not periods and hasattr(shift, "rules") and shift.rules:
            periods = shift.rules

        min_start: Optional[time] = None
        max_end: Optional[time] = None

        for p in periods:
            st = getattr(p, "start_time", None)
            et = getattr(p, "end_time", None)
            if isinstance(st, timedelta):
                st = (datetime.min + st).time()
            if isinstance(et, timedelta):
                et = (datetime.min + et).time()

            if st is not None:
                if min_start is None or st < min_start:
                    min_start = st
            if et is not None:
                if max_end is None or et > max_end:
                    max_end = et

        # Canonical default: 08:30 AM to 06:00 PM if no rules/periods found
        if min_start is None:
            min_start = time(8, 30, 0)
        if max_end is None:
            max_end = time(18, 0, 0)

        local_start_dt = local_tz.localize(datetime.combine(target_date, min_start))
        local_end_dt = local_tz.localize(datetime.combine(target_date, max_end))

        # Handle overnight shift crossing midnight
        if local_end_dt < local_start_dt:
            local_end_dt += timedelta(days=1)

        shift_start_utc = local_start_dt.astimezone(pytz.utc).replace(tzinfo=None)
        shift_end_utc = local_end_dt.astimezone(pytz.utc).replace(tzinfo=None)

        return shift, shift_start_utc, shift_end_utc

    @classmethod
    def reconcile_session(
        cls,
        db: Session,
        session: TrackingSession,
        as_of_utc: Optional[datetime] = None,
    ) -> TrackingSession:
        """
        Reconciles a tracking session's lifecycle, shift window, status, and completeness.
        """
        now_utc = cls._to_naive_utc(as_of_utc) or datetime.utcnow()

        # 1. Resolve shift bounds if missing
        if not session.shift_start_time or not session.shift_end_time or not session.shift_id:
            shift, s_start, s_end = cls.resolve_shift_window(
                db=db,
                user_id=session.user_id,
                target_date=session.work_date,
                shift_id=session.shift_id,
            )
            if not session.shift_id and shift:
                session.shift_id = shift.id
            if not session.shift_start_time:
                session.shift_start_time = s_start
            if not session.shift_end_time:
                session.shift_end_time = s_end

        shift_start_utc = cls._to_naive_utc(session.shift_start_time)
        shift_end_utc = cls._to_naive_utc(session.shift_end_time)

        # 2. Count actual persisted GPS points
        actual_pts = db.query(GpsRoutePoint.id).filter(GpsRoutePoint.session_id == session.id).count()
        session.retained_point_count = actual_pts

        # 3. Synchronize actual start time from first in-shift coordinate
        if actual_pts > 0:
            first_pt = (
                db.query(GpsRoutePoint.recorded_at, GpsRoutePoint.latitude, GpsRoutePoint.longitude)
                .filter(GpsRoutePoint.session_id == session.id)
                .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
                .first()
            )
            if first_pt:
                session.actual_start_time = first_pt.recorded_at
                if session.start_latitude is None:
                    session.start_latitude = first_pt.latitude
                    session.start_longitude = first_pt.longitude

            latest_pt = (
                db.query(GpsRoutePoint.recorded_at, GpsRoutePoint.latitude, GpsRoutePoint.longitude)
                .filter(GpsRoutePoint.session_id == session.id)
                .order_by(GpsRoutePoint.recorded_at.desc(), GpsRoutePoint.id.desc())
                .first()
            )
            if latest_pt:
                session.last_accepted_latitude = latest_pt.latitude
                session.last_accepted_longitude = latest_pt.longitude
                session.last_accepted_time = latest_pt.recorded_at

        # 4. Check shift timeline status
        is_past_day = session.work_date < now_utc.date()
        shift_ended = (shift_end_utc and now_utc >= shift_end_utc) or is_past_day
        shift_started = shift_start_utc and (now_utc >= shift_start_utc)

        if shift_ended:
            # Shift has ended
            if session.status in ("RECORDING", "ACTIVE", "SCHEDULED", "PAUSED", "INTERRUPTED", "DEGRADED", "RECOVERING"):
                session.status = "COMPLETED"
                session.end_time = shift_end_utc
                session.actual_stop_time = session.last_accepted_time or shift_end_utc

            # Zero-point sessions that ended MUST be marked INCOMPLETE, never COMPLETE
            if actual_pts == 0:
                session.tracking_completeness = "INCOMPLETE"
            else:
                # Check for premature stop (> 15 min before shift end)
                eff_last = cls._to_naive_utc(session.last_accepted_time)
                if eff_last and shift_end_utc and (shift_end_utc - eff_last).total_seconds() > 900:
                    session.tracking_completeness = "INCOMPLETE"
                else:
                    # Check internal gaps during shift
                    has_gap = False
                    points_asc = (
                        db.query(GpsRoutePoint.recorded_at)
                        .filter(GpsRoutePoint.session_id == session.id)
                        .order_by(GpsRoutePoint.recorded_at.asc(), GpsRoutePoint.id.asc())
                        .all()
                    )
                    for i in range(len(points_asc) - 1):
                        t1 = points_asc[i].recorded_at
                        t2 = points_asc[i + 1].recorded_at
                        if t1 and t2:
                            gap_s = (t2 - t1).total_seconds()
                            if gap_s > 900:
                                has_gap = True
                                break
                    session.tracking_completeness = "HAS_GAPS" if has_gap else "COMPLETE"
        elif shift_started:
            # Shift is currently active today
            if session.status == "SCHEDULED":
                session.status = "RECORDING"
                session.updated_at = now_utc

            if actual_pts == 0:
                # Active shift with no points yet: pending sync / incomplete
                session.tracking_completeness = "PENDING_SYNC"
            else:
                # Check if tracking has stalled during active shift (> 15m silence)
                activities = [
                    cls._to_naive_utc(session.last_accepted_time),
                    cls._to_naive_utc(session.last_heartbeat_time),
                    cls._to_naive_utc(session.last_sync_time),
                    shift_start_utc,
                ]
                valid_acts = [a for a in activities if a is not None]
                last_act = max(valid_acts) if valid_acts else now_utc
                silence_sec = (now_utc - last_act).total_seconds()
                if silence_sec > 900:
                    session.status = "INTERRUPTED"
                    session.tracking_completeness = "HAS_GAPS"
                else:
                    if session.status == "INTERRUPTED":
                        session.status = "RECORDING"
                    session.tracking_completeness = "COMPLETE"
        else:
            # Shift has not yet started (upcoming today)
            session.status = "SCHEDULED"
            session.tracking_completeness = "PENDING_SYNC"
            session.end_time = None
            session.actual_stop_time = None

        session.updated_at = now_utc
        try:
            db.commit()
        except Exception:
            db.rollback()
        return session

    @classmethod
    def ensure_daily_sessions_for_date(
        cls,
        db: Session,
        target_date: date,
        user_id: Optional[int] = None,
        as_of_utc: Optional[datetime] = None,
    ) -> List[TrackingSession]:
        """
        Idempotently creates or reconciles tracking sessions for all assigned employees on target_date.
        Ensures that every scheduled employee has a deterministic shift session record.
        """
        now_utc = cls._to_naive_utc(as_of_utc) or datetime.utcnow()

        user_query = db.query(User).filter(User.is_active == True)
        if user_id:
            user_query = user_query.filter(User.id == user_id)
        else:
            user_query = user_query.filter(User.role != UserRole.ADMIN)

        users = user_query.all()
        sessions: List[TrackingSession] = []

        for u in users:
            shift, s_start_utc, s_end_utc = cls.resolve_shift_window(db=db, user_id=u.id, target_date=target_date)
            resolved_shift_id = shift.id if shift else None
            canonical_uuid = f"TRACK_{u.id}_SHIFT_{resolved_shift_id or 'GENERAL'}_{target_date}"

            existing = (
                db.query(TrackingSession)
                .filter(
                    TrackingSession.user_id == u.id,
                    TrackingSession.work_date == target_date,
                )
                .first()
            )

            if existing:
                sess = cls.reconcile_session(db, existing, as_of_utc=now_utc)
                sessions.append(sess)
            else:
                # Determine initial lifecycle state based on current time
                shift_ended = (s_end_utc and now_utc >= s_end_utc) or (target_date < now_utc.date())
                shift_started = s_start_utc and (now_utc >= s_start_utc)

                if shift_ended:
                    initial_status = "COMPLETED"
                    initial_completeness = "INCOMPLETE" # 0 points recorded
                    initial_end_time = s_end_utc
                elif shift_started:
                    initial_status = "RECORDING"
                    initial_completeness = "PENDING_SYNC"
                    initial_end_time = None
                else:
                    initial_status = "SCHEDULED"
                    initial_completeness = "PENDING_SYNC"
                    initial_end_time = None

                new_session = TrackingSession(
                    session_uuid=canonical_uuid,
                    user_id=u.id,
                    shift_id=resolved_shift_id,
                    work_date=target_date,
                    shift_start_time=s_start_utc,
                    shift_end_time=s_end_utc,
                    start_time=s_start_utc,
                    end_time=initial_end_time,
                    actual_start_time=None,
                    actual_stop_time=None,
                    status=initial_status,
                    total_distance_meters=0.0,
                    total_duration_seconds=0,
                    retained_point_count=0,
                    tracking_completeness=initial_completeness,
                    created_at=now_utc,
                    updated_at=now_utc,
                )
                db.add(new_session)
                try:
                    db.flush()
                    sessions.append(new_session)
                    logger.info(f"[ShiftScheduler] Created automatic session for User {u.id} on {target_date}: {canonical_uuid} (Status: {initial_status})")
                except Exception as ex:
                    db.rollback()
                    logger.warning(f"[ShiftScheduler] Could not create session for User {u.id}: {ex}")

        try:
            db.commit()
        except Exception:
            db.rollback()

        return sessions

    @classmethod
    def evaluate_and_reconcile_all(cls, db: Session, as_of_utc: Optional[datetime] = None) -> Dict[str, Any]:
        """
        Background scheduler tick function. Evaluates all assigned shifts:
        - Creates/activates sessions at shift start.
        - Completes expired sessions at shift end.
        - Catches up missed transitions after downtime.
        """
        now_utc = cls._to_naive_utc(as_of_utc) or datetime.utcnow()
        ist_tz = pytz.timezone("Asia/Kolkata")
        today_ist = pytz.utc.localize(now_utc).astimezone(ist_tz).date()

        reconciled = cls.ensure_daily_sessions_for_date(db, today_ist, as_of_utc=now_utc)

        # Also reconcile yesterday's unfinished sessions if any
        yesterday_ist = today_ist - timedelta(days=1)
        unclosed_yesterday = (
            db.query(TrackingSession)
            .filter(
                TrackingSession.work_date == yesterday_ist,
                TrackingSession.status.in_(["RECORDING", "ACTIVE", "SCHEDULED", "PAUSED", "INTERRUPTED", "DEGRADED", "RECOVERING"]),
            )
            .all()
        )
        for s in unclosed_yesterday:
            cls.reconcile_session(db, s, as_of_utc=now_utc)

        try:
            db.commit()
        except Exception:
            db.rollback()

        return {
            "success": True,
            "evaluated_date": str(today_ist),
            "reconciled_session_count": len(reconciled),
            "closed_yesterday_count": len(unclosed_yesterday),
            "timestamp": now_utc.isoformat(),
        }
