// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlayerOverlayControllerTests: XCTestCase {
    @MainActor
    private final class PlaybackState {
        var isPlaying = true
    }

    func testHideThenRevealTogglesOverlayVisibility() {
        let controller = PlayerOverlayController()
        XCTAssertTrue(controller.isVisible)

        controller.hide()
        XCTAssertFalse(controller.isVisible)

        controller.reveal()
        XCTAssertTrue(controller.isVisible)
    }

    func testControlHoverPreventsScheduledHide() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        controller.setControlsHovered(true)
        controller.scheduleHide(
            isPlaying: { true },
            isControlInteractionActive: { false }
        )

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(controller.isVisible)
    }

    func testScheduledHideUsesLatestPlaybackState() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        let playback = PlaybackState()
        controller.scheduleHide(
            isPlaying: { playback.isPlaying },
            isControlInteractionActive: { false }
        )
        playback.isPlaying = false

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(controller.isVisible)
    }

    func testScheduledHideDismissesOverlayDuringPlayback() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        controller.scheduleHide(
            isPlaying: { true },
            isControlInteractionActive: { false }
        )

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(controller.isVisible)
    }

    func testKeyboardNavigationRevealsOverlayAndCancelsPendingHide() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        controller.hide()
        controller.scheduleHide(
            isPlaying: { true },
            isControlInteractionActive: { false }
        )

        controller.revealForKeyboardNavigation()

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(controller.isVisible)
    }

    func testFocusedControlPreventsScheduledHide() async {
        let controller = PlayerOverlayController(hideDelay: .milliseconds(10))
        controller.scheduleHide(
            isPlaying: { true },
            isControlInteractionActive: { true }
        )

        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(controller.isVisible)
    }

}
