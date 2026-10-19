from datetime import datetime, timezone
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.database import get_db
from app.models.role import RoleMaster
from app.models.user import User, UserRole
from app.schemas.role import (
    RoleMasterCreate,
    RoleMasterUpdate,
    RoleMasterResponse,
    AssignUserRoleRequest,
)
from app.dependencies import require_time_office
from app.services.audit_service import log_audit_event

router = APIRouter(prefix="/api/time-office/roles", tags=["Role Management Master"], dependencies=[Depends(require_time_office)])

@router.get("", response_model=List[RoleMasterResponse])
def list_master_roles(db: Session = Depends(get_db)):
    """List all Master Roles configured in the system along with count of assigned employees/supervisors."""
    roles = db.query(RoleMaster).order_by(RoleMaster.id.asc()).all()
    results = []

    for r in roles:
        # Count assigned users by matching User.role enum string with role_code
        count = db.query(func.count(User.id)).filter(User.role == r.role_code).scalar() or 0
        results.append(
            RoleMasterResponse(
                id=r.id,
                role_code=r.role_code,
                role_name=r.role_name,
                description=r.description,
                is_admin=r.is_admin,
                permissions=r.permissions,
                is_system_role=r.is_system_role,
                is_active=r.is_active,
                assigned_users_count=count,
                created_at=r.created_at,
                updated_at=r.updated_at,
            )
        )
    return results

@router.post("", response_model=RoleMasterResponse, status_code=status.HTTP_201_CREATED)
def create_master_role(
    role_in: RoleMasterCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office),
):
    """Create a new custom Master Role (e.g. Supervisor Zone 1, Shift Admin, Field Manager)."""
    clean_code = role_in.role_code.strip().upper().replace(" ", "_")
    existing = db.query(RoleMaster).filter(RoleMaster.role_code == clean_code).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Role code '{clean_code}' already exists.",
        )

    now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
    new_role = RoleMaster(
        role_code=clean_code,
        role_name=role_in.role_name.strip(),
        description=role_in.description.strip() if role_in.description else None,
        is_admin=role_in.is_admin,
        permissions=role_in.permissions or "attendance,reports",
        is_system_role=False,
        is_active=role_in.is_active,
        created_at=now_utc,
        updated_at=now_utc,
    )
    db.add(new_role)
    db.commit()
    db.refresh(new_role)

    log_audit_event(
        db=db,
        action="ROLE_MASTER_CREATED",
        actor_user_id=current_user.id,
        details={"role_code": new_role.role_code, "role_name": new_role.role_name, "is_admin": new_role.is_admin},
    )

    return RoleMasterResponse(
        id=new_role.id,
        role_code=new_role.role_code,
        role_name=new_role.role_name,
        description=new_role.description,
        is_admin=new_role.is_admin,
        permissions=new_role.permissions,
        is_system_role=new_role.is_system_role,
        is_active=new_role.is_active,
        assigned_users_count=0,
        created_at=new_role.created_at,
        updated_at=new_role.updated_at,
    )

@router.put("/{role_id}", response_model=RoleMasterResponse)
def update_master_role(
    role_id: int,
    role_update: RoleMasterUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office),
):
    """Edit an existing Master Role (update role name, description, is_admin privilege, permissions, or active status)."""
    r = db.query(RoleMaster).filter(RoleMaster.id == role_id).first()
    if not r:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Master Role not found.")

    if role_update.role_name is not None:
        r.role_name = role_update.role_name.strip()
    if role_update.description is not None:
        r.description = role_update.description.strip()
    if role_update.is_admin is not None:
        r.is_admin = role_update.is_admin
    if role_update.permissions is not None:
        r.permissions = role_update.permissions
    if role_update.is_active is not None:
        r.is_active = role_update.is_active

    r.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
    db.commit()
    db.refresh(r)

    count = db.query(func.count(User.id)).filter(User.role == r.role_code).scalar() or 0

    log_audit_event(
        db=db,
        action="ROLE_MASTER_UPDATED",
        actor_user_id=current_user.id,
        details={"role_code": r.role_code, "role_name": r.role_name, "is_admin": r.is_admin},
    )

    return RoleMasterResponse(
        id=r.id,
        role_code=r.role_code,
        role_name=r.role_name,
        description=r.description,
        is_admin=r.is_admin,
        permissions=r.permissions,
        is_system_role=r.is_system_role,
        is_active=r.is_active,
        assigned_users_count=count,
        created_at=r.created_at,
        updated_at=r.updated_at,
    )

@router.delete("/{role_id}")
def delete_master_role(
    role_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office),
):
    """Delete a custom Master Role (system default roles cannot be deleted)."""
    r = db.query(RoleMaster).filter(RoleMaster.id == role_id).first()
    if not r:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Master Role not found.")

    if r.is_system_role:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"System role '{r.role_code}' is built-in and cannot be deleted.",
        )

    # Check assigned users count
    count = db.query(func.count(User.id)).filter(User.role == r.role_code).scalar() or 0
    if count > 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot delete role '{r.role_code}' because it is assigned to {count} user(s). Reassign users first.",
        )

    db.delete(r)
    db.commit()

    log_audit_event(
        db=db,
        action="ROLE_MASTER_DELETED",
        actor_user_id=current_user.id,
        details={"role_code": r.role_code, "role_name": r.role_name},
    )

    return {"message": f"Role '{r.role_name}' deleted successfully."}

@router.post("/assign")
def assign_role_to_user(
    req: AssignUserRoleRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_time_office),
):
    """Assign a Master Role to any user/supervisor."""
    user = db.query(User).filter(User.id == req.user_id).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found.")

    role_master = db.query(RoleMaster).filter(RoleMaster.role_code == req.role_code).first()
    if not role_master:
        # Fallback check for enum UserRole
        if req.role_code not in ["ADMIN", "SUPERVISOR", "TIME_OFFICE", "USER"]:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Role '{req.role_code}' is not registered.")

    old_role = str(user.role)
    user.role = req.role_code
    db.commit()

    log_audit_event(
        db=db,
        action="USER_ROLE_ASSIGNED",
        actor_user_id=current_user.id,
        target_user_id=user.id,
        details={"old_role": old_role, "new_role": req.role_code},
    )

    return {
        "message": f"Successfully assigned role '{req.role_code}' to {user.full_name} ({user.employee_id}).",
        "employee_id": user.employee_id,
        "full_name": user.full_name,
        "new_role": req.role_code,
    }
