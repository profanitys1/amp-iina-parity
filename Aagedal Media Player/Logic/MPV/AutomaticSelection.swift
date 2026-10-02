// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The state behind the Automatic profile for one player: what is known about the file, what has
/// been rejected for it, and the profile that follows. It touches no mpv state, so the player only
/// applies the profile it returns.
nonisolated struct AutomaticSelection: Equatable, Sendable {
    nonisolated struct Choice: Equatable, Sendable {
        let profile: RenderProfile
        let classification: SourceClassification
        /// True once the GPU monitor or libplacebo has ruled out a heavier profile for this file.
        let isSteppedDown: Bool

        /// The badge text, for example `Auto · Compressed movie · 2.1 Mbit/s`.
        var badgeText: String {
            "Auto · \(profile.displayName) · \(classification.reason)" + (isSteppedDown ? " · stepped down" : "")
        }
    }

    private(set) var facts = SourceFacts()
    private(set) var stats: FrameStats?
    private(set) var current: Choice?
    private var drawablePixels = 0.0
    /// Profiles ruled out for the current file by the GPU budget.
    private var rejected: Set<RenderProfile> = []
    /// Profiles libplacebo refused to run. Kept for the life of the player.
    private var broken: Set<RenderProfile> = []
    private let thresholds: SourceClassifier.Thresholds

    init(thresholds: SourceClassifier.Thresholds = .calibrated) {
        self.thresholds = thresholds
    }

    /// A new file: metadata facts only, no stats yet, nothing rejected.
    mutating func beginFile(facts: SourceFacts) -> Choice {
        self.facts = facts
        stats = nil
        rejected = []
        return evaluate()
    }

    /// Analysis finished, or bitrate and tags became known. Facts replace the earlier ones.
    mutating func update(facts: SourceFacts, stats: FrameStats?) -> Choice {
        self.facts = facts
        self.stats = stats
        return evaluate()
    }

    /// The drawable changed size, in pixels. Rejections stay for the rest of the file.
    mutating func setDrawable(pixels: Double) -> Choice {
        drawablePixels = pixels
        return evaluate()
    }

    /// The GPU monitor reported over budget. Nil when already on Faithful.
    mutating func stepDown() -> Choice? {
        guard let active = current?.profile, active != .off else { return nil }
        rejected.insert(active)
        return evaluate()
    }

    /// libplacebo disabled the active profile's shaders. Nil when already on Faithful.
    mutating func markActiveProfileBroken() -> Choice? {
        guard let active = current?.profile, active != .off else { return nil }
        broken.insert(active)
        rejected.insert(active)
        return evaluate()
    }

    private mutating func evaluate() -> Choice {
        let classification = SourceClassifier.classify(facts, stats, thresholds: thresholds)
        let profile = ProfilePicker.pick(
            sourceClass: classification.sourceClass,
            fps: facts.fps,
            sourcePixels: facts.sourcePixels,
            drawablePixels: drawablePixels,
            excluding: broken.union(rejected)
        )
        let choice = Choice(profile: profile, classification: classification, isSteppedDown: !rejected.isEmpty)
        current = choice
        return choice
    }
}
