// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class MPVQueueIdentityTests: XCTestCase {
    /// The guard that makes an on-queue teardown safe only works if the queue
    /// carries its identity marker from construction.
    func testQueueCarriesIdentityKey() {
        let player = MPVPlayer()
        XCTAssertFalse(player.isRunningOnMPVQueue)

        var observed = true
        player.withMPVQueueForTesting {
            observed = player.isRunningOnMPVQueue
        }
        XCTAssertTrue(observed)
    }

    /// A player with no mpv context must deallocate cleanly; this is the case
    /// a naive queue.sync teardown would deadlock on if run on the queue.
    func testReleaseWithoutContextDoesNotCrash() {
        var player: MPVPlayer? = MPVPlayer()
        XCTAssertNotNil(player)
        player = nil
    }
}
