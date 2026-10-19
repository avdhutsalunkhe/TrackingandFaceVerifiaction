import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cv2
import numpy as np
from app.ml.models_manager import models_manager
from app.ml.pipeline import face_pipeline
from app.ml.similarity import compute_cosine_similarity
from app.ml.preprocessing import compress_to_jpeg

tpl_cv = cv2.imread('dump_user6_face.jpg')
tpl_emb = models_manager.recognizer.extract_embedding(tpl_cv)

req_img = cv2.imread('exports/latest/images/evidence_requests/request_11_emp_31675_2026-09-22.jpg')
print("Original image shape:", req_img.shape)

# Test 1: Normal upright
jpeg_0 = compress_to_jpeg(req_img)
res_0 = face_pipeline.process_single_frame(jpeg_0)
sim_0 = compute_cosine_similarity(tpl_emb, res_0.embedding) if res_0.success else None
print(f"Normal (0 deg): Success={res_0.success}, Sim={sim_0}")

# Test 2: Rotated 90 deg CW
img_90 = cv2.rotate(req_img, cv2.ROTATE_90_CLOCKWISE)
jpeg_90 = compress_to_jpeg(img_90)
res_90 = face_pipeline.process_single_frame(jpeg_90)
sim_90 = compute_cosine_similarity(tpl_emb, res_90.embedding) if res_90.success else None
print(f"Rotated 90 deg CW: Success={res_90.success}, Sim={sim_90}, Error={res_90.error_code} {res_90.error_message}")

# Test 3: Rotated 180 deg
img_180 = cv2.rotate(req_img, cv2.ROTATE_180)
jpeg_180 = compress_to_jpeg(img_180)
res_180 = face_pipeline.process_single_frame(jpeg_180)
sim_180 = compute_cosine_similarity(tpl_emb, res_180.embedding) if res_180.success else None
print(f"Rotated 180 deg: Success={res_180.success}, Sim={sim_180}, Error={res_180.error_code} {res_180.error_message}")

# Test 4: Rotated 270 deg CW (90 CCW)
img_270 = cv2.rotate(req_img, cv2.ROTATE_90_COUNTERCLOCKWISE)
jpeg_270 = compress_to_jpeg(img_270)
res_270 = face_pipeline.process_single_frame(jpeg_270)
sim_270 = compute_cosine_similarity(tpl_emb, res_270.embedding) if res_270.success else None
print(f"Rotated 270 deg CW: Success={res_270.success}, Sim={sim_270}, Error={res_270.error_code} {res_270.error_message}")

# Test 5: Horizontal flip (mirroring)
img_flip = cv2.flip(req_img, 1)
jpeg_flip = compress_to_jpeg(img_flip)
res_flip = face_pipeline.process_single_frame(jpeg_flip)
sim_flip = compute_cosine_similarity(tpl_emb, res_flip.embedding) if res_flip.success else None
print(f"Mirrored (Flip H): Success={res_flip.success}, Sim={sim_flip}")

# Test 6: RGB vs BGR inversion in ArcFace
# If an image is passed as RGB into extract_embedding (which treats it as BGR and converts it to RGB, resulting in swapped R and B channels)
bgr_swapped = cv2.cvtColor(tpl_cv, cv2.COLOR_BGR2RGB)
emb_swapped = models_manager.recognizer.extract_embedding(bgr_swapped)
sim_color = compute_cosine_similarity(tpl_emb, emb_swapped)
print(f"Color channel swap (BGR <-> RGB): Sim={sim_color}")
