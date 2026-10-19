from typing import Optional
from pydantic import BaseModel, Field

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int = Field(default=28800, description="Token validity duration in seconds (default: 8 hours)")
    expires_at: Optional[int] = Field(None, description="Expiration UTC timestamp in seconds")
    user_id: Optional[int] = None
    role: str
    employee_id: str
    full_name: str
    must_change_password: bool
    
    # Feature Flags
    face_enabled: bool = True
    geofence_enabled: bool = True
    shift_enabled: bool = True
    travel_map_enabled: bool = True
    device_binding_enabled: bool = True
    
    # Device Registration Status
    device_id: Optional[str] = None
    is_device_registered: bool = False

class LoginRequest(BaseModel):
    employee_id: str = Field(..., min_length=1, max_length=64, description="Employee ID or Admin ID")
    password: str = Field(..., min_length=1, max_length=128)
    client_type: Optional[str] = Field(None, description="Client platform: 'WEB' (Browser/PC) or 'MOBILE' (Phone app)")
    device_id: Optional[str] = Field(None, description="Client Device Hardware Identifier / Installation UUID")

class ChangePasswordRequest(BaseModel):
    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=6, max_length=128, description="Minimum 6 characters")

class TokenData(BaseModel):
    user_id: int
    employee_id: str
    role: str
