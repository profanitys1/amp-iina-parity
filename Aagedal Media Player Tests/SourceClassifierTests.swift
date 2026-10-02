// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Testing

struct SourceClassifierTests {
    private let thresholds = SourceClassifier.Thresholds(lowBitsPerPixel: 0.05, blockiness: 1.6, softDetailRatio: 0.54)

    private func facts(
        width: Int = 1920, height: Int = 1080, fps: Double = 25, bitrate: Int64 = 20_000_000,
        isHDR: Bool = false, topazTag: String? = nil
    ) -> SourceFacts {
        SourceFacts(codec: "h264", width: width, height: height, fps: fps, videoBitrate: bitrate,
                    bitDepth: 8, isHDR: isHDR, topazTag: topazTag)
    }

    private let healthy = FrameStats(detailRatio: 0.65, blockiness: 1.1, noise: 0.01)

    @Test func bitsPerPixelIsBitrateOverPixelsPerSecond() throws {
        let value = try #require(facts(width: 1280, height: 720, fps: 25, bitrate: 3_000_000).bitsPerPixel)
        #expect(abs(value - 3_000_000.0 / (1280 * 720 * 25)) < 1e-12)
    }

    @Test func bitsPerPixelNeedsEveryInput() {
        #expect(facts(bitrate: 0).bitsPerPixel == nil)
        #expect(facts(fps: 0).bitsPerPixel == nil)
        #expect(facts(width: 0).bitsPerPixel == nil)
    }

    @Test func hdrWinsOverEverything() {
        let result = SourceClassifier.classify(facts(bitrate: 500_000, isHDR: true, topazTag: "x"), healthy, thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .hdr, reason: "HDR"))
    }

    @Test func topazBeatsCompressedAndSoft() {
        let soft = FrameStats(detailRatio: 0.1, blockiness: 3, noise: 0)
        let result = SourceClassifier.classify(facts(bitrate: 500_000, topazTag: "Proteus"), soft, thresholds: thresholds)
        #expect(result.sourceClass == .topaz)
    }

    @Test func lowBitsPerPixelIsCompressedWithTheBitrateAsReason() {
        // 2.1 Mbit/s at 1920x1080x25 is 0.0405 bits per pixel.
        let result = SourceClassifier.classify(facts(bitrate: 2_100_000), nil, thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .compressed, reason: "2.1 Mbit/s"))
    }

    @Test func blockinessMakesACompressedSourceEvenAtAHighBitrate() {
        let blocky = FrameStats(detailRatio: 0.65, blockiness: 2.0, noise: 0)
        let result = SourceClassifier.classify(facts(), blocky, thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .compressed, reason: "blocky 2.0"))
    }

    @Test func lowDetailIsSoft() {
        let result = SourceClassifier.classify(facts(), FrameStats(detailRatio: 0.40, blockiness: 1.1, noise: 0), thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .soft, reason: "soft 0.40"))
    }

    @Test func compressedBeatsSoft() {
        let both = FrameStats(detailRatio: 0.2, blockiness: 2.5, noise: 0)
        #expect(SourceClassifier.classify(facts(), both, thresholds: thresholds).sourceClass == .compressed)
    }

    @Test func everythingElseIsClean() {
        #expect(SourceClassifier.classify(facts(), healthy, thresholds: thresholds).sourceClass == .clean)
    }

    @Test func withoutStatsOnlyMetadataRulesApply() {
        // Soft-looking numbers cannot matter when there are none.
        #expect(SourceClassifier.classify(facts(), nil, thresholds: thresholds).sourceClass == .clean)
        #expect(SourceClassifier.classify(facts(bitrate: 0), nil, thresholds: thresholds).sourceClass == .clean)
    }

    @Test(arguments: [
        ("yuv420p", 8), ("nv12", 8), ("yuv420p10le", 10), ("p010le", 10), ("yuv422p12le", 12),
        ("gbrp16le", 16), ("gray16le", 16), ("yuv444p10", 10),
    ] as [(String, Int)])
    func readsBitDepthFromPixelFormat(format: String, depth: Int) {
        #expect(SourceFacts.bitDepth(pixelFormat: format) == depth)
    }

    @Test func unknownPixelFormatHasNoBitDepth() {
        #expect(SourceFacts.bitDepth(pixelFormat: nil) == nil)
        #expect(SourceFacts.bitDepth(pixelFormat: "") == nil)
    }

    @Test func findsTopazTagsInFFmpegOutput() {
        let container = "  Metadata:\n    encoder         : Lavf\n    videoai         : Enhanced using Proteus v4\n"
        #expect(SourceFacts.topazTag(inFFmpegOutput: container) == "Enhanced using Proteus v4")
        // Matroska prints stream tag keys upper-case.
        #expect(SourceFacts.topazTag(inFFmpegOutput: "    Metadata:\n      VIDEOAI_PROVIDER: Topaz\n") == "Topaz")
        #expect(SourceFacts.topazTag(inFFmpegOutput: "    encoder         : Lavf\n") == nil)
    }
}
