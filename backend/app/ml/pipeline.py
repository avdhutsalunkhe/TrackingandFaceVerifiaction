import time
import cv2
import numpy as np
from typing import List, Tuple, Dict, Any, Optional
from app.config import settings
from app.ml.preprocessing import (
    decode_image_bytes,
    check_image_quality,
    compress_to_jpeg,
    enhance_indoor_illumination,
    normalize_face_crop_illumination,
    evaluate_face_crop_quality,
)
from app.ml.alignment import align_face_112
from app.ml.similarity import compute_cosine_similarity, aggregate_embeddings
from app.ml.models_manager import models_manager

class FacePipelineResult:
    def __init__(
        self,
        success: bool,
        error_code: Optional[str] = None,
        error_message: Optional[str] = None,
        embedding: Optional[np.ndarray] = None,
        aligned_face: Optional[np.ndarray] = None,
        quality_score: float = 0.0,
        landmarks: Optional[np.ndarray] = None,
        latency_ms: Optional[Dict[str, float]] = None,
    ):
        self.success = success
        self.error_code = error_code
        self.error_message = error_message
        self.embedding = embedding
        self.aligned_face = aligned_face
        self.quality_score = quality_score
        self.landmarks = landmarks
        self.latency_ms = latency_ms or {}

class FaceRecognitionPipeline:
    """
    High-Performance Biometric ML Pipeline.
    Persistent in-memory models (SCRFD + ArcFace + Anti-Spoofing).
    Optimized for continuous auto-capture and sub-second verification.
    """
    def __init__(self):
        self.models = models_manager

    def process_single_frame(self, image_bytes: bytes) -> FacePipelineResult:
        """
        Processes a single image frame with latency telemetry:
        1. Decode frame with automatic EXIF orientation transposition
        2. Fast quality & lighting pre-filter
        3. Detect face via SCRFD (with indoor illumination boost & orientation recovery)
        4. Enforce 1 face requirement
        5. Comprehensive face-centric quality evaluation (illumination, blur, pose, roll)
        6. 5-point landmark alignment to 112x112 via canonical Umeyama transform
        7. Face crop illumination normalization
        8. ArcFace 512-D L2-normalized embedding extraction
        """
        t0 = time.perf_counter()
        latencies = {}

        # 1. Decode
        t_dec_start = time.perf_counter()
        img = decode_image_bytes(image_bytes)
        latencies["decode_ms"] = round((time.perf_counter() - t_dec_start) * 1000, 2)
        if img is None:
            return FacePipelineResult(False, "CAPTURE_NOT_READY", "Failed to decode image frame", latency_ms=latencies)

        # 2. Fast Quality Pre-filter
        t_qual_start = time.perf_counter()
        is_quality_ok, pre_score, pre_msg = check_image_quality(img)
        latencies["quality_check_ms"] = round((time.perf_counter() - t_qual_start) * 1000, 2)
        if not is_quality_ok:
            return FacePipelineResult(False, "FACE_QUALITY_FAILED", pre_msg, quality_score=pre_score, latency_ms=latencies)

        # 3. Detect face via SCRFD (with indoor illumination boost & orientation recovery)
        t_det_start = time.perf_counter()
        faces = self.models.detector.detect(img)
        
        # If no face detected in low ambient light, try adaptive CLAHE enhancement
        if len(faces) == 0 and getattr(settings, 'INDOOR_ENHANCEMENT_ENABLED', True):
            enhanced_img = enhance_indoor_illumination(img)
            faces = self.models.detector.detect(enhanced_img)
            if len(faces) > 0:
                img = enhanced_img

        # Orientation recovery: if no face found OR if face roll is severe (>35 deg, indicating sideways frame without EXIF tag)
        needs_orientation_search = (len(faces) == 0)
        initial_roll = 0.0
        if len(faces) == 1 and faces[0].landmarks is not None and len(faces[0].landmarks) >= 2:
            dx = float(faces[0].landmarks[1][0] - faces[0].landmarks[0][0])
            dy = float(faces[0].landmarks[1][1] - faces[0].landmarks[0][1])
            initial_roll = abs(float(np.degrees(np.arctan2(dy, dx))))
            if initial_roll > 35.0:
                needs_orientation_search = True

        if needs_orientation_search:
            best_img = img
            best_faces = faces
            best_score = faces[0].score if (faces and len(faces) == 1 and initial_roll <= 25.0) else -1.0

            for rot_code in [cv2.ROTATE_90_CLOCKWISE, cv2.ROTATE_90_COUNTERCLOCKWISE, cv2.ROTATE_180]:
                rotated_candidate = cv2.rotate(img, rot_code)
                r_faces = self.models.detector.detect(rotated_candidate)
                if len(r_faces) == 1 and r_faces[0].landmarks is not None and len(r_faces[0].landmarks) >= 2:
                    rdx = float(r_faces[0].landmarks[1][0] - r_faces[0].landmarks[0][0])
                    rdy = float(r_faces[0].landmarks[1][1] - r_faces[0].landmarks[0][1])
                    candidate_roll = abs(float(np.degrees(np.arctan2(rdy, rdx))))
                    if candidate_roll <= 25.0 and r_faces[0].score > best_score:
                        best_score = r_faces[0].score
                        best_img = rotated_candidate
                        best_faces = r_faces

            img = best_img
            faces = best_faces

        latencies["detection_ms"] = round((time.perf_counter() - t_det_start) * 1000, 2)

        if len(faces) == 0:
            return FacePipelineResult(False, "FACE_NOT_DETECTED", "No face detected in frame. Please look directly at the camera.", latency_ms=latencies)
        
        if len(faces) > 1:
            return FacePipelineResult(False, "MULTIPLE_FACES", f"Multiple faces ({len(faces)}) detected. Only 1 person allowed.", latency_ms=latencies)

        face = faces[0]

        # 4. Face-Centric Quality Evaluation
        t_eval_start = time.perf_counter()
        is_face_ok, quality_score, quality_msg, face_metrics = evaluate_face_crop_quality(img, face.bbox, face.landmarks)
        latencies["face_eval_ms"] = round((time.perf_counter() - t_eval_start) * 1000, 2)

        if not is_face_ok:
            return FacePipelineResult(
                False,
                "FACE_QUALITY_FAILED",
                quality_msg,
                quality_score=quality_score,
                latency_ms=latencies
            )

        # 5. Alignment to 112x112 & Illumination Normalization
        t_align_start = time.perf_counter()
        aligned_112 = align_face_112(img, face.landmarks)
        norm_aligned_112 = normalize_face_crop_illumination(aligned_112)
        latencies["alignment_ms"] = round((time.perf_counter() - t_align_start) * 1000, 2)

        # 6. Feature extraction via ArcFace ONNX
        t_emb_start = time.perf_counter()
        try:
            embedding = self.models.recognizer.extract_embedding(norm_aligned_112)
            latencies["embedding_ms"] = round((time.perf_counter() - t_emb_start) * 1000, 2)
        except Exception as e:
            return FacePipelineResult(False, "BIOMETRIC_SERVICE_ERROR", f"Embedding extraction error: {str(e)}", latency_ms=latencies)

        latencies["total_pipeline_ms"] = round((time.perf_counter() - t0) * 1000, 2)

        return FacePipelineResult(
            success=True,
            embedding=embedding,
            aligned_face=norm_aligned_112,
            quality_score=quality_score,
            landmarks=face.landmarks,
            latency_ms=latencies
        )

    def verify_live_sequence(
        self,
        frames_bytes_list: List[bytes],
        reference_embedding: np.ndarray
    ) -> Tuple[bool, Optional[str], Optional[str], float, float, Dict[str, Any]]:
        """
        Fast-path biometric verification against stored reference embedding.
        Measures individual stage latencies and returns total benchmark breakdown.
        """
        t_total_start = time.perf_counter()
        if not frames_bytes_list:
            return False, "CAMERA_ERROR", "No image frames received", 0.0, 0.0, {}

        processed_frames = []
        landmarks_sequence = []
        best_frame_res = None
        highest_quality = -1.0

        for frame_bytes in frames_bytes_list:
            res = self.process_single_frame(frame_bytes)
            if res.success:
                processed_frames.append(res)
                landmarks_sequence.append(res.landmarks)
                if res.quality_score > highest_quality:
                    highest_quality = res.quality_score
                    best_frame_res = res
            else:
                if best_frame_res is None:
                    best_frame_res = res

        if not processed_frames or best_frame_res is None or not best_frame_res.success:
            err_code = best_frame_res.error_code if best_frame_res else "CAPTURE_NOT_READY"
            err_msg = best_frame_res.error_message if best_frame_res else "Could not detect face in live frames"
            return False, err_code, err_msg, 0.0, 0.0, {"stage_latency": best_frame_res.latency_ms if best_frame_res else {}}

        # Liveness & Anti-Spoof
        t_live_start = time.perf_counter()
        is_live, liveness_score, liveness_label, liveness_details = self.models.liveness.verify_liveness(
            best_face_crop=best_frame_res.aligned_face,
            frames_landmarks=landmarks_sequence
        )
        liveness_latency_ms = round((time.perf_counter() - t_live_start) * 1000, 2)

        if not is_live:
            return False, "LIVENESS_FAILED", f"Liveness verification failed ({liveness_label})", 0.0, liveness_score, liveness_details

        # Fast Dot-Product Cosine Similarity
        t_sim_start = time.perf_counter()
        similarity = compute_cosine_similarity(reference_embedding, best_frame_res.embedding)
        similarity_latency_ms = round((time.perf_counter() - t_sim_start) * 1000, 2)

        total_latency_ms = round((time.perf_counter() - t_total_start) * 1000, 2)

        benchmarks = {
            "decode_ms": best_frame_res.latency_ms.get("decode_ms", 0.0),
            "detection_ms": best_frame_res.latency_ms.get("detection_ms", 0.0),
            "alignment_ms": best_frame_res.latency_ms.get("alignment_ms", 0.0),
            "embedding_ms": best_frame_res.latency_ms.get("embedding_ms", 0.0),
            "liveness_ms": liveness_latency_ms,
            "similarity_calc_ms": similarity_latency_ms,
            "total_server_processing_ms": total_latency_ms,
        }

        details = {
            "liveness": liveness_details,
            "similarity_score": similarity,
            "threshold": settings.SIMILARITY_THRESHOLD,
            "frames_analyzed": len(processed_frames),
            "latency_benchmarks": benchmarks
        }

        # Check threshold
        if similarity < settings.SIMILARITY_THRESHOLD:
            return False, "FACE_MISMATCH", f"Face similarity {similarity:.2f} below threshold {settings.SIMILARITY_THRESHOLD}", similarity, liveness_score, details

        return True, None, "Face and liveness verified successfully", similarity, liveness_score, details

face_pipeline = FaceRecognitionPipeline()
