from datetime import datetime, date
from typing import Optional, List
from pydantic import BaseModel, Field


class StartTrackingRequest(BaseModel):
    session_uuid: str = Field(..., description="Idempotent client-generated UUID for the tracking session")
    attendance_id: Optional[int] = Field(None, description="Linked attendance punch ID")
    shift_id: Optional[int] = Field(None, description="Linked shift ID")
    start_latitude: Optional[float] = Field(None, description="Initial GPS Latitude")
    start_longitude: Optional[float] = Field(None, description="Initial GPS Longitude")
    start_time: Optional[datetime] = Field(None, description="Session start UTC timestamp")
    start_accuracy_meters: Optional[float] = Field(None, description="Observed horizontal accuracy in meters")
    start_altitude_meters: Optional[float] = Field(None, description="Observed altitude in meters")
    start_speed_mps: Optional[float] = Field(None, description="Observed speed in m/s")
    start_bearing_degrees: Optional[float] = Field(None, description="Observed bearing in degrees")


class StartTrackingResponse(BaseModel):
    success: bool
    message: str
    session_id: int
    session_uuid: str
    status: str


class RoutePointItem(BaseModel):
    client_point_id: str = Field(..., description="Idempotent point UUID")
    sequence_number: int = Field(..., description="Ascending point index")
    latitude: float
    longitude: float
    accuracy_meters: float
    altitude_meters: Optional[float] = None
    speed_mps: Optional[float] = None
    bearing_degrees: Optional[float] = None
    recorded_at: datetime
    is_gap: Optional[bool] = Field(False, description="True if this point begins a discontinuous segment")
    employee_id: Optional[str] = None
    device_id: Optional[str] = None


class SyncRoutePointsRequest(BaseModel):
    session_uuid: str = Field(..., description="Target session UUID")
    points: List[RoutePointItem] = Field(..., description="Batch of recorded GPS route points")
    current_distance_meters: Optional[float] = None
    current_duration_seconds: Optional[int] = None
    device_id: Optional[str] = None


class SyncRoutePointsResponse(BaseModel):
    success: bool
    synced_count: int
    accepted_count: Optional[int] = 0
    duplicate_count: Optional[int] = 0
    rejected_count: Optional[int] = 0
    synced_point_ids: List[str] = Field(default_factory=list, description="Client point IDs successfully persisted or already present")
    rejected_point_ids: List[str] = Field(default_factory=list, description="Client point IDs rejected due to invalid coordinates")
    total_points: int
    message: str


class RouteChunkItem(BaseModel):
    chunk_uuid: str = Field(..., description="Idempotent chunk UUID")
    chunk_sequence: int = Field(..., description="Ascending chunk sequence number")
    point_count: int = Field(..., description="Number of retained vertices in this chunk")
    encoded_geometry: str = Field(..., description="Compact JSON array of retained vertices: [[lat, lng, epochSec, acc, spd, bearing, is_gap], ...]")
    start_time: datetime = Field(..., description="Timestamp of first vertex in chunk")
    end_time: datetime = Field(..., description="Timestamp of last vertex in chunk")
    distance_meters: float = Field(0.0, description="Cumulative distance contribution of this chunk in meters")


class SyncRouteChunksRequest(BaseModel):
    session_uuid: str = Field(..., description="Target session UUID")
    chunks: List[RouteChunkItem] = Field(..., description="Batch of compressed route chunks")
    current_distance_meters: Optional[float] = Field(None, description="Current journey cumulative distance in meters")
    retained_point_count: Optional[int] = Field(None, description="Total count of retained route vertices")
    last_accepted_latitude: Optional[float] = None
    last_accepted_longitude: Optional[float] = None
    last_accepted_time: Optional[datetime] = None


class SyncRouteChunksResponse(BaseModel):
    success: bool
    synced_count: int
    synced_chunk_uuids: List[str] = Field(default_factory=list, description="Chunk UUIDs successfully persisted or already present")
    total_chunks: int
    retained_point_count: int
    total_distance_meters: float
    message: str


class RouteArchiveRequest(BaseModel):
    retention_days: int = Field(90, description="Delete route chunks older than X days while preserving sessions")


class PauseTrackingRequest(BaseModel):
    session_uuid: str = Field(..., description="Session UUID to pause")
    pause_latitude: Optional[float] = None
    pause_longitude: Optional[float] = None
    pause_time: Optional[datetime] = None


class PauseTrackingResponse(BaseModel):
    success: bool
    message: str
    session_id: int
    status: str


class ResumeTrackingRequest(BaseModel):
    session_uuid: str = Field(..., description="Session UUID to resume")
    resume_latitude: Optional[float] = None
    resume_longitude: Optional[float] = None
    resume_time: Optional[datetime] = None


class ResumeTrackingResponse(BaseModel):
    success: bool
    message: str
    session_id: int
    status: str


class StopTrackingRequest(BaseModel):
    session_uuid: str = Field(..., description="Session UUID to conclude")
    end_latitude: Optional[float] = None
    end_longitude: Optional[float] = None
    end_time: Optional[datetime] = None
    total_distance_meters: Optional[float] = None
    total_duration_seconds: Optional[int] = None


class StopTrackingResponse(BaseModel):
    success: bool
    message: str
    session_id: int
    status: str
    total_distance_meters: float
    total_duration_seconds: int


class RoutePointDetail(BaseModel):
    id: int
    sequence_number: int
    latitude: float
    longitude: float
    accuracy_meters: float
    altitude_meters: Optional[float] = None
    speed_mps: Optional[float] = None
    bearing_degrees: Optional[float] = None
    recorded_at: datetime
    is_gap: bool = False
    client_point_id: Optional[str] = None
    employee_id: Optional[str] = None
    device_id: Optional[str] = None

    class Config:
        from_attributes = True


class TrackingSessionSummary(BaseModel):
    id: int
    session_uuid: str
    user_id: int
    employee_id: str
    employee_name: str
    work_date: str
    start_time: datetime
    end_time: Optional[datetime] = None
    status: str
    start_latitude: Optional[float] = None
    start_longitude: Optional[float] = None
    end_latitude: Optional[float] = None
    end_longitude: Optional[float] = None
    total_distance_meters: float
    total_duration_seconds: int
    point_count: int = 0

    class Config:
        from_attributes = True


class TrackingRouteResponse(BaseModel):
    session: TrackingSessionSummary
    points: List[RoutePointDetail]
    total_points: Optional[int] = None
    is_raw: Optional[bool] = None


class RawRoutePointsResponse(BaseModel):
    session: TrackingSessionSummary
    points: List[RoutePointDetail]
    total_points: int
    page: Optional[int] = None
    limit: Optional[int] = None
    total_pages: Optional[int] = None


class PlaybackPointItem(BaseModel):
    id: int
    sequence_number: int
    client_point_id: Optional[str] = None
    latitude: float
    longitude: float
    accuracy_meters: float
    altitude_meters: Optional[float] = None
    speed_mps: Optional[float] = None
    bearing_degrees: Optional[float] = None
    recorded_at: datetime
    is_gap: bool = False


class PlaybackRouteResponse(BaseModel):
    session: TrackingSessionSummary
    points: List[PlaybackPointItem]
    total_points: int


class TrackingStatisticsResponse(BaseModel):
    total_sessions: int
    active_sessions: int
    completed_sessions: int
    total_distance_km: float
    total_duration_hours: float
    total_points: int


class TrackingEventRequest(BaseModel):
    session_uuid: str = Field(..., description="Target session UUID")
    event_type: str = Field(..., description="e.g. SERVICE_STARTED, SERVICE_STOPPED, GPS_DISABLED, RECOVERY_ATTEMPTED")
    details: Optional[str] = None
    battery_optimization_ignored: Optional[bool] = None
    timestamp: Optional[datetime] = None


class TrackingEventResponse(BaseModel):
    success: bool
    message: str

