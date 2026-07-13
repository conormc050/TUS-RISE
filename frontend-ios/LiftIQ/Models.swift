//
//  Models.swift
//  LiftIQ
//
//  Data model matching the JSON exported by VidCalc.py
//  (session_<video>.json, schema_version 1), plus the session
//  store with bundled mock data and file import.
//

import Foundation

// MARK: - Codable payload (mirrors VidCalc export exactly)

struct SessionPayload: Codable {
    var schema_version: Int?
    var video: String?
    var exercise: String?
    var date: String?
    var fps: Double?
    var process_every_n: Int?
    var rep_count: Int?
    var lumbar_baseline: Double?
    var trunk_baseline: Double?
    var lumbar_flex_threshold: Double?
    var calibrated: Bool?
    var reps: [RepStat]?
    var frames: [FrameSample]?
}

struct RepStat: Codable, Identifiable {
    var rep: Int
    var duration: Double?
    var depth: Double?
    var trunk: Double?
    var lumbar: Double?
    var flags: Int
    var id: Int { rep }
}

struct FrameSample: Codable, Identifiable {
    var frame: Int
    var knee_angle: Double?
    var hip_angle: Double?
    var trunk_lean: Double?
    var lumbar_lean: Double?
    var phase: String
    var rep_count: Int
    var lumbar_flag: Bool
    var id: Int { frame }
}

// MARK: - App-facing session

struct LiftSession: Identifiable {
    let id: String
    let isMock: Bool
    let video: String
    let exercise: String
    let date: Date
    let fps: Double
    let everyN: Int
    let repCount: Int
    let lumbarBaseline: Double?
    let trunkBaseline: Double?
    let threshold: Double
    let calibrated: Bool
    let reps: [RepStat]
    let frames: [FrameSample]

    var flaggedReps: Int { reps.filter { $0.flags > 0 }.count }

    var bestDepth: Double? {
        reps.compactMap(\.depth).min()
    }

    /// Form score heuristic (0–100): penalises lumbar flags,
    /// shallow depth, and inconsistent depth. Mirrors the web prototype.
    var score: Int? {
        guard !reps.isEmpty else { return nil }
        var s = 100.0
        let totalFlags = reps.reduce(0) { $0 + $1.flags }
        s -= min(45, Double(totalFlags) * 2.2)
        let depths = reps.compactMap(\.depth)
        if !depths.isEmpty {
            let avg = depths.reduce(0, +) / Double(depths.count)
            if avg > 100 { s -= min(20, (avg - 100) * 0.8) }
            let spread = depths.max()! - depths.min()!
            s -= min(15, max(0, spread - 12) * 0.9)
        }
        if !calibrated { s -= 10 }
        return max(0, Int(s.rounded()))
    }

    init(payload: SessionPayload, id: String = UUID().uuidString, isMock: Bool = false) {
        self.id = id
        self.isMock = isMock
        self.video = payload.video ?? "unknown.mp4"
        self.exercise = payload.exercise ?? "squat"
        self.date = payload.date.flatMap { ISO8601DateFormatter.flexible.date(from: $0) } ?? Date()
        self.fps = payload.fps ?? 30
        self.everyN = payload.process_every_n ?? 1
        self.reps = payload.reps ?? []
        self.repCount = payload.rep_count ?? self.reps.count
        self.lumbarBaseline = payload.lumbar_baseline
        self.trunkBaseline = payload.trunk_baseline
        self.threshold = payload.lumbar_flex_threshold ?? 12
        self.calibrated = (payload.calibrated ?? true) && payload.lumbar_baseline != nil
        self.frames = payload.frames ?? []
    }
}

extension ISO8601DateFormatter {
    /// Accepts both with and without fractional seconds.
    static let flexible: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Store

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [LiftSession] = []

    init() {
        sessions = MockData.sessions()
    }

    var sorted: [LiftSession] { sessions.sorted { $0.date > $1.date } }
    var latest: LiftSession? { sorted.first }

    func session(id: String) -> LiftSession? { sessions.first { $0.id == id } }

    @discardableResult
    func importSession(from url: URL) throws -> LiftSession {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let payload = try JSONDecoder().decode(SessionPayload.self, from: data)
        let session = LiftSession(payload: payload)
        sessions.insert(session, at: 0)
        return session
    }

    // Aggregates ---------------------------------------------------

    struct WeekStats { let sessions: Int; let reps: Int; let avgScore: Int? }

    var weekStats: WeekStats {
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        let wk = sessions.filter { $0.date >= cutoff }
        let scores = wk.compactMap(\.score)
        return WeekStats(
            sessions: wk.count,
            reps: wk.reduce(0) { $0 + $1.repCount },
            avgScore: scores.isEmpty ? nil : scores.reduce(0, +) / scores.count
        )
    }

    struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Int?
        let avgDepth: Double?
        let flagRate: Double
    }

    var trendPoints: [TrendPoint] {
        sorted.reversed().map { s in
            let depths = s.reps.compactMap(\.depth)
            return TrendPoint(
                date: s.date,
                score: s.score,
                avgDepth: depths.isEmpty ? nil : depths.reduce(0, +) / Double(depths.count),
                flagRate: s.repCount > 0 ? Double(s.flaggedReps) / Double(s.repCount) * 100 : 0
            )
        }
    }
}

// MARK: - Mock data generator (mirrors data.js)

enum MockData {
    static func sessions() -> [LiftSession] {
        [
            make(id: "m1", daysAgo: 0,  exercise: "squat",    reps: 5,  bad: [3],        name: "Squat3.mp4"),
            make(id: "m2", daysAgo: 2,  exercise: "squat",    reps: 8,  bad: [6, 7],     name: "Squat_heavy.mp4"),
            make(id: "m3", daysAgo: 5,  exercise: "deadlift", reps: 5,  bad: [],         name: "DL_warmup.mp4"),
            make(id: "m4", daysAgo: 9,  exercise: "squat",    reps: 6,  bad: [],         name: "Squat_light.mp4"),
            make(id: "m5", daysAgo: 14, exercise: "deadlift", reps: 4,  bad: [4],        name: "DL_top_set.mp4"),
            make(id: "m6", daysAgo: 20, exercise: "squat",    reps: 10, bad: [8, 9, 10], name: "Squat_amrap.mp4"),
        ]
    }

    private static func make(id: String, daysAgo: Int, exercise: String,
                             reps: Int, bad: [Int], name: String) -> LiftSession {
        let fps = 30.0, everyN = 2
        let lumbarBase = Double.random(in: 6...10)
        let trunkBase = Double.random(in: 9...13)
        let threshold = 12.0
        var frames: [FrameSample] = []
        var idx = 0
        func push(_ knee: Double, _ hip: Double, _ trunk: Double, _ lumbar: Double,
                  _ phase: String, _ repCount: Int, _ flag: Bool) {
            idx += everyN
            frames.append(FrameSample(frame: idx, knee_angle: knee, hip_angle: hip,
                                      trunk_lean: trunk, lumbar_lean: lumbar,
                                      phase: phase, rep_count: repCount, lumbar_flag: flag))
        }
        func noise(_ amp: Double) -> Double { Double.random(in: -amp/2...amp/2) }

        for _ in 0..<45 {
            push(172 + noise(3), 170 + noise(3), trunkBase + noise(2.5),
                 lumbarBase + noise(2), "STANDING", 0, false)
        }
        for r in 1...reps {
            let isBad = bad.contains(r)
            let depth = 78 + noise(10)
            let n = Int.random(in: 46...60)
            let half = n / 2
            for i in 0..<n {
                let t = Double(i) / Double(n - 1)
                let knee = depth + (172 - depth) * pow(abs(cos(.pi * t)), 1.3)
                let hip = 60 + 110 * pow(abs(cos(.pi * t)), 1.1)
                let trunk = trunkBase + 26 * sin(.pi * t) + noise(2)
                var lumbar = lumbarBase + 7 * sin(.pi * t) + noise(1.6)
                var flag = false
                if isBad, t > 0.5, t < 0.85 {
                    lumbar = lumbarBase + threshold + 4 + 5 * sin(.pi * (t - 0.5) / 0.35) + noise(1.5)
                    flag = lumbar > lumbarBase + threshold
                }
                let phase = i < half - 4 ? "DESCENDING" : (i < half + 4 ? "BOTTOM" : "ASCENDING")
                push(knee + noise(1.5), hip + noise(1.5), trunk, lumbar,
                     phase, r - 1, flag && phase == "ASCENDING")
            }
            for _ in 0..<8 {
                push(171 + noise(3), 169 + noise(3), trunkBase + noise(2.5),
                     lumbarBase + noise(2), "STANDING", r, false)
            }
        }

        // per-rep stats from frames
        var buckets: [Int: [FrameSample]] = [:]
        for f in frames where f.phase != "STANDING" {
            let rep = f.rep_count + 1
            if rep <= reps { buckets[rep, default: []].append(f) }
        }
        let repStats: [RepStat] = buckets.keys.sorted().map { rep in
            let fr = buckets[rep]!
            return RepStat(
                rep: rep,
                duration: (Double(fr.count * everyN) / fps * 10).rounded() / 10,
                depth: fr.compactMap(\.knee_angle).min().map { ($0 * 10).rounded() / 10 },
                trunk: fr.compactMap(\.trunk_lean).max().map { ($0 * 10).rounded() / 10 },
                lumbar: fr.compactMap(\.lumbar_lean).max().map { ($0 * 10).rounded() / 10 },
                flags: fr.filter(\.lumbar_flag).count
            )
        }

        var date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        date = Calendar.current.date(bySettingHour: Int.random(in: 9...19),
                                     minute: Int.random(in: 0...59), second: 0, of: date)!

        let payload = SessionPayload(
            schema_version: 1, video: name, exercise: exercise,
            date: ISO8601DateFormatter.flexible.string(from: date),
            fps: fps, process_every_n: everyN, rep_count: reps,
            lumbar_baseline: lumbarBase, trunk_baseline: trunkBase,
            lumbar_flex_threshold: threshold, calibrated: true,
            reps: repStats, frames: frames
        )
        return LiftSession(payload: payload, id: id, isMock: true)
    }
}
