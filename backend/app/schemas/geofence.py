from typing import Optional, List
from pydantic import BaseModel, Field, ConfigDict

class GeofenceCreate(BaseModel):
    location_name: str = Field(..., min_length=1, max_length=128)
    latitude: float = Field(..., ge=-90.0, le=90.0)
    longitude: float = Field(..., ge=-180.0, le=180.0)
    radius_meters: float = Field(..., gt=0, le=10000.0, description="Allowed radius in meters")
    is_active: bool = True

class GeofenceResponse(BaseModel):
    id: int
    user_id: int
    location_name: str
    latitude: float
    longitude: float
    radius_meters: float
    is_active: bool

    model_config = ConfigDict(from_attributes=True)

class AttendanceWindowCreate(BaseModel):
    start_time: str = Field(..., pattern=r"^\d{2}:\d{2}(:\d{2})?$", description="HH:MM or HH:MM:SS")
    end_time: str = Field(..., pattern=r"^\d{2}:\d{2}(:\d{2})?$", description="HH:MM or HH:MM:SS")
    timezone: str = Field("Asia/Kolkata", min_length=1, max_length=64)
    allowed_days: Optional[List[int]] = Field(default=[1, 2, 3, 4, 5, 6, 7], description="1=Monday ... 7=Sunday")
    is_active: bool = True

class AttendanceWindowResponse(BaseModel):
    id: int
    user_id: int
    start_time: str
    end_time: str
    timezone: str
    allowed_days: Optional[List[int]] = None
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
