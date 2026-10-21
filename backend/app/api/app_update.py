import os
import json
from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, JSONResponse

router = APIRouter(tags=["App Releases & Updates"])

def _find_release_apk() -> str | None:
    # Base candidates in project directories
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    candidates = [
        os.path.join(base_dir, "release_apks", "fieldstaff-attendance-universal-release.apk"),
        os.path.join(base_dir, "release_apks", "fieldstaff-attendance-arm64-v8a-release.apk"),
        os.path.join(base_dir, "..", "release_apks", "fieldstaff-attendance-universal-release.apk"),
        r"D:\Attend\field_staff_attendance_new\release_apks\fieldstaff-attendance-universal-release.apk",
        r"D:\Attend\field_staff_attendance_new\backend\release_apks\fieldstaff-attendance-universal-release.apk",
        os.path.join(base_dir, "mobile", "release_apks", "fieldstaff-attendance-universal-release.apk"),
        os.path.join(base_dir, "mobile", "mobile", "build", "app", "outputs", "flutter-apk", "app-release.apk"),
    ]
    for c in candidates:
        if os.path.isfile(c) and os.path.getsize(c) > 0:
            return c
    return None

def _get_version_metadata() -> dict:
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    meta_candidates = [
        r"D:\Attend\field_staff_attendance_new\release_apks\version.json",
        r"D:\Attend\field_staff_attendance_new\backend\release_apks\version.json",
        os.path.join(base_dir, "release_apks", "version.json"),
        os.path.join(base_dir, "..", "release_apks", "version.json"),
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

@router.get("/api/app/latest-release")
@router.get("/releases/latest_release.json")
def get_latest_release():
    """Returns metadata about the latest mobile app version for in-app auto-update."""
    apk_path = _find_release_apk()
    apk_available = apk_path is not None
    file_size_mb = round(os.path.getsize(apk_path) / (1024 * 1024), 1) if apk_path else 0.0

    meta = _get_version_metadata()

    return {
        "version": meta.get("version", "1.0.1"),
        "versionCode": meta.get("versionCode", 2),
        "apkUrl": "/api/app/download-apk",
        "apkAvailable": apk_available,
        "fileSizeMb": file_size_mb,
        "forceUpdate": meta.get("forceUpdate", False),
        "minimumSupportedVersionCode": meta.get("minimumSupportedVersionCode", 1),
        "releaseNotes": meta.get("releaseNotes", [
            "Live GPS duty journey tracking with real-time odometer",
            "15-meter precision route tracking across all travel modes",
            "Automatic background sync for attendance & route points"
        ])
    }

@router.get("/api/app/download-apk")
@router.get("/releases/app-release.apk")
def download_latest_apk():
    """Serves the latest compiled Android APK for direct OTA installation."""
    apk_path = _find_release_apk()
    if not apk_path:
        raise HTTPException(
            status_code=404,
            detail="Release APK not found on server. Please build release APK first."
        )
    return FileResponse(
        path=apk_path,
        media_type="application/vnd.android.package-archive",
        filename="fieldstaff-attendance-release.apk"
    )
