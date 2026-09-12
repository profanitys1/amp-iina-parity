// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class TrackRefreshTimingTests: XCTestCase {
    /// mpv only opens the file once a drawable is attached, so the surface has
    /// to outlive the controller for the whole test.
    private var retainedSurfaces: [MPVMetalLayer] = []

    override func tearDown() {
        retainedSurfaces.removeAll()
        super.tearDown()
    }

    /// The multichannel fixture carries a real audio track list. A fixed
    /// 0.5 s wait cannot satisfy this budget, so the test fails against the
    /// old implementation and passes against the event-driven one.
    func testTrackOptionsArriveWithTheFileLoadedSignal() async throws {
        let url = try fixtureDirectory().appending(path: "multichannel-5.1.m4a")
        let controller = PlayerController(
            proResRAWDetector: { _, _ in false }
        )
        defer { controller.teardown() }

        // Same seeding the fixture-backed live suites use: mpv is only driven
        // for a file the controller already has metadata for.
        let metadata = try await MetadataService.shared.metadata(for: url)
        var item = PlayerWindowCoordinator.makeMediaItem(for: url)
        item.metadata = metadata
        item.durationSeconds = metadata.duration ?? 0
        item.hasVideoStream = !metadata.videoStreams.isEmpty
        controller.loadMedia(item)
        controller.updateMetadata(item)

        // Without a drawable mpv never reaches MPV_EVENT_FILE_LOADED, so the
        // signal under test cannot fire at all. setupMPV runs from an async
        // preparation task, so the player does not exist until it completes.
        guard await waitUntil(timeout: 8, { controller.mpvPlayer != nil }) else {
            XCTFail("The forced playback backend was not constructed.")
            return
        }
        let mpv = try XCTUnwrap(controller.mpvPlayer)
        let layer = MPVMetalLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        layer.drawableSize = layer.frame.size
        mpv.attachDrawable(layer)
        retainedSurfaces.append(layer)

        let arrived = await waitUntil(timeout: 0.3) {
            !controller.audioTrackOptions.isEmpty
        }
        XCTAssertTrue(
            arrived,
            "Audio track options must follow MPV_EVENT_FILE_LOADED, not a 0.5 s timer"
        )
    }

    /// Same resolution order the existing fixture-backed suites use: an
    /// explicit override first, then the generated directory beside the
    /// repository. A missing manifest skips rather than failing.
    private func fixtureDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repository.appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: url.appending(path: "MANIFEST.txt").path) else {
            throw XCTSkip(
                "Generated media fixtures are unavailable. Run scripts/generate-test-fixtures.sh " +
                "or set MEDIA_FIXTURE_DIR."
            )
        }
        return url
    }

    /// Polls the main actor until `condition` holds or the budget expires.
    private func waitUntil(
        timeout: TimeInterval,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
