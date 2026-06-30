import cv2
import numpy as np
import mediapipe as mp
import matplotlib.pyplot as plt
from spinepose import SpinePoseEstimator

# ------------------ CONFIG ------------------

VIDEO_PATH  = r"C:\Users\conor\Downloads\Squat1.mp4"
OUTPUT_PATH = "output_combined.mp4"
PROCESS_EVERY_N_FRAMES = 2        # skip every other frame for speed
SPINE_INDICES          = list(range(17, 26))
CONFIDENCE_THRESHOLD   = 0.3

# ------------------ FUNCTIONS ------------------

def calculate_angle(a, b, c):
    a, b, c = np.array(a), np.array(b), np.array(c)
    ba, bc  = a - b, c - b
    denom   = np.linalg.norm(ba) * np.linalg.norm(bc)
    if denom == 0:
        return 0.0
    cosine = np.clip(np.dot(ba, bc) / denom, -1.0, 1.0)
    return float(np.degrees(np.arccos(cosine)))


def compute_spine_curvature(spine_points):
    valid = [p for p in spine_points if p is not None]
    if len(valid) < 3:
        return [], None
    segment_angles = []
    for i in range(len(valid) - 1):
        delta = np.array(valid[i + 1]) - np.array(valid[i])
        angle = np.degrees(np.arctan2(abs(delta[0]), abs(delta[1])))
        segment_angles.append(float(angle))
    top    = np.array(valid[0])
    bottom = np.array(valid[-1])
    diff   = bottom - top
    overall_lean = float(np.degrees(np.arctan2(abs(diff[0]), abs(diff[1]))))
    return segment_angles, overall_lean


def get_landmark_coords(landmarks, index, w, h):
    lm = landmarks[index]
    return (int(lm.x * w), int(lm.y * h))


def draw_text_bg(frame, text, pos, font_scale=0.6, color=(255, 255, 255), thickness=2):
    """Draw text with a dark background rectangle for readability in busy frames."""
    font = cv2.FONT_HERSHEY_SIMPLEX
    (tw, th), _ = cv2.getTextSize(text, font, font_scale, thickness)
    x, y = pos
    cv2.rectangle(frame, (x - 2, y - th - 4), (x + tw + 2, y + 4), (0, 0, 0), -1)
    cv2.putText(frame, text, pos, font, font_scale, color, thickness)


def save_angle_chart(frame_data):
    frames      = [d["frame"]      for d in frame_data]
    knee_angles = [d["knee_angle"] for d in frame_data]
    hip_angles  = [d["hip_angle"]  for d in frame_data]
    trunk_leans = [d["trunk_lean"] for d in frame_data]

    plt.figure(figsize=(14, 6))
    plt.plot(frames, knee_angles, label="Knee angle", color="green")
    plt.plot(frames, hip_angles,  label="Hip angle",  color="gold")
    plt.plot(frames, trunk_leans, label="Trunk lean", color="orange")
    plt.xlabel("Frame")
    plt.ylabel("Degrees")
    plt.title("Joint angles across lift")
    plt.legend()
    plt.grid(True, alpha=0.4)
    plt.tight_layout()
    plt.savefig("angle_chart.png", dpi=150)
    plt.close()
    print("Chart saved as angle_chart.png")


# ------------------ INIT ------------------

print("Loading models...")

# 'small' is meaningfully faster than 'medium' with acceptable accuracy loss
# swap back to 'medium' when validating final output quality
estimator = SpinePoseEstimator(mode="small")

mp_pose = mp.solutions.pose
mp_draw = mp.solutions.drawing_utils
pose = mp_pose.Pose(
    model_complexity=1,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

cap          = cv2.VideoCapture(VIDEO_PATH)
fps          = cap.get(cv2.CAP_PROP_FPS)
w            = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
h            = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

out = cv2.VideoWriter(
    OUTPUT_PATH,
    cv2.VideoWriter_fourcc(*'mp4v'),
    fps / PROCESS_EVERY_N_FRAMES,  # output fps matches skipped input fps
    (w, h)
)

frame_data  = []
frame_index = 0

# Cache last known values so output is always populated even on skipped frames
last_knee = None
last_hip  = None
last_lean = None

print(f"Processing {total_frames} frames (analysing every {PROCESS_EVERY_N_FRAMES})...")

# ------------------ MAIN LOOP ------------------

while True:
    ret, frame = cap.read()
    if not ret:
        break

    frame_index += 1

    # Skip frames for speed — only run models every Nth frame
    if frame_index % PROCESS_EVERY_N_FRAMES != 0:
        continue

    # Progress print every 100 processed frames
    processed = frame_index // PROCESS_EVERY_N_FRAMES
    if processed % 100 == 0:
        pct = (frame_index / total_frames) * 100
        print(f"  {pct:.1f}%  ({frame_index}/{total_frames} frames)")

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

    # -------- MediaPipe body pose --------
    mp_result  = pose.process(rgb)
    knee_angle = last_knee
    hip_angle  = last_hip

    if mp_result.pose_landmarks:
        lms = mp_result.pose_landmarks.landmark

        left_hip      = get_landmark_coords(lms, 23, w, h)
        left_knee     = get_landmark_coords(lms, 25, w, h)
        left_ankle    = get_landmark_coords(lms, 27, w, h)
        left_shoulder = get_landmark_coords(lms, 11, w, h)

        knee_angle = calculate_angle(left_hip, left_knee, left_ankle)
        hip_angle  = calculate_angle(left_shoulder, left_hip, left_knee)
        last_knee, last_hip = knee_angle, hip_angle

        draw_text_bg(frame, f"Knee: {knee_angle:.1f}", left_knee, color=(0, 255, 0))
        draw_text_bg(frame, f"Hip:  {hip_angle:.1f}",  left_hip,  color=(255, 255, 0))

        mp_draw.draw_landmarks(
            frame, mp_result.pose_landmarks, mp_pose.POSE_CONNECTIONS
        )

    # -------- SpinePose — called ONCE per frame --------
    keypoints, scores = estimator(frame)

    spine_points = []
    overall_lean = last_lean

    if len(keypoints) > 0:
        person_kps    = keypoints[0]
        person_scores = scores[0]

        for idx in SPINE_INDICES:
            if person_scores[idx] > CONFIDENCE_THRESHOLD:
                x, y = int(person_kps[idx][0]), int(person_kps[idx][1])
                spine_points.append((x, y))
            else:
                spine_points.append(None)

        _, computed_lean = compute_spine_curvature(spine_points)
        if computed_lean is not None:
            overall_lean = computed_lean
            last_lean    = overall_lean

        # Draw SpinePose skeleton on frame
        frame = estimator.visualize(frame, keypoints, scores)

    if overall_lean is not None:
        draw_text_bg(
            frame,
            f"Trunk lean: {overall_lean:.1f} deg",
            (20, 80),
            color=(0, 165, 255)
        )

    # -------- Store per-frame data for chart --------
    frame_data.append({
        "frame":      frame_index,
        "knee_angle": knee_angle,
        "hip_angle":  hip_angle,
        "trunk_lean": overall_lean,
    })

    out.write(frame)

# ------------------ CLEANUP ------------------

cap.release()
out.release()

print(f"\nDone. Saved as {OUTPUT_PATH}")
print(f"Frames analysed: {len(frame_data)}")

# ------------------ CHART OUTPUT ------------------

save_angle_chart(frame_data)