// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Chooses the heaviest shader profile of a class's fallback chain that fits the frame budget.
///
/// Costs are GPU milliseconds per frame measured in amp.app fullscreen (3448x1940 drawable)
/// on an M1 Pro with 720p and 1080p sources, for the profiles the chains use. Faithful needs no
/// entry: it is always accepted. `upscaleStrong` (64.6 ms at 720p, not measured at 1080p),
/// `compressedGrain` (measured at 1080p only) and `restore` appear in no chain.
nonisolated enum ProfilePicker {
    nonisolated struct Cost: Sendable {
        let p720: Double
        let p1080: Double
    }

    /// Share of the frame period a profile may use.
    static let budgetFraction = 0.8
    /// Above this the high-frame-rate chains apply. 30.5 keeps 30 and 29.97 fps on the normal chains.
    static let highFrameRate = 30.5
    /// Frame rate used when the container reports none.
    static let fallbackFPS = 30.0
    static let referenceDrawablePixels = 3448.0 * 1940.0
    static let pixels720p = 1280.0 * 720.0
    static let pixels1080p = 1920.0 * 1080.0

    static let costs: [RenderProfile: Cost] = [
        .chroma: Cost(p720: 7.0, p1080: 8.6),
        .efficient: Cost(p720: 10.9, p1080: 18.5),
        .sharpen: Cost(p720: 11.7, p1080: 11.7),
        .upscaleLight: Cost(p720: 15.4, p1080: 31.0),
        .compressed: Cost(p720: 16.1, p1080: 33.0),
        .crisp: Cost(p720: 21.3, p1080: 37.0),
    ]

    /// Heaviest first. Every chain ends in Faithful, which is always accepted.
    static func chain(for sourceClass: SourceClass, fps: Double) -> [RenderProfile] {
        let high = fps > highFrameRate
        switch sourceClass {
        case .hdr:
            return [.off]
        case .topaz, .clean:
            return high ? [.sharpen, .chroma, .off] : [.upscaleLight, .sharpen, .chroma, .off]
        case .compressed:
            return high ? [.efficient, .sharpen, .chroma, .off] : [.compressed, .efficient, .sharpen, .chroma, .off]
        case .soft:
            return high ? [.sharpen, .chroma, .off] : [.crisp, .upscaleLight, .sharpen, .chroma, .off]
        }
    }

    /// Milliseconds per frame, or nil when the profile has no measurement.
    ///
    /// The source-size term is piecewise linear through the 720p and 1080p measurements
    /// and proportional to pixels outside them; the drawable term is proportional to pixels.
    static func estimatedMilliseconds(
        profile: RenderProfile,
        sourcePixels: Double,
        drawablePixels: Double
    ) -> Double? {
        guard let cost = costs[profile] else { return nil }
        let base: Double
        if sourcePixels <= pixels720p {
            base = cost.p720 * sourcePixels / pixels720p
        } else if sourcePixels <= pixels1080p {
            base = cost.p720 + (cost.p1080 - cost.p720) * (sourcePixels - pixels720p) / (pixels1080p - pixels720p)
        } else {
            base = cost.p1080 * sourcePixels / pixels1080p
        }
        return base * drawablePixels / referenceDrawablePixels
    }

    /// The first profile of the class's chain that is not excluded and whose estimated cost fits
    /// the budget. Faithful is never excluded, so there is always an answer. Unknown sizes count
    /// as 1080p and fullscreen, the pessimistic case for the drawable.
    static func pick(
        sourceClass: SourceClass,
        fps: Double,
        sourcePixels: Double,
        drawablePixels: Double,
        excluding: Set<RenderProfile> = []
    ) -> RenderProfile {
        let rate = fps > 0 ? fps : fallbackFPS
        let budget = budgetFraction * 1000 / rate
        let source = sourcePixels > 0 ? sourcePixels : pixels1080p
        let drawable = drawablePixels > 0 ? drawablePixels : referenceDrawablePixels
        for profile in chain(for: sourceClass, fps: rate) {
            if profile == .off { return .off }
            guard !excluding.contains(profile),
                  let cost = estimatedMilliseconds(profile: profile, sourcePixels: source, drawablePixels: drawable),
                  cost <= budget else { continue }
            return profile
        }
        return .off
    }
}
