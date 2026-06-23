# TUS Rise

TUS Rise is a mobile fitness app for tracking squats and deadlifts using computer vision to reduce injury risk by tracking spinal position and key angles.

Repository structure:
- ios/ — iOS/Xcode project
- python/ — Python prototype for computer-vision algorithms (angle detection, pose estimation)
- docs/ — Architecture, setup, roadmap, privacy notes
- test_videos/ — sample/test videos (use Git LFS or external storage)

Quick start:
- For Python prototype:
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r python/requirements.txt
  python python/main.py

- For iOS: open ios/ in Xcode after adding your workspace/project files.

Notes:
- Use Git LFS for storing videos: git lfs install; git lfs track "*.mp4"
- Confirm privacy/compliance requirements for handling video and biomechanical data.
