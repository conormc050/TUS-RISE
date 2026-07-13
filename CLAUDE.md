# LiftIQ — TUS-RISE

Real-time biomechanical squat/deadlift analyser. TUS Athlone funded research internship. Python prototype (built on Windows) is complete and working; the project is now porting to iOS. Conor (the user) is a Python-competent student, new to Xcode/Swift — explain Mac/Xcode steps precisely, one at a time.

**Read `.claude/skills/project-roadmap/SKILL.md` first, every session.** It is the master state of the project and indexes five more skills (biomech-rules, session-schema, depth-3d-spine, ios-port, performance-optimization). Everything below is a summary; the skills are the source of truth.

## Repo layout (authoritative — do not reorganise)

- `python/VidCalc.py` — the whole analysis pipeline (MediaPipe BlazePose + SpinePose ONNX, rep state machine, calibration, rules engine, session JSON export)
- `python/requirements.txt`, `python/SpineKpValidation.py`
- `frontend-web/` — LiftIQ web prototype (open `index.html`)
- `frontend-ios/LiftIQ/` — 9 SwiftUI source files, written blind pre-Mac, never compiled. **No `.xcodeproj` exists yet.**
- `ios/` — destination for the real Xcode project when it's created
- `OutPuts/session_Squat3.json` — sample session export (schema_version 1); the iOS app's first test fixture
- `docs/`, `test_videos/`, plus legacy output images/videos at root

Known quirk: the mp4s are committed as plain git blobs despite `.gitattributes` marking them for LFS — they may show as perpetually "modified" in `git status`. Never stage or "fix" them.

## Current status (2026-07-13)

Mac access just arrived. iOS port is starting, following the port order in the ios-port skill:

1. **← WE ARE HERE.** Create the Xcode project: iOS → App, name **LiftIQ**, SwiftUI, Storage None, save into `ios/`. Delete the generated `ContentView.swift`/`LiftIQApp.swift`, drag in the 9 files from `frontend-ios/LiftIQ/` ("Copy items if needed"), then Cmd+B and fix compile errors until it builds and runs in the simulator.
2. Session JSON import — load `OutPuts/session_Squat3.json` into the app.
3. Vision 3D body pose (`VNDetectHumanBodyPose3DRequest`) on imported video; validate knee/hip angles vs `python/VidCalc.py` on the same clip (match trends and rep counts; raw angles ±3°).
4. Port rules engine + rep state machine (pure logic; constants in one struct mirroring VidCalc's CONFIG).
5. SpinePose via ONNX Runtime iOS; depth lifting after.
6. Live camera mode last.

Hardware note: Conor's phone is an iPhone 15 (non-Pro) — **no LiDAR**. Use the Vision-3D + scale-anchor fallback paths (depth-3d-spine skill, Path D). LiDAR code paths stay in the plan but can't be tested on this device. The simulator has no camera; on-device runs need a free Apple ID in Xcode → Settings → Accounts and Developer Mode on the phone.

## Design principles (do not violate)

1. Rules are normalised to per-person calibration baselines, never absolute angles.
2. Session JSON is a versioned contract — bump `schema_version` on breaking change; keep readers backward-compatible (session-schema skill).
3. Keep the analysis core portable: pure logic in a Swift package with no UIKit/ARKit imports, unit-tested against JSON fixtures from the Python pipeline.
4. Never present unvalidated metrics as medical/coaching truth — research prototype.