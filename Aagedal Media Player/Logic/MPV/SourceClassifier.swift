// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What amp knows about a file before it looks at any pixels.
nonisolated struct SourceFacts: Equatable, Sendable {
    var codec: String?
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 0
    /// Video stream bitrate in bits per second; 0 when unknown.
    var videoBitrate: Int64 = 0
    var bitDepth: Int?
    var isHDR = false
    /// The text of a `videoai` or `videoai_provider` tag, when the file carries one.
    var topazTag: String?

    var sourcePixels: Double { Double(max(0, width)) * Double(max(0, height)) }

    /// Bits per pixel per frame; nil until bitrate, size and frame rate are all known.
    var bitsPerPixel: Double? {
        guard videoBitrate > 0, width > 0, height > 0, fps > 0 else { return nil }
        return Double(videoBitrate) / (Double(width) * Double(height) * fps)
    }

    /// Bit depth from an mpv or ffmpeg pixel format name such as `yuv420p10le`.
    static func bitDepth(pixelFormat: String?) -> Int? {
        guard let format = pixelFormat?.lowercased(), !format.isEmpty else { return nil }
        for (token, depth) in [("p010", 10), ("p210", 10), ("p410", 10), ("p016", 16), ("p216", 16), ("p416", 16)]
        where format.contains(token) {
            return depth
        }
        for depth in [16, 14, 12, 10, 9] where format.contains("p\(depth)") || format.contains("\(depth)le") || format.contains("\(depth)be") {
            return depth
        }
        return 8
    }

    /// The value of a `videoai` or `videoai_provider` tag in `ffmpeg -i` output.
    /// ffmpeg prints tags as `    key   : value`; Matroska upper-cases the key.
    static func topazTag(inFFmpegOutput text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "videoai" || key == "videoai_provider" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? key : value
        }
        return nil
    }
}

/// Picture statistics averaged over the sampled frames.
nonisolated struct FrameStats: Equatable, Sendable {
    /// Residual after a 2x down/up round trip over the mean gradient. Low means little real fine detail.
    var detailRatio: Double
    /// Mean luma step across 8-pixel block boundaries over the mean step elsewhere. Well above 1 means visible blocking.
    var blockiness: Double
    /// Median local standard deviation of the flattest 10 % of 8x8 blocks, as a fraction of full scale.
    var noise: Double
}

nonisolated enum SourceClass: String, CaseIterable, Sendable {
    case hdr, topaz, compressed, soft, clean
}

nonisolated struct SourceClassification: Equatable, Sendable {
    let sourceClass: SourceClass
    /// Short text for the badge, for example `2.1 Mbit/s`.
    let reason: String
}

nonisolated enum SourceClassifier {
    nonisolated struct Thresholds: Equatable, Sendable {
        /// Below this many bits per pixel per frame a source counts as compressed.
        var lowBitsPerPixel: Double
        /// At or above this blockiness a source counts as compressed.
        var blockiness: Double
        /// Below this detail ratio a source counts as soft.
        var softDetailRatio: Double

        /// Starting values. Task 7 replaces them with the approved calibration.
        static let calibrated = Thresholds(lowBitsPerPixel: 0.05, blockiness: 1.6, softDetailRatio: 0.54)
    }

    /// Precedence: hdr, then topaz, then compressed, soft, clean. Without `stats` only
    /// the metadata rules apply.
    static func classify(
        _ facts: SourceFacts,
        _ stats: FrameStats?,
        thresholds: Thresholds = .calibrated
    ) -> SourceClassification {
        if facts.isHDR {
            return SourceClassification(sourceClass: .hdr, reason: "HDR")
        }
        if facts.topazTag != nil {
            return SourceClassification(sourceClass: .topaz, reason: "Topaz tag")
        }
        if let bitsPerPixel = facts.bitsPerPixel, bitsPerPixel < thresholds.lowBitsPerPixel {
            let megabits = Double(facts.videoBitrate) / 1_000_000
            return SourceClassification(sourceClass: .compressed, reason: String(format: "%.1f Mbit/s", megabits))
        }
        if let stats {
            if stats.blockiness >= thresholds.blockiness {
                return SourceClassification(sourceClass: .compressed, reason: String(format: "blocky %.1f", stats.blockiness))
            }
            if stats.detailRatio < thresholds.softDetailRatio {
                return SourceClassification(sourceClass: .soft, reason: String(format: "soft %.2f", stats.detailRatio))
            }
        }
        return SourceClassification(sourceClass: .clean, reason: "clean source")
    }
}
