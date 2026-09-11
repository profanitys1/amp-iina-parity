// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Aagedal_Media_Player

/// The character-key layer: the decision table key by key, and the monitor's
/// own entry point driven with no comparison session so the ordinary-playback
/// routes are measured against controller state rather than the helper's
/// return value.
@MainActor
final class PlayerKeyMapTests: XCTestCase {
    /// What a key event reports for each row: the character is
    /// `charactersIgnoringModifiers`, which keeps Shift applied, so a real
    /// Shift-`[` arrives as `{` and a real plain `[` as `[`.
    private static let plainRows: [(character: String, modifiers: NSEvent.ModifierFlags, action: PlayerCharacterAction?)] = [
        ("[", [], .stepRate(forward: false)),
        ("]", [], .stepRate(forward: true)),
        ("[", [.shift], .stepRate(forward: false)),
        ("]", [.shift], .stepRate(forward: true)),
        ("{", [.shift], .stepRate(forward: false)),
        ("}", [.shift], .stepRate(forward: true)),
        (".", [], .stepFrames(1)),
        (".", [.shift], .stepFrames(1)),
        (",", [], .stepFrames(-1)),
        (",", [.shift], .stepFrames(-1)),
        ("p", [], .togglePlayback),
        ("p", [.shift], .togglePlayback),
        ("f", [], .toggleFullscreen),
        ("f", [.shift], .toggleFullscreen),
    ]

    private static let wipeRows: [(character: String, modifiers: NSEvent.ModifierFlags, action: PlayerCharacterAction?)] = [
        ("[", [], .nudgeWipe(by: -PlayerKeyMap.wipeStep)),
        ("]", [], .nudgeWipe(by: PlayerKeyMap.wipeStep)),
        ("[", [.shift], .nudgeWipe(by: -PlayerKeyMap.wipeShiftStep)),
        ("]", [.shift], .nudgeWipe(by: PlayerKeyMap.wipeShiftStep)),
        ("{", [.shift], .nudgeWipe(by: -PlayerKeyMap.wipeShiftStep)),
        ("}", [.shift], .nudgeWipe(by: PlayerKeyMap.wipeShiftStep)),
        (".", [], .stepFrames(1)),
        (",", [], .stepFrames(-1)),
        ("p", [], .togglePlayback),
        ("f", [], .toggleFullscreen),
    ]

    // MARK: - Decision table

    func testTheCharacterMatrixMapsEveryKeyWithoutComparisonModifiers() {
        for row in Self.plainRows {
            XCTAssertEqual(
                PlayerKeyMap.characterAction(row.character, modifiers: row.modifiers, isWipeMode: false),
                row.action,
                "\(row.character) with \(row.modifiers)"
            )
        }
    }

    func testTheWipeTakesTheBracketsOnlyWhileItIsShowing() {
        for row in Self.wipeRows {
            XCTAssertEqual(
                PlayerKeyMap.characterAction(row.character, modifiers: row.modifiers, isWipeMode: true),
                row.action,
                "Wipe mode: \(row.character) with \(row.modifiers)"
            )
        }
    }

    func testEveryCommandControlOrOptionCombinationIsLeftToTheSystem() {
        let significant: [NSEvent.ModifierFlags] = [.command, .control, .option]
        var combinations: [NSEvent.ModifierFlags] = significant
        for first in significant {
            for second in significant where second != first {
                combinations.append([first, second])
            }
        }
        combinations.append([.command, .control, .option])
        combinations.append([.shift, .option])
        combinations.append([.shift, .command])

        for modifiers in combinations {
            for (character, _, _) in Self.plainRows {
                XCTAssertNil(
                    PlayerKeyMap.characterAction(character, modifiers: modifiers, isWipeMode: false),
                    "\(character) with \(modifiers)"
                )
                XCTAssertNil(
                    PlayerKeyMap.characterAction(character, modifiers: modifiers, isWipeMode: true),
                    "\(character) with \(modifiers) in wipe mode"
                )
            }
        }
    }

    func testUnrelatedCharactersStayUnmapped() {
        for character in ["b", "i", "o", "j", "k", "l", " ", "x", "0", ":", ";"] {
            XCTAssertNil(
                PlayerKeyMap.characterAction(character, modifiers: [], isWipeMode: false),
                "\(character) must stay with its own handler"
            )
        }
    }

    // MARK: - Call site

    func testTheMonitorDecidesTheCharacterKeysBeforeTheComparisonBranch() throws {
        let source = try String(contentsOf: playerViewSource(), encoding: .utf8)
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)

        let callLine = try XCTUnwrap(
            lines.firstIndex { $0.contains("PlayerKeyMap.characterAction(") }.map { $0 + 1 },
            "The monitor must call the character helper."
        )
        let compareLine = try XCTUnwrap(
            lines.firstIndex { $0.contains("if let compareSession, compareSession.isActive") }.map { $0 + 1 },
            "The comparison branch must still exist."
        )
        XCTAssertLessThan(
            callLine, compareLine,
            "The character helper must be decided before the comparison guard, "
            + "or pause, fullscreen, frame step and the rate keys would only work in Compare Mode."
        )
        let calls = lines.filter { $0.contains("PlayerKeyMap.characterAction(") }.count
        XCTAssertEqual(calls, 1, "The helper must be called exactly once.")
    }

    // MARK: - Monitor routing

    func testTheMonitorRoutesTheCharacterKeysInOrdinaryPlayback() async throws {
        let harness = try MonitorHarness()
        defer { harness.close() }
        try await harness.prepare()
        let controller = harness.controller
        let player = harness.playerView

        // `p` pauses and resumes the real backend.
        XCTAssertFalse(controller.isPlaying, "The clip must start paused for this check.")
        XCTAssertTrue(player.handleKeyEvent("p", [], nil), "`p` must be consumed.")
        let started = await waitUntil { controller.isPlaying }
        XCTAssertTrue(started, "`p` must start playback.")
        XCTAssertTrue(player.handleKeyEvent("p", [], nil))
        await waitUntil { !controller.isPlaying }

        // `[` and `]` step the rate by the app's own 0.5 additive step.
        XCTAssertEqual(controller.currentPlaybackSpeed, 1.0, accuracy: 0.001)
        XCTAssertTrue(player.handleKeyEvent("[", [], nil), "`[` must be consumed.")
        await harness.settle()
        XCTAssertEqual(controller.currentPlaybackSpeed, 0.5, accuracy: 0.001,
                       "`[` must step the rate down by 0.5.")
        XCTAssertTrue(player.handleKeyEvent("]", [], nil))
        await harness.settle()
        XCTAssertEqual(controller.currentPlaybackSpeed, 1.0, accuracy: 0.001,
                       "`]` must step the rate back up by 0.5.")

        // `.` and `,` step one frame, forward and back.
        controller.seekTo(5)
        await harness.settle()
        let anchor = controller.currentPlaybackTime
        XCTAssertTrue(player.handleKeyEvent(".", [], nil), "`.` must be consumed.")
        let advanced = await waitUntil { controller.currentPlaybackTime > anchor + 0.01 }
        XCTAssertTrue(advanced, "`.` must step one frame forward.")
        let forward = controller.currentPlaybackTime
        XCTAssertTrue(player.handleKeyEvent(",", [], nil), ", must be consumed.")
        let rewound = await waitUntil { controller.currentPlaybackTime < forward - 0.01 }
        XCTAssertTrue(rewound, "`,` must step one frame back.")

        // `f` has no published state of its own, so the posted command is the
        // observable: PlayerController.toggleFullscreen() only toggles the window.
        harness.observeCommands()
        XCTAssertTrue(player.handleKeyEvent("f", [], nil), "`f` must be consumed.")
        await harness.settle()
        let postedFullscreen = harness.observedCommands.contains { command in
            if case .toggleFullscreen = command { return true }
            return false
        }
        XCTAssertTrue(postedFullscreen,
                      "`f` must post the fullscreen command in ordinary playback.")
    }

    func testTheComparisonSessionKeepsTheRateKeysAwayFromThePrimary() async throws {
        let harness = try MonitorHarness()
        defer { harness.close() }
        try await harness.prepare()
        let controller = harness.controller
        let session = harness.compareSession

        session.loadSecondary(try MonitorHarness.fixtureURL("compare/source-b.mov"), alignedWith: controller)
        let activated = await waitUntil { session.isActive }
        XCTAssertTrue(activated, "The comparison session never activated.")

        XCTAssertTrue(harness.playerView.handleKeyEvent("[", [], nil))
        await harness.settle()
        XCTAssertEqual(controller.currentPlaybackSpeed, 1.0, accuracy: 0.001,
                       "A comparison session must not step the primary's rate alone.")
        XCTAssertTrue(harness.playerView.handleKeyEvent("]", [], nil))
        await harness.settle()
        XCTAssertEqual(controller.currentPlaybackSpeed, 1.0, accuracy: 0.001,
                       "A comparison session must not step the primary's rate alone.")

        // The wipe still owns the brackets while it is showing.
        session.viewMode = .verticalWipe
        session.setWipePosition(0.5)
        let before = session.wipePosition
        XCTAssertTrue(harness.playerView.handleKeyEvent("]", [], nil))
        await harness.settle()
        XCTAssertEqual(session.wipePosition, before + PlayerKeyMap.wipeStep, accuracy: 0.0001,
                       "`]` must still nudge the wipe by 2 %.")
        XCTAssertTrue(harness.playerView.handleKeyEvent("}", [.shift], nil))
        await harness.settle()
        XCTAssertEqual(session.wipePosition, before + PlayerKeyMap.wipeStep + PlayerKeyMap.wipeShiftStep,
                       accuracy: 0.0001, "Shift-`]` must still nudge the wipe by 10 %.")
    }

    // MARK: - Fixtures

    private func playerViewSource() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Aagedal Media Player/UI/PlayerView.swift")
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}

// MARK: - Harness

/// A real controller with the generated fixture loaded, the monitor's own entry
/// point, and the command handlers installed so posted commands reach the
/// controller exactly as they do in the window.
@MainActor
private final class MonitorHarness {
    let controller: PlayerController
    let compareSession: CompareSessionController
    let playerView: PlayerView
    private(set) var observedCommands: [AppCommand] = []

    private let window: NSWindow
    private let hosting: NSHostingView<AnyView>
    private var commandObserver: AnyCancellable?

    init() throws {
        let url = try Self.fixtureURL("compare/source-a.mov")
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

    /// Waits for the mounted MPV backend and gives it a drawable, the way the
    /// live-backend tests do, so the transport routes have something to drive.
    func prepare() async throws {
        let ready = await waitUntil(timeout: 20) { self.controller.mpvPlayer != nil }
        XCTAssertTrue(ready, "The MPV backend was never constructed.")
        if let mpv = controller.mpvPlayer {
            let layer = MPVMetalLayer()
            layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
            layer.drawableSize = CGSize(width: 320, height: 180)
            mpv.attachDrawable(layer)
        }
        let playable = await waitUntil(timeout: 20) { self.controller.isReady }
        XCTAssertTrue(playable, "The fixture never became playable.")
    }

    func close() {
        commandObserver?.cancel()
        commandObserver = nil
        window.contentView = nil
        window.close()
        compareSession.stop()
        controller.teardown()
    }

    static func fixtureURL(_ relativePath: String) throws -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repository.appending(path: "Test Fixtures/Generated/\(relativePath)")
        if !FileManager.default.fileExists(atPath: url.path) {
            XCTFail("The generated fixture tree is unavailable: \(url.path)")
        }
        return url
    }

    func observeCommands() {
        commandObserver = NotificationCenter.default.appCommandPublisher
            .sink { [weak self] notification in
                guard let command = notification.appCommand else { return }
                self?.observedCommands.append(command)
            }
    }

    /// Gives SwiftUI and the backend a run-loop turn to deliver posted commands.
    func settle() async {
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        hosting.layoutSubtreeIfNeeded()
    }

    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}
