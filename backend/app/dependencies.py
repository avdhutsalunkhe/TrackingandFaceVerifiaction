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

def require_admin(
    current_user: User = Depends(get_current_user)
) -> User:
    """Dependency to restrict route to ADMIN role."""
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )
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
