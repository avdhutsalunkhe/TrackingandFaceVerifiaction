from datetime import datetime, date
from typing import Optional, List
from pydantic import BaseModel, Field, ConfigDict, field_validator

class ShiftRuleBase(BaseModel):
    rule_code: Optional[str] = None
    rule_name: Optional[str] = None
    period_name: Optional[str] = None
    punch_no: Optional[int] = None
    verification_no: int = Field(default=1, ge=1)
    start_time: str = Field(..., pattern=r"^\d{2}:\d{2}:\d{2}$", description="HH:MM:SS with second-level precision")
    end_time: str = Field(..., pattern=r"^\d{2}:\d{2}:\d{2}$", description="HH:MM:SS with second-level precision")
    result_code: str = Field(default="PRESENT", min_length=1, max_length=64)
    result_classification: Optional[str] = None
    show_in_user_schedule: bool = True
    priority: int = Field(default=1, ge=1)
    require_face_verification: bool = True
    is_active: bool = True

class ShiftRuleCreate(ShiftRuleBase):
    pass

class ShiftRuleResponse(ShiftRuleBase):
    id: int
    shift_id: int
    created_at: datetime
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)

class ShiftPunchPeriodBase(ShiftRuleBase):
    pass

class ShiftPunchPeriodCreate(ShiftPunchPeriodBase):
    pass

class ShiftPunchPeriodResponse(ShiftRuleResponse):
    pass

class ShiftBase(BaseModel):
    shift_code: str = Field(..., min_length=1, max_length=32, description="e.g. S001, S002, S030")
    shift_name: str = Field(..., min_length=1, max_length=128, description="e.g. General Shift, Morning Shift")
    description: Optional[str] = None
    is_active: bool = True

class ShiftCreate(ShiftBase):
    punch_periods: Optional[List[ShiftRuleCreate]] = None
    rules: Optional[List[ShiftRuleCreate]] = None

class ShiftUpdate(BaseModel):
    shift_code: Optional[str] = None
    shift_name: Optional[str] = None
    description: Optional[str] = None
    is_active: Optional[bool] = None
    punch_periods: Optional[List[ShiftRuleCreate]] = None
    rules: Optional[List[ShiftRuleCreate]] = None

class ShiftDuplicateRequest(BaseModel):
    new_shift_code: str = Field(..., min_length=1, max_length=32, description="e.g. S002")
    new_shift_name: str = Field(..., min_length=1, max_length=128, description="e.g. General Shift (Copy)")

class ShiftResponse(ShiftBase):
    id: int
    punch_periods: List[ShiftRuleResponse] = []
    rules: List[ShiftRuleResponse] = []
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class EmployeeShiftAssignmentCreate(BaseModel):
    user_id: int
    shift_id: int
    effective_from: date = Field(default_factory=date.today)
    effective_to: Optional[date] = None

class EmployeeShiftAssignmentResponse(BaseModel):
    id: int
    user_id: int
    shift_id: int
    shift_code: Optional[str] = None
    shift_name: Optional[str] = None
    effective_from: date
    effective_to: Optional[date] = None
    is_active: bool
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
