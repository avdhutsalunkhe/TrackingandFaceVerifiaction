import cv2
import numpy as np

# Standard 112x112 reference landmarks for ArcFace / InsightFace (5 landmarks: [left_eye, right_eye, nose, left_mouth, right_mouth])
ARCFACE_REFERENCE_LANDMARKS = np.array([
    [38.2946, 51.6963],  # Left Eye
    [73.5318, 51.5014],  # Right Eye
    [56.0252, 71.7366],  # Nose Tip
    [41.5493, 92.3655],  # Left Mouth Corner
    [70.7299, 92.2041]   # Right Mouth Corner
], dtype=np.float32)

def umeyama(src: np.ndarray, dst: np.ndarray) -> np.ndarray:
    """
    Computes exact 2D similarity transformation matrix (scale, rotation, translation)
    using Umeyama's algorithm. Guaranteed deterministic closed-form solution.
    """
    num = src.shape[0]
    dim = src.shape[1]
    src_mean = src.mean(axis=0)
    dst_mean = dst.mean(axis=0)
    src_demean = src - src_mean
    dst_demean = dst - dst_mean
    A = np.dot(dst_demean.T, src_demean) / num
    d = np.ones(dim)
    if np.linalg.det(A) < 0:
        d[dim - 1] = -1
    T = np.eye(dim + 1)
    U, S, V = np.linalg.svd(A)
    rank = np.linalg.matrix_rank(A)
    if rank == 0:
        return np.array([[1.0, 0.0, 0.0], [0.0, 1.0, 0.0]], dtype=np.float32)
    elif rank == dim - 1:
        if np.linalg.det(U) * np.linalg.det(V) > 0:
            T[:dim, :dim] = np.dot(U, V)
        else:
            s = d[dim - 1]
            d[dim - 1] = -1
            T[:dim, :dim] = np.dot(U, np.dot(np.diag(d), V))
            d[dim - 1] = s
    else:
        T[:dim, :dim] = np.dot(U, np.dot(np.diag(d), V))
    scale = 1.0 / max(src_demean.var(axis=0).sum(), 1e-8) * np.dot(S, d)
    T[:dim, dim] = dst_mean - scale * np.dot(T[:dim, :dim], src_mean)
    T[:dim, :dim] *= scale
    return T[:2, :]

def estimate_norm(landmarks: np.ndarray, image_size: int = 112) -> np.ndarray:
    """
    Computes standard similarity transformation matrix using Umeyama algorithm.
    """
    assert landmarks.shape == (5, 2)
    src = ARCFACE_REFERENCE_LANDMARKS
    if image_size != 112:
        src = src * (image_size / 112.0)
    
    # Try OpenCV estimateAffinePartial2D with RANSAC fallback
    M, _ = cv2.estimateAffinePartial2D(landmarks, src, method=cv2.LMEDS)
    if M is None:
        M, _ = cv2.estimateAffinePartial2D(landmarks, src, method=cv2.RANSAC, ransacReprojThreshold=100.0)
    if M is None:
        M = umeyama(landmarks, src)
    return M

def align_face_112(image: np.ndarray, landmarks: np.ndarray) -> np.ndarray:
    """
    Align face into a normalized 112x112 crop using 5 facial landmarks.
    Ensures consistent canonical eye, nose, and mouth placement across all faces.
    """
    M = estimate_norm(landmarks, image_size=112)
    if M is None:
        # Fallback to crop if transform estimation fails completely
        x_min = int(max(0, np.min(landmarks[:, 0]) - 20))
        y_min = int(max(0, np.min(landmarks[:, 1]) - 20))
        x_max = int(min(image.shape[1], np.max(landmarks[:, 0]) + 20))
        y_max = int(min(image.shape[0], np.max(landmarks[:, 1]) + 20))
        crop = image[y_min:y_max, x_min:x_max]
        return cv2.resize(crop, (112, 112))

    aligned = cv2.warpAffine(image, M, (112, 112), borderValue=0.0)
    return aligned

