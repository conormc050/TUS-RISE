import cv2
from spinepose import SpinePoseEstimator

estimator = SpinePoseEstimator()

#interface on a image
image = cv2.imread(r"C:\Users\conor\Downloads\me2.png")
keypoints, scores = estimator(image)
visualized = estimator.visualize (image, keypoints, scores)
cv2.imwrite('output4.jpg', visualized)
