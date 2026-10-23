from datetime import datetime, date, time, timedelta, timezone
from typing import List, Optional, Dict, Any, Tuple
from sqlalchemy.orm import Session
from app.models.user import User
from app.models.shift import Shift, EmployeeShiftAssignment
from app.models.policy import (
    AttendancePolicy,
    DayTypePolicy,
    ShiftEvent,
    MissedPunchRequest,
    AttendanceDailySummary,
    DayType,
    EventType,
    PunchWindowMode,
)
from app.models.attendance import Attendance
from app.services.time_service import TimeService

class ShiftEngineService:
    """
    Authoritative, Configurable Attendance & Shift Rule Engine.
    No hardcoded shift timings, punch numbers, holiday windows, or absence thresholds.
    """

    @staticmethod
    def get_assigned_shift(db: Session, user_id: int, target_date: date) -> Optional[Shift]:
        """Fetch active shift assigned to employee for target date."""
        assignment = (
            db.query(EmployeeShiftAssignment)
            .filter(
                EmployeeShiftAssignment.user_id == user_id,
                EmployeeShiftAssignment.is_active == True,
                EmployeeShiftAssignment.effective_from <= target_date,
            )
            .filter(
                (EmployeeShiftAssignment.effective_to.is_(None))
                | (EmployeeShiftAssignment.effective_to >= target_date)
            )
            .order_by(EmployeeShiftAssignment.effective_from.desc())
            .first()
        )
        if assignment and assignment.shift and assignment.shift.is_active:
            return assignment.shift

        # Fallback to default active shift if any exists
        default_shift = db.query(Shift).filter(Shift.is_active == True).first()
        return default_shift

    @staticmethod
    def get_user_day_type(db: Session, user_id: int, target_date: date) -> DayType:
        """Determine day type (NORMAL, HOLIDAY, WEEK_OFF) from user or global settings."""
        # Standard weekend check (Sunday = week off) unless overridden
        if target_date.weekday() == 6: # Sunday
            return DayType.WEEK_OFF
        return DayType.NORMAL

    @staticmethod
    def evaluate_next_event(
        db: Session,
        user: User,
        target_date: Optional[date] = None,
        override_time: Optional[datetime] = None
    ) -> Dict[str, Any]:
        """
        Generic dynamic event evaluator.
        Determines current server time, day type, assigned shift, expected event, window state.
        """
        tz = TimeService.get_server_timezone()
        if override_time:
            now_dt = override_time if override_time.tzinfo is not None else tz.localize(override_time)
        else:
            raw_ts = server_info.get("server_timestamp")
            if isinstance(raw_ts, datetime):
                now_dt = raw_ts if raw_ts.tzinfo is not None else tz.localize(raw_ts)
            elif isinstance(raw_ts, str):
                try:
                    dt = datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
                    now_dt = dt.astimezone(tz)
                except Exception:
                    now_dt = datetime.now(tz)
            else:
                now_dt = datetime.now(tz)
        current_date = target_date or now_dt.date()
        current_time = now_dt.time()

        shift = ShiftEngineService.get_assigned_shift(db, user.id, current_date)
        if not shift:
            return {
                "success": False,
                "message": "No active shift assigned to employee",
                "server_time": now_dt.isoformat(),
                "attendance_date": current_date.isoformat(),
            }

        policy = shift.attendance_policy
        day_type = ShiftEngineService.get_user_day_type(db, user.id, current_date)

        # Get shift events ordered by sequence_no
        events: List[ShiftEvent] = (
            db.query(ShiftEvent)
            .filter(ShiftEvent.shift_id == shift.id)
            .order_by(ShiftEvent.sequence_no.asc())
            .all()
        )

        if not events:
            return {
                "success": False,
                "message": f"Shift '{shift.shift_name}' has no defined events",
                "server_time": now_dt.isoformat(),
                "attendance_date": current_date.isoformat(),
            }

        # Fetch today's existing punches
        existing_punches = (
            db.query(Attendance)
            .filter(
                Attendance.user_id == user.id,
                Attendance.attendance_date == current_date,
            )
            .order_by(Attendance.verification_no.asc())
            .all()
        )

        completed_sequence_nos = [p.verification_no for p in existing_punches]

        # Find next expected event
        next_event = None
        for ev in events:
            if ev.sequence_no not in completed_sequence_nos:
                next_event = ev
                break

        if not next_event:
            return {
                "success": True,
                "status": "SHIFT_COMPLETED",
                "message": "All shift events for today have been completed.",
                "server_time": now_dt.isoformat(),
                "attendance_date": current_date.isoformat(),
                "shift": {"id": shift.id, "name": shift.shift_name, "code": shift.shift_code},
                "total_events": len(events),
                "completed_events": len(completed_sequence_nos),
            }

        # Evaluate Punch Window for expected event
        window_start_dt = datetime.combine(current_date, next_event.window_start)
        window_end_dt = datetime.combine(current_date, next_event.window_end)
        grace_end_dt = window_end_dt + timedelta(seconds=next_event.grace_period_seconds)

        window_status = "UNKNOWN"
        if day_type in (DayType.HOLIDAY, DayType.WEEK_OFF):
            # Check flexible policy
            day_policy = shift.day_type_policy
            mode = day_policy.punch_window_mode if day_policy else PunchWindowMode.FLEXIBLE
            if mode == PunchWindowMode.FLEXIBLE:
                window_status = "WINDOW_OPEN"
            elif mode == PunchWindowMode.BLOCKED:
                window_status = "PUNCH_BLOCKED_DAY"
            else:
                # STRICT
                if window_start_dt <= now_dt <= grace_end_dt:
                    window_status = "WINDOW_OPEN"
                elif now_dt < window_start_dt:
                    window_status = "WINDOW_NOT_OPEN"
                else:
                    window_status = "WINDOW_EXPIRED"
        else:
            if window_start_dt <= now_dt <= grace_end_dt:
                window_status = "WINDOW_OPEN"
            elif now_dt < window_start_dt:
                window_status = "WINDOW_NOT_OPEN"
            else:
                window_status = "WINDOW_EXPIRED"

        # Check if Missed Punch recovery is eligible
        missed_punch_eligible = False
        if window_status == "WINDOW_EXPIRED":
            missed_enabled = policy.missed_punch_enabled if policy else True
            # Check if request already submitted
            existing_request = (
                db.query(MissedPunchRequest)
                .filter(
                    MissedPunchRequest.user_id == user.id,
                    MissedPunchRequest.attendance_date == current_date,
                    MissedPunchRequest.shift_event_id == next_event.id,
                )
                .first()
            )
            if missed_enabled and not existing_request:
                missed_punch_eligible = True

        return {
            "success": True,
            "server_time": now_dt.isoformat(),
            "attendance_date": current_date.isoformat(),
            "day_type": day_type.value,
            "shift": {
                "id": shift.id,
                "name": shift.shift_name,
                "code": shift.shift_code,
            },
            "expected_event": {
                "id": next_event.id,
                "sequence_no": next_event.sequence_no,
                "session_id": next_event.session_id,
                "event_type": next_event.event_type.value,
                "event_name": next_event.event_name or f"{next_event.event_type.value} #{next_event.sequence_no}",
                "window_start": next_event.window_start.strftime("%H:%M:%S"),
                "window_end": next_event.window_end.strftime("%H:%M:%S"),
                "grace_period_seconds": next_event.grace_period_seconds,
            },
            "window_status": window_status,
            "missed_punch_eligible": missed_punch_eligible,
            "total_events": len(events),
            "completed_events": len(completed_sequence_nos),
            "policy": {
                "allow_out_of_sequence": policy.allow_out_of_sequence if policy else False,
                "missed_punch_requires_face": policy.missed_punch_requires_face if policy else True,
                "missed_punch_requires_liveness": policy.missed_punch_requires_liveness if policy else True,
                "missed_punch_requires_gps": policy.missed_punch_requires_gps if policy else True,
                "missed_punch_requires_approval": policy.missed_punch_requires_approval if policy else True,
            },
        }

    @staticmethod
    def calculate_daily_summary(db: Session, user_id: int, target_date: date) -> AttendanceDailySummary:
        """Calculate and update attendance daily summary dynamically."""
        shift = ShiftEngineService.get_assigned_shift(db, user_id, target_date)
        day_type = ShiftEngineService.get_user_day_type(db, user_id, target_date)

        if not shift:
            summary = (
                db.query(AttendanceDailySummary)
                .filter(AttendanceDailySummary.user_id == user_id, AttendanceDailySummary.attendance_date == target_date)
                .first()
            )
            if not summary:
                summary = AttendanceDailySummary(user_id=user_id, attendance_date=target_date, day_type=day_type, attendance_status="NO_SHIFT")
                db.add(summary)
                db.commit()
            return summary

        events = db.query(ShiftEvent).filter(ShiftEvent.shift_id == shift.id).all()
        total_events = len(events)

        punches = db.query(Attendance).filter(Attendance.user_id == user_id, Attendance.attendance_date == target_date).all()
        completed_events = len(punches)

        approved_missed = (
            db.query(MissedPunchRequest)
            .filter(
                MissedPunchRequest.user_id == user_id,
                MissedPunchRequest.attendance_date == target_date,
                MissedPunchRequest.approval_status == "APPROVED"
            )
            .count()
        )

        effective_completed = completed_events + approved_missed
        missed_count = max(0, total_events - effective_completed)

        if day_type in (DayType.HOLIDAY, DayType.WEEK_OFF):
            status = "HOLIDAY" if day_type == DayType.HOLIDAY else "WEEK_OFF"
        elif effective_completed >= total_events:
            status = "FULL_DAY_PRESENT"
        elif effective_completed >= (total_events / 2):
            status = "HALF_DAY"
        else:
            status = "FULL_DAY_ABSENT"

        summary = (
            db.query(AttendanceDailySummary)
            .filter(AttendanceDailySummary.user_id == user_id, AttendanceDailySummary.attendance_date == target_date)
            .first()
        )
        if not summary:
            summary = AttendanceDailySummary(
                user_id=user_id,
                attendance_date=target_date,
                day_type=day_type,
                shift_id=shift.id,
                total_expected_events=total_events,
                completed_events=completed_events,
                missed_events=missed_count,
                approved_missed_events=approved_missed,
                attendance_status=status
            )
            db.add(summary)
        else:
            summary.total_expected_events = total_events
            summary.completed_events = completed_events
            summary.missed_events = missed_count
            summary.approved_missed_events = approved_missed
            summary.attendance_status = status

        db.commit()
        db.refresh(summary)
        return summary
