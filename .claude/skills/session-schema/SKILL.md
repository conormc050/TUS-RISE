---
name: session-schema
description: The session JSON contract between VidCalc.py (producer) and the LiftIQ web/iOS frontends (consumers) — current schema_version 1 fields, evolution rules, and the planned v2 3D extension. Use before changing session JSON export, import, or adding fields to frame data or rep stats.
---

# Session JSON Schema Contract

Producer: `VidCalc.py` → `session_<video>.json`. Consumers: `frontend-web/` (Analyze screen import + drag-drop) and `frontend-ios/LiftIQ/`. This file is the **only** interface between analysis and UI — treat it like a public API.

## Rules of evolution

1. **Additive changes** (new optional fields): allowed without version bump; consumers must ignore unknown fields.
2. **Breaking changes** (rename/remove/retype/re-mean a field): bump `schema_version`, keep frontend readers accepting *all* previous versions. Never re-emit old versions.
3. Readers must check `schema_version` and fail loudly on versions newer than they know — not silently misrender.
4. `null` means "not measured this frame" — distinct from 0. Preserve that distinction in charts (gaps, not zeros).

## schema_version 1 (current)

```jsonc
{
  "schema_version": 1,
  "video": "Squat3.mp4",
  "exercise": "squat",            // "deadlift" reserved, not yet produced
  "date": "2026-07-06T14:31:00",  // ISO 8601, local time
  "fps": 29.97,
  "process_every_n": 2,           // frame numbers are ORIGINAL video frames;
                                  // consecutive entries differ by this stride
  "rep_count": 5,
  "lumbar_baseline": 8.2,         // degrees; null if calibration never locked
  "trunk_baseline": 11.4,
  "lumbar_flex_threshold": 12,    // flag fires above baseline + this
  "calibrated": true,             // if false, flags are unreliable — surface it
  "smoothing": {                  // additive, 2026-07-06: One Euro params used
    "filter": "one_euro", "mincutoff": 1.0, "beta": 0.3
  },
  "reps": [{
    "rep": 1, "duration": 2.4,    // seconds
    "depth": 87.3,                // MIN knee angle in rep (lower = deeper)
    "depth_3d": 85.1,             // additive: MIN 3D world-landmark knee angle; null if never detected
    "trunk": 34.1, "lumbar": 15.9,// MAX leans in rep, degrees
    "flags": 0                    // count of lumbar-flagged frames
  }],
  "frames": [{
    "frame": 42,                  // original video frame index
    "knee_angle": 172.1, "hip_angle": 168.0,   // degrees, null if undetected
    "knee_angle_3d": 170.4, "hip_angle_3d": 166.2,  // additive: from MediaPipe
                                  // pose_world_landmarks (meters, hip-origin,
                                  // model-inferred depth) — view-independent
    "trunk_lean": 10.2, "lumbar_lean": 7.8,
    "phase": "STANDING",          // STANDING|DESCENDING|BOTTOM|ASCENDING
    "rep_count": 0,               // completed reps so far
    "lumbar_flag": false
  }]
}
```

The `smoothing`, `depth_3d`, and `*_angle_3d` fields were added 2026-07-06 as **additive** changes (rule 1 — no version bump; older consumers ignore them). All angles are computed from One-Euro-smoothed positions as of the same date.

Semantics worth restating (bugs have hidden here): `depth` is a minimum, `trunk`/`lumbar` are maxima; angles carry last-known-value through short detection gaps (so a long occlusion produces a flat line, not nulls); `rep_count` in frames is *completed* count, so the rep in progress is `rep_count + 1`.

## Planned: schema_version 2 (3D extension)

When the 3D spine pipeline lands (depth-3d-spine skill), add per frame:

```jsonc
"depth_source": "lidar" | "monocular_metric" | "monocular_relative"
              | "world_landmarks" | "scale_anchor" | "none",   // session-level
"frames": [{
  // ...v1 fields unchanged...
  "spine_3d": [[x, y, z], null, ...]   // 9 entries matching SPINE_IDS order;
                                       // meters, camera space, x right, y down,
                                       // z forward; null = not lifted this frame
}]
```

- Coordinate convention is fixed project-wide (matches `unproject_keypoints.py` and the Swift template). Convert to y-up only in visualisation code.
- If `depth_source` is `monocular_relative`, z is **not meters** — consumers may render shape but must not display distances.
- v1 fields keep their exact v1 meanings — 3D adds, it never redefines. 2D angles stay in the export even when 3D angles exist (comparability across the project's history).
- Keep file size in mind: 9 keypoints × 3 floats per frame roughly doubles the JSON; round to 3 decimals (mm precision) on export.

## When editing either side

- Producer change → grep both frontends for the field name before shipping (`frontend-web/data.js`, `app.js`, `charts.js`; `frontend-ios/LiftIQ/`).
- The web frontend also renders **mock data** — keep mock generators in `data.js` schema-conformant or the Analyze screen lies about what real imports look like.
- A tiny reference session JSON checked into the repo (few frames, 1 rep) would serve as both frontend test fixture and schema documentation — create one when touching this next.
