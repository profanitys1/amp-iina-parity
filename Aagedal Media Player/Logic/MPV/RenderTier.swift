// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// One rung of the automatic enhancement ladder, lightest first.
///
/// Used only while Enhance is on and the manual profile is Faithful. Measured
/// on an M1 Pro with gaia.mov (1280x720p30 ProRes), fullscreen at 2.69x, and
/// scored by 2x reconstruction (PSNR-Y / SSIM against the 720p master):
/// SSimSuperRes 11.2 ms, 41.46 dB / 0.99891; RAVU zoom 10.7 ms (not scorable
/// offline); ArtCNN C4F16 13.7 ms, 43.15 dB / 0.99940; FSRCNNX 16 about 16 ms,
/// 44.60 dB / 0.99956. ArtCNN C4F32 was dropped: 39.1 ms for no gain over
/// C4F16 (43.17 dB / 0.99939). The GPU budget monitor corrects for cost at
/// runtime.
///
/// Every tier above Faithful also loads CfL_Prediction. It only runs when the
/// chroma plane is smaller than luma (`!WHEN CHROMA.w LUMA.w <`), so it fixes
/// 4:2:0 and 4:2:2 colour edges and does nothing on 4:4:4 or RGB sources.
nonisolated enum RenderTier: Int, CaseIterable, Comparable, Sendable {
    case faithful
    case chroma
    case sharpen
    case ravuZoom
    case artcnnLight
    case fsrcnnx

    /// ArtCNN and FSRCNNX always emit exactly 2x. Below this ratio the overshoot would be
    /// thrown away again by `dscale`, which costs GPU time for nothing.
    static let neuralDoublerMinimumRatio = 1.9

    static func < (lhs: RenderTier, rhs: RenderTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .faithful: "Faithful"
        case .chroma: "Chroma reconstruction"
        case .sharpen: "Sharpened"
        case .ravuZoom: "RAVU zoom"
        case .artcnnLight: "ArtCNN light"
        case .fsrcnnx: "FSRCNNX"
        }
    }

    /// Shaders in load order. CfL rides along on every enhancing tier.
    var shaderFileNames: [String] {
        self == .faithful || self == .chroma
            ? requiredShaderFileNames
            : requiredShaderFileNames + RenderProfile.chroma.shaderFileNames
    }

    /// The shaders that define the tier. A missing CfL only drops the chroma
    /// pass from the luma tiers; it does not disqualify them.
    var requiredShaderFileNames: [String] {
        switch self {
        case .faithful: []
        case .chroma: RenderProfile.chroma.shaderFileNames
        case .sharpen: RenderProfile.sharpen.shaderFileNames
        case .ravuZoom: ["ravu-zoom-ar-r3.hook"]
        case .artcnnLight: ["ArtCNN_C4F16.glsl"]
        case .fsrcnnx: ["FSRCNNX_x2_16-0-4-1.glsl"]
        }
    }

    var scaleOptions: [String: String] {
        self == .sharpen ? RenderProfile.sharpen.scaleOptions : RenderProfile.off.scaleOptions
    }

    /// RAVU zoom renders at the target size, so it suits any upscale.
    /// SSimSuperRes guards itself with `!WHEN` and only runs when upscaling.
    /// Chroma is upscaled to luma size at any ratio, so CfL always qualifies.
    // ponytail: on 4:4:4 sources the badge still says "Chroma reconstruction"
    // although CfL skips itself; gate on mpv's pixel format if that misleads.
    func isEligible(ratio: Double) -> Bool {
        switch self {
        case .faithful, .chroma: true
        case .sharpen, .ravuZoom: ratio > 1.0
        case .artcnnLight, .fsrcnnx: ratio >= Self.neuralDoublerMinimumRatio
        }
    }

    var steppedDown: RenderTier { RenderTier(rawValue: rawValue - 1) ?? .faithful }
}

/// Picks a tier from the upscale ratio, what is installed, and how far the
/// GPU monitor has forced the ladder down.
nonisolated enum TierSelector {
    /// Drawable pixels per source pixel on the tighter axis. `nil` until both
    /// sizes are known.
    static func upscaleRatio(source: CGSize, drawable: CGSize) -> Double? {
        guard source.width > 0, source.height > 0, drawable.width > 0, drawable.height > 0 else { return nil }
        return min(drawable.width / source.width, drawable.height / source.height)
    }

    /// The heaviest tier that is eligible for `ratio`, installed, and no
    /// heavier than `floor`.
    static func select(ratio: Double, available: Set<RenderTier>, floor: RenderTier) -> RenderTier {
        RenderTier.allCases.reversed().first { tier in
            tier <= floor && available.contains(tier) && tier.isEligible(ratio: ratio)
        } ?? .faithful
    }
}
