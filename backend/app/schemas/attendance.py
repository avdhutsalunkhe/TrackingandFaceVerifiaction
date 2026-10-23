from datetime import datetime, date
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, ConfigDict
from app.models.attendance import AttendanceStatus, AttemptStatus, RejectionReason

class VerificationWindowItem(BaseModel):
    id: Optional[int] = None
    verification_no: int
    rule_name: Optional[str] = None
    rule_code: Optional[str] = None
    name: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    start: str
    end: str
    label: Optional[str] = None
    status: str # COMPLETED, AVAILABLE, UPCOMING, MISSED, PENDING_SYNC
    punch_time: Optional[str] = None
    verified_at: Optional[str] = None
    show_in_user_schedule: bool = True

class NextVerificationItem(BaseModel):
    id: Optional[int] = None
    verification_no: int
    name: Optional[str] = None
    rule_name: Optional[str] = None
    start: str
    end: str
    label: Optional[str] = None

class AttendanceConfigResponse(BaseModel):
    user_id: int
    employee_id: str
    full_name: str
    has_face_enrolled: bool
    geofence: Optional[Dict[str, Any]] = None
    attendance_window: Optional[Dict[str, Any]] = None
    shift: Optional[Dict[str, Any]] = None
    assigned_shift: Optional[Dict[str, Any]] = None
    server_time: Optional[Any] = None
    today_status: Optional[str] = None
    
    # Dynamic Multi-Shift + Multi-Punch-Period Structure
    has_active_shift: bool = True
    current_verification: Optional[int] = None
    verification_status: str = "CLOSED"
    verification_rules: List[VerificationWindowItem] = []
    verification_windows: List[VerificationWindowItem] = []
    punch_periods: List[Dict[str, Any]] = []
    next_verification: Optional[NextVerificationItem] = None
    attendance_action: Optional[Dict[str, Any]] = None
    today_attendance: List[Dict[str, Any]] = []

    # Effective Feature Toggles
    face_enabled: bool = True
    geofence_enabled: bool = True
    shift_enabled: bool = True
    travel_map_enabled: bool = True
    device_binding_enabled: bool = True
    device_id: Optional[str] = None
    is_device_registered: bool = False

class TodayScheduleResponse(BaseModel):
    has_active_shift: bool
    shift: Optional[Dict[str, Any]] = None
    server_time: str
    punch_periods: List[Dict[str, Any]] = []
    attendance_action: Dict[str, Any]

class AttendanceVerifyResponse(BaseModel):
    success: bool
    decision: str # "PRESENT" or "REJECTED"
    rejection_reason: Optional[Any] = None
    message: str
    
    # Punch Period / Verification Window Telemetry
    punch_period_id: Optional[int] = None
    punch_no: Optional[int] = None
    verification_no: Optional[int] = None
    verification_window: Optional[str] = None
    verification_status: Optional[str] = "CONFIRMED"
    client_punch_id: Optional[str] = None

    # Shift & Classification telemetry
    shift_id: Optional[int] = None
    shift_name: Optional[str] = None
    attendance_classification: Optional[str] = None
    
    # Telemetry details
    calculated_distance_meters: Optional[float] = None
    allowed_radius_meters: Optional[float] = None
    face_similarity_score: Optional[float] = None
    liveness_result: Optional[str] = None
    liveness_score: Optional[float] = None
    
    timestamp: datetime = Field(default_factory=datetime.utcnow)

class AttendanceRecordResponse(BaseModel):
    id: int
    user_id: int
    employee_id: Optional[str] = None
    full_name: Optional[str] = None
    verification_no: Optional[int] = 1
    verification_window: Optional[str] = None
    source: Optional[str] = "ONLINE"
    verification_status: Optional[str] = "CONFIRMED"
    client_punch_id: Optional[str] = None
    sync_status: Optional[str] = "SYNCED"
    sync_notes: Optional[str] = None
    shift_id: Optional[int] = None
    shift_code: Optional[str] = None
    shift_name: Optional[str] = None
    attendance_classification: Optional[str] = None
    attendance_date: date
    timestamp: datetime
    formatted_date: Optional[str] = None
    formatted_time: Optional[str] = None
    status: AttendanceStatus
    verified_latitude: float
    verified_longitude: float
    verified_distance_meters: float
    face_similarity_score: float
    liveness_score: float
    verification_mode: Optional[str] = "FACE"
    location_name: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)

# Offline Sync Schemas
class OfflineSyncItem(BaseModel):
    client_punch_id: str
    user_id: Optional[int] = None
    attendance_date: str # YYYY-MM-DD
    punch_period_id: Optional[int] = None
    punch_no: Optional[int] = None
    verification_no: Optional[int] = 1
    estimated_server_time: str # ISO string or YYYY-MM-DD HH:MM:SS
    device_wall_time: Optional[str] = None
    last_server_sync_time: str # ISO string
    server_time_offset: Optional[float] = None
    latitude: float
    longitude: float
    gps_accuracy: Optional[float] = None
    face_similarity_score: Optional[float] = 1.0
    liveness_score: Optional[float] = 1.0
    device_id: Optional[str] = None
    image_base64: Optional[str] = None

class OfflineSyncBatchRequest(BaseModel):
    items: List[OfflineSyncItem]

class OfflineSyncItemResult(BaseModel):
    client_punch_id: str
    punch_period_id: Optional[int] = None
    verification_no: int
    status: str # CONFIRMED, REVIEW_REQUIRED, REJECTED, DUPLICATE
    message: str
    attendance_id: Optional[int] = None

class OfflineSyncBatchResponse(BaseModel):
    results: List[OfflineSyncItemResult]
    total_processed: int
    confirmed_count: int
    rejected_count: int

class AttendanceAttemptResponse(BaseModel):
    id: int
    user_id: int
    employee_id: Optional[str] = None
    full_name: Optional[str] = None
    timestamp: datetime
    attempt_status: AttemptStatus
    rejection_reason: Optional[RejectionReason] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    calculated_distance_meters: Optional[float] = None
    face_similarity_score: Optional[float] = None
    liveness_result: Optional[str] = None
    details: Optional[Dict[str, Any]] = None

    model_config = ConfigDict(from_attributes=True)

class FaceEnrollmentSampleResponse(BaseModel):
    sample_index: int
    total_required: int = 3
    is_valid: bool
    quality_score: float
    message: str
