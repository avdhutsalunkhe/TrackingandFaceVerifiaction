import os
from typing import Optional
from app.config import settings
from app.ml.detector import SCRFDDetector
from app.ml.recognition import ArcFaceRecognizer
from app.ml.liveness import LivenessDetector

class ModelsManager:
    _instance: Optional['ModelsManager'] = None

    def _find_weight_file(self, weights_dir: str, primary_filename: str, fallback_prefixes: list) -> Optional[str]:
        primary_path = os.path.join(weights_dir, primary_filename)
        if os.path.exists(primary_path):
            return primary_path
        
        # Check files in weights directory for match
        if os.path.isdir(weights_dir):
            files = os.listdir(weights_dir)
            for f in files:
                if not f.endswith('.onnx'):
                    continue
                for prefix in fallback_prefixes:
                    if prefix.lower() in f.lower():
                        found = os.path.join(weights_dir, f)
                        print(f"[ModelsManager] Auto-discovered model for '{primary_filename}': {f}")
                        return found
        return None

    def __init__(self):
        weights_dir = settings.ML_WEIGHTS_DIR
        os.makedirs(weights_dir, exist_ok=True)

        detector_path = self._find_weight_file(
            weights_dir,
            settings.FACE_DETECTOR_MODEL,
            ['det_500m', 'scrfd_2.5g', 'scrfd_500m', 'scrfd', 'detector']
        )
        recognizer_path = self._find_weight_file(
            weights_dir,
            settings.FACE_RECOGNITION_MODEL,
            ['w600k_mbf', 'w600k_r50', 'w600k', 'arcface', 'mobilefacenet', 'recognizer']
        )
        liveness_path = self._find_weight_file(
            weights_dir,
            settings.ANTI_SPOOFING_MODEL,
            ['MiniFASNet', 'antispoof', 'spoof', 'liveness']
        )

        print(f"[ModelsManager] Initializing biometric models from {weights_dir}...")
        self.detector = SCRFDDetector(model_path=detector_path)
        self.recognizer = ArcFaceRecognizer(model_path=recognizer_path)
        self.liveness = LivenessDetector(model_path=liveness_path)

        det_mode = "ONNX ACTIVE (High Performance)" if self.detector.session else "Fallback Mode"
        rec_mode = "ONNX ACTIVE (ArcFace 512-D)" if self.recognizer.session else "Fallback Mode"
        live_mode = "ONNX ACTIVE (Deep Anti-Spoof)" if self.liveness.session else "Fallback Mode (Active Temporal & Texture)"

        print(f"[ModelsManager] Face Detector:   {det_mode}")
        print(f"[ModelsManager] Face Recognizer: {rec_mode}")
        self.is_warmed_up = False

    def warmup(self):
        """
        Execute controlled dummy forward passes across all models during startup.
        Initializes ONNX runtime execution graphs, memory arenas, kernel selectors,
        and OpenCV worker threads to eliminate the 200+ ms cold start penalty on first request.
        """
        if self.is_warmed_up:
            return

        import cv2
        import numpy as np
        from app.ml.alignment import align_face_112
        from app.ml.preprocessing import normalize_face_crop_illumination

        try:
            # 1. Warm up SCRFD detector
            dummy_img = np.zeros((640, 640, 3), dtype=np.uint8)
            cv2.circle(dummy_img, (320, 320), 120, (180, 180, 180), -1)
            cv2.putText(dummy_img, "WARMUP", (240, 330), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (50, 50, 50), 2)
            self.detector.detect(dummy_img)

            # 2. Warm up 5-point Umeyama alignment & OpenCV CLAHE
            dummy_lm = np.array([[220, 240], [340, 240], [280, 290], [240, 350], [320, 350]], dtype=np.float32)
            aligned = align_face_112(dummy_img, dummy_lm)
            norm_aligned = normalize_face_crop_illumination(aligned)

            # 3. Warm up ArcFace recognizer
            self.recognizer.extract_embedding(norm_aligned)

            # 4. Warm up Anti-Spoofing engine
            self.liveness.evaluate_passive_antispoof(norm_aligned)

            self.is_warmed_up = True
            print("[ModelsManager] Controlled model warmup completed successfully.")
        except Exception as e:
            print(f"[ModelsManager] Model warmup warning: {e}")

    @classmethod
    def get_instance(cls) -> 'ModelsManager':
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

models_manager = ModelsManager.get_instance()
