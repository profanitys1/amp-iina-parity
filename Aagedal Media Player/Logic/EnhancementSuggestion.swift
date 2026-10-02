// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Analyzes video properties and suggests enhancement profiles.
nonisolated enum EnhancementSuggestion {
    /// Bitrate threshold for WhatsApp-style compressed video (bits/sec).
    /// 10 Mbit/s = 10,000,000 bits/sec
    static let lowBitrateThreshold: Int64 = 10_000_000
    
    /// Resolution threshold for low-res content that benefits from upscaling.
    static let lowResThreshold: CGFloat = 720
    
    struct Suggestion {
        let shouldEnhance: Bool
        let reason: String
        let recommendedProfile: RenderProfile
    }
    
    /// Analyzes video properties and returns an enhancement suggestion.
    static func suggest(
        bitrate: Int64,
        sourceSize: NSSize?,
        pixelFormat: String?
    ) -> Suggestion {
        // Check if video is low-bitrate (WhatsApp-style compression)
        let isLowBitrate = bitrate > 0 && bitrate < lowBitrateThreshold
        let bitrateMBit = Double(bitrate) / 1_000_000
        
        // Check if video is low-resolution
        let isLowRes = sourceSize.map { max($0.width, $0.height) < lowResThreshold } ?? false
        
        // Check pixel format (4:2:0 chroma subsampling)
        let hasChromaSubsampling = pixelFormat?.contains("420") == true
        
        // Build suggestion based on video characteristics
        if isLowBitrate && isLowRes {
            let reason = "Low bitrate (\(String(format: "%.1f", bitrateMBit)) Mbit/s) and low resolution — enhancement recommended"
            return Suggestion(
                shouldEnhance: true,
                reason: reason,
                recommendedProfile: .compressed
            )
        } else if isLowBitrate {
            let reason = "Low bitrate (\(String(format: "%.1f", bitrateMBit)) Mbit/s) — enhancement may improve quality"
            return Suggestion(
                shouldEnhance: true,
                reason: reason,
                recommendedProfile: .compressed
            )
        } else if isLowRes {
            let reason = "Low resolution — upscaling may improve sharpness"
            return Suggestion(
                shouldEnhance: true,
                reason: reason,
                recommendedProfile: .compressed
            )
        } else {
            let reason = "High quality source — enhancement not needed"
            return Suggestion(
                shouldEnhance: false,
                reason: reason,
                recommendedProfile: .off
            )
        }
    }
}
