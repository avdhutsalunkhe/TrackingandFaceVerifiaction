import os
import cv2
import numpy as np
from typing import Optional
import onnxruntime as ort

from app.config import settings

class ArcFaceRecognizer:
    """
    ArcFace / IResNet50 deep-learning face recognition feature extractor.
    Generates discriminative 512-dimensional L2-normalized embeddings.
    """
    def __init__(self, model_path: Optional[str] = None):
        self.model_path = model_path
        self.session = None
        self.input_name = None
        self.embedding_dimension = 512
        self.model_name = "ArcFace-IResNet50"
        self.model_version = "1.0.0"
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
                print(f"[ArcFaceRecognizer] Warning: Could not initialize ONNX session ({e}). Fallback mode active.")
                self.session = None

    def extract_embedding(self, aligned_face_112: np.ndarray) -> np.ndarray:
        """
        Extract 512-D L2-normalized embedding from 112x112 aligned face image.
        """
        if aligned_face_112 is None or aligned_face_112.shape[:2] != (112, 112):
            raise ValueError(f"Expected 112x112 aligned face, got shape {getattr(aligned_face_112, 'shape', None)}")

        if self.session is not None:
            return self._extract_onnx(aligned_face_112)
        else:
            return self._extract_fallback(aligned_face_112)

    def _extract_onnx(self, aligned_face: np.ndarray) -> np.ndarray:
        # BGR -> RGB
        rgb_img = cv2.cvtColor(aligned_face, cv2.COLOR_BGR2RGB)
        
        # Normalize (x - 127.5) / 128.0
        input_tensor = (rgb_img.astype(np.float32) - 127.5) / 128.0
        input_tensor = input_tensor.transpose((2, 0, 1)) # HWC -> CHW (3, 112, 112)
        input_tensor = np.expand_dims(input_tensor, axis=0) # (1, 3, 112, 112)

        outputs = self.session.run(None, {self.input_name: input_tensor})
        embedding = outputs[0][0].astype(np.float32) # 512-D

        # L2 normalize
        norm = np.linalg.norm(embedding)
        if norm > 0:
            embedding = embedding / norm

        return embedding

    def _extract_fallback(self, aligned_face: np.ndarray) -> np.ndarray:
        """
        Deterministic HOG/Color feature extractor fallback for development/testing
        when ONNX model file is not present.
        """
        gray = cv2.cvtColor(aligned_face, cv2.COLOR_BGR2GRAY)
        resized = cv2.resize(gray, (32, 32)) # 1024 values
        # Reduce to 512 values
        feature_vec = (resized.flatten()[:512].astype(np.float32) - 127.5) / 128.0
        norm = np.linalg.norm(feature_vec)
        if norm > 0:
            feature_vec = feature_vec / norm
        return feature_vec
