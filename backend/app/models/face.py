from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, LargeBinary, Float, JSON
from sqlalchemy.orm import relationship
from app.database import Base

class FaceTemplate(Base):
    __tablename__ = "face_templates"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False, index=True)
    model_name = Column(String(64), nullable=False, default="ArcFace-IResNet50")
    model_version = Column(String(32), nullable=False, default="1.0.0")
    embedding_dimension = Column(Integer, nullable=False, default=512)
    face_embedding = Column(LargeBinary, nullable=False) # 512 float32 binary bytes
    face_image = Column(LargeBinary, nullable=False) # Original reference JPEG bytes (MEDIUMBLOB)
    sample_count = Column(Integer, nullable=False, default=4)
    quality_score = Column(Float, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="face_template")

class FaceEnrollmentSample(Base):
    __tablename__ = "face_enrollment_samples"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    sample_index = Column(Integer, nullable=False) # 1, 2, 3, 4
    sample_embedding = Column(LargeBinary, nullable=False)
    sample_image = Column(LargeBinary, nullable=True)
    quality_metrics = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    user = relationship("User", back_populates="enrollment_samples")
