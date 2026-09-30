// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// GPU time per fresh frame, from mpv's `vo-passes` property.
nonisolated struct VOPassTiming: Equatable, Sendable {
    /// Sum of every fresh pass's average, in milliseconds.
    let totalMilliseconds: Double
    /// The fewest samples any fresh pass has. libplacebo keeps samples per
    /// pass and starts again from zero when a shader stack changes, so a low
    /// count means the averages still include the shader compile.
    let minimumSampleCount: Int
}

nonisolated extension VOPassTiming {
    /// Parses `vo-passes` read as a string. mpv prints node properties with
    /// `json_write`, and every time is in nanoseconds.
    ///
    /// Passes with no samples at all are left out. With some shader stacks
    /// (FSRCNNX_x2_16) mpv 0.41 never samples the final output pass, and
    /// counting it would hold the warm-up gate shut for the whole file.
    init?(json: String) {
        struct Pass: Decodable { let avg: Int64; let count: Int64 }
        struct Passes: Decodable { let fresh: [Pass] }
        guard let passes = try? JSONDecoder().decode(Passes.self, from: Data(json.utf8)) else { return nil }
        let sampled = passes.fresh.filter { $0.count > 0 }
        guard let fewest = sampled.map(\.count).min() else { return nil }
        self.init(
            totalMilliseconds: Double(sampled.reduce(0) { $0 + $1.avg }) / 1_000_000,
            minimumSampleCount: Int(fewest)
        )
    }
}

/// One once-a-second reading taken while playing.
nonisolated struct BudgetSample: Sendable {
    let timing: VOPassTiming?
    /// mpv's `frame-drop-count`. Frames dropped by the VO under `framedrop=vo`.
    let droppedFrames: Int
    /// `ProcessInfo.systemUptime` when the sample was taken.
    let uptime: TimeInterval
}

/// Decides whether the active shader tier fits the GPU.
///
/// The budget is half the frame period of the slower of source and display,
/// because fresh frames are needed only at that rate. The 0.5 comes from
/// measurement: at 24 fps, ArtCNN C4F32 dropped frames while using 68% of
/// the period, and C4F16 at 29% did not. The drop counter backs the timing
/// up, because `vo-passes` misses queueing and presentation cost.
nonisolated struct GPUBudgetMonitor: Sendable {
    enum Verdict: Equatable, Sendable { case warmingUp, withinBudget, overBudget }

    static let budgetFraction = 0.5
    static let warmUpSamples = 30
    static let dropLimit = 3
    static let dropWindow: TimeInterval = 2

    /// `nil` when neither frame rate is known. Only drops count then.
    let budgetMilliseconds: Double?
    private var dropHistory: [(uptime: TimeInterval, count: Int)] = []

    init(sourceFPS: Double, displayFPS: Double) {
        let slowest = [sourceFPS, displayFPS].filter { $0.isFinite && $0 > 0 }.min()
        budgetMilliseconds = slowest.map { Self.budgetFraction * 1000 / $0 }
    }

    mutating func evaluate(_ sample: BudgetSample) -> Verdict {
        dropHistory.append((sample.uptime, sample.droppedFrames))
        dropHistory.removeAll { sample.uptime - $0.uptime > Self.dropWindow }
        if let oldest = dropHistory.first, sample.droppedFrames - oldest.count >= Self.dropLimit {
            return .overBudget
        }
        guard let budget = budgetMilliseconds, let timing = sample.timing else { return .withinBudget }
        guard timing.minimumSampleCount >= Self.warmUpSamples else { return .warmingUp }
        return timing.totalMilliseconds > budget ? .overBudget : .withinBudget
    }

    /// libplacebo logs this at error level when a user shader fails, and then
    /// skips the hook every frame without further notice (`renderer.c:1103`).
    static func isShaderFailure(prefix: String, text: String) -> Bool {
        prefix == "vo/gpu-next/libplacebo" && text.hasPrefix("Failed executing hook")
    }
}
