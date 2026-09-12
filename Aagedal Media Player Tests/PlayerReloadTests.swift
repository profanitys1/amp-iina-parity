// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlayerReloadTests: XCTestCase {
    /// A reload with no media must not leave a resume task behind that could
    /// start playback on the next file.
    func testReloadWithoutMediaIsInert() {
        let controller = PlayerController()
        XCTAssertNil(controller.mediaItem)
        controller.reloadPreservingPlaybackState()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.playbackPhase, .idle)
    }
}
