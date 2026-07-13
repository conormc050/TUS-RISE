# LiftIQ — Frontend

Two implementations of the same design:

| Folder | What it is | How to run |
|---|---|---|
| `frontend-web/` | Interactive prototype | **Double-click `index.html`** — runs in any browser, today, on Windows |
| `frontend-ios/`  | SwiftUI source (iOS 17+) | Open in Xcode when you get Mac access — create a new iOS App project named `LiftIQ` and drop the `.swift` files in |

## Web prototype

- Renders inside an iPhone 14 Pro–class frame (393×852) on desktop; full-bleed on an actual phone.
- **Splash screen** → tab shell: Home, History, Analyze, Trends, Settings.
- **Dark / light / auto theme** — Settings → Appearance (persisted in localStorage).
- **Simple vs Detailed session view** — segmented toggle on any session; default mode is a setting.
- **Import real data**: run `VidCalc.py` (it now exports `session_<video>.json`) then drag the JSON onto the Analyze tab's drop zone. Mock sessions are bundled so every screen works without the pipeline.
- No build step, no dependencies — plain HTML/CSS/JS + hand-rolled SVG charts.

## Data contract (schema_version 1)

`VidCalc.py` exports:

```json
{
  "schema_version": 1,
  "video": "Squat3.mp4",
  "exercise": "squat",
  "date": "2026-07-06T14:31:00",
  "fps": 30.0,
  "process_every_n": 2,
  "rep_count": 5,
  "lumbar_baseline": 7.2,
  "trunk_baseline": 10.9,
  "lumbar_flex_threshold": 12,
  "calibrated": true,
  "reps":   [{ "rep": 1, "duration": 3.2, "depth": 82.1, "trunk": 38.4, "lumbar": 12.9, "flags": 0 }],
  "frames": [{ "frame": 2, "knee_angle": 171.2, "hip_angle": 169.8, "trunk_lean": 10.1,
               "lumbar_lean": 7.4, "phase": "STANDING", "rep_count": 0, "lumbar_flag": false }]
}
```

Both frontends decode exactly this shape (`Models.swift` / `data.js normalize()`).

## Form score heuristic

`100 − flags·2.2 (cap 45) − shallow-depth penalty (cap 20) − depth-inconsistency penalty (cap 15) − 10 if uncalibrated`, floored at 0. Deliberately simple — replace once validated rules exist.

## SwiftUI port notes

- Files: `LiftIQApp` (entry + splash + tabs), `Models` (Codable + store + mock), `Theme` (colors, GlassCard, ScoreRing…), one file per screen, `SessionDetailView` (Simple/Detailed).
- Charts use **Swift Charts**, glass uses `.ultraThinMaterial` — both native, no packages.
- Import uses `fileImporter`; on-device capture/analysis is stubbed as "coming soon" (that's the CoreML/Vision port of the Python pipeline).
