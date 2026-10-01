// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import AppKit

// Workaround for MoltenVK problems - matches MPVKit demo
// https://github.com/mpv-player/mpv/pull/13651
class MPVMetalLayer: CAMetalLayer {

    nonisolated override init() {
        super.init()
    }

    nonisolated override init(layer: Any) {
        super.init(layer: layer)
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Applies a colour decision. SDR content gets the display's own colour
    /// space and no EDR; HDR content gets a PQ space and EDR. Forcing EDR on
    /// for everything, as this layer used to, shows SDR material through an
    /// extended-range path it was never graded for.
    nonisolated func apply(_ state: DisplayColorState, sdrColorSpace: CGColorSpace) {
        guard state.usesEDR else {
            colorspace = sdrColorSpace
            wantsExtendedDynamicRangeContent = false
            return
        }
        let name: CFString = state.targetPrimaries == "display-p3"
            ? CGColorSpace.displayP3_PQ
            : CGColorSpace.itur_2100_PQ
        colorspace = CGColorSpace(name: name)
        wantsExtendedDynamicRangeContent = true
    }

    /// Called after every accepted drawable size change, on whichever thread
    /// assigned it. Set once, before the layer is handed to mpv.
    nonisolated(unsafe) var onDrawableSizeChange: (@Sendable (CGSize) -> Void)?

    // Workaround for a MoltenVK that sets the drawableSize to 1x1 to forcefully complete
    // the presentation, this causes flicker and the drawableSize possibly staying at 1x1
    nonisolated override var drawableSize: CGSize {
        get { return super.drawableSize }
        set {
            guard Int(newValue.width) > 1 && Int(newValue.height) > 1 else { return }
            let old = super.drawableSize
            super.drawableSize = newValue
            if super.drawableSize != old { onDrawableSizeChange?(super.drawableSize) }
        }
    }
}
