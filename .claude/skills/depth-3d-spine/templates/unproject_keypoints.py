"""Core 2D→3D lifting utilities for LiftIQ.

Camera-space convention (project standard): x right, y down, z forward, meters.
These functions are pure math — no model dependencies — so they port 1:1 to Swift.
"""

import numpy as np

try:
    from OneEuroFilter import OneEuroFilter  # already installed in the project venv
except ImportError:
    OneEuroFilter = None


def estimate_intrinsics(width, height, fov_scale=1.2):
    """Fallback intrinsics for uncalibrated video. fx ≈ 1.2*max(w,h) matches a
    typical smartphone FOV. Angles tolerate this; absolute distances do not —
    on iPhone always use ARCamera.intrinsics instead."""
    f = fov_scale * max(width, height)
    return np.array([
        [f, 0.0, width / 2.0],
        [0.0, f, height / 2.0],
        [0.0, 0.0, 1.0],
    ])


def sample_depth(depth_map, u, v, patch=3, confidence_map=None, min_conf=1):
    """Median-of-patch depth sample at pixel (u, v) in DEPTH-MAP coordinates.

    Median + confidence rejection is what prevents the classic bug where a
    keypoint on the body silhouette grabs the background wall's depth.
    Returns None if no valid depth in the patch.
    """
    h, w = depth_map.shape[:2]
    r = patch // 2
    u0, u1 = max(0, int(u) - r), min(w, int(u) + r + 1)
    v0, v1 = max(0, int(v) - r), min(h, int(v) + r + 1)
    window = depth_map[v0:v1, u0:u1].astype(np.float64)

    mask = np.isfinite(window) & (window > 0)
    if confidence_map is not None:
        mask &= confidence_map[v0:v1, u0:u1] >= min_conf
    if not mask.any():
        return None
    return float(np.median(window[mask]))


def unproject(u, v, depth, K):
    """Pixel (u, v) + depth (m) → 3D camera-space point. K = 3x3 intrinsics
    matching the resolution (u, v) are expressed in."""
    fx, fy = K[0, 0], K[1, 1]
    cx, cy = K[0, 2], K[1, 2]
    return np.array([
        (u - cx) * depth / fx,
        (v - cy) * depth / fy,
        depth,
    ])


def lift_keypoints_3d(keypoints_2d, scores, depth_map, K_rgb,
                      rgb_size, depth_size, conf_threshold=0.3,
                      confidence_map=None):
    """Lift SpinePose 2D keypoints (RGB-resolution pixels) to 3D.

    depth_map may be a different resolution (e.g. ARKit 256x192 vs RGB
    1920x1440 — same aspect ratio, so plain scaling maps between them).
    Returns list of (3,) arrays or None per keypoint.
    """
    su = depth_size[0] / rgb_size[0]
    sv = depth_size[1] / rgb_size[1]
    out = []
    for (u, v), score in zip(keypoints_2d, scores):
        if score < conf_threshold:
            out.append(None)
            continue
        d = sample_depth(depth_map, u * su, v * sv,
                         confidence_map=confidence_map)
        out.append(unproject(u, v, d, K_rgb) if d is not None else None)
    return out


def angle_3d(a, b, c):
    """Angle at b (degrees) between 3D points a-b-c. Same contract as the 2D
    calculate_angle in VidCalc.py."""
    ba, bc = np.asarray(a) - np.asarray(b), np.asarray(c) - np.asarray(b)
    denom = np.linalg.norm(ba) * np.linalg.norm(bc)
    if denom == 0:
        return 0.0
    cos = np.clip(np.dot(ba, bc) / denom, -1.0, 1.0)
    return float(np.degrees(np.arccos(cos)))


def angle_from_gravity(pt_bottom, pt_top, gravity=(0.0, 1.0, 0.0)):
    """3D replacement for angle_from_vertical. gravity default = image-down,
    valid for tripod footage; on iPhone pass ARKit's gravity vector."""
    seg = np.asarray(pt_top) - np.asarray(pt_bottom)
    g = -np.asarray(gravity)  # "up"
    denom = np.linalg.norm(seg) * np.linalg.norm(g)
    if denom == 0:
        return 0.0
    cos = np.clip(np.dot(seg, g) / denom, -1.0, 1.0)
    return float(np.degrees(np.arccos(cos)))


class Keypoint3DSmoother:
    """One Euro filter per coordinate per keypoint. Filter POSITIONS, then
    compute angles — never the reverse. Depth noise makes this mandatory."""

    def __init__(self, n_keypoints, freq=30.0, min_cutoff=1.0, beta=0.3):
        if OneEuroFilter is None:
            raise ImportError("pip install OneEuroFilter")
        self.filters = [
            [OneEuroFilter(freq=freq, mincutoff=min_cutoff, beta=beta)
             for _ in range(3)]
            for _ in range(n_keypoints)
        ]

    def __call__(self, pts_3d, timestamp):
        out = []
        for i, pt in enumerate(pts_3d):
            if pt is None:
                out.append(None)  # don't feed gaps into the filter
                continue
            out.append(np.array([
                self.filters[i][axis](float(pt[axis]), timestamp)
                for axis in range(3)
            ]))
        return out
