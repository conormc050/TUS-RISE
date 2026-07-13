"""Windows prototype: SpinePose 2D keypoints + Depth Anything V2 → 3D spine.

Setup (one-off):
    git clone https://github.com/DepthAnything/Depth-Anything-V2
    pip install -r Depth-Anything-V2/requirements.txt
    # Metric checkpoint (indoor/gym): depth_anything_v2_metric_hypersim_vits.pth
    # from the repo's metric_depth section. The non-metric checkpoints give
    # RELATIVE depth only — fine for ordering/plane checks, not for meters.

This is a template — adjust paths, then fold the working parts into VidCalc.py.
"""

import cv2
import numpy as np
import torch

from unproject_keypoints import (
    estimate_intrinsics, lift_keypoints_3d, angle_3d, Keypoint3DSmoother,
)
from spinepose import SpinePoseEstimator

# --- Depth Anything V2 metric model (indoor) ---
# sys.path.append(r"path\to\Depth-Anything-V2\metric_depth")
from depth_anything_v2.dpt import DepthAnythingV2

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
depth_model = DepthAnythingV2(
    encoder="vits",
    features=64,
    out_channels=[48, 96, 192, 384],
    max_depth=20.0,          # metric head: meters, indoor config
)
depth_model.load_state_dict(
    torch.load("depth_anything_v2_metric_hypersim_vits.pth", map_location="cpu")
)
depth_model = depth_model.to(DEVICE).eval()

estimator = SpinePoseEstimator(mode="small")
SPINE_IDS = estimator.SPINE_IDS

VIDEO_PATH = r"C:\Users\conor\Downloads\Squat3.mp4"
cap = cv2.VideoCapture(VIDEO_PATH)
w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
fps = cap.get(cv2.CAP_PROP_FPS) or 30.0

K = estimate_intrinsics(w, h)          # replace with real intrinsics when known
smoother = Keypoint3DSmoother(n_keypoints=len(SPINE_IDS), freq=fps)

frame_idx = 0
while True:
    ret, frame = cap.read()
    if not ret:
        break
    frame_idx += 1

    # Depth Anything expects RGB; infer_image handles resize internally
    depth = depth_model.infer_image(frame)      # (h, w) float32, meters (metric ckpt)

    keypoints, scores = estimator(frame)
    if len(keypoints) == 0:
        continue

    spine_2d = [keypoints[0][i] for i in SPINE_IDS]
    spine_scores = [scores[0][i] for i in SPINE_IDS]

    pts_3d = lift_keypoints_3d(
        spine_2d, spine_scores, depth, K,
        rgb_size=(w, h), depth_size=(depth.shape[1], depth.shape[0]),
    )
    pts_3d = smoother(pts_3d, frame_idx / fps)

    # --- Sanity check (run this before trusting anything downstream) ---
    # Spine keypoints are near co-planar on a real torso. A point >0.3 m off
    # the plane of its neighbours = edge pixel grabbed background depth.
    valid = [p for p in pts_3d if p is not None]
    if len(valid) >= 3:
        zs = [p[2] for p in valid]
        spread = max(zs) - min(zs)
        if spread > 0.5:
            print(f"frame {frame_idx}: depth spread {spread:.2f} m — sampling bug likely")

cap.release()
