// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// mpv has no way to ask macOS how bright the display gets, so target-peak=auto
// falls back to a guess from the transfer function. IINA reads the private
// CoreDisplay_DisplayCreateInfoDictionary for NonReferencePeakHDRLuminance.
// The public EDR headroom gets the same answer without private API: headroom is
// a multiple of SDR reference white, which is 100 nits by convention.

import AppKit

nonisolated enum DisplayPeakBrightness {
    static let sdrReferenceWhiteNits: CGFloat = 100

    static func nits(forHeadroom headroom: CGFloat, referenceWhite: CGFloat) -> Int? {
        guard headroom > 1, headroom.isFinite else { return nil }
        return Int((headroom * referenceWhite).rounded())
    }

    @MainActor
    static func nits(for screen: NSScreen) -> Int? {
        nits(forHeadroom: screen.maximumPotentialExtendedDynamicRangeColorComponentValue,
             referenceWhite: sdrReferenceWhiteNits)
    }
}
