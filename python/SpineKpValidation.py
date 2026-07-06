import cv2
from spinepose import SpinePoseEstimator

estimator = SpinePoseEstimator(mode="small")
frame = cv2.imread(r"C:\Users\conor\OneDrive\Pictures\Screenshots\SquatPic1.png")  # grab one still frame from your video

keypoints, scores = estimator(frame)
person_kps = keypoints[0]

for i, (x, y) in enumerate(person_kps):
    cv2.putText(frame, str(i), (int(x), int(y)),
                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (0, 0, 255), 1)
    cv2.circle(frame, (int(x), int(y)), 3, (0, 255, 0), -1)

cv2.imwrite("keypoint_check.jpg", frame)