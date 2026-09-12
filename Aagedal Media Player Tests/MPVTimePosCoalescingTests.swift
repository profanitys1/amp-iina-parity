// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class MPVTimePosCoalescingTests: XCTestCase {
    /// Matches the interval IINA uses for its sync timer (AppData.swift:14).
    func testCoalescingIntervalMatchesReference() {
        XCTAssertEqual(MPVPlayer.timePosPublishInterval, 0.1, accuracy: 0.0001)
    }

    /// Resetting must be safe before any mpv context exists.
    func testResetBeforeContextDoesNotCrash() {
        let player = MPVPlayer()
        player.resetTimePosCoalescing()
    }
}
