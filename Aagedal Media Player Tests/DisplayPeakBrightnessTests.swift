// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class DisplayPeakBrightnessTests: XCTestCase {
    /// A 10x headroom display at the 100-nit SDR reference is a 1000-nit panel.
    func testHeadroomScalesReferenceWhite() {
        XCTAssertEqual(DisplayPeakBrightness.nits(forHeadroom: 10, referenceWhite: 100), 1000)
    }

    /// No headroom means no EDR, so there is nothing to report.
    func testNoHeadroomReturnsNil() {
        XCTAssertNil(DisplayPeakBrightness.nits(forHeadroom: 1, referenceWhite: 100))
    }

    func testBelowUnityHeadroomReturnsNil() {
        XCTAssertNil(DisplayPeakBrightness.nits(forHeadroom: 0.5, referenceWhite: 100))
    }

    func testFractionalHeadroomRounds() {
        XCTAssertEqual(DisplayPeakBrightness.nits(forHeadroom: 1.6, referenceWhite: 100), 160)
    }
}
