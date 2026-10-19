import io
import cv2
import numpy as np
from PIL import Image, ImageOps
from typing import Tuple, Optional

def decode_image_bytes(image_bytes: bytes) -> Optional[np.ndarray]:
    """
    Decode raw image bytes (JPEG/PNG) into an OpenCV BGR numpy array.
    Automatically applies EXIF orientation normalization (handles portrait/landscape
    orientation tags written by Android Camera2 and iOS camera plugins).
    """
    if not image_bytes:
        return None
    try:
        pil_img = Image.open(io.BytesIO(image_bytes))
        pil_img = ImageOps.exif_transpose(pil_img)
        if pil_img.mode != 'RGB':
            pil_img = pil_img.convert('RGB')
        rgb_arr = np.array(pil_img)
        return cv2.cvtColor(rgb_arr, cv2.COLOR_RGB2BGR)
    except Exception:
        # Fallback to direct OpenCV imdecode if PIL decoding fails
        nparr = np.frombuffer(image_bytes, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        return image

from app.config import settings

def enhance_indoor_illumination(image: np.ndarray, clip_limit: float = 2.0) -> np.ndarray:
    """
    Adaptive illumination normalization & contrast enhancement for adverse indoor lighting.
    Improves face detection and feature stability in dim rooms, high-ISO noise, or uneven lighting.
    """
    if image is None or image.size == 0:
        return image

    # Convert BGR to LAB color space
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)

    mean_l = np.mean(l_channel)

    # Adaptive CLAHE (Contrast Limited Adaptive Histogram Equalization) on L channel
    clahe = cv2.createCLAHE(clipLimit=clip_limit, tileGridSize=(8, 8))
    enhanced_l = clahe.apply(l_channel)

    # If scene is noticeably dark (mean L < 95), apply adaptive gamma correction to lift shadows
    if mean_l < 95.0 and mean_l > 5.0:
        gamma = float(np.clip(np.log(0.50) / np.log(max(mean_l, 10.0) / 255.0), 0.50, 0.85))
        table = np.array([((i / 255.0) ** gamma) * 255 for i in range(256)]).astype("uint8")
        enhanced_l = cv2.LUT(enhanced_l, table)

    # Merge back and convert to BGR
    merged_lab = cv2.merge([enhanced_l, a_channel, b_channel])
    enhanced_bgr = cv2.cvtColor(merged_lab, cv2.COLOR_LAB2BGR)
    return enhanced_bgr

def normalize_face_crop_illumination(face_crop_112: np.ndarray) -> np.ndarray:
    """
    Standardize illumination & contrast on the aligned 112x112 face crop prior to
    ArcFace embedding extraction. Makes feature representations invariant to indoor light variations.
    """
    if face_crop_112 is None or face_crop_112.shape[:2] != (112, 112):
        return face_crop_112

    lab = cv2.cvtColor(face_crop_112, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    
    # Mild CLAHE on face crop to balance highlights and shadows without over-sharpening
    clahe = cv2.createCLAHE(clipLimit=1.6, tileGridSize=(4, 4))
    l_norm = clahe.apply(l)

    # Denoise high-ISO sensor grain if luminance is low
    mean_l = np.mean(l)
    if mean_l < 80.0:
        l_norm = cv2.GaussianBlur(l_norm, (3, 3), 0.5)

    merged = cv2.merge([l_norm, a, b])
    return cv2.cvtColor(merged, cv2.COLOR_LAB2BGR)

def evaluate_face_crop_quality(
    image: np.ndarray,
    bbox: np.ndarray,
    landmarks: Optional[np.ndarray] = None
) -> Tuple[bool, float, str, dict]:
    """
    Comprehensive face-centric biometric quality evaluation:
    - Face bounding box resolution
    - Face region brightness (independent of background)
    - Face sharpness / blur via localized Laplacian variance
    - Head pose symmetry (frontal face angle via eye-to-nose distances)
    - Head roll angle (eye tilt)
    - Border margin verification
    """
    if image is None or image.size == 0 or bbox is None:
        return False, 0.0, "No face region provided", {}

    img_h, img_w = image.shape[:2]
    x1, y1, x2, y2 = [int(v) for v in bbox]
    x1, y1 = max(0, x1), max(0, y1)
    x2, y2 = min(img_w, x2), min(img_h, y2)

    face_w = x2 - x1
    face_h = y2 - y1

    min_size = getattr(settings, 'MIN_FACE_SIZE', 80)
    if face_w < min_size or face_h < min_size:
        return False, 0.2, "Face too far. Move closer to the camera.", {
            "face_width": face_w, "face_height": face_h, "min_required": min_size
        }

    # Extract face crop
    face_crop = image[y1:y2, x1:x2]
    if face_crop.size == 0:
        return False, 0.0, "Invalid face bounding box", {}

    gray_face = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY)

    # 1. Face region illumination check
    face_brightness = float(np.mean(gray_face))
    min_brightness = getattr(settings, 'MIN_FACE_BRIGHTNESS', 28.0)
    if face_brightness < min_brightness:
        return False, float(face_brightness / 100.0), "Lighting too dim. Please face a light source.", {
            "face_brightness": round(face_brightness, 1), "min_required": min_brightness
        }
    if face_brightness > 245.0:
        return False, 0.3, "Lighting too bright/overexposed. Adjust room light.", {
            "face_brightness": round(face_brightness, 1)
        }

    # 2. Localized face sharpness (Laplacian variance)
    face_sharpness = float(cv2.Laplacian(gray_face, cv2.CV_64F).var())
    min_sharpness = getattr(settings, 'MIN_FACE_SHARPNESS', 12.0)
    if face_sharpness < min_sharpness:
        return False, float(min(1.0, face_sharpness / 50.0)), "Image blurry. Please hold phone steady.", {
            "face_sharpness": round(face_sharpness, 1), "min_required": min_sharpness
        }

    # 3. Head pose frontal check via landmarks (if available)
    pose_ok = True
    pose_ratio = 1.0
    roll_deg = 0.0
    if landmarks is not None and len(landmarks) >= 5:
        left_eye = landmarks[0]
        right_eye = landmarks[1]
        nose = landmarks[2]

        d_left = abs(nose[0] - left_eye[0])
        d_right = abs(right_eye[0] - nose[0])
        
        if d_right > 0:
            pose_ratio = d_left / d_right
            # Extreme yaw (looking sideways)
            if pose_ratio < 0.35 or pose_ratio > 2.85:
                pose_ok = False
                return False, 0.4, "Please look directly at the camera.", {
                    "pose_ratio": round(pose_ratio, 2)
                }

        # 4. Head roll angle check (in-plane tilt)
        dx = float(right_eye[0] - left_eye[0])
        dy = float(right_eye[1] - left_eye[1])
        roll_deg = float(np.degrees(np.arctan2(dy, dx)))
        if abs(roll_deg) > 28.0:
            return False, 0.4, "Please hold phone upright and look straight at the camera.", {
                "head_roll_deg": round(roll_deg, 1)
            }

    # Compute continuous quality score [0.0 - 1.0]
    sharpness_factor = min(1.0, face_sharpness / 80.0)
    brightness_factor = min(1.0, face_brightness / 120.0)
    size_factor = min(1.0, face_w / 200.0)
    quality_score = float(np.clip(sharpness_factor * 0.45 + brightness_factor * 0.35 + size_factor * 0.20, 0.1, 1.0))

    metrics = {
        "face_brightness": round(face_brightness, 1),
        "face_sharpness": round(face_sharpness, 1),
        "face_width": face_w,
        "face_height": face_h,
        "pose_ratio": round(pose_ratio, 2),
        "head_roll_deg": round(roll_deg, 1),
        "quality_score": round(quality_score, 3)
    }

    return True, quality_score, "OK", metrics

def check_image_quality(image: np.ndarray) -> Tuple[bool, float, str]:
    """
    Fast pre-filter for initial frame validity (minimum resolution, corruption, pitch-black frames).
    """
    if image is None or image.size == 0:
        return False, 0.0, "Empty image"

    h, w = image.shape[:2]
    if h < 100 or w < 100:
        return False, 0.0, f"Image resolution too low ({w}x{h})"

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    
    # Global brightness check (allow darker indoor scenes; adaptive enhancement handles the rest)
    mean_brightness = float(np.mean(gray))
    if mean_brightness < 12.0:
        return False, float(mean_brightness), "Image is too dark. Please face a light source."
    if mean_brightness > 248.0:
        return False, float(mean_brightness), "Image is overexposed."

    # Whole frame blur check
    laplacian_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    if laplacian_var < 8.0:
        return False, float(laplacian_var), "Image is too blurry. Hold phone steady."

    quality_score = float(min(1.0, (laplacian_var / 150.0) * 0.5 + (mean_brightness / 128.0) * 0.5))
    return True, quality_score, "OK"

def compress_to_jpeg(image: np.ndarray, quality: int = 90) -> bytes:
    """Encode OpenCV BGR image into JPEG bytes."""
    encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), quality]
    success, encimg = cv2.imencode('.jpg', image, encode_param)
    if not success:
        raise ValueError("Failed to encode image to JPEG")
    return encimg.tobytes()
