// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The window configurator's decisions, without a window: which alpha the
// traffic lights get in each mode, when the first media load fills the screen,
// and what minimum size each source shape asks for.

import AppKit
import XCTest
@testable import Aagedal_Media_Player

final class WindowConfiguratorTests: XCTestCase {
    /// The display these decisions are tuned against.
    private let screen = NSSize(width: 1724, height: 1119)

    // MARK: - Traffic lights

    /// Native fullscreen reveals its own titlebar. An alpha of 0 there makes
    /// the dots arrive invisible exactly when the player moves the pointer to
    /// the top edge to reach them.
    func testTheTrafficLightsStayOpaqueInFullScreenWhateverTheHoverState() {
        XCTAssertEqual(
            WindowConfigurator.trafficLightAlpha(showTrafficLights: false, isFullScreen: false), 0,
            "An ordinary window with the pointer away fades the dots out.")
        XCTAssertEqual(
            WindowConfigurator.trafficLightAlpha(showTrafficLights: true, isFullScreen: false), 1,
            "An ordinary window with the pointer over it shows the dots.")
        XCTAssertEqual(
            WindowConfigurator.trafficLightAlpha(showTrafficLights: false, isFullScreen: true), 1,
            "Full screen must not fade the dots out; AppKit owns their reveal there.")
        XCTAssertEqual(
            WindowConfigurator.trafficLightAlpha(showTrafficLights: true, isFullScreen: true), 1)
    }

    // MARK: - Screen fill

    func testTheScreenFillHappensOncePerWindowAndNeverInFullScreen() {
        XCTAssertTrue(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForMedia: false, isFullScreen: false, openMaximized: true),
            "The first media load in a window fills the screen.")
        XCTAssertFalse(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForMedia: true, isFullScreen: false, openMaximized: true),
            "A later load leaves the size the player chose alone.")
        XCTAssertFalse(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForMedia: false, isFullScreen: true, openMaximized: true),
            "Full screen already owns the window frame.")
        XCTAssertFalse(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForMedia: false, isFullScreen: false, openMaximized: false),
            "The behaviour is switched off, so the old sizing stands.")
    }

    func testSourceResizingStopsOnceTheWindowHasFilledTheScreen() {
        XCTAssertTrue(
            WindowConfigurator.mayResizeToSource(hasMaximizedForMedia: false, openMaximized: true))
        XCTAssertFalse(
            WindowConfigurator.mayResizeToSource(hasMaximizedForMedia: true, openMaximized: true),
            "Folder next/previous must not shrink a filled window back to source size.")
        XCTAssertTrue(
            WindowConfigurator.mayResizeToSource(hasMaximizedForMedia: true, openMaximized: false),
            "With the fill off, the window keeps resizing to its source as before.")
        XCTAssertTrue(
            WindowConfigurator.mayResizeToSource(hasMaximizedForMedia: false, openMaximized: false))
    }

    // MARK: - Minimum size

    /// The screen fill drops to the base minimum for this reason: a portrait
    /// source asks for a minimum taller than the screen, which AppKit would
    /// honour by refusing the frame.
    func testAPortraitSourceAsksForAMinimumTallerThanTheScreen() {
        let portrait = WindowConfigurator.minContentSize(for: 320 / 640)
        XCTAssertGreaterThan(
            portrait.height, screen.height,
            "A 320x640 source must be the case the screen fill has to work around.")
    }

    func testTheScreenFillUsesAMinimumThatFitsTheScreen() {
        let base = WindowConfigurator.minContentSize(for: nil)
        XCTAssertEqual(base, NSSize(width: 690, height: 540))
        XCTAssertLessThanOrEqual(base.width, screen.width)
        XCTAssertLessThanOrEqual(base.height, screen.height)
    }

    func testLandscapeMinimumsFollowTheSourceShape() {
        let wide = WindowConfigurator.minContentSize(for: 16 / 9)
        XCTAssertEqual(wide.width, 960, accuracy: 0.5)
        XCTAssertEqual(wide.height, 540, accuracy: 0.5)

        // Degenerate ratios must not produce a zero or negative minimum.
        XCTAssertEqual(WindowConfigurator.minContentSize(for: 0), NSSize(width: 690, height: 540))
        XCTAssertEqual(WindowConfigurator.minContentSize(for: -1), NSSize(width: 690, height: 540))
    }

    // MARK: - Registration

    func testOpenMaximizedIsRegisteredAndDefaultsToTrue() throws {
        XCTAssertTrue(
            AppSettings.openMaximized.defaultValue,
            "Every movie must open in a window that fills the screen.")

        let suiteName = "WindowConfiguratorTests.openMaximized"
        let probe = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        probe.removePersistentDomain(forName: suiteName)
        AppSettings.registerDefaults(in: probe)
        XCTAssertEqual(probe.object(forKey: AppSettings.openMaximized.key) as? Bool, true)
        probe.removePersistentDomain(forName: suiteName)
    }
}

/// The reported defect, against a real window: entering full screen while the
/// pointer is away from it left the traffic lights faded out, so AppKit's own
/// titlebar reveal slid down an invisible set of dots. Driven through the same
/// notifications `FullscreenSurfaceReloadTests` uses rather than a real
/// transition, which needs a display and an animation.
@MainActor
final class WindowConfiguratorFullScreenChromeTests: XCTestCase {
    /// Configured the way `ConfiguratorNSView.viewDidMoveToWindow` configures
    /// the player window, because the traffic lights only exist on a titled
    /// window whose content runs under the titlebar.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 711, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 711, height: 400))
        return window
    }

    /// All three dots share one titlebar view, which is what the fade animates.
    private func trafficLightAlpha(_ window: NSWindow) -> CGFloat? {
        window.standardWindowButton(.closeButton)?.superview?.alphaValue
    }

    /// The exit path animates, so the run loop has to turn.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
    }

    func testEnteringFullScreenRestoresDotsTheFadeHadHidden() {
        let window = makeWindow()
        defer { window.close() }
        let coordinator = WindowConfigurator.Coordinator()
        coordinator.observeWindow(window)

        coordinator.lastShowTrafficLights = false
        coordinator.lastTrafficLightAlpha = WindowConfigurator.trafficLightAlpha(
            showTrafficLights: false, isFullScreen: false)
        coordinator.applyTrafficLightAlpha(window, animated: false)
        XCTAssertEqual(
            trafficLightAlpha(window), 0,
            "With the pointer away an ordinary window must fade the dots out.")

        NotificationCenter.default.post(
            name: NSWindow.willEnterFullScreenNotification, object: window)

        XCTAssertEqual(
            trafficLightAlpha(window), 1,
            "Entering full screen must restore the dots before AppKit takes the titlebar over.")
        XCTAssertTrue(
            coordinator.isEnteringFullScreen,
            "The transition must count as full screen until the style mask catches up.")
    }

    func testExitingFullScreenHandsTheDotsBackToHover() {
        let window = makeWindow()
        defer { window.close() }
        let coordinator = WindowConfigurator.Coordinator()
        coordinator.observeWindow(window)

        coordinator.lastShowTrafficLights = false
        NotificationCenter.default.post(
            name: NSWindow.willEnterFullScreenNotification, object: window)
        XCTAssertEqual(trafficLightAlpha(window), 1)

        NotificationCenter.default.post(
            name: NSWindow.didExitFullScreenNotification, object: window)
        settle()
        XCTAssertFalse(coordinator.isEnteringFullScreen)
        XCTAssertEqual(
            trafficLightAlpha(window), 0,
            "Back in an ordinary window with the pointer away, the fade resumes.")

        coordinator.lastShowTrafficLights = true
        NotificationCenter.default.post(
            name: NSWindow.didExitFullScreenNotification, object: window)
        settle()
        XCTAssertEqual(
            trafficLightAlpha(window), 1,
            "Hover must show the dots again once full screen is over.")
    }
}
