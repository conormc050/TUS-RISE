import cv2
import numpy as np
import mediapipe as mp
import matplotlib.pyplot as plt
from collections import deque
from spinepose import SpinePoseEstimator
from OneEuroFilter import OneEuroFilter
import os
import json
from datetime import datetime

# ------------------ CONFIG ------------------

VIDEO_PATH = r"C:\Users\conor\Downloads\Squat3.mp4"
_base      = os.path.splitext(os.path.basename(VIDEO_PATH))[0]
OUTPUT_PATH = f"output_{_base}.mp4"

PROCESS_EVERY_N_FRAMES = 2
CONFIDENCE_THRESHOLD   = 0.3

# Positions within SPINE_IDS list (set after estimator init)
# [0]=hip  [1]=spine_01  [2]=spine_02  [3]=spine_03  [4]=spine_04
# [5]=spine_05  [6]=neck  [7]=neck_02  [8]=neck_03
LUMBAR_TOP_POS = 3   # spine_03 — endpoint for lumbar lean
TRUNK_TOP_POS  = 5   # spine_05 — endpoint for trunk lean (excludes neck)

# Rep detection — hysteresis prevents jitter at the threshold boundary
SQUAT_ENTRY_ANGLE = 120   # knee below this → rep started
SQUAT_EXIT_ANGLE  = 125   # knee above this (after entry) → rep complete
MIN_REP_FRAMES    = 8     # minimum processed frames to count as a real rep

# Calibration: collect this many valid STANDING frames to lock in the neutral baseline
CALIBRATION_FRAMES = 40

# Rules engine: lumbar lean must exceed baseline by this many degrees to trigger a flag
LUMBAR_FLEX_THRESHOLD = 12

# One Euro smoothing — positions are filtered, then angles computed from them
# (never the reverse). mincutoff lower = more jitter removed but more lag;
# beta higher = less lag on fast movement at the cost of letting jitter through.
SMOOTH_MINCUTOFF = 1.0   # Hz
SMOOTH_BETA      = 0.3
SMOOTH_RESET_GAP = 0.5   # seconds without data for a point → reset its filter state

# ------------------ FUNCTIONS ------------------

def calculate_angle(a, b, c):
    a, b, c = np.array(a), np.array(b), np.array(c)
    ba, bc  = a - b, c - b
    denom   = np.linalg.norm(ba) * np.linalg.norm(bc)
    if denom == 0:
        return 0.0
    cosine = np.clip(np.dot(ba, bc) / denom, -1.0, 1.0)
    return float(np.degrees(np.arccos(cosine)))


def angle_from_vertical(pt_bottom, pt_top):
    """Angle between the vector pt_bottom→pt_top and the vertical axis."""
    diff = np.array(pt_top) - np.array(pt_bottom)
    return float(np.degrees(np.arctan2(abs(diff[0]), abs(diff[1]))))


def extract_spine_points(keypoints, scores, spine_ids, threshold):
    """Confidence-gated spine keypoints as float (x, y) tuples, None where low."""
    if len(keypoints) == 0:
        return [None] * len(spine_ids)

    person_kps    = keypoints[0]
    person_scores = scores[0]

    pts = []
    for idx in spine_ids:
        if person_scores[idx] > threshold:
            pts.append((float(person_kps[idx][0]), float(person_kps[idx][1])))
        else:
            pts.append(None)
    return pts


def draw_spine_chain(frame, pts):
    for pt in pts:
        if pt is not None:
            cv2.circle(frame, (int(pt[0]), int(pt[1])), 5, (255, 105, 180), -1)

    for i in range(len(pts) - 1):
        if pts[i] is not None and pts[i + 1] is not None:
            p0 = (int(pts[i][0]),     int(pts[i][1]))
            p1 = (int(pts[i + 1][0]), int(pts[i + 1][1]))
            cv2.line(frame, p0, p1, (51, 153, 255), 2)

    return frame


class PointSmoother:
    """Bank of One Euro filters keyed by point name, one filter per coordinate.

    Positions are filtered and angles computed from the smoothed positions —
    filtering angles derived from raw positions loses the jitter structure.
    A point that disappears (low confidence) longer than SMOOTH_RESET_GAP gets
    fresh filter state instead of dragging stale history into its comeback.
    """

    def __init__(self, freq):
        self.freq    = freq
        self.filters = {}   # name → (per-axis filter list, last timestamp)

    def smooth(self, name, coords, t):
        if coords is None:
            return None
        coords = tuple(float(c) for c in coords)
        entry  = self.filters.get(name)
        if entry is None or (t - entry[1]) > SMOOTH_RESET_GAP:
            entry = (
                [OneEuroFilter(self.freq, mincutoff=SMOOTH_MINCUTOFF, beta=SMOOTH_BETA)
                 for _ in coords],
                t,
            )
        filts = entry[0]
        smoothed = tuple(f(c, t) for f, c in zip(filts, coords))
        self.filters[name] = (filts, t)
        return smoothed


def get_landmark_coords(landmarks, index, w, h):
    lm = landmarks[index]
    return (int(lm.x * w), int(lm.y * h))


def draw_text_bg(frame, text, pos, font_scale=0.6, color=(255, 255, 255), thickness=2):
    font = cv2.FONT_HERSHEY_SIMPLEX
    (tw, th), _ = cv2.getTextSize(text, font, font_scale, thickness)
    x, y = pos
    cv2.rectangle(frame, (x - 2, y - th - 4), (x + tw + 2, y + 4), (0, 0, 0), -1)
    cv2.putText(frame, text, pos, font, font_scale, color, thickness)


def to_float_series(frame_data, key):
    return [d[key] if d[key] is not None else float("nan") for d in frame_data]


def compute_rep_stats(frame_data, total_rep_count, fps, process_every_n):
    """Group frame_data by completed rep and return a list of summary dicts."""
    buckets = {}
    for d in frame_data:
        if d["phase"] == "STANDING":
            continue
        rep_num = d["rep_count"] + 1   # rep in progress = completed count + 1
        if rep_num > total_rep_count:   # skip any incomplete rep at end
            continue
        buckets.setdefault(rep_num, []).append(d)

    stats = []
    for rep_num in sorted(buckets):
        frames = buckets[rep_num]
        knee_vals   = [f["knee_angle"]  for f in frames if f["knee_angle"]  is not None]
        trunk_vals  = [f["trunk_lean"]  for f in frames if f["trunk_lean"]  is not None]
        lumbar_vals = [f["lumbar_lean"] for f in frames if f["lumbar_lean"] is not None]
        knee3d_vals = [f["knee_angle_3d"] for f in frames if f.get("knee_angle_3d") is not None]
        stats.append({
            "rep":       rep_num,
            "duration":  round(len(frames) * process_every_n / fps, 1),
            "depth":     round(min(knee_vals),    1) if knee_vals   else None,
            "depth_3d":  round(min(knee3d_vals),  1) if knee3d_vals else None,
            "trunk":     round(max(trunk_vals),   1) if trunk_vals  else None,
            "lumbar":    round(max(lumbar_vals),  1) if lumbar_vals else None,
            "flags":     sum(1 for f in frames if f.get("lumbar_flag")),
        })
    return stats


def print_rep_table(stats):
    print("\n" + "=" * 70)
    print(f"{'Rep':<5} {'Time(s)':<9} {'Depth°':<9} {'Depth3D°':<10} {'Trunk°':<9} {'Lumbar°':<9} {'Flags'}")
    print("-" * 70)
    for s in stats:
        flag_str = f"{s['flags']} !" if s["flags"] else "  -"
        print(
            f"{s['rep']:<5} "
            f"{s['duration']:<9} "
            f"{str(s['depth']):<9} "
            f"{str(s.get('depth_3d')):<10} "
            f"{str(s['trunk']):<9} "
            f"{str(s['lumbar']):<9} "
            f"{flag_str}"
        )
    print("=" * 70)


def save_rep_chart(stats, lumbar_baseline):
    if not stats:
        return
    reps        = [s["rep"]    for s in stats]
    trunk_vals  = [s["trunk"]  if s["trunk"]  is not None else 0 for s in stats]
    lumbar_vals = [s["lumbar"] if s["lumbar"] is not None else 0 for s in stats]
    flagged     = [s["flags"] > 0 for s in stats]

    x      = np.arange(len(reps))
    width  = 0.35
    fig, ax = plt.subplots(figsize=(10, 5))

    bars_t = ax.bar(x - width / 2, trunk_vals,  width, label="Peak trunk lean",  color="orange", alpha=0.85)
    bars_l = ax.bar(x + width / 2, lumbar_vals, width, label="Peak lumbar lean", color="red",    alpha=0.85)

    # Red outline on flagged reps
    for i, flag in enumerate(flagged):
        if flag:
            bars_l[i].set_edgecolor("darkred")
            bars_l[i].set_linewidth(2.5)

    if lumbar_baseline is not None:
        ax.axhline(lumbar_baseline,                          color="red",     linestyle="--", alpha=0.5, label=f"Lumbar baseline ({lumbar_baseline:.1f}°)")
        ax.axhline(lumbar_baseline + LUMBAR_FLEX_THRESHOLD,  color="darkred", linestyle=":",  alpha=0.5, label=f"Flag threshold ({lumbar_baseline + LUMBAR_FLEX_THRESHOLD:.1f}°)")

    ax.set_xticks(x)
    ax.set_xticklabels([f"Rep {r}" for r in reps])
    ax.set_ylabel("Degrees")
    ax.set_title("Peak trunk & lumbar lean per rep  (red outline = lumbar flag triggered)")
    ax.legend(fontsize=8)
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig("rep_summary.png", dpi=150)
    plt.close(fig)
    print("Rep summary chart saved as rep_summary.png")


def save_angle_chart(frame_data, lumbar_baseline):
    frames       = [d["frame"]       for d in frame_data]
    knee_angles  = to_float_series(frame_data, "knee_angle")
    hip_angles   = to_float_series(frame_data, "hip_angle")
    trunk_leans  = to_float_series(frame_data, "trunk_lean")
    lumbar_leans = to_float_series(frame_data, "lumbar_lean")

    knee_3d      = to_float_series(frame_data, "knee_angle_3d")

    fig, ax = plt.subplots(figsize=(14, 6))
    ax.plot(frames, knee_angles,  label="Knee angle",  color="green")
    ax.plot(frames, knee_3d,      label="Knee angle (3D world)", color="teal", linestyle=":")
    ax.plot(frames, hip_angles,   label="Hip angle",   color="gold")
    ax.plot(frames, trunk_leans,  label="Trunk lean",  color="orange")
    ax.plot(frames, lumbar_leans, label="Lumbar lean", color="red", linestyle="--")

    # Baseline reference lines
    if lumbar_baseline is not None:
        ax.axhline(lumbar_baseline, color="red", linestyle=":", alpha=0.5,
                   label=f"Lumbar baseline ({lumbar_baseline:.1f}°)")
        ax.axhline(lumbar_baseline + LUMBAR_FLEX_THRESHOLD, color="darkred",
                   linestyle=":", alpha=0.5,
                   label=f"Lumbar flag threshold ({lumbar_baseline + LUMBAR_FLEX_THRESHOLD:.1f}°)")

    # Shade flagged frames
    flagged = [d["frame"] for d in frame_data if d.get("lumbar_flag")]
    if flagged:
        # Group consecutive flagged frames into spans
        spans, start = [], flagged[0]
        for i in range(1, len(flagged)):
            if flagged[i] - flagged[i - 1] > PROCESS_EVERY_N_FRAMES * 3:
                spans.append((start, flagged[i - 1]))
                start = flagged[i]
        spans.append((start, flagged[-1]))
        for s, e in spans:
            ax.axvspan(s, e, color="red", alpha=0.12)

    # Rep completion markers
    prev_count = 0
    for d in frame_data:
        if d["rep_count"] > prev_count:
            ax.axvline(x=d["frame"], color="purple", linestyle="--", alpha=0.6, linewidth=1.2)
            ax.text(d["frame"] + 1, 155, f'Rep {d["rep_count"]}', fontsize=8, color="purple")
            prev_count = d["rep_count"]

    ax.set_xlabel("Frame")
    ax.set_ylabel("Degrees")
    ax.set_title("Joint angles across lift")
    ax.legend(fontsize=8)
    ax.grid(True, alpha=0.4)
    fig.tight_layout()
    fig.savefig("angle_chart.png", dpi=150)
    plt.close(fig)
    print("Chart saved as angle_chart.png")


# ------------------ INIT ------------------

print("Loading models...")

estimator     = SpinePoseEstimator(mode="small")
SPINE_INDICES = estimator.SPINE_IDS

mp_pose = mp.solutions.pose
mp_draw = mp.solutions.drawing_utils
pose = mp_pose.Pose(
    model_complexity=1,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

cap          = cv2.VideoCapture(VIDEO_PATH)
fps          = cap.get(cv2.CAP_PROP_FPS) or 30.0   # broken metadata reports 0
w            = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
h            = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

out = cv2.VideoWriter(
    OUTPUT_PATH,
    cv2.VideoWriter_fourcc(*"mp4v"),
    fps / PROCESS_EVERY_N_FRAMES,
    (w, h)
)

frame_data  = []
frame_index = 0

# Effective sample rate after frame skipping — what the smoother actually sees
smoother = PointSmoother(freq=fps / PROCESS_EVERY_N_FRAMES)

last_knee   = None
last_hip    = None
last_trunk  = None
last_lumbar = None
last_knee3d = None
last_hip3d  = None

# Rep detection state
rep_count     = 0
in_rep        = False
phase         = "STANDING"
frames_in_rep = 0
knee_history  = deque(maxlen=7)

# Per-rep flag tracking: rep_index → flag count
rep_flags = {}

# Calibration state
calib_lumbar_samples = []
calib_trunk_samples  = []
calibration_done     = False
lumbar_baseline      = None
trunk_baseline       = None

PHASE_COLORS = {
    "STANDING":   (200, 200, 200),
    "DESCENDING": (0,   165, 255),
    "BOTTOM":     (0,   80,  255),
    "ASCENDING":  (0,   210,   0),
}

print(f"Processing {total_frames} frames (analysing every {PROCESS_EVERY_N_FRAMES})...")

# ------------------ MAIN LOOP ------------------

while True:
    ret, frame = cap.read()
    if not ret:
        break

    frame_index += 1

    if frame_index % PROCESS_EVERY_N_FRAMES != 0:
        continue

    processed = frame_index // PROCESS_EVERY_N_FRAMES
    if processed % 100 == 0:
        pct = (frame_index / total_frames) * 100
        print(f"  {pct:.1f}%  ({frame_index}/{total_frames} frames)")

    rgb   = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    t_now = frame_index / fps

    # -------- MediaPipe body pose --------
    mp_result  = pose.process(rgb)
    knee_angle = last_knee
    hip_angle  = last_hip

    if mp_result.pose_landmarks:
        lms = mp_result.pose_landmarks.landmark

        # Smooth positions first, then compute angles from the smoothed points
        left_hip      = smoother.smooth("l_hip",      get_landmark_coords(lms, 23, w, h), t_now)
        left_knee     = smoother.smooth("l_knee",     get_landmark_coords(lms, 25, w, h), t_now)
        left_ankle    = smoother.smooth("l_ankle",    get_landmark_coords(lms, 27, w, h), t_now)
        left_shoulder = smoother.smooth("l_shoulder", get_landmark_coords(lms, 11, w, h), t_now)

        knee_angle = calculate_angle(left_hip, left_knee, left_ankle)
        hip_angle  = calculate_angle(left_shoulder, left_hip, left_knee)
        last_knee, last_hip = knee_angle, hip_angle

        draw_text_bg(frame, f"Knee: {knee_angle:.1f}", (int(left_knee[0]), int(left_knee[1])), color=(0, 255, 0))
        draw_text_bg(frame, f"Hip:  {hip_angle:.1f}",  (int(left_hip[0]),  int(left_hip[1])),  color=(255, 255, 0))

        mp_draw.draw_landmarks(
            frame, mp_result.pose_landmarks, mp_pose.POSE_CONNECTIONS
        )

    # -------- 3D angles from BlazePose world landmarks --------
    # pose_world_landmarks is metric 3D (meters, origin at hip midpoint) inferred
    # by the model — view-independent baseline for the depth pipeline to beat.
    knee_angle_3d = last_knee3d
    hip_angle_3d  = last_hip3d

    if mp_result.pose_world_landmarks:
        wl = mp_result.pose_world_landmarks.landmark
        w_shoulder = smoother.smooth("w_l_shoulder", (wl[11].x, wl[11].y, wl[11].z), t_now)
        w_hip      = smoother.smooth("w_l_hip",      (wl[23].x, wl[23].y, wl[23].z), t_now)
        w_knee     = smoother.smooth("w_l_knee",     (wl[25].x, wl[25].y, wl[25].z), t_now)
        w_ankle    = smoother.smooth("w_l_ankle",    (wl[27].x, wl[27].y, wl[27].z), t_now)

        knee_angle_3d = calculate_angle(w_hip, w_knee, w_ankle)
        hip_angle_3d  = calculate_angle(w_shoulder, w_hip, w_knee)
        last_knee3d, last_hip3d = knee_angle_3d, hip_angle_3d

    # -------- Rep detection — state machine on knee angle --------
    if knee_angle is not None:
        knee_history.append(knee_angle)

        if not in_rep and knee_angle < SQUAT_ENTRY_ANGLE:
            in_rep        = True
            frames_in_rep = 0
            rep_flags[rep_count + 1] = 0

        if in_rep:
            frames_in_rep += 1

            if len(knee_history) >= 4:
                trend = knee_history[-1] - knee_history[-4]
                if trend < -3:
                    phase = "DESCENDING"
                elif trend > 3:
                    phase = "ASCENDING"
                else:
                    phase = "BOTTOM"

            if knee_angle > SQUAT_EXIT_ANGLE and frames_in_rep >= MIN_REP_FRAMES:
                in_rep    = False
                rep_count += 1
                phase      = "STANDING"
        else:
            phase = "STANDING"

    # -------- SpinePose — called ONCE per frame --------
    keypoints, scores = estimator(frame)

    trunk_lean  = last_trunk
    lumbar_lean = last_lumbar

    if len(keypoints) > 0:
        spine_pts = extract_spine_points(keypoints, scores, SPINE_INDICES, CONFIDENCE_THRESHOLD)
        spine_pts = [
            smoother.smooth(f"spine_{i}", pt, t_now)
            for i, pt in enumerate(spine_pts)
        ]
        frame = draw_spine_chain(frame, spine_pts)

        hip_pt    = spine_pts[0]
        lumbar_pt = spine_pts[LUMBAR_TOP_POS]
        trunk_pt  = spine_pts[TRUNK_TOP_POS]

        if hip_pt is not None and trunk_pt is not None:
            trunk_lean = angle_from_vertical(hip_pt, trunk_pt)
            last_trunk = trunk_lean

        if hip_pt is not None and lumbar_pt is not None:
            lumbar_lean = angle_from_vertical(hip_pt, lumbar_pt)
            last_lumbar = lumbar_lean

    # -------- Calibration — lock baseline from first N standing frames --------
    if not calibration_done and not in_rep:
        if lumbar_lean is not None:
            calib_lumbar_samples.append(lumbar_lean)
        if trunk_lean is not None:
            calib_trunk_samples.append(trunk_lean)
        if len(calib_lumbar_samples) >= CALIBRATION_FRAMES and len(calib_trunk_samples) >= CALIBRATION_FRAMES:
            lumbar_baseline  = float(np.mean(calib_lumbar_samples))
            trunk_baseline   = float(np.mean(calib_trunk_samples))
            calibration_done = True
            print(f"  Baseline locked — lumbar: {lumbar_baseline:.1f}°  trunk: {trunk_baseline:.1f}°")

    # -------- Rules engine --------
    lumbar_flag = False
    if (phase == "ASCENDING"
            and calibration_done
            and lumbar_lean is not None
            and lumbar_lean > lumbar_baseline + LUMBAR_FLEX_THRESHOLD):
        lumbar_flag = True
        current_rep = rep_count + 1  # rep in progress
        rep_flags[current_rep] = rep_flags.get(current_rep, 0) + 1

    # -------- Overlay text --------
    y_offset = 40
    if trunk_lean is not None:
        draw_text_bg(frame, f"Trunk lean:  {trunk_lean:.1f} deg",  (20, y_offset),      color=(0, 165, 255))
    if lumbar_lean is not None:
        draw_text_bg(frame, f"Lumbar lean: {lumbar_lean:.1f} deg", (20, y_offset + 30), color=(0, 100, 255))

    if lumbar_baseline is not None:
        calib_text = f"Baseline: {lumbar_baseline:.1f} deg"
        draw_text_bg(frame, calib_text, (20, y_offset + 60), color=(180, 180, 180), font_scale=0.5, thickness=1)
    elif not calibration_done:
        remaining = CALIBRATION_FRAMES - len(calib_lumbar_samples)
        draw_text_bg(frame, f"Calibrating... ({remaining} frames)", (20, y_offset + 60),
                     color=(180, 180, 50), font_scale=0.5, thickness=1)

    if lumbar_flag:
        draw_text_bg(frame, "! LUMBAR FLEXION", (20, h - 70),
                     font_scale=0.8, color=(0, 0, 255), thickness=2)

    phase_color = PHASE_COLORS.get(phase, (255, 255, 255))
    draw_text_bg(frame, phase, (20, h - 30), font_scale=0.8, color=phase_color, thickness=2)

    rep_text = f"Reps: {rep_count}"
    draw_text_bg(frame, rep_text, (w - 130, 40), font_scale=1.0, color=(255, 255, 255), thickness=2)

    # -------- Store per-frame data --------
    frame_data.append({
        "frame":         frame_index,
        "knee_angle":    knee_angle,
        "hip_angle":     hip_angle,
        "knee_angle_3d": knee_angle_3d,
        "hip_angle_3d":  hip_angle_3d,
        "trunk_lean":    trunk_lean,
        "lumbar_lean":   lumbar_lean,
        "phase":         phase,
        "rep_count":     rep_count,
        "lumbar_flag":   lumbar_flag,
    })

    out.write(frame)

# ------------------ CLEANUP ------------------

cap.release()
out.release()

print(f"\nDone. Saved as {OUTPUT_PATH}")
print(f"Frames analysed: {len(frame_data)}")
print(f"Total reps detected: {rep_count}")

if lumbar_baseline is not None:
    print(f"Lumbar baseline: {lumbar_baseline:.1f}°  |  Trunk baseline: {trunk_baseline:.1f}°")
    print(f"Lumbar flag threshold: {lumbar_baseline + LUMBAR_FLEX_THRESHOLD:.1f}°")
else:
    print("WARNING: calibration baseline was never locked (not enough standing frames at start)")

if rep_flags:
    print("\nPer-rep flag summary:")
    for rep_num in sorted(rep_flags):
        flagged = rep_flags[rep_num]
        status = f"  {flagged} flagged frames" if flagged else "  clean"
        print(f"  Rep {rep_num}:{status}")

# ------------------ PER-REP STATS ------------------

rep_stats = compute_rep_stats(frame_data, rep_count, fps, PROCESS_EVERY_N_FRAMES)
print_rep_table(rep_stats)

# ------------------ CHART OUTPUT ------------------

save_angle_chart(frame_data, lumbar_baseline)
save_rep_chart(rep_stats, lumbar_baseline)

# ------------------ JSON EXPORT (frontend) ------------------

session = {
    "schema_version": 1,
    "video": os.path.basename(VIDEO_PATH),
    "exercise": "squat",
    "date": datetime.now().isoformat(timespec="seconds"),
    "fps": fps,
    "process_every_n": PROCESS_EVERY_N_FRAMES,
    "rep_count": rep_count,
    "lumbar_baseline": lumbar_baseline,
    "trunk_baseline": trunk_baseline,
    "lumbar_flex_threshold": LUMBAR_FLEX_THRESHOLD,
    "calibrated": calibration_done,
    "smoothing": {
        "filter": "one_euro",
        "mincutoff": SMOOTH_MINCUTOFF,
        "beta": SMOOTH_BETA,
    },
    "reps": rep_stats,
    "frames": frame_data,
}

json_path = f"session_{_base}.json"
with open(json_path, "w") as f:
    json.dump(session, f)
print(f"Session data exported as {json_path}")