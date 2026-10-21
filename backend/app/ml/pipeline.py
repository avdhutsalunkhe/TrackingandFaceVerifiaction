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
    Optimized for continuous auto-capture, multi-frame burst processing, and sub-second verification.
    """
    def __init__(self):
        self.models = models_manager

    def evaluate_frame_candidate(self, image_bytes: bytes) -> Dict[str, Any]:
        """
        Fast-path candidate evaluation:
        1. Decode frame with EXIF orientation fast-path
        2. Fast quality & lighting pre-filter (CV_32F Laplacian)
        3. Detect face via SCRFD (with indoor illumination boost & orientation recovery)
        4. Enforce 1 face requirement
        5. Comprehensive face-centric quality evaluation (illumination, blur, pose, roll)
        """
        t0 = time.perf_counter_ns()
        latencies = {}

        # 1. Decode
        t_dec_start = time.perf_counter_ns()
        img = decode_image_bytes(image_bytes)
        latencies["decode_ms"] = round((time.perf_counter_ns() - t_dec_start) / 1_000_000.0, 2)
        if img is None:
            return {
                "success": False,
                "error_code": "CAPTURE_NOT_READY",
                "error_message": "Failed to decode image frame",
                "latencies": latencies
            }

        # 2. Fast Quality Pre-filter
        t_qual_start = time.perf_counter_ns()
        is_quality_ok, pre_score, pre_msg = check_image_quality(img)
        latencies["quality_check_ms"] = round((time.perf_counter_ns() - t_qual_start) / 1_000_000.0, 2)
        if not is_quality_ok:
            return {
                "success": False,
                "error_code": "FACE_QUALITY_FAILED",
                "error_message": pre_msg,
                "quality_score": pre_score,
                "latencies": latencies
            }

        # 3. Detect face via SCRFD (with indoor illumination boost & orientation recovery)
        t_det_start = time.perf_counter_ns()
        faces = self.models.detector.detect(img)

        # If no face detected in low ambient light, try adaptive CLAHE enhancement
        if len(faces) == 0 and getattr(settings, 'INDOOR_ENHANCEMENT_ENABLED', True):
            enhanced_img = enhance_indoor_illumination(img)
            faces = self.models.detector.detect(enhanced_img)
            if len(faces) > 0:
                img = enhanced_img

        # Orientation recovery: if no face found OR if face roll is severe (>35 deg)
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

        latencies["detection_ms"] = round((time.perf_counter_ns() - t_det_start) / 1_000_000.0, 2)

        if len(faces) == 0:
            return {
                "success": False,
                "error_code": "FACE_NOT_DETECTED",
                "error_message": "No face detected in frame. Please look directly at the camera.",
                "latencies": latencies
            }

        if len(faces) > 1:
            return {
                "success": False,
                "error_code": "MULTIPLE_FACES",
                "error_message": f"Multiple faces ({len(faces)}) detected. Only 1 person allowed.",
                "latencies": latencies
            }

        face = faces[0]

        # 4. Face-Centric Quality Evaluation
        t_eval_start = time.perf_counter_ns()
        is_face_ok, quality_score, quality_msg, face_metrics = evaluate_face_crop_quality(img, face.bbox, face.landmarks)
        latencies["face_eval_ms"] = round((time.perf_counter_ns() - t_eval_start) / 1_000_000.0, 2)

        if not is_face_ok:
            return {
                "success": False,
                "error_code": "FACE_QUALITY_FAILED",
                "error_message": quality_msg,
                "quality_score": quality_score,
                "latencies": latencies
            }

        return {
            "success": True,
            "error_code": None,
            "error_message": None,
            "image": img,
            "face": face,
            "quality_score": quality_score,
            "latencies": latencies
        }

    def process_single_frame(self, image_bytes: bytes) -> FacePipelineResult:
        """
        Processes a single image frame with full pipeline execution (detection, alignment, embedding).
        Used during progressive face enrollment and single-frame requests.
        """
        t0 = time.perf_counter_ns()
        cand = self.evaluate_frame_candidate(image_bytes)

        if not cand["success"]:
            return FacePipelineResult(
                False,
                error_code=cand.get("error_code"),
                error_message=cand.get("error_message"),
                quality_score=cand.get("quality_score", 0.0),
                latency_ms=cand.get("latencies", {})
            )

        latencies = dict(cand["latencies"])
        img = cand["image"]
        face = cand["face"]
        quality_score = cand["quality_score"]

        # Alignment to 112x112 & Illumination Normalization
        t_align_start = time.perf_counter_ns()
        aligned_112 = align_face_112(img, face.landmarks)
        norm_aligned_112 = normalize_face_crop_illumination(aligned_112)
        latencies["alignment_ms"] = round((time.perf_counter_ns() - t_align_start) / 1_000_000.0, 2)

        # Feature extraction via ArcFace ONNX
        t_emb_start = time.perf_counter_ns()
        try:
            embedding = self.models.recognizer.extract_embedding(norm_aligned_112)
            latencies["embedding_ms"] = round((time.perf_counter_ns() - t_emb_start) / 1_000_000.0, 2)
        except Exception as e:
            return FacePipelineResult(False, "BIOMETRIC_SERVICE_ERROR", f"Embedding extraction error: {str(e)}", latency_ms=latencies)

        latencies["total_pipeline_ms"] = round((time.perf_counter_ns() - t0) / 1_000_000.0, 2)

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
        Optimized multi-frame biometric verification pipeline:
        1. Fast candidate evaluation across all frames (decoding, quality check, SCRFD detection).
        2. Preserves full temporal landmark sequence across frames for active blink / motion challenge.
        3. Selects the single best quality candidate frame for alignment and ArcFace embedding extraction.
           (Saves redundant neural network forward passes and alignments on secondary frames).
        4. Validates deep-learning passive anti-spoofing + active dynamic landmark challenge.
        5. Computes high-speed cosine similarity against reference template.
        """
        t_total_start = time.perf_counter_ns()
        if not frames_bytes_list:
            return False, "CAMERA_ERROR", "No image frames received", 0.0, 0.0, {}

        valid_candidates = []
        landmarks_sequence = []
        best_candidate = None
        highest_quality = -1.0
        first_failure = None

        for frame_bytes in frames_bytes_list:
            cand = self.evaluate_frame_candidate(frame_bytes)
            if cand["success"]:
                valid_candidates.append(cand)
                landmarks_sequence.append(cand["face"].landmarks)
                if cand["quality_score"] > highest_quality:
                    highest_quality = cand["quality_score"]
                    best_candidate = cand
            else:
                if first_failure is None:
                    first_failure = cand

        if not valid_candidates or best_candidate is None:
            err_code = first_failure.get("error_code") if first_failure else "CAPTURE_NOT_READY"
            err_msg = first_failure.get("error_message") if first_failure else "Could not detect face in live frames"
            return False, err_code, err_msg, 0.0, 0.0, {"stage_latency": first_failure.get("latencies", {}) if first_failure else {}}

        # Perform 5-point Umeyama alignment & illumination normalization ONCE on best candidate
        t_align_start = time.perf_counter_ns()
        best_img = best_candidate["image"]
        best_face = best_candidate["face"]
        aligned_112 = align_face_112(best_img, best_face.landmarks)
        norm_aligned_112 = normalize_face_crop_illumination(aligned_112)
        alignment_latency_ms = round((time.perf_counter_ns() - t_align_start) / 1_000_000.0, 2)

        # Liveness & Anti-Spoof (Passive DL / texture check on best face crop + active temporal blink on landmarks sequence)
        t_live_start = time.perf_counter_ns()
        is_live, liveness_score, liveness_label, liveness_details = self.models.liveness.verify_liveness(
            best_face_crop=norm_aligned_112,
            frames_landmarks=landmarks_sequence
        )
        liveness_latency_ms = round((time.perf_counter_ns() - t_live_start) / 1_000_000.0, 2)

        if not is_live:
            return False, "LIVENESS_FAILED", f"Liveness verification failed ({liveness_label})", 0.0, liveness_score, liveness_details

        # Extract ArcFace embedding ONCE on best candidate
        t_emb_start = time.perf_counter_ns()
        try:
            live_embedding = self.models.recognizer.extract_embedding(norm_aligned_112)
            embedding_latency_ms = round((time.perf_counter_ns() - t_emb_start) / 1_000_000.0, 2)
        except Exception as e:
            return False, "BIOMETRIC_SERVICE_ERROR", f"Embedding extraction error: {str(e)}", 0.0, liveness_score, {}

        # Fast Dot-Product Cosine Similarity
        t_sim_start = time.perf_counter_ns()
        similarity = compute_cosine_similarity(reference_embedding, live_embedding)
        similarity_latency_ms = round((time.perf_counter_ns() - t_sim_start) / 1_000_000.0, 2)

        total_latency_ms = round((time.perf_counter_ns() - t_total_start) / 1_000_000.0, 2)

        benchmarks = {
            "decode_ms": best_candidate["latencies"].get("decode_ms", 0.0),
            "detection_ms": best_candidate["latencies"].get("detection_ms", 0.0),
            "quality_check_ms": best_candidate["latencies"].get("quality_check_ms", 0.0),
            "face_eval_ms": best_candidate["latencies"].get("face_eval_ms", 0.0),
            "alignment_ms": alignment_latency_ms,
            "embedding_ms": embedding_latency_ms,
            "liveness_ms": liveness_latency_ms,
            "similarity_calc_ms": similarity_latency_ms,
            "total_server_processing_ms": total_latency_ms,
        }

        details = {
            "liveness": liveness_details,
            "similarity_score": similarity,
            "threshold": settings.SIMILARITY_THRESHOLD,
            "frames_analyzed": len(valid_candidates),
            "latency_benchmarks": benchmarks
        }

        # Check threshold
        if similarity < settings.SIMILARITY_THRESHOLD:
            return False, "FACE_MISMATCH", f"Face similarity {similarity:.2f} below threshold {settings.SIMILARITY_THRESHOLD}", similarity, liveness_score, details

        return True, None, "Face and liveness verified successfully", similarity, liveness_score, details

face_pipeline = FaceRecognitionPipeline()
