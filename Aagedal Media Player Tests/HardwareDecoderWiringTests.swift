// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

/// Proves mpv's `hwdec-current` observation reaches `MPVPlayer`'s published
/// property, which is the only thing standing between mpv and the inspector's
/// decoder row. `HardwareDecodingStatusTests` covers the formatting of the
/// value; this covers getting the value at all.
///
/// The fixture must carry video. `hwdec-current` is a property of the *video*
/// decoder, so an audio-only file leaves it unavailable forever and the
/// assertion below can never be satisfied — see the fix report for the
/// measurement against `multichannel-5.1.m4a`.
@MainActor
final class HardwareDecoderWiringTests: XCTestCase {
    func testMPVReportsTheDecoderItEngaged() async throws {
        let fixtures = try fixtureDirectory()
        let url = fixtures.appending(path: "sdr-bt709.mp4")

        let player = MPVPlayer()
        defer { player.destroy() }

        let layer = MPVMetalLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        layer.drawableSize = layer.frame.size
        player.attachDrawable(layer)

        player.load(url: url, autostart: true)

        let deadline = Date().addingTimeInterval(5)
        while player.activeHardwareDecoder == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }

        let decoder = try XCTUnwrap(
            player.activeHardwareDecoder,
            "mpv never reported hwdec-current for sdr-bt709.mp4 within 5 seconds. " +
            "MPVPlayer.error=\(player.error ?? "nil") isFileLoaded=\(player.isFileLoaded)"
        )
        XCTAssertFalse(decoder.isEmpty)
    }

    @MainActor
    private func fixtureDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"],
           !override.isEmpty {
            return try validateFixtureDirectory(URL(fileURLWithPath: override, isDirectory: true))
        }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        return try validateFixtureDirectory(
            repository.appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        )
    }

    @MainActor
    private func validateFixtureDirectory(_ url: URL) throws -> URL {
        let manifest = url.appending(path: "MANIFEST.txt")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw XCTSkip(
                "Generated media fixtures are unavailable. Run scripts/generate-test-fixtures.sh " +
                "or set MEDIA_FIXTURE_DIR."
            )
        }
        return url
    }
}
