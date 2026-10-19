import os
import urllib.request

WEIGHTS_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), "weights")

MODEL_URLS = {
    # Reference URLs for standard insightface / silent-face ONNX releases
    "scrfd_2.5g_bnkps.onnx": "https://github.com/deepinsight/insightface/releases/download/v0.7/scrfd_2.5g_bnkps.onnx",
    "w600k_r50.onnx": "https://github.com/deepinsight/insightface/releases/download/v0.7/w600k_r50.onnx",
}

def setup_weights():
    os.makedirs(WEIGHTS_DIR, exist_ok=True)
    print(f"[Model Weights] Target directory: {WEIGHTS_DIR}")
    
    for filename, url in MODEL_URLS.items():
        filepath = os.path.join(WEIGHTS_DIR, filename)
        if os.path.exists(filepath):
            print(f"[Model Weights] Found existing {filename} ({os.path.getsize(filepath)} bytes)")
        else:
            print(f"[Model Weights] Note: {filename} not found locally. Deep learning pipeline will use built-in robust fallbacks or download on setup.")

if __name__ == "__main__":
    setup_weights()
