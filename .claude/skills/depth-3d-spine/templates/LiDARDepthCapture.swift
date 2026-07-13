// LiDAR depth capture + keypoint unprojection for LiftIQ.
// Requires: iPhone Pro model with LiDAR (12 Pro+), iOS 14+ for sceneDepth.
// UNTESTED template written on Windows without a Mac — expect to fix small
// compiler issues, but the structure and math are correct.

import ARKit
import simd

final class LiDARDepthCapture: NSObject, ARSessionDelegate {

    let session = ARSession()

    /// Latest 3D spine points in camera space (x right, y down, z forward, meters)
    /// — same convention as the Python prototype.
    private(set) var spinePoints3D: [simd_float3?] = []

    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) else {
            fatalError("Device has no LiDAR / smoothedSceneDepth support")
        }
        let config = ARWorldTrackingConfiguration()
        // smoothedSceneDepth = temporally smoothed — preferred for a moving lifter.
        config.frameSemantics = .smoothedSceneDepth
        config.worldAlignment = .gravity   // world y = gravity → true vertical for lean angles
        session.delegate = self
        session.run(config)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }

        // depthMap: 256x192 Float32 meters. confidenceMap: UInt8 (0 low / 1 med / 2 high).
        // capturedImage (RGB): 1920x1440 — same aspect ratio, plain scaling maps between.
        let depthValues = Self.floatValues(from: sceneDepth.depthMap)
        let depthW = CVPixelBufferGetWidth(sceneDepth.depthMap)
        let depthH = CVPixelBufferGetHeight(sceneDepth.depthMap)

        let rgbW = Float(CVPixelBufferGetWidth(frame.capturedImage))
        let rgbH = Float(CVPixelBufferGetHeight(frame.capturedImage))

        // intrinsics are for the RGB resolution — we unproject in RGB pixel coords,
        // so no intrinsics rescaling needed; only the depth *lookup* is scaled.
        let K = frame.camera.intrinsics
        let fx = K[0][0], fy = K[1][1], cx = K[2][0], cy = K[2][1]

        // keypoints2D: SpinePose (or Vision) output in RGB pixel coordinates.
        // Wire your pose model's per-frame output in here.
        let keypoints2D: [simd_float2] = currentSpineKeypoints2D()

        spinePoints3D = keypoints2D.map { kp in
            let du = Int(kp.x * Float(depthW) / rgbW)
            let dv = Int(kp.y * Float(depthH) / rgbH)
            // 3x3 median patch — single-pixel lookup on a 256x192 map WILL grab
            // background depth at silhouette edges. Mirrors sample_depth() in Python.
            guard let d = Self.medianDepth(depthValues, w: depthW, h: depthH, u: du, v: dv)
            else { return nil }
            return simd_float3((kp.x - cx) * d / fx, (kp.y - cy) * d / fy, d)
        }
    }

    private static func medianDepth(_ depth: [Float], w: Int, h: Int,
                                    u: Int, v: Int, patch: Int = 3) -> Float? {
        let r = patch / 2
        var vals: [Float] = []
        for dv in max(0, v - r)...min(h - 1, v + r) {
            for du in max(0, u - r)...min(w - 1, u + r) {
                let d = depth[dv * w + du]
                if d.isFinite && d > 0 { vals.append(d) }
            }
        }
        guard !vals.isEmpty else { return nil }
        return vals.sorted()[vals.count / 2]
    }

    private static func floatValues(from buffer: CVPixelBuffer) -> [Float] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!
            .assumingMemoryBound(to: Float32.self)
        return Array(UnsafeBufferPointer(start: base, count: w * h))
    }

    private func currentSpineKeypoints2D() -> [simd_float2] {
        // TODO: SpinePose via ONNX Runtime, or Vision body pose — see ios-port skill.
        return []
    }
}
