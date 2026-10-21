import time
import threading
from datetime import datetime
from typing import Optional, Dict, Tuple, Any
import numpy as np
from sqlalchemy.orm import Session
from app.config import settings
from app.models.face import FaceTemplate

class FaceCacheService:
    """
    High-Performance Thread-Safe Face Template Embedding Cache.
    Prevents repeated fetching of heavy biometric blobs (face_image + face_embedding)
    across the database wire on every attendance verification request.
    Includes automatic TTL expiration and immediate cache invalidation on re-enrollment.
    """
    _lock = threading.Lock()
    _cache: Dict[int, Dict[str, Any]] = {}

    @classmethod
    def get_user_face_embedding(cls, db: Session, user_id: int) -> Optional[np.ndarray]:
        """
        Retrieves the 512-D float32 normalized face embedding for user_id.
        Uses in-memory cache if enabled, querying only necessary columns (avoiding face_image blob).
        """
        enabled = getattr(settings, "TEMPLATE_CACHE_ENABLED", True)
        ttl = getattr(settings, "TEMPLATE_CACHE_TTL_SECONDS", 3600)
        now = time.monotonic()

        if enabled:
            with cls._lock:
                cached = cls._cache.get(user_id)
                if cached is not None:
                    if (now - cached["cached_at"]) < ttl:
                        return cached["embedding"]
                    else:
                        cls._cache.pop(user_id, None)

        # Database lookup: Select ONLY face_embedding and updated_at
        # Defers/excludes the heavy JPEG face_image column
        row = db.query(FaceTemplate.face_embedding, FaceTemplate.updated_at).filter(
            FaceTemplate.user_id == user_id
        ).first()

        if not row or not row.face_embedding:
            return None

        embedding = np.frombuffer(row.face_embedding, dtype=np.float32)

        if enabled:
            with cls._lock:
                cls._cache[user_id] = {
                    "embedding": embedding,
                    "updated_at": row.updated_at,
                    "cached_at": now
                }

        return embedding

    @classmethod
    def invalidate(cls, user_id: int) -> None:
        """
        Evict a user's cached embedding immediately upon face re-enrollment or profile update.
        """
        with cls._lock:
            cls._cache.pop(user_id, None)

    @classmethod
    def clear(cls) -> None:
        """Clear all cached face templates."""
        with cls._lock:
            cls._cache.clear()

    @classmethod
    def stats(cls) -> Dict[str, Any]:
        """Return cache occupancy stats."""
        with cls._lock:
            return {
                "cached_templates_count": len(cls._cache),
                "enabled": getattr(settings, "TEMPLATE_CACHE_ENABLED", True)
            }
