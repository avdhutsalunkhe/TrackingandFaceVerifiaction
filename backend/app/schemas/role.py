from datetime import datetime
from typing import Optional, List
from pydantic import BaseModel

class RoleMasterBase(BaseModel):
    role_code: str
    role_name: str
    description: Optional[str] = None
    is_admin: bool = False
    permissions: Optional[str] = "attendance,reports"
    is_active: bool = True

class RoleMasterCreate(RoleMasterBase):
    pass

class RoleMasterUpdate(BaseModel):
    role_name: Optional[str] = None
    description: Optional[str] = None
    is_admin: Optional[bool] = None
    permissions: Optional[str] = None
    is_active: Optional[bool] = None

class RoleMasterResponse(RoleMasterBase):
    id: int
    is_system_role: bool
    assigned_users_count: int = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True

class AssignUserRoleRequest(BaseModel):
    user_id: int
    role_code: str
