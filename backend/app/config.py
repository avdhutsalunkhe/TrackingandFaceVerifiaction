import os
from typing import List
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import computed_field

class Settings(BaseSettings):
    PROJECT_NAME: str = "FieldStaff AI Biometric Attendance"
    ENV: str = "development"
    DEBUG: bool = True

    # Database
    DB_HOST: str = "127.0.0.1"
    DB_PORT: int = 3306
    DB_USER: str = "root"
    DB_PASSWORD: str = "rootpassword"
    DB_NAME: str = "fieldstaff_attendance_db"

    # SQLite fallback option for lightweight development/testing if MySQL not running
    USE_SQLITE_FALLBACK: bool = False
    SQLITE_DB_PATH: str = "./fieldstaff_attendance.db"

    # JWT
    JWT_SECRET_KEY: str = "fieldstaff_super_secret_jwt_key_change_in_production_2026_xyz"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 1440
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # ML Weights & Model Names
    ML_WEIGHTS_DIR: str = os.path.join(os.path.dirname(os.path.dirname(__file__)), "weights")
    FACE_DETECTOR_MODEL: str = "det_500m.onnx"
    FACE_RECOGNITION_MODEL: str = "w600k_mbf.onnx"
    ANTI_SPOOFING_MODEL: str = "2.7_80x80_MiniFASNetV2.onnx"
    SIMILARITY_THRESHOLD: float = 0.60
    LIVENESS_CONFIDENCE_THRESHOLD: float = 0.70
    MIN_FACE_SIZE: int = 80

    # Indoor Illumination & Quality Enhancement
    INDOOR_ENHANCEMENT_ENABLED: bool = True
    MIN_FACE_BRIGHTNESS: float = 28.0
    MIN_FACE_SHARPNESS: float = 12.0
    CLAHE_CLIP_LIMIT: float = 2.0

    # GPS
    MAX_GPS_ACCURACY_THRESHOLD_METERS: float = 50.0

    # ONNX Inference Optimization & Threading
    ONNX_NUM_THREADS: int = 4
    ONNX_INTER_OP_THREADS: int = 1
    MODEL_WARMUP_ON_STARTUP: bool = True
    TEMPLATE_CACHE_ENABLED: bool = True
    TEMPLATE_CACHE_TTL_SECONDS: int = 3600

    # CORS
    CORS_ORIGINS: str = "*"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )

    @computed_field
    @property
    def DATABASE_URL(self) -> str:
        if self.USE_SQLITE_FALLBACK:
            return f"sqlite:///{self.SQLITE_DB_PATH}"
        return f"mysql+pymysql://{self.DB_USER}:{self.DB_PASSWORD}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}?charset=utf8mb4"

    @property
    def cors_origin_list(self) -> List[str]:
        if self.CORS_ORIGINS == "*":
            return ["*"]
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

settings = Settings()
