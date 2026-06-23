# Architecture Overview

TUS Rise aims to detect squats and deadlifts and compute spinal angles to help prevent injuries.

High-level components:
- Mobile (iOS) client:
  - Camera capture, local preprocessing, optional on-device inference for pose/keypoint extraction.
  - UI for repetition counting, feedback, and history.
- Prototype/Server (Python):
  - CV pipeline (pose estimation -> spine segmentation -> angle computation).
  - Data labeling/analytics (offline evaluation).
- Data handling:
  - Test videos stored via Git LFS or external storage.
  - Health and personally identifiable data must be stored securely; consider encryption and minimal retention.

Key algorithms:
- Pose/keypoint estimation (MediaPipe / OpenPose / a custom model).
- Spinal angle calculation from keypoints: compute lumbar and thoracic angles, and hip angles; measure changes across reps and flag unsafe ranges.
- Repetition segmentation and drop detection.

Privacy & compliance:
- Explicit user consent for video capture.
- Optionally process on-device to avoid transmitting video.
- Anonymize or aggregate metrics if collecting for analytics.

Next steps:
- Choose on-device vs server inference.
- Define thresholds for "unsafe" angles and feedback messages.
