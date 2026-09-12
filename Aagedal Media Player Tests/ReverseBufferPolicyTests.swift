// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class ReverseBufferPolicyTests: XCTestCase {
    /// mpv's default is used until mpv itself complains, so the first step up
    /// is the first entry in the ladder, not the biggest one.
    func testFirstOverflowTakesTheFirstStep() {
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: -1), "1GiB")
    }

    func testLadderClimbsOneStepAtATime() {
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: 0), "2GiB")
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: 1), "4GiB")
    }

    /// Past the top of the ladder the policy stops rather than growing without
    /// bound, so a pathological file cannot ask for 64 GiB.
    func testLadderEnds() {
        XCTAssertNil(ReverseBufferPolicy.next(currentIndex: 2))
    }

    func testIndexRoundTripsThroughTheValue() {
        for (index, value) in ReverseBufferPolicy.ladder.enumerated() {
            XCTAssertEqual(ReverseBufferPolicy.index(ofBufferValue: value), index)
        }
    }

    /// An unknown value means the buffer was not set by this policy.
    func testUnknownValueHasNoIndex() {
        XCTAssertNil(ReverseBufferPolicy.index(ofBufferValue: "512MiB"))
    }
}
