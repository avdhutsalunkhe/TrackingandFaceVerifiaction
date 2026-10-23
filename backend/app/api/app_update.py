import os
import re
import json
import hashlib
from datetime import datetime
from typing import Optional, List, Dict, Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc, func

from app.database import get_db
from app.models.app_update import AppUpdatePolicy, AppUpdateLog
from app.schemas.app_update import (
    AppUpdateCheckRequest,
    AppUpdatePolicyResponse,
    CreateUpdatePolicyRequest,
    UpdateTelemetryLogRequest,
)

router = APIRouter(tags=["App Releases & Updates"])

def _find_release_apk() -> Optional[str]:
    """Locate release APK in the project directory hierarchy."""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    candidates = [
        os.path.join(base_dir, "release_apks", "fieldstaff-attendance-universal-release.apk"),
        os.path.join(base_dir, "release_apks", "fieldstaff-attendance-arm64-v8a-release.apk"),
        os.path.join(base_dir, "..", "release_apks", "fieldstaff-attendance-universal-release.apk"),
        os.path.join(base_dir, "..", "release_apks", "fieldstaff-attendance-arm64-v8a-release.apk"),
        r"D:\Attend\field_staff_attendance_new\release_apks\fieldstaff-attendance-universal-release.apk",
        r"D:\Attend\field_staff_attendance_new\backend\release_apks\fieldstaff-attendance-universal-release.apk",
        os.path.join(base_dir, "mobile", "release_apks", "fieldstaff-attendance-universal-release.apk"),
        os.path.join(base_dir, "mobile", "mobile", "build", "app", "outputs", "flutter-apk", "app-arm64-v8a-release.apk"),
        os.path.join(base_dir, "mobile", "mobile", "build", "app", "outputs", "flutter-apk", "app-release.apk"),
    ]
    for c in candidates:
        if os.path.isfile(c) and os.path.getsize(c) > 0:
            return c
    return None

def _calculate_file_sha256(filepath: str) -> str:
    """Computes SHA-256 hash of a local file in 64KB blocks."""
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            sha256.update(chunk)
    return sha256.hexdigest()

def _get_version_metadata() -> dict:
    """Reads static version metadata fallback if database has not yet been seeded."""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    meta_candidates = [
        os.path.join(base_dir, "release_apks", "version.json"),
        os.path.join(base_dir, "..", "release_apks", "version.json"),
        r"D:\Attend\field_staff_attendance_new\release_apks\version.json",
        r"D:\Attend\field_staff_attendance_new\backend\release_apks\version.json",
        os.path.join(base_dir, "release_apks", "latest_release.json"),
    ]
    for p in meta_candidates:
        if os.path.isfile(p):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
    return {}

def _get_or_create_default_policy(db: Session, channel: str = "direct_apk") -> AppUpdatePolicy:
    """Retrieves active policy from DB or seeds/updates one from local version metadata."""
    meta = _get_version_metadata()
    meta_version_code = meta.get("versionCode", 4)

    policy = (
        db.query(AppUpdatePolicy)
        .filter(
            AppUpdatePolicy.platform == "android",
            AppUpdatePolicy.distribution_channel.in_([channel, "all"]),
            AppUpdatePolicy.is_active == True,
        )
        .order_by(desc(AppUpdatePolicy.latest_version_code))
        .first()
    )

    apk_path = _find_release_apk()
    file_size = meta.get("file_size_bytes") or (os.path.getsize(apk_path) if apk_path and os.path.isfile(apk_path) else 0)
    sha256_hash = meta.get("sha256") or (_calculate_file_sha256(apk_path) if apk_path and os.path.isfile(apk_path) else None)

    if policy:
        if policy.latest_version_code < meta_version_code:
            policy.latest_version = meta.get("version", policy.latest_version)
            policy.latest_version_code = meta_version_code
            policy.min_supported_version_code = meta.get("minimumSupportedVersionCode", policy.min_supported_version_code)
            policy.is_mandatory = meta.get("forceUpdate", policy.is_mandatory)
            if file_size > 0:
                policy.file_size_bytes = file_size
            if sha256_hash:
                policy.sha256_hash = sha256_hash
            if "releaseNotes" in meta:
                policy.release_notes = json.dumps(meta["releaseNotes"])
            policy.updated_at = datetime.utcnow()
            db.commit()
            db.refresh(policy)
        return policy

    # Fallback to local artifacts
    version_str = meta.get("version", "1.0.3")
    version_code = meta.get("versionCode", 4)
    force_update = meta.get("forceUpdate", False)
    min_supported = meta.get("minimumSupportedVersionCode", 1)
    notes = meta.get("releaseNotes", [
        "Automatic shift-based GPS duty journey tracking",
        "Unlimited background coordinate synchronizer",
        "Resumable high-speed OTA patch updates",
        "Offline battery-optimized tracking recovery"
    ])

    new_policy = AppUpdatePolicy(
        platform="android",
        distribution_channel="all",
        update_type="direct_apk",
        latest_version=version_str,
        latest_version_code=version_code,
        min_supported_version_code=min_supported,
        is_mandatory=force_update,
        is_active=True,
        download_url="/api/app/download-apk",
        file_size_bytes=file_size,
        sha256_hash=sha256_hash,
        release_title="FieldStaff Attendance System Update",
        release_notes=json.dumps(notes),
        published_by="System Initializer",
    )
    db.add(new_policy)
    db.commit()
    db.refresh(new_policy)
    return new_policy


# =====================================================================
# CLIENT API: UPDATE CHECK & POLICY RESOLUTION
# =====================================================================

@router.get("/api/app/update-policy", response_model=AppUpdatePolicyResponse)
def get_app_update_policy(
    platform: str = Query("android", description="Target platform (android, ios, etc.)"),
    channel: str = Query("direct_apk", description="Distribution channel (direct_apk, google_play)"),
    version_code: int = Query(1, description="Client current versionCode"),
    version_name: str = Query("1.0.0", description="Client current versionName"),
    device_id: Optional[str] = Query(None, description="Client unique device ID"),
    user_id: Optional[int] = Query(None, description="Optional logged in user ID"),
    db: Session = Depends(get_db),
):
    """
    Evaluates whether an update is available for the requesting client.
    Supports dynamic developer-controlled policies, dual distribution (Play Store vs Direct APK),
    and resource patch vs full APK updates.
    """
    policy = _get_or_create_default_policy(db, channel)

    has_update = policy.latest_version_code > version_code
    is_mandatory = policy.is_mandatory or (version_code < policy.min_supported_version_code)

    # Parse release notes
    notes_list: List[str] = []
    if policy.release_notes:
        try:
            parsed = json.loads(policy.release_notes)
            if isinstance(parsed, list):
                notes_list = [str(x) for x in parsed]
            else:
                notes_list = [str(policy.release_notes)]
        except Exception:
            notes_list = [n.strip() for n in policy.release_notes.split("\n") if n.strip()]

    # Parse metadata if present
    meta_dict: Optional[Dict[str, Any]] = None
    if policy.metadata_json:
        try:
            meta_dict = json.loads(policy.metadata_json)
        except Exception:
            pass

    file_size_mb = round(policy.file_size_bytes / (1024 * 1024), 2) if policy.file_size_bytes > 0 else 0.0

    return AppUpdatePolicyResponse(
        has_update=has_update,
        platform=policy.platform,
        distribution_channel=policy.distribution_channel,
        update_type=policy.update_type,
        latest_version=policy.latest_version,
        latest_version_code=policy.latest_version_code,
        min_supported_version_code=policy.min_supported_version_code,
        is_mandatory=is_mandatory,
        download_url=policy.download_url,
        patch_manifest_url=policy.patch_manifest_url,
        file_size_bytes=policy.file_size_bytes,
        file_size_mb=file_size_mb,
        sha256_hash=policy.sha256_hash,
        release_title=policy.release_title or "System Update Available",
        release_notes=notes_list,
        metadata=meta_dict,
        server_time=datetime.utcnow(),
    )


@router.get("/api/app/latest-release")
@router.get("/releases/latest_release.json")
def get_latest_release(
    channel: str = Query("direct_apk", description="Distribution channel (direct_apk or google_play)"),
    db: Session = Depends(get_db),
):
    """
    Backward-compatible endpoint for existing mobile clients.
    Backed dynamically by the active AppUpdatePolicy.
    """
    policy = _get_or_create_default_policy(db, channel)
    file_size_mb = round(policy.file_size_bytes / (1024 * 1024), 2) if policy.file_size_bytes > 0 else 0.0

    notes_list: List[str] = []
    if policy.release_notes:
        try:
            parsed = json.loads(policy.release_notes)
            notes_list = parsed if isinstance(parsed, list) else [str(policy.release_notes)]
        except Exception:
            notes_list = [n.strip() for n in policy.release_notes.split("\n") if n.strip()]

    return {
        "version": policy.latest_version,
        "versionCode": policy.latest_version_code,
        "apkUrl": policy.download_url,
        "apkAvailable": policy.file_size_bytes > 0 or _find_release_apk() is not None,
        "fileSizeMb": file_size_mb,
        "fileSizeBytes": policy.file_size_bytes,
        "sha256": policy.sha256_hash,
        "forceUpdate": policy.is_mandatory,
        "minimumSupportedVersionCode": policy.min_supported_version_code,
        "updateType": policy.update_type,
        "releaseTitle": policy.release_title,
        "releaseNotes": notes_list,
        "patchManifestUrl": policy.patch_manifest_url,
    }


# =====================================================================
# HIGH-PERFORMANCE RESUMABLE APK & PATCH STREAMING (HTTP 206 PARTIAL)
# =====================================================================

def _stream_file_range(filepath: str, start: int, end: int, chunk_size: int = 65536):
    """Yields byte chunks from start offset to end offset for HTTP Range requests."""
    with open(filepath, "rb") as f:
        f.seek(start)
        remaining = (end - start) + 1
        while remaining > 0:
            read_size = min(chunk_size, remaining)
            data = f.read(read_size)
            if not data:
                break
            remaining -= len(data)
            yield data

@router.get("/api/app/download-apk")
@router.get("/releases/app-release.apk")
def download_latest_apk(request: Request, db: Session = Depends(get_db)):
    """
    Streams the latest Android APK with full HTTP Range request support (HTTP 206 Partial Content).
    Enables reliable, resumable downloads when mobile network connections drop.
    """
    apk_path = _find_release_apk()
    if not apk_path or not os.path.isfile(apk_path):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Release APK not found on server. Please build release APK first.",
        )

    file_size = os.path.getsize(apk_path)
    sha256_hash = _calculate_file_sha256(apk_path)
    range_header = request.headers.get("Range") or request.headers.get("range")

    headers = {
        "Accept-Ranges": "bytes",
        "ETag": f'"{sha256_hash}"',
        "X-Checksum-SHA256": sha256_hash,
        "Content-Disposition": 'attachment; filename="fieldstaff-attendance-release.apk"',
    }

    if range_header:
        # Example: Range: bytes=1048576- or bytes=1048576-2097151
        range_match = re.match(r"^bytes=(\d+)-(\d*)$", range_header.strip())
        if range_match:
            start = int(range_match.group(1))
            end_str = range_match.group(2)
            end = int(end_str) if end_str else file_size - 1

            if start >= file_size or end >= file_size or start > end:
                raise HTTPException(
                    status_code=status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE,
                    headers={"Content-Range": f"bytes */{file_size}"},
                    detail="Requested Range Not Satisfiable",
                )

            content_length = (end - start) + 1
            headers["Content-Range"] = f"bytes {start}-{end}/{file_size}"
            headers["Content-Length"] = str(content_length)

            return StreamingResponse(
                _stream_file_range(apk_path, start, end),
                status_code=status.HTTP_206_PARTIAL_CONTENT,
                media_type="application/vnd.android.package-archive",
                headers=headers,
            )

    # Standard full file download (HTTP 200)
    headers["Content-Length"] = str(file_size)
    return StreamingResponse(
        _stream_file_range(apk_path, 0, file_size - 1),
        status_code=status.HTTP_200_OK,
        media_type="application/vnd.android.package-archive",
        headers=headers,
    )


@router.get("/api/app/patches/{patch_filename}")
def download_resource_patch(patch_filename: str, request: Request):
    """
    Serves downloadable asset/config patch archives with HTTP Range and SHA-256 integrity verification.
    """
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    patch_dir = os.path.join(base_dir, "release_apks", "patches")
    target_path = os.path.abspath(os.path.join(patch_dir, patch_filename))

    # Security: Directory traversal prevention
    if not target_path.startswith(patch_dir) or not os.path.isfile(target_path):
        raise HTTPException(status_code=404, detail="Patch file not found")

    file_size = os.path.getsize(target_path)
    sha256_hash = _calculate_file_sha256(target_path)
    range_header = request.headers.get("Range")

    headers = {
        "Accept-Ranges": "bytes",
        "ETag": f'"{sha256_hash}"',
        "X-Checksum-SHA256": sha256_hash,
        "Content-Disposition": f'attachment; filename="{patch_filename}"',
    }

    if range_header:
        range_match = re.match(r"^bytes=(\d+)-(\d*)$", range_header.strip())
        if range_match:
            start = int(range_match.group(1))
            end_str = range_match.group(2)
            end = int(end_str) if end_str else file_size - 1

            if start >= file_size or end >= file_size or start > end:
                raise HTTPException(
                    status_code=status.HTTP_416_REQUESTED_RANGE_NOT_SATISFIABLE,
                    headers={"Content-Range": f"bytes */{file_size}"},
                    detail="Requested Range Not Satisfiable",
                )

            content_length = (end - start) + 1
            headers["Content-Range"] = f"bytes {start}-{end}/{file_size}"
            headers["Content-Length"] = str(content_length)

            return StreamingResponse(
                _stream_file_range(target_path, start, end),
                status_code=status.HTTP_206_PARTIAL_CONTENT,
                media_type="application/zip",
                headers=headers,
            )

    headers["Content-Length"] = str(file_size)
    return StreamingResponse(
        _stream_file_range(target_path, 0, file_size - 1),
        status_code=status.HTTP_200_OK,
        media_type="application/zip",
        headers=headers,
    )


# =====================================================================
# CLIENT TELEMETRY & LOGGING
# =====================================================================

@router.post("/api/app/telemetry/update-log")
def log_client_update_event(
    req: UpdateTelemetryLogRequest,
    request: Request,
    db: Session = Depends(get_db),
):
    """
    Records mobile client telemetry during update checks, downloads, installations, and failures.
    """
    client_ip = request.client.host if request.client else None
    log_entry = AppUpdateLog(
        device_id=req.device_id,
        user_id=req.user_id,
        current_version=req.current_version,
        current_version_code=req.current_version_code,
        target_version=req.target_version,
        target_version_code=req.target_version_code,
        update_type=req.update_type,
        status=req.status.upper(),
        download_duration_ms=req.download_duration_ms,
        bytes_downloaded=req.bytes_downloaded,
        error_message=req.error_message,
        ip_address=client_ip,
        created_at=datetime.utcnow(),
    )
    db.add(log_entry)
    db.commit()
    return {"success": True, "log_id": log_entry.id}


# =====================================================================
# ADMIN MANAGEMENT APIS
# =====================================================================

@router.post("/api/app/admin/update-policy")
def publish_update_policy(
    req: CreateUpdatePolicyRequest,
    db: Session = Depends(get_db),
):
    """
    Admin endpoint to publish a new developer-controlled update policy.
    Automatically computes file size and SHA-256 for local APKs if not explicitly provided.
    """
    apk_path = _find_release_apk()
    file_size = req.file_size_bytes or (os.path.getsize(apk_path) if apk_path else 0)
    sha256_hash = req.sha256_hash or (_calculate_file_sha256(apk_path) if apk_path else None)

    # Deactivate existing active policies for the same platform & channel if new version is higher
    if req.distribution_channel == "all":
        db.query(AppUpdatePolicy).filter(
            AppUpdatePolicy.platform == req.platform
        ).update({"is_active": False}, synchronize_session=False)
    else:
        db.query(AppUpdatePolicy).filter(
            AppUpdatePolicy.platform == req.platform,
            AppUpdatePolicy.distribution_channel.in_([req.distribution_channel, "all"]),
        ).update({"is_active": False}, synchronize_session=False)

    policy = AppUpdatePolicy(
        platform=req.platform,
        distribution_channel=req.distribution_channel,
        update_type=req.update_type,
        latest_version=req.latest_version,
        latest_version_code=req.latest_version_code,
        min_supported_version_code=req.min_supported_version_code,
        is_mandatory=req.is_mandatory,
        is_active=True,
        download_url=req.download_url or "/api/app/download-apk",
        patch_manifest_url=req.patch_manifest_url,
        file_size_bytes=file_size,
        sha256_hash=sha256_hash,
        release_title=req.release_title or "System Update Available",
        release_notes=json.dumps(req.release_notes),
        metadata_json=json.dumps(req.metadata) if req.metadata else None,
        published_by=req.published_by,
        created_at=datetime.utcnow(),
        updated_at=datetime.utcnow(),
    )
    db.add(policy)
    db.commit()
    db.refresh(policy)

    return {
        "success": True,
        "message": f"Successfully published policy v{policy.latest_version} (Build {policy.latest_version_code})",
        "policy_id": policy.id,
    }


@router.put("/api/app/admin/update-policy/{policy_id}/toggle")
def toggle_policy_status(
    policy_id: int,
    is_active: bool = Query(..., description="Set active status or rollback"),
    db: Session = Depends(get_db),
):
    """Enables, disables, or rolls back an update policy."""
    policy = db.query(AppUpdatePolicy).filter(AppUpdatePolicy.id == policy_id).first()
    if not policy:
        raise HTTPException(status_code=404, detail="Policy not found")

    policy.is_active = is_active
    policy.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(policy)
    return {"success": True, "policy_id": policy.id, "is_active": policy.is_active}


@router.get("/api/app/admin/update-policies")
def list_update_policies(
    platform: str = Query("android"),
    limit: int = Query(50),
    db: Session = Depends(get_db),
):
    """Lists all update policies and history for the admin console."""
    policies = (
        db.query(AppUpdatePolicy)
        .filter(AppUpdatePolicy.platform == platform)
        .order_by(desc(AppUpdatePolicy.created_at))
        .limit(limit)
        .all()
    )
    results = []
    for p in policies:
        notes = []
        if p.release_notes:
            try:
                notes = json.loads(p.release_notes)
            except Exception:
                notes = [p.release_notes]
        results.append({
            "id": p.id,
            "platform": p.platform,
            "distribution_channel": p.distribution_channel,
            "update_type": p.update_type,
            "latest_version": p.latest_version,
            "latest_version_code": p.latest_version_code,
            "min_supported_version_code": p.min_supported_version_code,
            "is_mandatory": p.is_mandatory,
            "is_active": p.is_active,
            "download_url": p.download_url,
            "file_size_mb": round(p.file_size_bytes / (1024 * 1024), 2),
            "sha256": p.sha256_hash,
            "release_title": p.release_title,
            "release_notes": notes,
            "published_by": p.published_by,
            "created_at": p.created_at.isoformat(),
        })
    return {"policies": results}


@router.get("/api/app/admin/update-telemetry")
def get_update_telemetry_summary(
    limit: int = Query(100),
    db: Session = Depends(get_db),
):
    """Returns analytics and device telemetry logs for update rollouts."""
    logs = (
        db.query(AppUpdateLog)
        .order_by(desc(AppUpdateLog.created_at))
        .limit(limit)
        .all()
    )
    
    # Aggregations
    status_counts = (
        db.query(AppUpdateLog.status, func.count(AppUpdateLog.id))
        .group_by(AppUpdateLog.status)
        .all()
    )
    status_summary = {st: count for st, count in status_counts}

    recent_logs = [
        {
            "id": l.id,
            "device_id": l.device_id,
            "user_id": l.user_id,
            "current_version_code": l.current_version_code,
            "target_version_code": l.target_version_code,
            "update_type": l.update_type,
            "status": l.status,
            "download_duration_ms": l.download_duration_ms,
            "bytes_downloaded": l.bytes_downloaded,
            "error_message": l.error_message,
            "ip_address": l.ip_address,
            "timestamp": l.created_at.isoformat(),
        }
        for l in logs
    ]

    return {
        "summary": status_summary,
        "recent_logs": recent_logs,
    }
