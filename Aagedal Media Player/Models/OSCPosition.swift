// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import Foundation

/// Where the floating control card sits inside the video rect, stored as
/// fractions so the card keeps its relative place when the window resizes.
nonisolated struct OSCPosition: Equatable, Sendable {
    /// Gap between the card and the bottom of the video, matching IINA.
    static let bottomMargin: CGFloat = 25

    /// Drag distance within which the card locks to horizontal centre.
    static let snapThreshold: Double = 5

    let horizontal: Double
    let vertical: Double

    init(horizontal: Double, vertical: Double) {
        self.horizontal = Self.clampFraction(horizontal)
        self.vertical = Self.clampFraction(vertical)
    }

    static let `default` = OSCPosition(horizontal: 0.5, vertical: 1)

    /// Top-left corner of the card, clamped so it never leaves the video rect.
    /// A video rect smaller than the card pins it to the origin rather than
    /// producing a negative offset.
    func origin(in videoSize: CGSize, cardSize: CGSize) -> CGPoint {
        let freeWidth = max(0, videoSize.width - cardSize.width)
        let freeHeight = max(0, videoSize.height - cardSize.height - Self.bottomMargin)
        return CGPoint(
            x: freeWidth * CGFloat(horizontal),
            y: freeHeight * CGFloat(vertical)
        )
    }

    /// Converts a dragged x position into a stored fraction, locking to centre
    /// inside the snap threshold. `didSnap` drives the haptic feedback.
    static func snappedHorizontal(
        forProposedX x: Double,
        videoWidth: Double,
        cardWidth: Double
    ) -> (fraction: Double, didSnap: Bool) {
        let freeWidth = max(0, videoWidth - cardWidth)
        guard freeWidth > 0 else { return (0.5, false) }

        let centreX = freeWidth / 2
        if abs(x - centreX) <= snapThreshold {
            return (0.5, true)
        }
        return (clampFraction(x / freeWidth), false)
    }

    private static func clampFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0.5 }
        return min(1, max(0, value))
    }
}
