// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class FullscreenSurfaceReloadTests: XCTestCase {
    /// A fullscreen transition made while playing must still recreate mpv:
    /// on device, the stale destination rectangle survived seconds of playback
    /// (window-sized picture after entering, cropped zoom after exiting).
    func testFullscreenTransitionsReloadWhilePlaying() async throws {
        let player = MPVPlayer()
        defer { player.destroy() }
        let controller = MPVViewController(
            player: player, managesSurfaceReloads: true,
            surfaceSize: CGSize(width: 320, height: 180)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            window.contentViewController = nil
            window.close()
        }
        // viewDidLayout installs the window observers.
        controller.viewDidLayout()

        var reloadCount = 0
        let observation = NotificationCenter.default.appCommandPublisher.sink { notification in
            if let command = notification.appCommand, case .reloadPlayer = command {
                reloadCount += 1
            }
        }
        defer { observation.cancel() }

        player.isFileLoaded = true
        player.isPlaying = true

        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        XCTAssertEqual(reloadCount, 1, "Entering fullscreen while playing must reload mpv.")

        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertEqual(reloadCount, 2, "Exiting fullscreen while playing must reload mpv.")

        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
        XCTAssertEqual(reloadCount, 3, "Ending a live resize while playing must reload mpv.")
    }
}
