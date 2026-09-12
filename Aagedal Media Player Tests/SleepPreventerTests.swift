// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class SleepPreventerTests: XCTestCase {
    private final class Owner {}

    /// Forgetting an owner that never registered must be harmless, so a window
    /// that closes before playing cannot unbalance the assertion.
    func testForgetUnknownOwnerIsHarmless() {
        let owner = Owner()
        SleepPreventer.shared.forget(owner)
    }

    /// Registering then forgetting must leave no assertion behind.
    func testRegisterThenForgetReleases() {
        let owner = Owner()
        SleepPreventer.shared.update(for: owner, isPlaying: true, isAudioOnly: false)
        SleepPreventer.shared.forget(owner)
        XCTAssertFalse(SleepPreventer.shared.isHoldingAssertion)
    }
}
