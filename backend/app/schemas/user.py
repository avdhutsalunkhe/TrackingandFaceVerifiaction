from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel, Field, ConfigDict
from app.models.user import UserRole

class UserBase(BaseModel):
    employee_id: str = Field(..., min_length=1, max_length=64)
    full_name: str = Field(..., min_length=1, max_length=128)
    role: UserRole = UserRole.USER
    is_active: bool = True
    department: Optional[str] = None
    department_id: Optional[int] = None
    unit_number: Optional[int] = None
    designation: Optional[str] = None

class UserCreate(UserBase):
    initial_password: Optional[str] = Field(None, min_length=4, max_length=128, description="If omitted, defaults to employee_id")

class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    role: Optional[UserRole] = None
    is_active: Optional[bool] = None
    must_change_password: Optional[bool] = None
    password: Optional[str] = None
    department: Optional[str] = None
    department_id: Optional[int] = None
    unit_number: Optional[int] = None
    designation: Optional[str] = None

class FaceTemplateSummary(BaseModel):
    is_enrolled: bool
    sample_count: int = 0
    enrolled_at: Optional[datetime] = None

class GeofenceSummary(BaseModel):
    location_name: str
    latitude: float
    longitude: float
    radius_meters: float

class AttendanceWindowSummary(BaseModel):
    start_time: str
    end_time: str
    timezone: str

class UserResponse(BaseModel):
    id: int
    employee_id: str
    full_name: str
    role: UserRole
    is_active: bool
    must_change_password: bool
    department: Optional[str] = None
    department_id: Optional[int] = None
    unit_number: Optional[int] = None
    designation: Optional[str] = None
    has_face_enrolled: bool = False
    geofence: Optional[GeofenceSummary] = None
    attendance_window: Optional[AttendanceWindowSummary] = None
    
    # Feature Toggles
    face_enabled: bool = True
    geofence_enabled: bool = True
    shift_enabled: bool = True
    travel_map_enabled: bool = True
    device_binding_enabled: bool = True
    
    # Device ID Registration
    device_id: Optional[str] = None
    is_device_registered: bool = False
    device_registered_at: Optional[datetime] = None
    device_model: Optional[str] = None

    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class FeatureToggleRequest(BaseModel):
    feature: str = Field(..., description="Feature name: 'face', 'geofence', 'shift', 'travel_map', or 'device_binding'")
    enabled: bool = Field(..., description="New toggle state: True or False")

class EmployeeFeaturesResponse(BaseModel):
    user_id: int
    employee_id: str
    full_name: str
    face_enabled: bool
    geofence_enabled: bool
    shift_enabled: bool
    travel_map_enabled: bool
    device_binding_enabled: bool = True
    device_id: Optional[str] = None
    is_device_registered: bool
    device_registered_at: Optional[datetime] = None
    device_model: Optional[str] = None

class DeviceRegistrationRequest(BaseModel):
    device_id: str = Field(..., min_length=1, max_length=128, description="Client device UUID")
    device_model: Optional[str] = Field(None, max_length=128)

class DeviceRegistrationResponse(BaseModel):
    success: bool
    message: str
    employee_id: str
    full_name: str
    device_id: Optional[str] = None
    is_registered: bool
    registered_at: Optional[datetime] = None
    device_model: Optional[str] = None

class DashboardStatsResponse(BaseModel):
    total_employees: int
    active_employees: int
    today_present: int
    today_failed_attempts: int
    enrolled_faces_count: int
    pending_attendance_requests: int = 0
