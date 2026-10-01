// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class DisplayColorStateTests: XCTestCase {
    func testBT709IsSDR() {
        let state = DisplayColorState.decide(primaries: "bt.709", gamma: "bt.1886",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertEqual(state, .sdr)
    }

    /// PQ or HLG with wide primaries is the only thing that counts as HDR.
    func testPQBT2020IsHDR() {
        let state = DisplayColorState.decide(primaries: "bt.2020", gamma: "pq",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertTrue(state.usesEDR)
        XCTAssertEqual(state.targetPrimaries, "bt.2020")
        XCTAssertEqual(state.targetTransfer, "pq")
    }

    /// HLG is converted to PQ for display, as IINA does.
    func testHLGIsConvertedToPQ() {
        let state = DisplayColorState.decide(primaries: "display-p3", gamma: "hlg",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertTrue(state.usesEDR)
        XCTAssertEqual(state.targetTransfer, "pq")
        XCTAssertEqual(state.targetPrimaries, "display-p3")
    }

    func testHDRContentOnSDRDisplayFallsBackToSDR() {
        let state = DisplayColorState.decide(primaries: "bt.2020", gamma: "pq",
                                             displaySupportsEDR: false, hdrEnabled: true)
        XCTAssertFalse(state.usesEDR)
    }

    func testHDRDisabledByUserFallsBackToSDR() {
        let state = DisplayColorState.decide(primaries: "bt.2020", gamma: "pq",
                                             displaySupportsEDR: true, hdrEnabled: false)
        XCTAssertFalse(state.usesEDR)
    }

    /// Missing parameters must not be guessed at.
    func testUnknownParametersAreSDR() {
        let state = DisplayColorState.decide(primaries: nil, gamma: nil,
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertFalse(state.usesEDR)
    }

    /// An unrecognised primaries value with an HDR transfer is not assumed HDR.
    func testUnsupportedPrimariesIsSDR() {
        let state = DisplayColorState.decide(primaries: "smpte-431", gamma: "pq",
                                             displaySupportsEDR: true, hdrEnabled: true)
        XCTAssertFalse(state.usesEDR)
    }
}
