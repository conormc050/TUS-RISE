---
name: ios-port
description: Plan and reference for porting the LiftIQ Python analysis pipeline to iOS — pose framework options (Vision 3D, ARKit body tracking, SpinePose via ONNX Runtime/CoreML), camera capture, performance budgets. Use when Mac access arrives, when writing Swift for frontend-ios, or when choosing iOS pose/depth APIs.
---

# iOS Port Guide

The SwiftUI shell already exists in `frontend-ios/LiftIQ/` (iOS 17+, Swift Charts, untested — written without a Mac). This skill covers the analysis engine port.

## Pose model options on iOS — decision matrix

| Option | 3D? | Spine detail | Notes |
|---|---|---|---|
| **Vision `VNDetectHumanBodyPose3DRequest`** (iOS 17+) | Yes, 17 joints, meters | root + spine + neck only (no vertebral chain) | Uses depth/LiDAR automatically when available for true metric scale; **single person only** (picks the closest); no model to ship. Best replacement for MediaPipe. |
| **ARKit `ARBodyTrackingConfiguration`** | Yes, full rigged skeleton | spine_1..spine_7 exist but most are leaf/interpolated joints, not truly tracked | Rear camera only; absolute scale known to be off (forum reports ~0.3 m height error); good for animation, weak for measurement. Avoid as primary. |
| **SpinePose via ONNX Runtime iOS** | No (2D) — lift with depth | Full 9-keypoint spinal chain | `onnxruntime-objc` / C API pod runs the existing .onnx directly, **no conversion risk**. SpinePose-small is 0.72 GFLOPS → real-time on A-series is realistic. Recommended first approach. |
| **SpinePose → CoreML** | No (2D) | same | coremltools no longer converts ONNX directly; route is PyTorch source → coremltools, or onnx→TF→coreml. Only worth it if ONNX Runtime proves too slow (CoreML gets ANE acceleration). |
| **MediaPipe Tasks iOS** | pose_world_landmarks (3D-ish) | none | Exists as a CocoaPod; keeps parity with the Windows prototype during transition. |

**Recommended architecture:** Vision 3D body pose (body joints, metric 3D, free) + SpinePose-small via ONNX Runtime (spinal chain, 2D) + LiDAR depth lifting for the spine (see depth-3d-spine skill). This mirrors the Python pipeline exactly: body model + spine model + depth.

## Capture pipeline

- Live analysis: `ARSession` with `.smoothedSceneDepth` (LiDAR) — gives RGB frame + depth + intrinsics + gravity in one `ARFrame`. See `depth-3d-spine/templates/LiDARDepthCapture.swift`.
- Recorded video import: `AVAssetReader`; **apply `preferredTransform`** or portrait iPhone video arrives rotated — same gotcha as OpenCV on Windows.
- Non-LiDAR devices: `AVCaptureDevice` `builtInDualCamera` depth is photo-oriented and unreliable for video → fall back to scale-anchor method (depth-3d-spine Path D) or Vision 3D pose alone.

## Port order (when Mac arrives)

1. Xcode-build the existing `frontend-ios/LiftIQ/` shell as-is; fix compile errors (it was written blind).
2. Session JSON import first — the app becomes useful immediately by consuming Python-produced sessions (schema contract: session-schema skill).
3. Vision 3D body pose on imported video → knee/hip angles in Swift; validate numbers against VidCalc.py on the same clip (**tolerance ±3°** — different models won't match exactly; check trends and rep counts match, not raw values).
4. Port the rules engine + rep state machine (pure logic, direct translation — keep constants in one struct mirroring VidCalc's CONFIG block).
5. SpinePose via ONNX Runtime; then LiDAR depth lifting.
6. Live camera mode last — it's a UX problem more than an algorithm problem (tripod guidance, framing checks, audio cues).

## Performance budget (rule of thumb — full playbook in the performance-optimization skill)

Target 30 fps live: Vision pose ~10–15 ms, SpinePose-small ONNX ~10–20 ms on ANE/GPU, depth sampling negligible, rules negligible. If over budget: process every 2nd frame (the Python pipeline already proves 15 fps analysis is enough), or defer SpinePose to a post-set replay pass while live mode shows body-pose-only feedback.

## Gotchas

- Vision/ARKit coordinate systems differ (Vision: normalized, origin bottom-left; ARKit: meters, camera/world space). Convert everything to the project convention (x right, y down, z forward, meters, camera space) at the boundary — one adapter function per framework, then the core math is shared.
- Vision 3D positions are **relative to a root joint** unless depth gives metric scale — check `bodyHeight` / camera origin APIs before assuming meters-from-camera.
- The analysis core should be a Swift package with zero UIKit/ARKit imports (pure math + rules), unit-tested against JSON fixtures exported from the Python pipeline — this is how you keep Python and Swift results provably in sync.
