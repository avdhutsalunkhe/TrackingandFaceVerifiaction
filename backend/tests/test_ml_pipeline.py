import numpy as np
import cv2
import pytest
from app.ml.preprocessing import check_image_quality, compress_to_jpeg
from app.ml.similarity import compute_cosine_similarity, aggregate_embeddings
from app.ml.alignment import align_face_112
from app.ml.liveness import LivenessDetector

def test_cosine_similarity():
    v1 = np.array([1.0, 0.0, 0.0], dtype=np.float32)
    v2 = np.array([1.0, 0.0, 0.0], dtype=np.float32)
    assert round(compute_cosine_similarity(v1, v2), 4) == 1.0

    v3 = np.array([0.0, 1.0, 0.0], dtype=np.float32)
    assert round(compute_cosine_similarity(v1, v3), 4) == 0.0

def test_aggregate_embeddings():
    v1 = np.array([1.0, 0.0, 0.0], dtype=np.float32)
    v2 = np.array([1.0, 0.0, 0.0], dtype=np.float32)
    v3 = np.array([1.0, 0.0, 0.0], dtype=np.float32)
    v4 = np.array([1.0, 0.0, 0.0], dtype=np.float32)
    agg = aggregate_embeddings([v1, v2, v3, v4])
    assert agg.shape == (3,)
    assert np.allclose(agg, [1.0, 0.0, 0.0])

def test_image_quality_check():
    # Valid synthetic test image with natural illumination
    img = np.full((200, 200, 3), 120, dtype=np.uint8)
    cv2.circle(img, (100, 100), 40, (200, 200, 200), -1)
    cv2.putText(img, "TEST", (50, 100), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (50, 50, 50), 2)
    
    is_ok, quality_score, msg = check_image_quality(img)
    assert is_ok is True
    assert quality_score > 0.0

def test_align_face_112():
    img = np.zeros((300, 300, 3), dtype=np.uint8)
    landmarks = np.array([
        [100, 100],
        [200, 100],
        [150, 150],
        [120, 220],
        [180, 220]
    ], dtype=np.float32)
    aligned = align_face_112(img, landmarks)
    assert aligned.shape == (112, 112, 3)

def test_active_blink_challenge_detector():
    detector = LivenessDetector()
    
    # Simulate a sequence of 4 landmark sets with a dip in eye height (blink)
    frame1 = np.array([[100, 100], [200, 100], [150, 150], [120, 200], [180, 200]], dtype=np.float32) # Open
    frame2 = np.array([[100, 100], [200, 100], [150, 142], [120, 200], [180, 200]], dtype=np.float32) # Closed
    frame3 = np.array([[100, 100], [200, 100], [150, 142], [120, 200], [180, 200]], dtype=np.float32) # Closed
    frame4 = np.array([[100, 100], [200, 100], [150, 150], [120, 200], [180, 200]], dtype=np.float32) # Open

    passed, msg, details = detector.evaluate_active_blink_challenge([frame1, frame2, frame3, frame4])
    assert passed is True
    assert details["pattern"] == "OPEN -> CLOSED -> OPEN"

def test_models_manager_onnx_active():
    from app.ml.models_manager import models_manager
    assert models_manager.detector.session is not None, "SCRFD ONNX Detector session should be active"
    assert models_manager.recognizer.session is not None, "ArcFace ONNX Recognizer session should be active"

def test_enhance_indoor_illumination():
    from app.ml.preprocessing import enhance_indoor_illumination
    # Create dark image (simulating indoor room)
    dark_img = np.full((120, 120, 3), 35, dtype=np.uint8)
    enhanced = enhance_indoor_illumination(dark_img)
    assert enhanced.shape == dark_img.shape
    # Mean luminance should increase
    assert np.mean(enhanced) > np.mean(dark_img)

def test_normalize_face_crop_illumination():
    from app.ml.preprocessing import normalize_face_crop_illumination
    crop = np.full((112, 112, 3), 60, dtype=np.uint8)
    norm_crop = normalize_face_crop_illumination(crop)
    assert norm_crop.shape == (112, 112, 3)

def test_evaluate_face_crop_quality():
    from app.ml.preprocessing import evaluate_face_crop_quality
    # Create image with a clear face-like region
    img = np.full((300, 300, 3), 100, dtype=np.uint8)
    cv2.circle(img, (150, 150), 45, (180, 180, 180), -1)
    cv2.putText(img, "FACE", (120, 155), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (40, 40, 40), 2)
    
    bbox = np.array([100, 100, 200, 200], dtype=np.float32)
    landmarks = np.array([
        [130, 130],
        [170, 130],
        [150, 150],
        [135, 175],
        [165, 175]
    ], dtype=np.float32)

    is_ok, score, msg, metrics = evaluate_face_crop_quality(img, bbox, landmarks)
    assert is_ok is True
    assert score > 0.0
    assert "face_brightness" in metrics
    assert "face_sharpness" in metrics

def test_face_pipeline_latency():
    from app.ml.pipeline import face_pipeline
    # Valid synthetic JPEG frame
    img = np.full((480, 640, 3), 100, dtype=np.uint8)
    _, enc = cv2.imencode('.jpg', img)
    res = face_pipeline.process_single_frame(enc.tobytes())
    # Even if no face detected in blank image, latency telemetry must be populated
    assert "decode_ms" in res.latency_ms
    assert res.latency_ms["decode_ms"] >= 0.0

