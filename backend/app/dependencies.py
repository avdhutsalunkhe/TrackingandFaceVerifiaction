from typing import Optional
from fastapi import Depends, HTTPException, status, Request
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from app.database import get_db
from app.models.user import User, UserRole
from app.security.tokens import decode_access_token

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)

def get_current_user(
    request: Request,
    token: Optional[str] = Depends(oauth2_scheme),
    db: Session = Depends(get_db)
) -> User:
    """Dependency to extract authenticated User from Bearer JWT, Authorization header, or query parameter."""
    auth_token = token
    if not auth_token:
        # Check standard headers if oauth2_scheme didn't match (e.g. without 'Bearer' prefix or lowercase)
        auth_header = request.headers.get("Authorization") or request.headers.get("authorization")
        if auth_header:
            auth_token = auth_header
        else:
            auth_token = (
                request.headers.get("x-access-token")
                or request.headers.get("token")
                or request.query_params.get("token")
            )

    if not auth_token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated - Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_access_token(auth_token)
    user_id = payload.get("sub") or payload.get("user_id")
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Store client_type on request.state for downstream permission checks
    request.state.client_type = (payload.get("client_type") or request.headers.get("x-client-type") or "WEB").upper()
    
    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Employee account is deactivated",
        )
    
    return user

import re

def require_admin(
    request: Request,
    current_user: User = Depends(get_current_user)
) -> User:
    """Dependency to restrict route to ADMIN role.
    When Admin logs in from the mobile application (client_type == 'MOBILE'),
    access is strictly limited to Employee Face Registration endpoints.
    All other administrative operations require the Web / PC portal.
    """
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )
    
    # Check mobile admin restriction
    client_type = getattr(request.state, "client_type", None)
    if not client_type:
        auth_header = request.headers.get("Authorization") or request.headers.get("authorization")
        if auth_header:
            try:
                payload = decode_access_token(auth_header)
                client_type = payload.get("client_type")
            except Exception:
                pass
    if not client_type:
        client_type = request.headers.get("x-client-type")

    if client_type and str(client_type).strip().upper() == "MOBILE":
        path = request.url.path
        method = request.method.upper()
        # Allowed exclusively for Mobile Admin:
        # GET /api/admin/users
        # GET /api/admin/users/{id}
        # POST /api/admin/users/{id}/face
        # GET /api/admin/users/{id}/face/samples
        # DELETE /api/admin/users/{id}/face
        is_allowed = False
        if method == "GET" and re.match(r"^/api/admin/users/?$", path):
            is_allowed = True
        elif method == "GET" and re.match(r"^/api/admin/users/\d+/?$", path):
            is_allowed = True
        elif method in ("GET", "POST", "DELETE") and re.match(r"^/api/admin/users/\d+/face.*", path):
            is_allowed = True

        if not is_allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Mobile admin session is restricted exclusively to employee face registration. Please use the Web / PC portal for full system administration.",
            )

    return current_user

def require_web_admin(
    request: Request,
    current_user: User = Depends(require_admin)
) -> User:
    """Explicit dependency ensuring caller is an admin on Web/PC."""
    return current_user

def require_time_office(
    current_user: User = Depends(get_current_user)
) -> User:
    """Dependency to restrict route to TIME_OFFICE or ADMIN roles."""
    if current_user.role not in (UserRole.TIME_OFFICE, UserRole.ADMIN):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Time Office or Admin privileges required",
        )
    return current_user

def require_active_user(
    current_user: User = Depends(get_current_user)
) -> User:
    """Dependency to ensure active employee."""
    if not current_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is inactive",
        )
    return current_user
