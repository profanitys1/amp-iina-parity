// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Aagedal_Media_Player

/// Proves the new keys reach the controller rather than only the helper's
/// return value: the real command handlers are installed, a real fixture is
/// loaded, and every assertion reads controller state.
@MainActor
final class PlayerKeyWiringTests: XCTestCase {
    /// `PlayerController.volume` writes the installed app's preferences; both
    /// are saved before the first write and restored in `tearDown`.
    private nonisolated(unsafe) static var savedVolume: Any?
    private nonisolated(unsafe) static var savedMuted: Any?

    override func setUp() {
        super.setUp()
        Self.savedVolume = UserDefaults.standard.object(forKey: AppSettings.playbackVolume.key)
        Self.savedMuted = UserDefaults.standard.object(forKey: AppSettings.playbackMuted.key)
    }

    override func tearDown() {
        Self.restore(Self.savedVolume, forKey: AppSettings.playbackVolume.key)
        Self.restore(Self.savedMuted, forKey: AppSettings.playbackMuted.key)
        super.tearDown()
    }

    func testTheRateCommandStepsAndClampsThePlaybackSpeed() async throws {
        let harness = try WiringHarness()
        defer { harness.close() }
        try await harness.prepare()
        let controller = harness.controller

        XCTAssertEqual(controller.currentPlaybackSpeed, 1.0, accuracy: 0.001)

        NotificationCenter.default.post(.stepRate(forward: false))
        await harness.settle()
        XCTAssertEqual(controller.currentPlaybackSpeed, 0.5, accuracy: 0.001,
                       "Speed Down must step 1.0 down by 0.5.")

        for _ in 0..<4 {
            NotificationCenter.default.post(.stepRate(forward: false))
            await harness.settle()
        }
        XCTAssertEqual(controller.currentPlaybackSpeed, 0.25, accuracy: 0.001,
                       "The rate must clamp at 0.25.")

        for _ in 0..<20 {
            NotificationCenter.default.post(.stepRate(forward: true))
            await harness.settle()
        }
        XCTAssertEqual(controller.currentPlaybackSpeed, 8.0, accuracy: 0.001,
                       "The rate must clamp at 8.0.")

        for _ in 0..<20 {
            NotificationCenter.default.post(.stepRate(forward: false))
            await harness.settle()
        }
        XCTAssertEqual(controller.currentPlaybackSpeed, 0.25, accuracy: 0.001,
                       "The rate must come back down to the lower clamp.")
    }

    func testTheArrowVolumeBranchMovesTheControllerVolume() async throws {
        let harness = try WiringHarness()
        defer { harness.close() }
        try await harness.prepare()
        let controller = harness.controller

        controller.volume = 50
        await harness.settle()

        // The monitor's own entry point, with the arrow cell that IINA binds to
        // volume: plain Up is +5, Option+Up is +1.
        XCTAssertTrue(harness.playerView.handleKeyEvent("\u{F700}", [], .upArrow))
        await harness.settle()
        XCTAssertEqual(controller.volume, 55, accuracy: 0.001,
                       "Plain Up must raise the volume by 5.")

        XCTAssertTrue(harness.playerView.handleKeyEvent("\u{F700}", [.option], .upArrow))
        await harness.settle()
        XCTAssertEqual(controller.volume, 56, accuracy: 0.001,
                       "Option+Up must raise the volume by 1.")

        XCTAssertTrue(harness.playerView.handleKeyEvent("\u{F701}", [], .downArrow))
        await harness.settle()
        XCTAssertEqual(controller.volume, 51, accuracy: 0.001,
                       "Plain Down must lower the volume by 5.")

        controller.volume = 2
        await harness.settle()
        XCTAssertTrue(harness.playerView.handleKeyEvent("\u{F701}", [], .downArrow))
        await harness.settle()
        XCTAssertEqual(controller.volume, 0, accuracy: 0.001,
                       "The volume must clamp at 0.")
    }

    func testTheCharacterHelperTogglesPlaybackThroughTheHandlers() async throws {
        let harness = try WiringHarness()
        defer { harness.close() }
        try await harness.prepare()
        let controller = harness.controller

        XCTAssertFalse(controller.isPlaying)
        XCTAssertTrue(harness.playerView.handleKeyEvent("p", [], nil))
        let started = await harness.waitUntil { controller.isPlaying }
        XCTAssertTrue(started, "`p` must start playback through the handlers.")

        XCTAssertTrue(harness.playerView.handleKeyEvent("p", [], nil))
        let paused = await harness.waitUntil { !controller.isPlaying }
        XCTAssertTrue(paused, "`p` must pause through the handlers.")
    }

    // MARK: - Defaults isolation

    private nonisolated static func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - Harness

/// A real controller with the generated fixture loaded and the same command
/// handlers ContentView installs, driven through the monitor's entry point.
@MainActor
private final class WiringHarness {
    let controller: PlayerController
    let compareSession: CompareSessionController
    let playerView: PlayerView

    private let window: NSWindow
    private let hosting: NSHostingView<AnyView>
    private var commandObserver: AnyCancellable?

    init() throws {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repository.appending(path: "Test Fixtures/Generated/compare/source-a.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "The fixture tree is unavailable: \(url.path)")

        controller = PlayerController(proResRAWDetector: { _, _ in false })
        compareSession = CompareSessionController()

        var item = PlayerWindowCoordinator.makeMediaItem(for: url)
        item.durationSeconds = 12
        item.hasVideoStream = true
        controller.loadMedia(item)

        playerView = PlayerView(
            controller: controller,
            audioWaveformGenerator: AudioWaveformGenerator(),
            item: item,
            showsAudioWaveform: false,
            isEditingTimecode: .constant(false),
            isTimelineFocused: .constant(false),
            isOverlayControlFocused: false,
            timecodeActivationTrigger: .constant(nil),
            compareSession: compareSession
        )

        let content = Color.clear
            .frame(width: 16, height: 16)
            .modifier(NotificationHandlers(
                controller: controller,
                compareSession: compareSession,
                nsWindow: nil,
                isEditingTimecode: .constant(false),
                showInspector: .constant(false),
                scopeWindowController: .constant(nil),
                showScopeOverlay: .constant(false),
                audioWaveformWindowController: .constant(nil),
                showAudioWaveformOverlay: .constant(false),
                audioWaveformGenerator: AudioWaveformGenerator(),
                timecodeMode: .constant(.relative),
                overlayController: PlayerOverlayController(),
                isMediaLoaded: true,
                openFilePanel: {},
                openFile: { _ in },
                openPreviousFile: {},
                openNextFile: {},
                openCompareFilePanel: {},
                toggleLoupeControls: {},
                toggleReviewNotes: {},
                addSubtitle: { _ in }
            ))
        hosting = NSHostingView(rootView: AnyView(content))
        hosting.sizingOptions = []
        hosting.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
        window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
    }

    func close() {
        commandObserver?.cancel()
        commandObserver = nil
        window.contentView = nil
        window.close()
        compareSession.stop()
        controller.teardown()
    }

    /// Mounts the MPV backend on a disposable drawable and waits until the
    /// controller accepts transport commands.
    func prepare() async throws {
        let mounted = await waitUntil { self.controller.mpvPlayer != nil }
        XCTAssertTrue(mounted, "The MPV backend was never constructed.")
        if let mpv = controller.mpvPlayer {
            let layer = MPVMetalLayer()
            layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
            layer.drawableSize = CGSize(width: 320, height: 180)
            mpv.attachDrawable(layer)
        }
        let ready = await waitUntil { self.controller.isReady }
        XCTAssertTrue(ready, "The fixture never became playable.")
    }

    func settle() async {
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        hosting.layoutSubtreeIfNeeded()
    }

    func waitUntil(timeout: TimeInterval = 10, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}
