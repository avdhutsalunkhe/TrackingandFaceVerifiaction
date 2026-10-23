from datetime import datetime
from sqlalchemy import Column, Integer, BigInteger, String, Boolean, DateTime, Text, JSON
from app.database import Base

class AppUpdatePolicy(Base):
    __tablename__ = "app_update_policies"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    platform = Column(String(32), default="android", nullable=False, index=True) # android, ios, windows, web
    distribution_channel = Column(String(32), default="all", nullable=False, index=True) # direct_apk, google_play, all
    update_type = Column(String(32), default="direct_apk", nullable=False) # resource_patch, direct_apk, in_app_play
    latest_version = Column(String(32), nullable=False) # e.g. "1.0.4"
    latest_version_code = Column(Integer, nullable=False, index=True) # e.g. 5
    min_supported_version_code = Column(Integer, default=1, nullable=False)
    is_mandatory = Column(Boolean, default=False, nullable=False)
    is_active = Column(Boolean, default=True, nullable=False, index=True)
    
    download_url = Column(String(512), nullable=False) # e.g. "/api/app/download-apk" or CDN URL
    patch_manifest_url = Column(String(512), nullable=True) # for resource/asset patch packages
    file_size_bytes = Column(BigInteger, default=0, nullable=False)
    sha256_hash = Column(String(64), nullable=True) # 64-char hex SHA-256 checksum
    
    release_title = Column(String(255), default="System Update Available", nullable=False)
    release_notes = Column(Text, nullable=True) # JSON array or newline-separated notes
    metadata_json = Column(Text, nullable=True) # JSON payload: changed assets, dynamic configs
    
    published_by = Column(String(128), default="Admin", nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

class AppUpdateLog(Base):
    __tablename__ = "app_update_logs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    device_id = Column(String(128), nullable=False, index=True)
    user_id = Column(Integer, nullable=True, index=True)
    current_version = Column(String(32), nullable=True)
    current_version_code = Column(Integer, default=0, nullable=False)
    target_version = Column(String(32), nullable=True)
    target_version_code = Column(Integer, default=0, nullable=False)
    update_type = Column(String(32), default="direct_apk", nullable=False) # resource_patch, direct_apk, in_app_play
    
    # Status: CHECKED, DOWNLOADING, DOWNLOADED, APPLIED, INSTALLED, FAILED, DISMISSED
    status = Column(String(32), nullable=False, index=True)
    download_duration_ms = Column(Integer, nullable=True)
    bytes_downloaded = Column(BigInteger, default=0, nullable=True)
    error_message = Column(Text, nullable=True)
    ip_address = Column(String(64), nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
