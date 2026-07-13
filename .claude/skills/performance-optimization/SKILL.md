---
name: performance-optimization
description: Performance optimization playbook for the LiftIQ pipeline — Python/Windows prototype speed, iOS real-time budgets (ANE/CoreML/ONNX Runtime, thermal, battery), and LiDAR depth-path costs. Use when the pipeline is too slow, when targeting real-time/live analysis, when frames drop or the phone heats up, or before optimizing anything.
---

# Performance Optimization Playbook

## Rule zero: measure before touching anything

Optimizing unprofiled code wastes internship time. One slow component usually dominates; find it first.

- Python: wrap each stage with `time.perf_counter()` and print a per-stage ms table every 100 frames (MediaPipe / SpinePose / depth model / drawing / video write). `cProfile` for anything surprising.
- iOS: Instruments → Time Profiler + Core ML template; `os_signpost` around each pipeline stage so stages show up named in Instruments.
- Track a single number as the health metric: **ms per processed frame**. Log it in every experiment; keep a note of before/after — that table goes straight into the internship write-up.

## Known cost structure (this project, measured/estimated)

| Stage | Typical cost | Notes |
|---|---|---|
| MediaPipe BlazePose (complexity 1) | ~10–30 ms CPU | complexity 0 is ~2× faster, noticeably worse ankles/wrists |
| SpinePose small | 0.72 GFLOPS, ~15–40 ms CPU | medium is 1.98 GFLOPS for marginal gain — stay on small |
| Depth Anything V2 small | ~50–150 ms CPU, ~10–20 ms GPU | the elephant; see monocular section |
| LiDAR depth sampling | ~0 (256×192 lookup) | free — the win of LiDAR over monocular is not accuracy alone, it's compute |
| Drawing + `out.write` | 5–15 ms | matters more than people expect at high res |
| Rules/angles/JSON | negligible | never optimize these |

## Python prototype levers (in order of payoff)

1. **Frame stride** — `PROCESS_EVERY_N_FRAMES` already exists. 15 fps analysis is proven sufficient for squat tempo; don't burn time making 30 fps fast.
2. **ROI cropping for SpinePose** — biggest untapped win. Crop the frame to the previous frame's person bounding box (MediaPipe landmarks bbox + 20% margin) before calling `estimator()`. On a 1080p gym video where the lifter is ~⅓ of frame width, this cuts SpinePose input pixels ~8–10× (remember to add the crop offset back to keypoint coords). Re-detect on full frame whenever confidence drops.
3. **Downscale before inference** — pose models are trained at modest resolutions; feeding 1080p+ buys nothing. Downscale to ~720p for inference, keep full res only for the annotated output video. Scale keypoints back up.
4. **ONNX Runtime providers** — SpinePose runs on ORT: check `ort.get_available_providers()`; `DmlExecutionProvider` (DirectML) uses the Windows GPU with zero code change if the package allows provider selection.
5. **Skip drawing when benchmarking** — set a `HEADLESS` flag that skips all cv2 drawing + video write; that's the honest number for the eventual phone pipeline (the phone won't write annotated mp4s live).
6. Don't bother with: multithreading the loop (models hold the GIL wrong / aren't thread-safe), micro-optimizing numpy, caching angle math.

## Monocular depth (Depth Anything V2) specifics

- It does not need to run every processed frame: depth changes slowly relative to pose. Run depth every 3rd–5th processed frame and reuse the last map — keypoints move, the torso's distance barely does within 100 ms. Validate reuse against per-frame depth on one clip before trusting.
- Inference resolution: 518 px input is default; smaller `input_size` (e.g. 392) is materially faster with modest quality loss at gym distances.
- If it's still the bottleneck on CPU-only Windows: export to ONNX and run on DirectML, or accept offline (non-real-time) processing — the prototype's job is validating the 3D math, not being fast. Real-time depth is what LiDAR is for.

## iOS real-time budgets

Target: 30 fps live analysis → **33 ms total budget**; plan for ~20 ms of model work, leaving headroom for capture + UI.

- **Compute units**: CoreML — `MLModelConfiguration.computeUnits = .all` (lets ANE take it); ONNX Runtime — enable the **CoreML execution provider** so SpinePose ONNX also reaches ANE/GPU. CPU-only ORT on A-series will likely blow the budget; check provider actually engaged (ORT logs fallbacks silently).
- **First-run compile**: CoreML compiles models on first load (seconds). Load models once at app start behind the splash screen, never per-session.
- **Pipeline threading**: capture on the `ARSession` thread, inference on one serial background queue, UI on main. **Drop frames when busy** (process latest, discard queued) — never queue frames; queuing turns a slow frame into permanent latency.
- **Resolution**: request the smallest capture format that works (pose models don't need 4K); avoid `CVPixelBuffer` copies — crop/scale via `CIImage`/vImage on GPU, and pass buffers by reference.
- **Vision + SpinePose staging**: run Vision body pose every frame (it's cheap and Apple-optimized); run SpinePose at half rate and interpolate spine keypoints between runs — spine moves slower than limbs.
- **Same ROI trick as Python**: crop to Vision's person bbox before SpinePose. Identical logic, shared design.

## Thermal & battery (the silent killers of live mode)

A phone on a tripod running camera + ANE + screen for a 45-min session **will** thermal-throttle, and throttling shows up as sudden frame drops mid-set.

- Observe `ProcessInfo.processInfo.thermalState` — on `.serious`, degrade gracefully: drop to 15 fps analysis, pause SpinePose (body-only feedback), dim preview. On `.critical`, stop inference, keep recording for post-set analysis.
- Biggest battery/heat levers: screen brightness of the live preview (consider rep-count-only minimal UI), capture resolution, and ANE duty cycle (frame stride).
- Offer a **"record now, analyze after the set"** mode: capture-only is cool and cheap, analysis runs between sets while the phone rests. Lifters don't watch the screen mid-set anyway — this is likely the better product default *and* the easy performance win.

## LiDAR-path notes

- Depth is essentially free at runtime (256×192 map, 60 Hz). The costs to avoid:
  - **Don't copy the whole depth buffer per frame** (the `LiDARDepthCapture.swift` template's `floatValues(from:)` does exactly that for clarity — replace with direct `CVPixelBuffer` base-address indexing of just the 3×3 patches you sample; ~9 keypoints × 9 px, not 49k floats).
  - `smoothedSceneDepth` costs nothing extra over `sceneDepth` — always prefer it.
  - ARKit session itself has overhead vs plain `AVCaptureSession` (~world tracking). If live mode only needs depth + gravity, still use ARKit (no lighter API exposes LiDAR depth for video), but disable everything optional: no plane detection, no scene reconstruction, no environment texturing.
- LiDAR vs monocular on-device: if LiDAR is present, never run a monocular depth model — it's strictly worse on both accuracy and compute.

## Acceptance targets (write results against these)

- Windows prototype, offline: ≥ 10 processed fps at 720p inference on the dev laptop (comfortable iteration speed; not a product metric).
- iOS live: 30 fps capture, ≥ 15 fps full analysis, zero queued-frame latency growth, no `.serious` thermal state within a 20-min session.
- iOS post-set: analyze a 60 s set in ≤ 30 s.
