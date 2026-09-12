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

        var observed = false
        player.withMPVQueueForTesting {
            observed = player.isRunningOnMPVQueue
        }
        XCTAssertTrue(observed)
    }

    /// A player that never had an mpv context must deallocate cleanly, with no
    /// queue involved. This does not cover the on-queue teardown path: an
    /// object holding a live context cannot deallocate at all, because
    /// `wakeupContext` is a +1 on self released only by `destroy()` or by the
    /// deinit itself.
    func testReleaseWithoutContextDoesNotCrash() {
        var player: MPVPlayer? = MPVPlayer()
        XCTAssertNotNil(player)
        player = nil
    }
}
