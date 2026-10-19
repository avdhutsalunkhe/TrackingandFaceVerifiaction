from datetime import datetime, time, date
from typing import List, Optional, Tuple, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import and_, or_
from app.models.shift import Shift, ShiftRule, EmployeeShiftAssignment
from app.schemas.shift import ShiftRuleCreate, ShiftCreate

class ShiftServiceException(Exception):
    pass

class ShiftService:
    """
    Generic Shift Rule Engine & Management Service.
    Supports 30+ unlimited configurable shifts without hardcoded logic.
    """

    @staticmethod
    def parse_time_str(time_str: str) -> time:
        """Parse HH:MM:SS or HH:MM string to time object with second-level precision."""
        parts = [int(p) for p in time_str.strip().split(":")]
        if len(parts) == 2:
            return time(parts[0], parts[1], 0)
        elif len(parts) == 3:
            return time(parts[0], parts[1], parts[2])
        raise ValueError(f"Invalid time format: '{time_str}'. Expected HH:MM:SS or HH:MM")

    @classmethod
    def validate_rules_non_overlapping(cls, rules: List[ShiftRuleCreate]) -> Tuple[bool, Optional[str]]:
        """
        Validate that:
        1. start_time < end_time for each rule
        2. No two active rules overlap in their time windows (second-level precision)
        """
        if not rules:
            return True, None

        parsed_intervals = []
        for idx, rule in enumerate(rules):
            try:
                st = cls.parse_time_str(rule.start_time)
                et = cls.parse_time_str(rule.end_time)
            except Exception as e:
                return False, f"Rule '{rule.rule_name}' ({rule.rule_code}) has invalid time format: {e}"

            st_secs = st.hour * 3600 + st.minute * 60 + st.second
            et_secs = et.hour * 3600 + et.minute * 60 + et.second

            if st_secs >= et_secs:
                return False, (
                    f"Rule '{rule.rule_name}' ({rule.rule_code}): "
                    f"Start time ({rule.start_time}) must be strictly earlier than End time ({rule.end_time})."
                )

            if rule.is_active:
                parsed_intervals.append({
                    "index": idx + 1,
                    "rule_code": rule.rule_code,
                    "rule_name": rule.rule_name,
                    "start_secs": st_secs,
                    "end_secs": et_secs,
                    "start_str": rule.start_time,
                    "end_str": rule.end_time,
                })

        # Check all pairs for overlap
        n = len(parsed_intervals)
        for i in range(n):
            for j in range(i + 1, n):
                r1 = parsed_intervals[i]
                r2 = parsed_intervals[j]

                # Two half-open intervals [A_start, A_end) and [B_start, B_end) overlap if:
                # max(A_start, B_start) < min(A_end, B_end)
                overlap_start = max(r1["start_secs"], r2["start_secs"])
                overlap_end = min(r1["end_secs"], r2["end_secs"])

                if overlap_start < overlap_end:
                    ov_st_str = f"{overlap_start // 3600:02d}:{(overlap_start % 3600) // 60:02d}:{overlap_start % 60:02d}"
                    ov_et_str = f"{overlap_end // 3600:02d}:{(overlap_end % 3600) // 60:02d}:{overlap_end % 60:02d}"
                    return False, (
                        f"Time window conflict detected!\n"
                        f"Punch Period '{r1['rule_name']}' ({r1['start_str']} - {r1['end_str']}) overlaps with "
                        f"Punch Period '{r2['rule_name']}' ({r2['start_str']} - {r2['end_str']}) "
                        f"from {ov_st_str} to {ov_et_str}."
                    )

        return True, None

    @classmethod
    def evaluate_punch_timestamp(cls, shift: Optional[Shift], punch_time: time) -> Tuple[str, str, Optional[Any]]:
        """
        Dynamic Multi-Period Verification Evaluation Engine:
        Evaluates punch_time against active shift rules in the database.
        Returns:
            (classification: str, status: str, matched_rule: Optional[Any])
        """
        from app.services.time_service import TimeService
        active_window = TimeService.get_active_verification_window(punch_time, shift=shift)

        if active_window:
            classification = active_window.get("result_classification") or active_window.get("rule_code") or "PRESENT"
            matched_rule = None
            if shift and shift.rules:
                for r in shift.rules:
                    if r.is_active and (r.id == active_window.get("id") or r.rule_code == active_window.get("rule_code")):
                        matched_rule = r
                        break
            return classification, "PRESENT", matched_rule

        return "WINDOW_CLOSED", "REJECTED", None

    @staticmethod
    def get_effective_shift_for_user(db: Session, user_id: int, target_date: date) -> Optional[Shift]:
        """
        Resolves the employee's active shift on target_date based on assignment history.
        Handles date ranges: effective_from <= target_date AND (effective_to IS NULL OR effective_to >= target_date).
        If employee has no assignment or shift is inactive, returns None.
        """
        assignment = db.query(EmployeeShiftAssignment).filter(
            EmployeeShiftAssignment.user_id == user_id,
            EmployeeShiftAssignment.is_active == True,
            EmployeeShiftAssignment.effective_from <= target_date,
            or_(
                EmployeeShiftAssignment.effective_to.is_(None),
                EmployeeShiftAssignment.effective_to >= target_date
            )
        ).order_by(EmployeeShiftAssignment.effective_from.desc(), EmployeeShiftAssignment.id.desc()).first()

        if assignment and assignment.shift and assignment.shift.is_active:
            return assignment.shift

        # No active shift assigned to employee
        return None

    @staticmethod
    def duplicate_shift(db: Session, source_shift_id: int, new_code: str, new_name: str) -> Shift:
        """Clones an existing shift along with all its child rules."""
        source = db.query(Shift).filter(Shift.id == source_shift_id).first()
        if not source:
            raise ShiftServiceException(f"Source shift #{source_shift_id} not found")

        # Check unique code
        existing = db.query(Shift).filter(Shift.shift_code == new_code.strip()).first()
        if existing:
            raise ShiftServiceException(f"Shift code '{new_code}' already exists")

        new_shift = Shift(
            shift_code=new_code.strip().upper(),
            shift_name=new_name.strip(),
            description=f"Cloned from {source.shift_code} - {source.shift_name}",
            is_active=True
        )
        db.add(new_shift)
        db.flush() # Populate new_shift.id

        # Clone all punch periods & rules
        child_items = source.punch_periods if source.punch_periods else source.rules
        for p in child_items:
            p_no = getattr(p, "punch_no", getattr(p, "verification_no", 1))
            p_name = getattr(p, "period_name", getattr(p, "rule_name", "Punch Period"))
            period = ShiftPunchPeriod(
                shift_id=new_shift.id,
                punch_no=p_no,
                period_name=p_name,
                start_time=p.start_time,
                end_time=p.end_time,
                show_in_user_schedule=getattr(p, "show_in_user_schedule", True),
                priority=getattr(p, "priority", 1),
                require_face_verification=getattr(p, "require_face_verification", True),
                is_active=p.is_active
            )
            db.add(period)

            rule = ShiftRule(
                shift_id=new_shift.id,
                rule_code=getattr(p, "rule_code", f"PUNCH_{p_no}"),
                rule_name=p_name,
                verification_no=p_no,
                start_time=p.start_time,
                end_time=p.end_time,
                result_code=getattr(p, "result_code", "PRESENT"),
                result_classification="PRESENT",
                show_in_user_schedule=getattr(p, "show_in_user_schedule", True),
                priority=getattr(p, "priority", 1),
                is_active=p.is_active
            )
            db.add(rule)

        db.commit()
        db.refresh(new_shift)
        return new_shift

    @staticmethod
    def safe_delete_or_deactivate_shift(db: Session, shift_id: int) -> Tuple[bool, str]:
        """
        Safely handles shift deletion:
        - If shift is linked to historical attendance records, prevents hard delete and soft deactivates instead.
        - If unlinked, performs hard delete.
        """
        shift = db.query(Shift).filter(Shift.id == shift_id).first()
        if not shift:
            return False, "Shift not found"

        # Check if attendance records reference this shift
        from app.models.attendance import Attendance
        attendance_count = db.query(Attendance).filter(Attendance.shift_id == shift_id).count()

        if attendance_count > 0:
            # Soft deactivate to protect historical audit trail
            shift.is_active = False
            db.commit()
            return True, f"Shift '{shift.shift_code}' is linked to {attendance_count} attendance records and has been safely deactivated instead of deleted to protect historical data."

        # Otherwise safe to delete
        db.delete(shift)
        db.commit()
        return True, f"Shift '{shift.shift_code}' and its rules were deleted successfully."
