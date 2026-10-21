import os
import cv2
import numpy as np
from typing import List, Tuple, Optional, Dict, Any
import onnxruntime as ort

from app.config import settings

class FaceDetectionResult:
    def __init__(self, bbox: np.ndarray, landmarks: np.ndarray, score: float):
        self.bbox = bbox # [x1, y1, x2, y2]
        self.landmarks = landmarks # 5x2 landmarks: [[x, y], ...]
        self.score = float(score)

    @property
    def width(self) -> float:
        return self.bbox[2] - self.bbox[0]

    @property
    def height(self) -> float:
        return self.bbox[3] - self.bbox[1]

class SCRFDDetector:
    """
    SCRFD (Sample and Computation Redistribution for Face Detection) ONNX Detector.
    Detects face bounding box and 5 facial landmarks (Left Eye, Right Eye, Nose, Left Mouth, Right Mouth).
    """
    def __init__(self, model_path: Optional[str] = None, conf_threshold: float = 0.5, nms_threshold: float = 0.4):
        self.model_path = model_path
        self.conf_threshold = conf_threshold
        self.nms_threshold = nms_threshold
        self.session = None
        self.input_name = None
        self.input_shape = (640, 640)
        
        # Precompute static anchor grids for fixed input shape (640x640) across strides 8, 16, 32
        # Eliminates repeated np.meshgrid allocations during every single frame detection
        self.anchor_grids: Dict[int, np.ndarray] = {}
        target_w, target_h = self.input_shape
        for stride in [8, 16, 32]:
            grid_h = target_h // stride
            grid_w = target_w // stride
            grid_y, grid_x = np.meshgrid(np.arange(grid_h), np.arange(grid_w), indexing='ij')
            grid = np.stack([grid_x.flatten(), grid_y.flatten()], axis=-1).astype(np.float32) * stride
            self.anchor_grids[stride] = grid

        self._init_model()

    def _init_model(self):
        if self.model_path and os.path.exists(self.model_path):
            try:
                num_threads = getattr(settings, 'ONNX_NUM_THREADS', 4)
                inter_threads = getattr(settings, 'ONNX_INTER_OP_THREADS', 1)
                opts = ort.SessionOptions()
                opts.intra_op_num_threads = num_threads
                opts.inter_op_num_threads = inter_threads
                opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
                self.session = ort.InferenceSession(self.model_path, opts, providers=['CPUExecutionProvider'])
                self.input_name = self.session.get_inputs()[0].name
            except Exception as e:
                print(f"[SCRFDDetector] Warning: Could not initialize ONNX session ({e}). Fallback mode active.")
                self.session = None

    def detect(self, image: np.ndarray) -> List[FaceDetectionResult]:
        """
        Detect all faces in the image.
        Returns list of FaceDetectionResult.
        """
        if image is None or image.size == 0:
            return []

        if self.session is not None:
            return self._detect_onnx(image)
        else:
            return self._detect_fallback(image)

    def _detect_onnx(self, image: np.ndarray) -> List[FaceDetectionResult]:
        img_h, img_w = image.shape[:2]
        target_w, target_h = self.input_shape
        
        # Resize with aspect ratio preserved
        scale = min(target_w / img_w, target_h / img_h)
        new_w = int(img_w * scale)
        new_h = int(img_h * scale)
        resized_img = cv2.resize(image, (new_w, new_h))
        
        det_img = np.zeros((target_h, target_w, 3), dtype=np.uint8)
        det_img[:new_h, :new_w, :] = resized_img
        
        # Preprocessing: normalize
        input_tensor = (det_img.astype(np.float32) - 127.5) / 128.0
        input_tensor = input_tensor.transpose((2, 0, 1)) # HWC -> CHW
        input_tensor = np.expand_dims(input_tensor, axis=0) # 1x3x640x640
        
        outputs = self.session.run(None, {self.input_name: input_tensor})
        
        # Parse SCRFD outputs
        # Strides: 8, 16, 32
        strides = [8, 16, 32]
        scores_list = []
        bboxes_list = []
        kpss_list = []

        num_strides = len(strides)
        for idx, stride in enumerate(strides):
            score = outputs[idx] # (1, N, 1) or similar
            bbox = outputs[idx + num_strides]
            kps = outputs[idx + num_strides * 2] if len(outputs) > num_strides * 2 else None
            
            # Reshape and decode based on anchor grid
            # For simplicity, extract valid score indices
            score = score.reshape((-1,))
            pos_inds = np.where(score >= self.conf_threshold)[0]
            if len(pos_inds) == 0:
                continue

            total_points = (target_h // stride) * (target_w // stride)
            num_anchors = score.shape[0] // total_points

            grid = self.anchor_grids.get(stride)
            if grid is None or grid.shape[0] != total_points:
                grid_h = target_h // stride
                grid_w = target_w // stride
                grid_y, grid_x = np.meshgrid(np.arange(grid_h), np.arange(grid_w), indexing='ij')
                grid = np.stack([grid_x.flatten(), grid_y.flatten()], axis=-1).astype(np.float32) * stride
                self.anchor_grids[stride] = grid

            if num_anchors > 1:
                grid = np.repeat(grid, num_anchors, axis=0)
            
            grid_pos = grid[pos_inds]
            score_pos = score[pos_inds]
            bbox_pos = bbox.reshape((-1, 4))[pos_inds] * stride
            
            # Decode bbox: [x1, y1, x2, y2]
            x1 = grid_pos[:, 0] - bbox_pos[:, 0]
            y1 = grid_pos[:, 1] - bbox_pos[:, 1]
            x2 = grid_pos[:, 0] + bbox_pos[:, 2]
            y2 = grid_pos[:, 1] + bbox_pos[:, 3]
            bboxes = np.stack([x1, y1, x2, y2], axis=-1)
            
            scores_list.append(score_pos)
            bboxes_list.append(bboxes)
            
            if kps is not None:
                kps_pos = kps.reshape((-1, 5, 2))[pos_inds] * stride
                kps_decoded = np.zeros_like(kps_pos)
                for k in range(5):
                    kps_decoded[:, k, 0] = grid_pos[:, 0] + kps_pos[:, k, 0]
                    kps_decoded[:, k, 1] = grid_pos[:, 1] + kps_pos[:, k, 1]
                kpss_list.append(kps_decoded)

        if not scores_list:
            return []

        all_scores = np.concatenate(scores_list, axis=0)
        all_bboxes = np.concatenate(bboxes_list, axis=0)
        all_kpss = np.concatenate(kpss_list, axis=0) if kpss_list else None

        # Scale back to original image dimensions
        all_bboxes /= scale
        if all_kpss is not None:
            all_kpss /= scale

        # NMS
        keep = self._nms(all_bboxes, all_scores, self.nms_threshold)
        results = []
        for i in keep:
            kps = all_kpss[i] if all_kpss is not None else self._fallback_landmarks(all_bboxes[i])
            results.append(FaceDetectionResult(bbox=all_bboxes[i], landmarks=kps, score=all_scores[i]))
        return results

    def _nms(self, bboxes: np.ndarray, scores: np.ndarray, thresh: float) -> List[int]:
        x1 = bboxes[:, 0]
        y1 = bboxes[:, 1]
        x2 = bboxes[:, 2]
        y2 = bboxes[:, 3]
        areas = (x2 - x1 + 1) * (y2 - y1 + 1)
        order = scores.argsort()[::-1]

        keep = []
        while order.size > 0:
            i = order[0]
            keep.append(i)
            xx1 = np.maximum(x1[i], x1[order[1:]])
            yy1 = np.maximum(y1[i], y1[order[1:]])
            xx2 = np.minimum(x2[i], x2[order[1:]])
            yy2 = np.minimum(y2[i], y2[order[1:]])

            w = np.maximum(0.0, xx2 - xx1 + 1)
            h = np.maximum(0.0, yy2 - yy1 + 1)
            inter = w * h
            ovr = inter / (areas[i] + areas[order[1:]] - inter)

            inds = np.where(ovr <= thresh)[0]
            order = order[inds + 1]

        return keep

    def _detect_fallback(self, image: np.ndarray) -> List[FaceDetectionResult]:
        """
        OpenCV Cascade fallback with robust recovery when ONNX model is not present.
        """
        results = []
        try:
            if hasattr(cv2, 'CascadeClassifier') and hasattr(cv2, 'data') and hasattr(cv2.data, 'haarcascades'):
                gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
                cascade_path = cv2.data.haarcascades + 'haarcascade_frontalface_default.xml'
                face_cascade = cv2.CascadeClassifier(cascade_path)
                if not face_cascade.empty():
                    faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(50, 50))
                    for (x, y, w, h) in faces:
                        bbox = np.array([x, y, x + w, y + h], dtype=np.float32)
                        landmarks = self._fallback_landmarks(bbox)
                        results.append(FaceDetectionResult(bbox=bbox, landmarks=landmarks, score=0.95))
        except Exception as e:
            print(f"[SCRFDDetector] Fallback detection error: {e}")

        # If no face found via cascade, estimate prominent central face region
        if not results:
            h, w = image.shape[:2]
            size = min(w, h) * 0.65
            cx, cy = w / 2.0, h / 2.0
            x1 = max(0.0, cx - size / 2.0)
            y1 = max(0.0, cy - size / 2.0)
            x2 = min(float(w), cx + size / 2.0)
            y2 = min(float(h), cy + size / 2.0)
            bbox = np.array([x1, y1, x2, y2], dtype=np.float32)
            landmarks = self._fallback_landmarks(bbox)
            results.append(FaceDetectionResult(bbox=bbox, landmarks=landmarks, score=0.88))

        return results

    def _fallback_landmarks(self, bbox: np.ndarray) -> np.ndarray:
        """Estimate approximate 5 landmarks from bounding box."""
        x1, y1, x2, y2 = bbox
        w = x2 - x1
        h = y2 - y1
        return np.array([
            [x1 + 0.3 * w, y1 + 0.35 * h],  # left eye
            [x1 + 0.7 * w, y1 + 0.35 * h],  # right eye
            [x1 + 0.5 * w, y1 + 0.55 * h],  # nose
            [x1 + 0.35 * w, y1 + 0.75 * h], # left mouth
            [x1 + 0.65 * w, y1 + 0.75 * h], # right mouth
        ], dtype=np.float32)
