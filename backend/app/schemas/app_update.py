from datetime import datetime
from typing import List, Optional, Any, Dict
from pydantic import BaseModel, Field

class AppUpdateCheckRequest(BaseModel):
    platform: str = "android"
    distribution_channel: str = "direct_apk" # direct_apk, google_play, all
    current_version: str = "1.0.0"
    current_version_code: int = 1
    device_id: Optional[str] = None
    user_id: Optional[int] = None

class AppUpdatePolicyResponse(BaseModel):
    has_update: bool
    platform: str
    distribution_channel: str
    update_type: str # resource_patch, direct_apk, in_app_play
    latest_version: str
    latest_version_code: int
    min_supported_version_code: int
    is_mandatory: bool
    download_url: str
    patch_manifest_url: Optional[str] = None
    file_size_bytes: int
    file_size_mb: float
    sha256_hash: Optional[str] = None
    release_title: str
    release_notes: List[str]
    metadata: Optional[Dict[str, Any]] = None
    server_time: datetime

class CreateUpdatePolicyRequest(BaseModel):
    platform: str = "android"
    distribution_channel: str = "all" # direct_apk, google_play, all
    update_type: str = "direct_apk" # resource_patch, direct_apk, in_app_play
    latest_version: str
    latest_version_code: int
    min_supported_version_code: int = 1
    is_mandatory: bool = False
    download_url: Optional[str] = None
    patch_manifest_url: Optional[str] = None
    file_size_bytes: Optional[int] = None
    sha256_hash: Optional[str] = None
    release_title: Optional[str] = "System Update Available"
    release_notes: List[str] = Field(default_factory=list)
    metadata: Optional[Dict[str, Any]] = None
    published_by: str = "Admin"

class UpdateTelemetryLogRequest(BaseModel):
    device_id: str
    user_id: Optional[int] = None
    current_version: Optional[str] = None
    current_version_code: int
    target_version: Optional[str] = None
    target_version_code: int
    update_type: str = "direct_apk"
    status: str # CHECKED, DOWNLOADING, DOWNLOADED, APPLIED, INSTALLED, FAILED, DISMISSED
    download_duration_ms: Optional[int] = None
    bytes_downloaded: Optional[int] = None
    error_message: Optional[str] = None
