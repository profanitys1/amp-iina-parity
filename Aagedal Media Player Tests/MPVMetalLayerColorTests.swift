// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import CoreGraphics
@testable import Aagedal_Media_Player

final class MPVMetalLayerColorTests: XCTestCase {
    /// SDR content must not sit in an EDR-flagged layer. This was the bug: the
    /// layer forced wantsExtendedDynamicRangeContent on for everything.
    func testSDRStateTurnsEDROffAndSetsDisplayColorSpace() {
        let layer = MPVMetalLayer()
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        layer.apply(.sdr, sdrColorSpace: sRGB)
        XCTAssertFalse(layer.wantsExtendedDynamicRangeContent)
        XCTAssertEqual(layer.colorspace, sRGB)
    }

    func testHDRStateTurnsEDROnAndUsesPQColorSpace() {
        let layer = MPVMetalLayer()
        let state = DisplayColorState(usesEDR: true, targetPrimaries: "bt.2020", targetTransfer: "pq")
        layer.apply(state, sdrColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        XCTAssertTrue(layer.wantsExtendedDynamicRangeContent)
        XCTAssertEqual(layer.colorspace, CGColorSpace(name: CGColorSpace.itur_2100_PQ))
    }

    func testDisplayP3HDRUsesDisplayP3PQ() {
        let layer = MPVMetalLayer()
        let state = DisplayColorState(usesEDR: true, targetPrimaries: "display-p3", targetTransfer: "pq")
        layer.apply(state, sdrColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        XCTAssertEqual(layer.colorspace, CGColorSpace(name: CGColorSpace.displayP3_PQ))
    }
}
