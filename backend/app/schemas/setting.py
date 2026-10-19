from typing import Optional
from pydantic import BaseModel, Field

class BiometricSettingsResponse(BaseModel):
    similarity_threshold: float
    liveness_confidence_threshold: float
    min_face_size: int

class BiometricSettingsUpdate(BaseModel):
    similarity_threshold: float = Field(..., ge=0.0, le=1.0, description="Global Cosine Similarity Threshold (0.0 to 1.0)")
    liveness_confidence_threshold: Optional[float] = Field(None, ge=0.0, le=1.0, description="Global Liveness Confidence Threshold")
    min_face_size: Optional[int] = Field(None, ge=20, le=400, description="Minimum face bounding box size in pixels")
