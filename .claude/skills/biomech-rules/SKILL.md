---
name: biomech-rules
description: Design of the LiftIQ biomechanics rules engine — calibration baselines, rep detection state machine, phase tagging, form flags (lumbar flexion, hip hinge, knee valgus), form score policy, and how to validate rules. Use when adding/changing analysis rules, thresholds, rep detection, or when asked about squat/deadlift form logic.
---

# Biomechanics Rules Engine

## Core principle (non-negotiable)

**All rules are relative to a per-person calibration baseline, never absolute angles.** A tall lifter with long femurs shows 45° trunk lean on a perfect squat; a short lifter shows 25°. Fixed thresholds misfire on both. VidCalc.py locks a baseline from the first `CALIBRATION_FRAMES = 40` standing frames (mean lumbar + trunk lean), and flags fire on *deviation from baseline*.

Corollary: every session must start with the lifter standing still in view. If calibration never locks, the session's flags are meaningless — VidCalc prints a warning; frontends must surface `"calibrated": false` prominently.

## Rep detection (current: squat-specific)

Knee-angle state machine with hysteresis (VidCalc.py CONFIG block):
- entry: knee < `SQUAT_ENTRY_ANGLE` (120°) → in rep
- exit: knee > `SQUAT_EXIT_ANGLE` (125°) after ≥ `MIN_REP_FRAMES` (8) processed frames
- The 5° gap + minimum frames kill jitter-double-counting. Don't "simplify" them away.

Phase tagging inside a rep: knee-angle trend over a 7-sample deque — trend < −3 DESCENDING, > +3 ASCENDING, else BOTTOM.

**Deadlift needs a different trigger** — conventional pulls may never break 120° knee. Use hip angle (shoulder-hip-knee) or wrist-landmark height relative to knee. Keep both machines behind one interface: `detect_rep(exercise, frame_metrics) -> phase, rep_event`.

## Implemented flags

**Lumbar flexion under load** — fires when phase == ASCENDING and lumbar lean > baseline + `LUMBAR_FLEX_THRESHOLD` (12°). Rationale: spinal flexion under load during the concentric is the classic injury-risk pattern; during descent some flexion is normal setup variance. Uses SPINE_IDS positions [0] hip → [3] spine_03 (lumbar) and [0] → [5] spine_05 (trunk, excludes neck).

## Flags to implement

- **Hip hinge vs lumbar hinge**: during DESCENDING, hip angle change should dominate lumbar lean change. Ratio `Δlumbar / Δhip` above ~0.5 sustained = hinging through the spine, not the hips. Baseline-normalise both deltas.
- **Knee valgus**: knee tracking inward. **Cannot be measured from sagittal 2D** — parked until the 3D pipeline (depth-3d-spine skill) or a frontal-view mode exists. Do not fake it from side view.
- **Depth consistency**: per-rep min knee angle variance across a set — fatigue indicator, cheap to compute from existing rep_stats.
- **Bar path deviation**: once bar tracking exists (wrist landmark or plate Hough circle) — horizontal drift from vertical line through mid-foot.

## Signal quality rules

- Confidence threshold 0.3 on keypoints; below it, VidCalc carries the last known value. That's acceptable for 1–2 frames; longer gaps should mark the rep `"reliable": false` rather than silently flagging on stale data. (Not yet implemented — see roadmap.)
- Smoothing (implemented 2026-07-06): One Euro filters on positions *before* angle computation — `PointSmoother` in VidCalc.py, params in CONFIG. Raw jitter was ±2–3°, a quarter of the 12° flag threshold. Filter positions, then compute angles — never the reverse. Filters reset after 0.5 s data gaps so a returning keypoint doesn't drag stale history.
- A flag needs ≥ 2–3 consecutive flagged frames before being surfaced to the user (single-frame flags are noise). Frontends currently show raw counts — the rules engine should own the debounce.

## Form score policy

The 0–100 form score in the frontends is **explicitly provisional** — a placeholder heuristic, never validated. Until a validation study exists: keep it out of any research write-up, or replace with the honest alternative (surface raw flags + per-rep table only). Do not tune it to "look right"; that's validation theatre.

## Validating any new rule (the internship deliverable is credibility)

1. **Face validity**: does the flag fire on video where a coach agrees the fault occurred? Collect a small labelled set (even 10 clips, self-labelled with supervisor review).
2. **Test–retest**: same lifter, same day, two sets — flag counts should be stable.
3. **Gold standard**: OpenCap (opencap.stanford.edu — free, research-grade, two phones) is the practical comparator; a Vicon lab if TUS has one. Compare joint-angle time series (RMSE, not just peaks).
4. **Ethics first**: recording identifiable participants = personal data (GDPR). TUS ethics approval before collecting anyone but yourself.

Report sensitivity to: camera angle (±15° off sagittal), distance (2–4 m), clothing (baggy vs fitted), lighting. These are the confounds a reviewer will ask about.
