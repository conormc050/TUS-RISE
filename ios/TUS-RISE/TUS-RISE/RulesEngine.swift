//
//  RulesEngine.swift
//  TUS-RISE
//
//  Faithful port of VidCalc.py's rep state machine, calibration, and
//  rules engine (step 4 of the iOS port). Pure logic — Foundation only,
//  no Vision/UIKit — so it can move into the portable analysis package
//  and be unit-tested against JSON fixtures from the Python pipeline.
//
//  Deviations from VidCalc.py (temporary, until SpinePose lands in step 5):
//  - lumbar_lean is never available, so the lumbar baseline can't lock and
//    the lumbar-flexion flag can't fire. `calibrated` stays false — honest.
//  - The trunk baseline locks independently from standing frames so trunk
//    numbers are usable now. VidCalc locks lumbar+trunk together; restore
//    that coupling when spine keypoints exist.
//  - No One Euro smoothing on positions yet — Vision output is steadier
//    than raw MediaPipe, and the 5° hysteresis + MIN_REP_FRAMES guard
//    double-counting. Port PointSmoother if rep counts prove jittery.
//

import Foundation

/// Mirrors the CONFIG block in VidCalc.py — keep names and values in sync.
nonisolated struct RulesConfig {
    var squatEntryAngle: Double = 120    // knee below this → rep started
    var squatExitAngle: Double = 125     // knee above this (after entry) → rep complete
    var minRepFrames: Int = 8            // minimum processed frames for a real rep
    var calibrationFrames: Int = 40      // standing frames needed to lock the baseline
    var lumbarFlexThreshold: Double = 12 // degrees over baseline that trigger a flag
}

nonisolated enum RulesEngine {

    struct Result {
        var frames: [FrameSample]        // phase / rep_count / lumbar_flag filled in
        var reps: [RepStat]
        var repCount: Int
        var lumbarBaseline: Double?
        var trunkBaseline: Double?
        var calibrated: Bool             // true only when the spine baseline locked
    }

    /// Run the state machine over per-frame angles (already in VidCalc's
    /// processed-frame order) and tag phases, count reps, and apply rules.
    static func process(frames rawFrames: [FrameSample],
                        fps: Double,
                        processEveryN: Int,
                        config: RulesConfig = RulesConfig()) -> Result {
        var kneeHistory: [Double] = []   // rolling window; trend needs last 4
        var inRep = false
        var framesInRep = 0
        var repCount = 0
        var phase = "STANDING"

        var calibLumbar: [Double] = []
        var calibTrunk: [Double] = []
        var calibrationDone = false
        var lumbarBaseline: Double?
        var trunkBaseline: Double?

        var frames: [FrameSample] = []
        frames.reserveCapacity(rawFrames.count)

        for var f in rawFrames {
            // ---- Rep detection — state machine on knee angle ----
            if let knee = f.knee_angle {
                kneeHistory.append(knee)
                if kneeHistory.count > 7 { kneeHistory.removeFirst() }

                if !inRep && knee < config.squatEntryAngle {
                    inRep = true
                    framesInRep = 0
                }

                if inRep {
                    framesInRep += 1

                    if kneeHistory.count >= 4 {
                        let trend = kneeHistory[kneeHistory.count - 1] - kneeHistory[kneeHistory.count - 4]
                        if trend < -3 {
                            phase = "DESCENDING"
                        } else if trend > 3 {
                            phase = "ASCENDING"
                        } else {
                            phase = "BOTTOM"
                        }
                    }

                    if knee > config.squatExitAngle && framesInRep >= config.minRepFrames {
                        inRep = false
                        repCount += 1
                        phase = "STANDING"
                    }
                } else {
                    phase = "STANDING"
                }
            }

            // ---- Calibration — lock baseline from first N standing frames ----
            if !calibrationDone && !inRep {
                if let lumbar = f.lumbar_lean { calibLumbar.append(lumbar) }
                if let trunk = f.trunk_lean { calibTrunk.append(trunk) }
                if calibLumbar.count >= config.calibrationFrames,
                   calibTrunk.count >= config.calibrationFrames {
                    lumbarBaseline = calibLumbar.reduce(0, +) / Double(calibLumbar.count)
                    trunkBaseline = calibTrunk.reduce(0, +) / Double(calibTrunk.count)
                    calibrationDone = true
                }
                // Temporary trunk-only lock (see header) so trunk numbers work
                // before SpinePose provides lumbar data.
                if trunkBaseline == nil, calibTrunk.count >= config.calibrationFrames {
                    trunkBaseline = calibTrunk.reduce(0, +) / Double(calibTrunk.count)
                }
            }

            // ---- Rules engine ----
            var lumbarFlag = false
            if phase == "ASCENDING",
               calibrationDone,
               let lumbar = f.lumbar_lean,
               let baseline = lumbarBaseline,
               lumbar > baseline + config.lumbarFlexThreshold {
                lumbarFlag = true
            }

            f.phase = phase
            f.rep_count = repCount
            f.lumbar_flag = lumbarFlag
            frames.append(f)
        }

        let reps = repStats(frames: frames, totalReps: repCount,
                            fps: fps, processEveryN: processEveryN)
        return Result(frames: frames,
                      reps: reps,
                      repCount: repCount,
                      lumbarBaseline: lumbarBaseline,
                      trunkBaseline: trunkBaseline,
                      calibrated: calibrationDone)
    }

    /// Port of compute_rep_stats(): group tagged frames by rep and summarise.
    static func repStats(frames: [FrameSample],
                         totalReps: Int,
                         fps: Double,
                         processEveryN: Int) -> [RepStat] {
        var buckets: [Int: [FrameSample]] = [:]
        for f in frames where f.phase != "STANDING" {
            let rep = f.rep_count + 1        // rep in progress = completed + 1
            guard rep <= totalReps else { continue }   // skip incomplete last rep
            buckets[rep, default: []].append(f)
        }

        func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

        return buckets.keys.sorted().map { rep in
            let fr = buckets[rep]!
            let knees = fr.compactMap(\.knee_angle)
            let trunks = fr.compactMap(\.trunk_lean)
            let lumbars = fr.compactMap(\.lumbar_lean)
            return RepStat(rep: rep,
                           duration: round1(Double(fr.count * processEveryN) / fps),
                           depth: knees.min().map(round1),
                           trunk: trunks.max().map(round1),
                           lumbar: lumbars.max().map(round1),
                           flags: fr.filter(\.lumbar_flag).count)
        }
    }
}
