// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class ReverseBufferPolicyTests: XCTestCase {
    /// mpv's own default is used until mpv itself complains, and that default
    /// is already 1 GiB — writing it back would be a no-op, so the first rung
    /// must be strictly larger.
    func testFirstOverflowTakesTheFirstStep() {
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: -1)?.video, "2GiB")
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: -1)?.audio, "256MiB")
    }

    func testLadderClimbsOneStepAtATime() {
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: 0)?.video, "4GiB")
        XCTAssertEqual(ReverseBufferPolicy.next(currentIndex: 0)?.audio, "512MiB")
    }

    /// Past the top of the ladder the policy stops rather than growing without
    /// bound, so a pathological file cannot ask for 64 GiB.
    func testLadderEnds() {
        XCTAssertNil(ReverseBufferPolicy.next(currentIndex: 1))
    }

    /// mpv's log line names no stream, so every rung has to carry both sizes.
    func testEveryRungCarriesBothBuffers() {
        for rung in ReverseBufferPolicy.ladder {
            XCTAssertFalse(rung.video.isEmpty)
            XCTAssertFalse(rung.audio.isEmpty)
        }
    }

    func testIndexRoundTripsThroughTheVideoValue() {
        for (index, rung) in ReverseBufferPolicy.ladder.enumerated() {
            XCTAssertEqual(ReverseBufferPolicy.index(ofVideoValue: rung.video), index)
        }
    }

    /// An unknown value means the buffer was not set by this policy.
    func testUnknownValueHasNoIndex() {
        XCTAssertNil(ReverseBufferPolicy.index(ofVideoValue: "512MiB"))
    }

    func testOverflowLineMatches() {
        XCTAssertTrue(ReverseBufferPolicy.isOverflowLogLine("Reversal queue overflow, discarding frame.\n"))
    }

    func testOverflowLineMatchesWithLevelPrefix() {
        XCTAssertTrue(ReverseBufferPolicy.isOverflowLogLine("[ffmpeg/decoder] error: Reversal queue overflow, discarding frame."))
    }

    func testNearMissLineDoesNotMatch() {
        XCTAssertFalse(ReverseBufferPolicy.isOverflowLogLine("Reversal queue underflow, discarding frame."))
    }

    func testEmptyLineDoesNotMatch() {
        XCTAssertFalse(ReverseBufferPolicy.isOverflowLogLine(""))
    }

    /// mpv emits the overflow line once per discarded frame, so without a
    /// cooldown the ladder would be consumed in a few frames and the
    /// progressive climb would collapse into an instant jump to the top.
    func testSecondRaiseInsideTheWindowIsRefused() {
        XCTAssertFalse(ReverseBufferPolicy.canRaise(elapsedSinceLastRaise: 0))
        XCTAssertFalse(ReverseBufferPolicy.canRaise(elapsedSinceLastRaise: 0.499))
    }

    func testRaiseAfterTheWindowIsAllowed() {
        XCTAssertTrue(ReverseBufferPolicy.canRaise(elapsedSinceLastRaise: ReverseBufferPolicy.cooldown))
        XCTAssertTrue(ReverseBufferPolicy.canRaise(elapsedSinceLastRaise: 5))
    }

    /// The first raise has no predecessor to wait behind.
    func testFirstRaiseIsAlwaysAllowed() {
        XCTAssertTrue(ReverseBufferPolicy.canRaise(elapsedSinceLastRaise: nil))
    }
}
