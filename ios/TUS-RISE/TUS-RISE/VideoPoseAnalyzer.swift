//
//  VideoPoseAnalyzer.swift
//  TUS-RISE
//
//  Step 3 of the iOS port: run Apple Vision's 3D body-pose model over an
//  imported video and emit per-frame knee/hip angles in the same shape as
//  VidCalc.py's session export, so the existing charts display them and
//  the numbers can be validated against the Python pipeline on the same
//  clip (tolerance ±3°; trends and rep counts are what must match).
//
//  Rep detection, phases, and calibration come from RulesEngine (step 4).
//  Lumbar/spine angles arrive with SpinePose (step 5).
//

import AVFoundation
import Vision
import simd

nonisolated enum VideoPoseAnalyzerError: LocalizedError {
    case noVideoTrack
    case decodeFailed(String)
    case visionFailed(String)
    case noPersonDetected

    var errorDescription: String? {
        switch self {
        case .noVideoTrack: return "The file has no video track."
        case .decodeFailed(let reason): return "Couldn't decode the video: \(reason)"
        case .visionFailed(let reason): return "The pose model couldn't run: \(reason)"
        case .noPersonDetected: return "No person was detected in the video."
        }
    }
}

nonisolated enum VideoPoseAnalyzer {

    /// Analyse every Nth frame — mirrors PROCESS_EVERY_N in VidCalc's CONFIG.
    static let processEveryN = 2

    /// Decode the video and run 3D body-pose detection frame by frame.
    /// Runs off the main actor; `progress` is called with 0…1.
    @concurrent
    static func analyze(url: URL,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> SessionPayload {
        // fileImporter URLs are security-scoped and may point at a file
        // provider (Files app, iCloud) that AVFoundation can't stream from —
        // copy into our own container and analyse the local copy instead.
        let localURL = try copyIntoSandbox(url)
        defer { try? FileManager.default.removeItem(at: localURL) }

        let asset = AVURLAsset(url: localURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoPoseAnalyzerError.noVideoTrack
        }
        let fps = try await track.load(.nominalFrameRate)
        let duration = try await asset.load(.duration)
        let expectedFrames = max(1.0, Double(fps) * duration.seconds)

        // iPhone videos carry rotation in preferredTransform (same gotcha as
        // OpenCV on Windows). Rather than passing an orientation hint to
        // Vision (unreliable for the 3D request), decode through a video
        // composition that bakes the rotation in — every frame reaches
        // Vision physically upright, portrait or landscape, front or back
        // camera.
        let videoComposition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        ])
        output.videoComposition = videoComposition
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var frames: [FrameSample] = []
        var index = 0
        var lastVisionError: Error?
        // The 3D pose model only runs on real Apple hardware — in the
        // simulator it throws, so we drop to the 2D model after the first
        // failure. 2D also mirrors VidCalc.py's pixel-space math exactly.
        var use3D = true

        while let sample = output.copyNextSampleBuffer() {
            defer { index += 1 }
            try Task.checkCancellation()
            guard index % processEveryN == 0,
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }

            progress(min(1, Double(index) / expectedFrames))

            var angles: FrameAngles?
            if use3D {
                do {
                    angles = try analyze3D(pixelBuffer)
                } catch {
                    lastVisionError = error
                    use3D = false
                }
            }
            if !use3D {
                do {
                    angles = try analyze2D(pixelBuffer)
                } catch {
                    lastVisionError = error
                    continue
                }
            }
            guard let angles else { continue }   // no person in this frame

            frames.append(FrameSample(frame: index,
                                      knee_angle: angles.knee,
                                      hip_angle: angles.hip,
                                      trunk_lean: angles.trunk,
                                      lumbar_lean: nil,      // needs SpinePose (step 5)
                                      phase: "UNKNOWN",      // needs rules engine (step 4)
                                      rep_count: 0,
                                      lumbar_flag: false))
        }
        progress(1)

        // Never finish silently with nothing to show — say why.
        if reader.status == .failed {
            throw VideoPoseAnalyzerError.decodeFailed(reader.error?.localizedDescription ?? "unknown decoder error")
        }
        if frames.isEmpty {
            if let lastVisionError {
                throw VideoPoseAnalyzerError.visionFailed(lastVisionError.localizedDescription)
            }
            throw VideoPoseAnalyzerError.noPersonDetected
        }

        // Step 4: rep detection, phases, calibration, and rules — the same
        // state machine as VidCalc.py, run over the per-frame angles.
        let config = RulesConfig()
        let result = RulesEngine.process(frames: frames,
                                         fps: Double(fps),
                                         processEveryN: processEveryN,
                                         config: config)

        let iso = ISO8601DateFormatter()
        return SessionPayload(schema_version: 1,
                              video: url.lastPathComponent,
                              exercise: "squat",
                              date: iso.string(from: Date()),
                              fps: Double(fps),
                              process_every_n: processEveryN,
                              rep_count: result.repCount,
                              lumbar_baseline: result.lumbarBaseline,
                              trunk_baseline: result.trunkBaseline,
                              lumbar_flex_threshold: config.lumbarFlexThreshold,
                              calibrated: result.calibrated,
                              reps: result.reps,
                              frames: result.frames)
    }

    /// Copy a picked file into the app's temp directory while we hold
    /// security-scoped access, so all later reads are plain local file I/O.
    private static func copyIntoSandbox(_ url: URL) throws -> URL {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
        let localURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: url, to: localURL)
        return localURL
    }

    /// Per-frame result, whichever pose model produced it.
    private struct FrameAngles {
        var knee: Double?
        var hip: Double?
        var trunk: Double?
    }

    /// Vision 3D body pose (17 joints, meters). Device + macOS only.
    /// Returns nil when no person is in the frame; throws if the model can't run.
    /// Frames arrive already upright (rotation baked in during decode).
    private static func analyze3D(_ pixelBuffer: CVPixelBuffer) throws -> FrameAngles? {
        let request = VNDetectHumanBodyPose3DRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try handler.perform([request])
        guard let obs = request.results?.first else { return nil }

        // Same joints as VidCalc (landmarks 11/23/25/27, left side).
        func pos(_ name: VNHumanBodyPose3DObservation.JointName) -> SIMD3<Float>? {
            guard let point = try? obs.recognizedPoint(name) else { return nil }
            let t = point.position.columns.3
            return SIMD3<Float>(t.x, t.y, t.z)
        }
        let shoulder = pos(.leftShoulder), hip = pos(.leftHip)
        let knee = pos(.leftKnee), ankle = pos(.leftAnkle)

        var angles = FrameAngles()
        if let hip, let knee, let ankle {
            angles.knee = AngleMath.jointAngle(at: knee, a: hip, c: ankle)
        }
        if let shoulder, let hip, let knee {
            angles.hip = AngleMath.jointAngle(at: hip, a: shoulder, c: knee)
        }
        if let shoulder, let hip {
            angles.trunk = AngleMath.angleFromVertical(from: hip, to: shoulder)
        }
        return (angles.knee == nil && angles.hip == nil) ? nil : angles
    }

    /// Vision 2D body pose fallback — runs everywhere, including the
    /// simulator, and matches VidCalc.py's pixel-space angles most closely.
    private static func analyze2D(_ pixelBuffer: CVPixelBuffer) throws -> FrameAngles? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try handler.perform([request])
        guard let obs = request.results?.first else { return nil }

        // Vision returns normalized coords (origin bottom-left); convert to
        // pixel coords with y down, like OpenCV, so the math matches the
        // Python pipeline. Frames are already upright from the decoder.
        let width = Float(CVPixelBufferGetWidth(pixelBuffer))
        let height = Float(CVPixelBufferGetHeight(pixelBuffer))
        func pos(_ name: VNHumanBodyPoseObservation.JointName) -> SIMD2<Float>? {
            guard let point = try? obs.recognizedPoint(name), point.confidence > 0.3 else { return nil }
            return SIMD2<Float>(Float(point.location.x) * width,
                                (1 - Float(point.location.y)) * height)
        }
        let shoulder = pos(.leftShoulder), hip = pos(.leftHip)
        let knee = pos(.leftKnee), ankle = pos(.leftAnkle)

        var angles = FrameAngles()
        if let hip, let knee, let ankle {
            angles.knee = AngleMath.jointAngle(at: knee, a: hip, c: ankle)
        }
        if let shoulder, let hip, let knee {
            angles.hip = AngleMath.jointAngle(at: hip, a: shoulder, c: knee)
        }
        if let shoulder, let hip {
            angles.trunk = AngleMath.angleFromVertical(from: hip, to: shoulder)
        }
        return (angles.knee == nil && angles.hip == nil) ? nil : angles
    }
}
