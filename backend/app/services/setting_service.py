from sqlalchemy.orm import Session
from app.models.setting import SystemSetting
from app.config import settings

class SettingService:
    @staticmethod
    def load_all_settings(db: Session):
        """Loads all persisted system settings into the global settings instance."""
        records = db.query(SystemSetting).all()
        for r in records:
            if r.key == "SIMILARITY_THRESHOLD":
                try:
                    settings.SIMILARITY_THRESHOLD = float(r.value)
                except ValueError:
                    pass
            elif r.key == "LIVENESS_CONFIDENCE_THRESHOLD":
                try:
                    settings.LIVENESS_CONFIDENCE_THRESHOLD = float(r.value)
                except ValueError:
                    pass
            elif r.key == "MIN_FACE_SIZE":
                try:
                    settings.MIN_FACE_SIZE = int(r.value)
                except ValueError:
                    pass

    @staticmethod
    def get_biometric_settings(db: Session) -> dict:
        """Get current active biometric settings."""
        # Ensure fresh values from DB if available
        sim_rec = db.query(SystemSetting).filter(SystemSetting.key == "SIMILARITY_THRESHOLD").first()
        if sim_rec:
            try:
                settings.SIMILARITY_THRESHOLD = float(sim_rec.value)
            except ValueError:
                pass

        live_rec = db.query(SystemSetting).filter(SystemSetting.key == "LIVENESS_CONFIDENCE_THRESHOLD").first()
        if live_rec:
            try:
                settings.LIVENESS_CONFIDENCE_THRESHOLD = float(live_rec.value)
            except ValueError:
                pass

        size_rec = db.query(SystemSetting).filter(SystemSetting.key == "MIN_FACE_SIZE").first()
        if size_rec:
            try:
                settings.MIN_FACE_SIZE = int(size_rec.value)
            except ValueError:
                pass

        return {
            "similarity_threshold": float(settings.SIMILARITY_THRESHOLD),
            "liveness_confidence_threshold": float(settings.LIVENESS_CONFIDENCE_THRESHOLD),
            "min_face_size": int(settings.MIN_FACE_SIZE)
        }

    @staticmethod
    def update_biometric_settings(
        db: Session,
        similarity_threshold: float,
        liveness_confidence_threshold: float = None,
        min_face_size: int = None
    ) -> dict:
        """Updates and persists global biometric settings."""
        # 1. Update in-memory global settings (guarded to calibrated safe range [0.45, 0.85])
        clamped_sim = max(0.45, min(0.85, float(similarity_threshold)))
        settings.SIMILARITY_THRESHOLD = round(clamped_sim, 4)
        
        # 2. Persist to DB
        sim_rec = db.query(SystemSetting).filter(SystemSetting.key == "SIMILARITY_THRESHOLD").first()
        if not sim_rec:
            sim_rec = SystemSetting(
                key="SIMILARITY_THRESHOLD",
                value=str(settings.SIMILARITY_THRESHOLD),
                description="Global ArcFace Cosine Similarity Threshold (0.0 to 1.0)"
            )
            db.add(sim_rec)
        else:
            sim_rec.value = str(settings.SIMILARITY_THRESHOLD)

        if liveness_confidence_threshold is not None:
            settings.LIVENESS_CONFIDENCE_THRESHOLD = round(float(liveness_confidence_threshold), 4)
            live_rec = db.query(SystemSetting).filter(SystemSetting.key == "LIVENESS_CONFIDENCE_THRESHOLD").first()
            if not live_rec:
                live_rec = SystemSetting(
                    key="LIVENESS_CONFIDENCE_THRESHOLD",
                    value=str(settings.LIVENESS_CONFIDENCE_THRESHOLD),
                    description="Global MiniFASNet Liveness Confidence Threshold"
                )
                db.add(live_rec)
            else:
                live_rec.value = str(settings.LIVENESS_CONFIDENCE_THRESHOLD)

        if min_face_size is not None:
            settings.MIN_FACE_SIZE = int(min_face_size)
            size_rec = db.query(SystemSetting).filter(SystemSetting.key == "MIN_FACE_SIZE").first()
            if not size_rec:
                size_rec = SystemSetting(
                    key="MIN_FACE_SIZE",
                    value=str(settings.MIN_FACE_SIZE),
                    description="Minimum face size bounding box in pixels"
                )
                db.add(size_rec)
            else:
                size_rec.value = str(settings.MIN_FACE_SIZE)

        db.commit()

        return {
            "similarity_threshold": float(settings.SIMILARITY_THRESHOLD),
            "liveness_confidence_threshold": float(settings.LIVENESS_CONFIDENCE_THRESHOLD),
            "min_face_size": int(settings.MIN_FACE_SIZE)
        }
