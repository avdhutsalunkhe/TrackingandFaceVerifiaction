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
        print(f"[ModelsManager] Liveness Engine: {live_mode}")

    @classmethod
    def get_instance(cls) -> 'ModelsManager':
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

models_manager = ModelsManager.get_instance()
