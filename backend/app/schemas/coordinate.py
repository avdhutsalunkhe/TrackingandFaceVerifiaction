from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict, Field

class CoordinatePoint(BaseModel):
    """
    Standard coordinate point model representing complete, unrounded GPS coordinates.
    Never truncates or reduces captured decimal precision.
    """
    latitude: float = Field(..., description="Full captured latitude decimal value", ge=-90.0, le=90.0)
    longitude: float = Field(..., description="Full captured longitude decimal value", ge=-180.0, le=180.0)
    accuracy: Optional[float] = Field(None, description="GPS accuracy radius in meters")
    altitude: Optional[float] = Field(None, description="GPS altitude in meters")
    speed: Optional[float] = Field(None, description="GPS speed in m/s")
    timestamp: Optional[datetime] = Field(None, description="Capture timestamp")

    model_config = ConfigDict(from_attributes=True)

    def to_coordinates_tuple(self) -> tuple[float, float]:
        """Returns (latitude, longitude) as full precision float tuple."""
        return (self.latitude, self.longitude)

    def __str__(self) -> str:
        return f"{self.latitude}, {self.longitude}"
