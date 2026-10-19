from datetime import datetime, date
from typing import Optional, List
from pydantic import BaseModel, ConfigDict

class ServerTimeResponse(BaseModel):
    server_timestamp: str
    server_date: str
    server_time: str
    formatted_date: str
    formatted_time: str
    timezone: str
    epoch_ms: int

    model_config = ConfigDict(from_attributes=True)

class AttendanceRequestReview(BaseModel):
    admin_notes: Optional[str] = None

class AttendanceRequestResponse(BaseModel):
    id: int
    user_id: int
    employee_id: str
    full_name: str
    request_date: str
    server_timestamp: str
    server_formatted_date: str
    server_formatted_time: str
    device_timestamp: Optional[str] = None
    shift_id: Optional[int] = None
    shift_name: Optional[str] = None
    shift_code: Optional[str] = None
    status: str
    rejection_reason_trigger: Optional[str] = None
    latitude: float
    longitude: float
    gps_accuracy: Optional[float] = None
    location_name: Optional[str] = None
    assigned_location_name: Optional[str] = None
    distance_from_location: float
    is_within_geofence: bool
    has_evidence_image: bool = True
    admin_notes: Optional[str] = None
    reviewed_at: Optional[datetime] = None
    reviewed_by_name: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
