from datetime import datetime, date, time, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User
from app.models.shift import Shift, ShiftRule, ShiftPunchPeriod, EmployeeShiftAssignment
from app.schemas.shift import (
    ShiftCreate,
    ShiftUpdate,
    ShiftResponse,
    ShiftRuleCreate,
    ShiftRuleResponse,
    ShiftDuplicateRequest,
    EmployeeShiftAssignmentCreate,
    EmployeeShiftAssignmentResponse,
)
from app.dependencies import require_admin
from app.services.shift_service import ShiftService, ShiftServiceException
from app.services.audit_service import log_audit_event

router = APIRouter(prefix="/api/admin/shifts", tags=["Shift Management"], dependencies=[Depends(require_admin)])

def _format_rule_resp(r) -> ShiftRuleResponse:
    p_name = getattr(r, "period_name", None) or getattr(r, "rule_name", "Punch Period")
    p_no = getattr(r, "punch_no", getattr(r, "verification_no", 1))
    return ShiftRuleResponse(
        id=r.id,
        shift_id=r.shift_id,
        rule_code=getattr(r, "rule_code", f"PUNCH_{p_no}"),
        rule_name=p_name,
        period_name=p_name,
        punch_no=p_no,
        verification_no=p_no,
        start_time=r.start_time.strftime("%H:%M:%S"),
        end_time=r.end_time.strftime("%H:%M:%S"),
        result_code=getattr(r, "result_code", "PRESENT"),
        result_classification=getattr(r, "result_classification", "PRESENT"),
        show_in_user_schedule=getattr(r, "show_in_user_schedule", True),
        require_face_verification=getattr(r, "require_face_verification", True),
        priority=getattr(r, "priority", 1),
        is_active=r.is_active,
        created_at=r.created_at,
        updated_at=getattr(r, "updated_at", None)
    )

@router.get("", response_model=List[ShiftResponse])
def list_all_shifts(db: Session = Depends(get_db)):
    """List all shifts with their active rules / punch periods."""
    shifts = db.query(Shift).order_by(Shift.id.asc()).all()
    res = []
    for s in shifts:
        child_items = s.punch_periods if s.punch_periods else s.rules
        rules_resp = [_format_rule_resp(r) for r in child_items]
        res.append(
            ShiftResponse(
                id=s.id,
                shift_code=s.shift_code,
                shift_name=s.shift_name,
                description=s.description,
                is_active=s.is_active,
                punch_periods=rules_resp,
                rules=rules_resp,
                created_at=s.created_at,
                updated_at=s.updated_at
            )
        )
    return res

@router.post("", response_model=ShiftResponse, status_code=status.HTTP_201_CREATED)
def create_shift(
    shift_in: ShiftCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Create a new shift with configured non-overlapping punch periods.
    Validates second-level precision and window intervals.
    """
    # 1. Check unique shift code
    existing = db.query(Shift).filter(Shift.shift_code == shift_in.shift_code.strip().upper()).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Shift code '{shift_in.shift_code}' already exists. Please choose a unique code (e.g. S001..S030)."
        )

    incoming_periods = shift_in.punch_periods if shift_in.punch_periods is not None else (shift_in.rules or [])

    # 2. Strict non-overlapping rule validation
    is_valid, err_msg = ShiftService.validate_rules_non_overlapping(incoming_periods)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=err_msg
        )

    # 3. Create shift record
    new_shift = Shift(
        shift_code=shift_in.shift_code.strip().upper(),
        shift_name=shift_in.shift_name.strip(),
        description=shift_in.description,
        is_active=shift_in.is_active
    )
    db.add(new_shift)
    db.flush()

    # 4. Add child punch periods & rules
    for idx, r_in in enumerate(incoming_periods, start=1):
        st = ShiftService.parse_time_str(r_in.start_time)
        et = ShiftService.parse_time_str(r_in.end_time)
        p_name = r_in.period_name or r_in.rule_name or f"Punch #{idx}"
        p_no = r_in.punch_no or r_in.verification_no or idx
        r_code = r_in.rule_code or f"PUNCH_{p_no}"

        period = ShiftPunchPeriod(
            shift_id=new_shift.id,
            punch_no=p_no,
            period_name=p_name.strip(),
            start_time=st,
            end_time=et,
            show_in_user_schedule=r_in.show_in_user_schedule,
            is_active=r_in.is_active,
            priority=r_in.priority if r_in.priority is not None else idx,
            require_face_verification=r_in.require_face_verification
        )
        db.add(period)

        rule = ShiftRule(
            shift_id=new_shift.id,
            rule_code=r_code.strip().upper(),
            rule_name=p_name.strip(),
            verification_no=p_no,
            start_time=st,
            end_time=et,
            result_code=r_in.result_code.strip().upper() if r_in.result_code else "PRESENT",
            result_classification="PRESENT",
            show_in_user_schedule=r_in.show_in_user_schedule,
            priority=r_in.priority if r_in.priority is not None else idx,
            is_active=r_in.is_active
        )
        db.add(rule)

    db.commit()
    db.refresh(new_shift)

    log_audit_event(
        db=db,
        action="SHIFT_CREATED",
        actor_user_id=admin.id,
        target_user_id=None,
        details={"shift_code": new_shift.shift_code, "shift_name": new_shift.shift_name, "periods_count": len(incoming_periods)}
    )

    child_items = new_shift.punch_periods if new_shift.punch_periods else new_shift.rules
    rules_resp = [_format_rule_resp(r) for r in child_items]

    return ShiftResponse(
        id=new_shift.id,
        shift_code=new_shift.shift_code,
        shift_name=new_shift.shift_name,
        description=new_shift.description,
        is_active=new_shift.is_active,
        punch_periods=rules_resp,
        rules=rules_resp,
        created_at=new_shift.created_at,
        updated_at=new_shift.updated_at
    )

@router.get("/{shift_id}", response_model=ShiftResponse)
def get_shift_details(shift_id: int, db: Session = Depends(get_db)):
    """Retrieve details and punch periods of a single shift."""
    shift = db.query(Shift).filter(Shift.id == shift_id).first()
    if not shift:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shift not found")

    child_items = shift.punch_periods if shift.punch_periods else shift.rules
    rules_resp = [_format_rule_resp(r) for r in child_items]

    return ShiftResponse(
        id=shift.id,
        shift_code=shift.shift_code,
        shift_name=shift.shift_name,
        description=shift.description,
        is_active=shift.is_active,
        punch_periods=rules_resp,
        rules=rules_resp,
        created_at=shift.created_at,
        updated_at=shift.updated_at
    )

@router.put("/{shift_id}", response_model=ShiftResponse)
def update_shift(
    shift_id: int,
    shift_in: ShiftUpdate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Update shift metadata and replace rules with non-overlapping validation."""
    shift = db.query(Shift).filter(Shift.id == shift_id).first()
    if not shift:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shift not found")

    if shift_in.shift_code:
        code_check = db.query(Shift).filter(Shift.shift_code == shift_in.shift_code.strip().upper(), Shift.id != shift_id).first()
        if code_check:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Shift code '{shift_in.shift_code}' is already taken.")
        shift.shift_code = shift_in.shift_code.strip().upper()

    if shift_in.shift_name:
        shift.shift_name = shift_in.shift_name.strip()
    if shift_in.description is not None:
        shift.description = shift_in.description
    if shift_in.is_active is not None:
        shift.is_active = shift_in.is_active

    incoming_periods = shift_in.punch_periods if shift_in.punch_periods is not None else shift_in.rules
    if incoming_periods is not None:
        is_valid, err_msg = ShiftService.validate_rules_non_overlapping(incoming_periods)
        if not is_valid:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=err_msg)

        # Remove existing child periods & rules, replace with updated set
        db.query(ShiftPunchPeriod).filter(ShiftPunchPeriod.shift_id == shift_id).delete()
        db.query(ShiftRule).filter(ShiftRule.shift_id == shift_id).delete()

        for idx, r_in in enumerate(incoming_periods, start=1):
            st = ShiftService.parse_time_str(r_in.start_time)
            et = ShiftService.parse_time_str(r_in.end_time)
            p_name = r_in.period_name or r_in.rule_name or f"Punch #{idx}"
            p_no = r_in.punch_no or r_in.verification_no or idx
            r_code = r_in.rule_code or f"PUNCH_{p_no}"

            period = ShiftPunchPeriod(
                shift_id=shift.id,
                punch_no=p_no,
                period_name=p_name.strip(),
                start_time=st,
                end_time=et,
                show_in_user_schedule=r_in.show_in_user_schedule,
                is_active=r_in.is_active,
                priority=r_in.priority if r_in.priority is not None else idx,
                require_face_verification=r_in.require_face_verification
            )
            db.add(period)

            rule = ShiftRule(
                shift_id=shift.id,
                rule_code=r_code.strip().upper(),
                rule_name=p_name.strip(),
                verification_no=p_no,
                start_time=st,
                end_time=et,
                result_code=r_in.result_code.strip().upper() if r_in.result_code else "PRESENT",
                result_classification="PRESENT",
                show_in_user_schedule=r_in.show_in_user_schedule,
                priority=r_in.priority if r_in.priority is not None else idx,
                is_active=r_in.is_active
            )
            db.add(rule)

    shift.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
    db.commit()
    db.refresh(shift)

    log_audit_event(
        db=db,
        action="SHIFT_UPDATED",
        actor_user_id=admin.id,
        target_user_id=None,
        details={"shift_id": shift.id, "shift_code": shift.shift_code}
    )

    child_items = shift.punch_periods if shift.punch_periods else shift.rules
    rules_resp = [_format_rule_resp(r) for r in child_items]

    return ShiftResponse(
        id=shift.id,
        shift_code=shift.shift_code,
        shift_name=shift.shift_name,
        description=shift.description,
        is_active=shift.is_active,
        punch_periods=rules_resp,
        rules=rules_resp,
        created_at=shift.created_at,
        updated_at=shift.updated_at
    )

@router.delete("/{shift_id}")
def delete_shift(
    shift_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Safely delete or soft-deactivate shift if linked to historical records."""
    success, msg = ShiftService.safe_delete_or_deactivate_shift(db, shift_id)
    if not success:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=msg)

    log_audit_event(
        db=db,
        action="SHIFT_DELETED_OR_DEACTIVATED",
        actor_user_id=admin.id,
        target_user_id=None,
        details={"shift_id": shift_id, "message": msg}
    )

    return {"message": msg, "success": True}

@router.post("/{shift_id}/duplicate", response_model=ShiftResponse)
def duplicate_shift(
    shift_id: int,
    dup_req: ShiftDuplicateRequest,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Clone an existing shift with all its rules under a new code and name."""
    try:
        new_shift = ShiftService.duplicate_shift(
            db=db,
            source_shift_id=shift_id,
            new_code=dup_req.new_shift_code,
            new_name=dup_req.new_shift_name
        )
    except ShiftServiceException as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))

    log_audit_event(
        db=db,
        action="SHIFT_DUPLICATED",
        actor_user_id=admin.id,
        target_user_id=None,
        details={"source_shift_id": shift_id, "new_shift_id": new_shift.id, "new_shift_code": new_shift.shift_code}
    )

    rules_resp = [
        ShiftRuleResponse(
            id=r.id,
            shift_id=r.shift_id,
            rule_code=r.rule_code,
            rule_name=r.rule_name,
            start_time=r.start_time.strftime("%H:%M:%S"),
            end_time=r.end_time.strftime("%H:%M:%S"),
            result_code=r.result_code,
            priority=r.priority,
            is_active=r.is_active,
            created_at=r.created_at
        ) for r in new_shift.rules
    ]

    return ShiftResponse(
        id=new_shift.id,
        shift_code=new_shift.shift_code,
        shift_name=new_shift.shift_name,
        description=new_shift.description,
        is_active=new_shift.is_active,
        rules=rules_resp,
        created_at=new_shift.created_at,
        updated_at=new_shift.updated_at
    )

@router.post("/assign", response_model=EmployeeShiftAssignmentResponse)
def assign_shift_to_employee(
    assign_in: EmployeeShiftAssignmentCreate,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """
    Assign a shift to an employee with effective date range.
    Maintains historical shift assignments for auditing.
    """
    usr = db.query(User).filter(User.id == assign_in.user_id).first()
    if not usr:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Employee not found")

    shf = db.query(Shift).filter(Shift.id == assign_in.shift_id).first()
    if not shf:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Shift not found")

    if assign_in.effective_to and assign_in.effective_to < assign_in.effective_from:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="effective_to cannot be earlier than effective_from")

    # If new assignment starts today, mark previous overlapping ongoing assignments
    ongoing = db.query(EmployeeShiftAssignment).filter(
        EmployeeShiftAssignment.user_id == assign_in.user_id,
        EmployeeShiftAssignment.is_active == True,
        EmployeeShiftAssignment.effective_to.is_(None),
        EmployeeShiftAssignment.effective_from < assign_in.effective_from
    ).all()
    for o in ongoing:
        # Cap end date to yesterday of new assignment
        o.effective_to = assign_in.effective_from

    assignment = EmployeeShiftAssignment(
        user_id=assign_in.user_id,
        shift_id=assign_in.shift_id,
        effective_from=assign_in.effective_from,
        effective_to=assign_in.effective_to,
        is_active=True
    )
    db.add(assignment)
    db.commit()
    db.refresh(assignment)

    log_audit_event(
        db=db,
        action="EMPLOYEE_SHIFT_ASSIGNED",
        actor_user_id=admin.id,
        target_user_id=usr.id,
        details={
            "shift_id": shf.id,
            "shift_code": shf.shift_code,
            "effective_from": str(assign_in.effective_from),
            "effective_to": str(assign_in.effective_to) if assign_in.effective_to else None
        }
    )

    return EmployeeShiftAssignmentResponse(
        id=assignment.id,
        user_id=assignment.user_id,
        shift_id=assignment.shift_id,
        shift_code=shf.shift_code,
        shift_name=shf.shift_name,
        effective_from=assignment.effective_from,
        effective_to=assignment.effective_to,
        is_active=assignment.is_active,
        created_at=assignment.created_at
    )

@router.get("/users/{user_id}/shift-history", response_model=List[EmployeeShiftAssignmentResponse])
def get_user_shift_history(user_id: int, db: Session = Depends(get_db)):
    """Retrieve all past and present shift assignments for an employee."""
    assignments = db.query(EmployeeShiftAssignment).filter(
        EmployeeShiftAssignment.user_id == user_id
    ).order_by(EmployeeShiftAssignment.effective_from.desc()).all()

    res = []
    for a in assignments:
        res.append(
            EmployeeShiftAssignmentResponse(
                id=a.id,
                user_id=a.user_id,
                shift_id=a.shift_id,
                shift_code=a.shift.shift_code if a.shift else None,
                shift_name=a.shift.shift_name if a.shift else None,
                effective_from=a.effective_from,
                effective_to=a.effective_to,
                is_active=a.is_active,
                created_at=a.created_at
            )
        )
    return res

@router.delete("/assignments/{assignment_id}")
def delete_shift_assignment(
    assignment_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin)
):
    """Remove / delete an employee shift assignment."""
    assignment = db.query(EmployeeShiftAssignment).filter(
        EmployeeShiftAssignment.id == assignment_id
    ).first()

    if not assignment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Shift assignment #{assignment_id} not found"
        )

    user_id = assignment.user_id
    shift_id = assignment.shift_id

    log_audit_event(
        db=db,
        action="EMPLOYEE_SHIFT_ASSIGNMENT_REMOVED",
        actor_user_id=admin.id,
        target_user_id=user_id,
        details={
            "assignment_id": assignment_id,
            "shift_id": shift_id
        }
    )

    db.delete(assignment)
    db.commit()

    return {"success": True, "message": "Shift assignment removed successfully"}

