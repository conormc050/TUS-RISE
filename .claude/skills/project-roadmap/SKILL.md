---
name: project-roadmap
description: Master roadmap and state of the LiftIQ biomechanical squat/deadlift analyser (TUS Athlone internship). Read this first when resuming work on this project, planning next steps, or asked "where were we" / "what's left". Indexes the other project skills.
---

# LiftIQ Project Roadmap

Real-time biomechanical squat/deadlift analyser. Python prototype on Windows (PyCharm) → eventual iOS app. TUS Athlone funded research internship. User: Conor, Python-competent student, no Mac access yet.

## Architecture (current)

```
gym video (mp4)
   └─> VidCalc.py
         ├─ MediaPipe BlazePose ─ body keypoints → knee/hip angles
         ├─ SpinePose (dfki-av, ONNX, 37 kpts) ─ estimator.SPINE_IDS → 9 spinal keypoints
         ├─ rep state machine (knee-angle hysteresis 120°/125°)
         ├─ calibration (first 40 standing frames → lumbar/trunk baseline)
         ├─ rules engine (lumbar flexion under load, baseline-relative)
         └─ outputs: annotated mp4, angle_chart.png, rep_summary.png,
                     session_<video>.json (schema_version 1)
                          └─> frontend-web/ (LiftIQ HTML/CSS/JS, iPhone frame mock)
                          └─> frontend-ios/LiftIQ/ (SwiftUI mirror, untested — no Mac)
```

## Done

- Full 2D pipeline in `VidCalc.py` (see [biomech-rules](../biomech-rules/SKILL.md) for the logic)
- Rep detection, phase tagging (STANDING/DESCENDING/BOTTOM/ASCENDING), per-rep stats
- Per-person calibration baseline + lumbar-flexion flag
- Session JSON export (see [session-schema](../session-schema/SKILL.md))
- LiftIQ frontends (web prototype + SwiftUI skeleton)

## Next major milestone: 3D spine

Lift the 2D spine keypoints into 3D using depth. Three paths, in order of when they're usable — full detail and code templates in [depth-3d-spine](../depth-3d-spine/SKILL.md):

1. **Now, on Windows**: MediaPipe `pose_world_landmarks` (already computed, ignored today — 3D in meters for free) + monocular depth (Depth Anything V2) sampled at SpinePose pixel positions.
2. **On iPhone with LiDAR**: ARKit `sceneDepth` (256×192 depth map) + camera intrinsics unprojection — the accurate endgame.
3. **Scale anchor fallback** (non-LiDAR iPhones): known body-segment length converts relative depth to metric.

## Remaining work checklist (things easy to forget)

### Engineering hygiene
- [x] `requirements.txt` — pinned from the working venv (2026-07-06)
- [x] `.gitignore` + initial commit (2026-07-06)
- [ ] Golden regression test: run VidCalc on a short reference clip, assert rep count + flag count match known-good values

### Pipeline robustness
- [x] **Smoothing** (2026-07-06): One Euro filters on all landmark/spine POSITIONS (never on derived angles) via `PointSmoother` in VidCalc.py; params in CONFIG (`SMOOTH_MINCUTOFF=1.0`, `SMOOTH_BETA=0.3`), filter state resets after 0.5 s gaps
- [x] **World-landmark 3D baseline** (2026-07-06): `pose_world_landmarks` → `knee_angle_3d`/`hip_angle_3d` per frame, `depth_3d` per rep, teal dotted line on angle_chart.png — this is depth-path validation step 1 (compare vs 2D on sagittal footage)
- [ ] **iPhone video rotation**: iPhone mp4s carry a rotation flag; OpenCV versions differ on honouring it (`cv2.CAP_PROP_ORIENTATION_AUTO`). Videos may arrive sideways — detect and correct, or every angle is garbage
- [ ] **Side auto-detection**: landmarks 11/23/25/27 (left side) are hardcoded; pick side by comparing mean visibility of left vs right landmarks
- [ ] **Person selection**: `keypoints[0]` assumes the lifter is detection #0 — in a real gym pick largest bounding box / most central person
- [ ] **Occlusion handling**: plates occlude hip/knee from sagittal view; currently papered over with last-known-value — add confidence-based interpolation and flag low-confidence reps as unreliable

### Analysis features
- [ ] **Deadlift support**: the rep state machine is squat-specific (knee < 120°); conventional deadlifts have far less knee flexion — trigger on hip angle or bar/wrist height instead. `exercise` field already exists in the JSON
- [ ] **Knee valgus flag**: impossible from sagittal 2D; needs frontal view or the 3D pipeline — park until 3D lands
- [ ] **Hip-hinge vs lumbar-hinge discrimination**: compare hip-angle change vs lumbar-lean change during descent
- [ ] **Bar path tracking**: track wrist landmark or plate centre (Hough circle) — classic lifter-facing feature, cheap to add
- [ ] **Camera-angle guard**: 2D sagittal angles are only valid filmed side-on; detect off-axis filming (shoulder-width-to-hip-width pixel ratio) and warn

### Research/validation (this is an internship — the write-up matters)
- [ ] **Validation study**: compare against a gold standard — OpenCap (free, research-grade, multi-phone) or the university's motion-capture lab if TUS has Vicon
- [ ] **Ethics + GDPR**: recording identifiable people lifting = personal data; TUS ethics approval likely required before collecting participant videos
- [ ] **Replace the provisional form score** — the 0–100 heuristic in the frontend was explicitly marked placeholder; either validate it or present raw flags only
- [ ] **Document coordinate conventions and units** in one place (see session-schema skill) — 3D will multiply the confusion otherwise

### iOS (when Mac access arrives)
See [ios-port](../ios-port/SKILL.md): framework choice matrix, SpinePose-on-iOS options (ONNX Runtime vs CoreML), capture pipeline.

### Performance
See [performance-optimization](../performance-optimization/SKILL.md) before optimizing anything: profiling method, ROI cropping (biggest untapped Python win), iOS ANE/thermal/battery, LiDAR-path costs, and acceptance targets.

## Design principles (do not violate)

1. Rules are normalised to per-person calibration baselines, never absolute angles — body types vary.
2. Session JSON is a versioned contract; bump `schema_version` on breaking change, keep frontend readers backward-compatible.
3. Prototype on Windows first, keep iOS-specific code isolated so the analysis core stays portable.
4. Never present unvalidated metrics as medical/coaching truth — this is a research prototype.
