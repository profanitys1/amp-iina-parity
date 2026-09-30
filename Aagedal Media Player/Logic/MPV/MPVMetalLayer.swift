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
        configureForHDR()
    }

    nonisolated override init(layer: Any) {
        super.init(layer: layer)
        configureForHDR()
    }

    nonisolated required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureForHDR()
    }

    private nonisolated func configureForHDR() {
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
