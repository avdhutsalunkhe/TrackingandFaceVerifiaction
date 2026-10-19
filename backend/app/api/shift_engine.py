from datetime import date
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.dependencies import get_current_user, require_admin
from app.models.user import User
from app.models.policy import MissedPunchRequest, ShiftEvent
from app.services.shift_engine_service import ShiftEngineService

router = APIRouter(prefix="/api/attendance", tags=["Configurable Shift Engine"])

@router.get("/next-event", summary="Get current attendance state and next expected event")
def get_next_event(
    target_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Evaluates server time, assigned shift, day type, expected event, window state,
    and missed punch eligibility dynamically without hardcoded assumptions.
    """
    parsed_date = None
    if target_date:
        try:
            parsed_date = date.fromisoformat(target_date)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid target_date format. Use YYYY-MM-DD")
            
    eval_result = ShiftEngineService.evaluate_next_event(db, current_user, target_date=parsed_date)
    return eval_result

@router.post("/missed-punch", summary="Submit missed punch request for expired window")
def submit_missed_punch(
    shift_event_id: int,
    reason: str,
    attendance_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Allows employee to submit a missed punch request if permitted by shift policy.
    """
    event = db.query(ShiftEvent).filter(ShiftEvent.id == shift_event_id).first()
    if not event:
        raise HTTPException(status_code=404, detail="Shift event not found")

    target_dt = date.fromisoformat(attendance_date) if attendance_date else date.today()

    existing = db.query(MissedPunchRequest).filter(
        MissedPunchRequest.user_id == current_user.id,
        MissedPunchRequest.shift_event_id == shift_event_id,
        MissedPunchRequest.attendance_date == target_dt
    ).first()

    if existing:
        return {"success": False, "message": "Missed punch request already submitted for this event.", "status": existing.approval_status}

    request_rec = MissedPunchRequest(
        user_id=current_user.id,
        shift_id=event.shift_id,
        shift_event_id=shift_event_id,
        attendance_date=target_dt,
        reason=reason,
        approval_status="PENDING"
    )
    db.add(request_rec)
    db.commit()
    db.refresh(request_rec)

    return {
        "success": True,
        "message": "Missed punch request submitted successfully. Pending admin approval.",
        "request_id": request_rec.id,
        "status": request_rec.approval_status
    }

@router.get("/summary", summary="Get daily attendance summary calculated by rule engine")
def get_daily_summary(
    attendance_date: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    target_dt = date.fromisoformat(attendance_date) if attendance_date else date.today()
    summary = ShiftEngineService.calculate_daily_summary(db, current_user.id, target_dt)
    return {
        "success": True,
        "attendance_date": summary.attendance_date.isoformat(),
        "day_type": summary.day_type.value,
        "total_expected_events": summary.total_expected_events,
        "completed_events": summary.completed_events,
        "missed_events": summary.missed_events,
        "approved_missed_events": summary.approved_missed_events,
        "attendance_status": summary.attendance_status
    }
