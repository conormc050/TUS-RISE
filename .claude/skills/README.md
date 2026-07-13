# LiftIQ Project Skills Library

Written 2026-07-06 by Claude (Fable 5) as a knowledge base for future sessions.
Each subfolder is a Claude Code project skill (`SKILL.md` + templates).
Read `project-roadmap` first — it is the master index of what is done and what remains.

| Skill | What it covers |
|---|---|
| `project-roadmap` | Project state, milestones, and the full checklist of remaining work |
| `depth-3d-spine` | Lifting 2D spine keypoints into 3D: LiDAR, monocular depth, world landmarks + code templates |
| `ios-port` | Porting the Python pipeline to iOS: framework options, CoreML conversion, capture pipeline |
| `biomech-rules` | Rules engine design, calibration philosophy, rep detection, validation methodology |
| `session-schema` | The session JSON contract between VidCalc.py and the frontends, and how to evolve it |
| `performance-optimization` | Speed/thermal/battery playbook: Python prototype, iOS real-time budgets, LiDAR-path costs |

Ground rules that apply across all skills:
- Rules are normalised to per-person calibration baselines, never fixed angle thresholds.
- The session JSON is a versioned contract — never change it without bumping `schema_version`.
- The form score heuristic is provisional; do not present it as validated.
