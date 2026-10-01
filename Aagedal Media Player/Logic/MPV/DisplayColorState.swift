// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Decides how the picture should be shown on the display it is on.
//
// The HDR test matches IINA's isHDRVideo() (VideoView.swift:437-460): an HDR
// transfer function AND primaries wide enough to mean it. Anything else is SDR,
// including unknown values — a review tool must not guess at colour.

import Foundation

nonisolated struct DisplayColorState: Equatable {
    /// Whether the layer should accept extended-range content.
    var usesEDR: Bool
    /// mpv `target-prim`, or nil for "auto".
    var targetPrimaries: String?
    /// mpv `target-trc`, or nil for "auto".
    var targetTransfer: String?

    static let sdr = DisplayColorState(usesEDR: false, targetPrimaries: nil, targetTransfer: nil)

    static func decide(
        primaries: String?,
        gamma: String?,
        displaySupportsEDR: Bool,
        hdrEnabled: Bool
    ) -> DisplayColorState {
        // Pattern match: TransferFunction's Equatable conformance is main-actor isolated.
        if case .sdr = HDRTransferResolver.resolve(colorTransfer: gamma) { return .sdr }
        guard hdrEnabled, displaySupportsEDR,
              let primaries, primaries == "bt.2020" || primaries == "display-p3" else {
            return .sdr
        }
        // PQ is shown as authored; HLG is converted to PQ for display.
        return DisplayColorState(usesEDR: true, targetPrimaries: primaries, targetTransfer: "pq")
    }
}
