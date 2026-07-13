---
name: depth-3d-spine
description: How to lift 2D spine keypoints (SpinePose) into 3D space using iPhone LiDAR depth, monocular depth estimation, MediaPipe world landmarks, or an anthropometric scale anchor. Use when implementing 3D keypoints, depth sampling, unprojection, point clouds, or 3D joint angles for the LiftIQ analyser. Includes Python and Swift templates.
---

# Lifting the spine to 3D

Goal: turn SpinePose's 2D pixel keypoints into 3D positions (meters, camera space) so joint angles become view-independent and knee valgus / true lumbar curvature become measurable.

## The one equation that matters

A pixel (u, v) with depth d (meters) unprojects through the camera intrinsics K:

```
X = (u - cx) * d / fx
Y = (v - cy) * d / fy
Z = d
```

fx, fy = focal lengths in pixels; cx, cy = principal point. Everything in this skill is "get d and K, then apply this". Template: `templates/unproject_keypoints.py`.

**Convention (project standard — keep consistent everywhere):** camera space, x right, y down (image convention), z forward away from camera, units meters. Convert y-up only at visualisation time.

## Path A — iPhone LiDAR (the accurate endgame)

ARKit with `frameSemantics = .sceneDepth` (LiDAR devices: iPhone 12 Pro+ Pro models):
- `ARFrame.sceneDepth.depthMap`: **256×192 Float32** meters, plus `confidenceMap` (low/medium/high per pixel). RGB frame is 1920×1440 — same aspect ratio, so map keypoint coords by simple scaling: `u_depth = u_rgb * 256/1920`.
- Prefer `smoothedSceneDepth` (temporally smoothed) for moving subjects — less frame-to-frame flicker in joint depth.
- `ARFrame.camera.intrinsics` is a 3×3 simd matrix **for the RGB resolution** — scale fx,cx by 256/1920 and fy,cy by 192/1440 if unprojecting in depth-map coordinates (or sample depth and unproject in RGB coordinates, simpler — see Swift template).
- Depth is ~60 Hz, gym distances (2–4 m) are well within LiDAR range (~5 m); accuracy degrades near the range limit — advise filming from 2–3.5 m.
- 256×192 is coarse: one depth pixel ≈ 7.5 RGB pixels. **Sample a 3×3 median patch** around each keypoint and reject low-confidence pixels, otherwise a keypoint on a body edge grabs background depth (the classic bug: spine keypoint at the silhouette boundary reads the wall 2 m behind).

Template: `templates/LiDARDepthCapture.swift`.

## Path B — Monocular depth on Windows (prototype now, no iPhone needed)

Depth Anything V2 (github.com/DepthAnything/Depth-Anything-V2):
- Use the **Small** variant (~25M params) — runs near-real-time on CPU/modest GPU; fine for offline video.
- Base models output **relative** (affine-invariant) depth. The **metric fine-tuned variants** (indoor/Hypersim) output meters directly — use `depth_anything_v2_metric_hypersim_vits.pth` for gym (indoor) footage.
- Relative depth is still useful: within one frame it orders the spine keypoints front-to-back correctly, which is enough to prototype 3D angle math before metric depth arrives.
- Pipeline: run once per processed frame, bilinear-sample depth at each SpinePose pixel, unproject with estimated intrinsics (see "Intrinsics without calibration" below).

Template: `templates/depth_anything_prototype.py`.

## Path C — MediaPipe world landmarks (free, already computed, use TODAY)

`mp_result.pose_world_landmarks` — VidCalc.py already gets this on every frame and ignores it. It is a 3D skeleton in **meters, origin at the hip midpoint**, from BlazePose's learned 3D lifting. No depth sensor, no extra compute.

- Good: instant 3D knee/hip angles that are view-independent; a sanity baseline to validate Paths A/B against.
- Limits: no spinal detail (only shoulders/hips bracket the spine), depth axis is model-inferred (least accurate axis), origin is body-relative not camera-relative.
- Hybrid trick: fit the SpinePose 2D spine chain onto the world-landmark torso — use world landmarks for scale/orientation of the hip–shoulder segment, distribute spine keypoints along it using their 2D positions. Crude but gives "3D-ish" spine with zero new dependencies.

## Path D — Anthropometric scale anchor (non-LiDAR iPhones / plain video)

The user's "distance of the pixels from the camera" idea, formalised: if a body segment's real length L (meters) is known (measured once at calibration — e.g. lateral thigh, hip-to-knee) and its pixel length is p at roughly camera-perpendicular orientation, then depth to that segment ≈ `fx * L / p`. Combine with relative depth (Path B) to fix the unknown scale/offset: solve `d_metric = a * d_rel + b` from two anchor segments, or one anchor + the floor plane.

Accuracy is modest (±10–20%) but it converts relative depth into usable meters with nothing but a tape measure at onboarding. This is also the standard fallback when LiDAR is absent.

## Intrinsics without calibration

- iPhone: always use `ARCamera.intrinsics` / `AVCaptureDevice` calibration data — ground truth, never estimate.
- Arbitrary mp4 (Windows prototype): estimate `fx = fy ≈ 1.2 * max(w, h)` (typical smartphone FOV ~65–70°), `cx = w/2, cy = h/2`. Fine for angles (angles are scale-invariant to intrinsics errors to first order); not fine for absolute distances.
- Proper option: OpenCV chessboard calibration (`cv2.calibrateCamera`) if the same camera films everything.

## Once you have 3D keypoints

- **3D joint angles**: same `calculate_angle` math but on 3D vectors — `angle_from_vertical` needs a defined vertical: use gravity from ARKit (`ARCamera.transform` is gravity-aligned in `.gravity` world alignment) or assume image-vertical ≈ gravity for tripod footage.
- **Knee valgus** becomes measurable: angle between the hip→knee and knee→ankle vectors projected onto the frontal plane.
- **True lumbar curvature**: fit a curve through the 3D spine chain; curvature change under load is a better flag than the 2D lean proxy.
- **Smoothing is mandatory in 3D** — depth noise dwarfs 2D jitter. One Euro filter per coordinate per keypoint (package already in venv: `OneEuroFilter`). Filter positions, then compute angles; never filter angles computed from unfiltered positions.
- **Schema**: export as `keypoints_3d` per frame under `schema_version: 2` with a `depth_source` field — see the session-schema skill before touching the JSON.

## Validation order (do not skip)

1. Path C world-landmark knee angle vs current 2D knee angle on existing videos — should broadly agree on sagittal footage.
2. Path B relative-depth ordering: spine keypoints should be nearly co-planar; a keypoint jumping 0.5 m out of the torso plane = depth sampling bug (edge/background grab).
3. Path A vs tape measure: LiDAR distance to a static object, then to a standing person's hip.
4. Only then trust 3D angles in the rules engine.
