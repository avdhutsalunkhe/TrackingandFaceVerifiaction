from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any
from jose import jwt, JWTError
from fastapi import HTTPException, status
from app.config import settings

def create_access_token(data: Dict[str, Any], expires_delta: Optional[timedelta] = None) -> str:
    """Generate a signed JWT access token."""
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire, "iat": now})
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> Dict[str, Any]:
    """Decode and validate a JWT access token."""
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token is missing or empty",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Strip any accidental Bearer prefixes, whitespace, or surrounding quotes from client storage
    clean_token = token.strip()
    while clean_token.lower().startswith("bearer "):
        clean_token = clean_token[7:].strip()
    clean_token = clean_token.strip('"').strip("'")

    try:
        # Include leeway to accommodate client/server clock skew
        payload = jwt.decode(
            clean_token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"verify_exp": True, "verify_iat": False, "leeway": 3600}
        )
        return payload
    except jwt.ExpiredSignatureError as e:
        print(f"[Auth Error] JWT signature expired: {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except JWTError as e:
        print(f"[Auth Error] JWT validation failed ({type(e).__name__}): {e}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Could not validate credentials: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

def create_refresh_token(data: Dict[str, Any], expires_delta: Optional[timedelta] = None) -> str:
    """Generate a signed JWT refresh token with extended validity."""
    to_encode = data.copy()
    now = datetime.now(timezone.utc)
    if expires_delta:
        expire = now + expires_delta
    else:
        expire = now + timedelta(days=getattr(settings, "REFRESH_TOKEN_EXPIRE_DAYS", 30))
    to_encode.update({
        "exp": expire,
        "iat": now,
        "token_type": "refresh"
    })
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt

def decode_refresh_token(token: str) -> Dict[str, Any]:
    """Decode and validate a JWT refresh token."""
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token is missing or empty",
            headers={"WWW-Authenticate": "Bearer"},
        )
    clean_token = token.strip()
    while clean_token.lower().startswith("bearer "):
        clean_token = clean_token[7:].strip()
    clean_token = clean_token.strip('"').strip("'")

    try:
        payload = jwt.decode(
            clean_token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
            options={"verify_exp": True, "verify_iat": False, "leeway": 60}
        )
        if payload.get("token_type") != "refresh":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token type: expected refresh token",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Refresh token expired. Please log in again.",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Could not validate refresh token: {str(e)}",
            headers={"WWW-Authenticate": "Bearer"},
        )

