// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import XCTest

/// Runs the bundled ffmpeg against the generated fixtures in `analysis/`
/// (scripts/generate-test-fixtures.sh). Debug builds are slow at the pixel maths, so these
/// calls use a long timeout; the production default is 5 s.
final class FrameAnalyzerIntegrationTests: XCTestCase {
    private let timeout = Duration.seconds(60)

    @MainActor
    private func fixture(_ name: String) throws -> URL {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is unavailable.") }
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        }
        guard FileManager.default.fileExists(atPath: directory.appending(path: "MANIFEST.txt").path) else {
            throw XCTSkip("Generated media fixtures are unavailable. Run scripts/generate-test-fixtures.sh or set MEDIA_FIXTURE_DIR.")
        }
        let url = directory.appending(path: "analysis/\(name)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("analysis/\(name) is missing. Re-run scripts/generate-test-fixtures.sh.")
        }
        return url
    }

    @MainActor
    func testMeasuresALowBitrateFixtureWithinBounds() async throws {
        let url = try fixture("low-bitrate-720p.mp4")
        let analysis = await FrameAnalyzer.shared.analyze(url: url, duration: 4, timeout: timeout)
        let stats = try XCTUnwrap(analysis.stats)
        XCTAssertTrue((0.3...1.5).contains(stats.detailRatio), "detailRatio \(stats.detailRatio)")
        XCTAssertTrue((2.0...20).contains(stats.blockiness), "blockiness \(stats.blockiness)")
        XCTAssertTrue((0...1).contains(stats.noise), "noise \(stats.noise)")
        XCTAssertNil(analysis.topazTag)
    }

    @MainActor
    func testStarvedEncodeIsBlockierThanAnOrdinaryOne() async throws {
        let starvedURL = try fixture("low-bitrate-720p.mp4")
        let ordinaryURL = try fixture("topaz-container.mp4")
        let starvedAnalysis = await FrameAnalyzer.shared.analyze(url: starvedURL, duration: 4, timeout: timeout)
        let ordinaryAnalysis = await FrameAnalyzer.shared.analyze(url: ordinaryURL, duration: 4, timeout: timeout)
        let starved = try XCTUnwrap(starvedAnalysis.stats)
        let ordinary = try XCTUnwrap(ordinaryAnalysis.stats)
        XCTAssertGreaterThan(starved.blockiness, ordinary.blockiness)
    }

    @MainActor
    func testReadsTheTopazTagFromContainerAndStream() async throws {
        let containerURL = try fixture("topaz-container.mp4")
        let streamURL = try fixture("topaz-stream.mkv")
        let container = await FrameAnalyzer.shared.analyze(url: containerURL, duration: 4, timeout: timeout)
        XCTAssertEqual(container.topazTag, "Enhanced using Proteus v4")
        let stream = await FrameAnalyzer.shared.analyze(url: streamURL, duration: 4, timeout: timeout)
        XCTAssertEqual(stream.topazTag, "Topaz")
    }

    @MainActor
    func testRepeatedAnalysisComesFromTheCache() async throws {
        let url = try fixture("low-bitrate-720p.mp4")
        let analyzer = FrameAnalyzer()
        let first = await analyzer.analyze(url: url, duration: 4, timeout: timeout)
        let started = ContinuousClock.now
        let second = await analyzer.analyze(url: url, duration: 4, timeout: timeout)
        XCTAssertEqual(first, second)
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(200))
    }

    @MainActor
    func testFilesShorterThanTwoSecondsGetNoStatistics() async throws {
        let url = try fixture("short.mp4")
        let analysis = await FrameAnalyzer.shared.analyze(url: url, duration: 1, timeout: timeout)
        XCTAssertNil(analysis.stats)
    }

    @MainActor
    func testTimeoutKeepsTheMetadataOnlyPick() async throws {
        let url = try fixture("low-bitrate-720p.mp4")
        let analysis = await FrameAnalyzer().analyze(url: url, duration: 4, timeout: .milliseconds(1))
        XCTAssertEqual(analysis, SourceAnalysis())
    }
}
