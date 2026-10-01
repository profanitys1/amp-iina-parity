// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keeps the picture correct for the display it is on. Modelled on IINA's
// VideoView.refreshEdrMode (VideoView.swift:415-435), with two differences
// forced by this app embedding mpv via wid= rather than the render API:
// the ICC profile goes to mpv as a file path, and the peak comes from the
// public EDR headroom rather than the private CoreDisplay dictionary.

import AppKit
import OSLog

@MainActor
final class DisplayColorController {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "colour")
    private let profileStore = DisplayICCProfileStore()
    private weak var player: MPVPlayer?
    private weak var layer: MPVMetalLayer?
    private var lastApplied: DisplayColorState?

    init(player: MPVPlayer, layer: MPVMetalLayer) {
        self.player = player
        self.layer = layer
    }

    /// Re-decides and re-applies. Safe to call repeatedly.
    func refresh(screen: NSScreen?) {
        guard let player, let layer else { return }
        let defaults = UserDefaults.standard

        let headroom = screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        let state = DisplayColorState.decide(
            primaries: player.getString(MPVProperty.videoParamsPrimaries),
            gamma: player.getString(MPVProperty.videoParamsGamma),
            displaySupportsEDR: headroom > 1,
            hdrEnabled: defaults.value(for: AppSettings.hdrEnabled))

        let sdrColorSpace = screen?.colorSpace?.cgColorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        layer.apply(state, sdrColorSpace: sdrColorSpace)

        player.setString(MPVProperty.targetPrim, state.targetPrimaries ?? "auto")
        player.setString(MPVProperty.targetTrc, state.targetTransfer ?? "auto")
        applyICCProfile(for: screen, state: state, player: player, defaults: defaults)
        applyTargetPeak(for: screen, state: state, player: player, defaults: defaults)

        if lastApplied != state {
            logger.info("Colour state: EDR=\(state.usesEDR, privacy: .public) prim=\(state.targetPrimaries ?? "auto", privacy: .public) trc=\(state.targetTransfer ?? "auto", privacy: .public)")
            lastApplied = state
        }
    }

    private func applyICCProfile(
        for screen: NSScreen?,
        state: DisplayColorState,
        player: MPVPlayer,
        defaults: UserDefaults
    ) {
        // An HDR path is already display-referred; a display profile on top of
        // it would double-correct, which is why IINA only sets one or the other.
        guard !state.usesEDR,
              defaults.value(for: AppSettings.loadDisplayICCProfile),
              let data = screen?.colorSpace?.iccProfileData else {
            player.setString(MPVProperty.iccProfile, "")
            return
        }
        do {
            let url = try profileStore.url(for: data)
            player.setString(MPVProperty.iccProfile, url.path)
        } catch {
            logger.error("Could not write the display ICC profile: \(error.localizedDescription, privacy: .public)")
            player.setString(MPVProperty.iccProfile, "")
        }
    }

    private func applyTargetPeak(
        for screen: NSScreen?,
        state: DisplayColorState,
        player: MPVPlayer,
        defaults: UserDefaults
    ) {
        guard state.usesEDR else {
            player.setString(MPVProperty.targetPeak, "auto")
            return
        }
        let override = defaults.value(for: AppSettings.toneMappingTargetPeakOverride)
        if override > 0 {
            player.setString(MPVProperty.targetPeak, String(override))
        } else if let screen, let nits = DisplayPeakBrightness.nits(for: screen) {
            player.setString(MPVProperty.targetPeak, String(nits))
        } else {
            player.setString(MPVProperty.targetPeak, "auto")
        }
    }
}
