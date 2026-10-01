// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Foundation
@testable import Aagedal_Media_Player

struct EnhancementSuggestionTests {
    @Test func lowBitrateVideoSuggestsEnhancement() {
        let suggestion = EnhancementSuggestion.suggest(
            bitrate: 2_000_000,  // 2 Mbit/s (WhatsApp)
            sourceSize: CGSize(width: 640, height: 352),
            pixelFormat: "yuv420p"
        )
        
        #expect(suggestion.shouldEnhance == true)
        #expect(suggestion.recommendedProfile == .upscaleLight)
        #expect(suggestion.reason.contains("Low bitrate"))
    }
    
    @Test func highBitrateVideoSkipsEnhancement() {
        let suggestion = EnhancementSuggestion.suggest(
            bitrate: 50_000_000,  // 50 Mbit/s (high quality)
            sourceSize: CGSize(width: 1920, height: 1080),
            pixelFormat: "yuv420p"
        )
        
        #expect(suggestion.shouldEnhance == false)
    }
    
    @Test func lowResolutionSuggestsEnhancement() {
        let suggestion = EnhancementSuggestion.suggest(
            bitrate: 15_000_000,  // 15 Mbit/s (medium)
            sourceSize: CGSize(width: 480, height: 270),  // Low res
            pixelFormat: "yuv420p"
        )
        
        #expect(suggestion.shouldEnhance == true)
        #expect(suggestion.reason.contains("Low resolution"))
    }
    
    @Test func borderlineBitrateAtThreshold() {
        let suggestion = EnhancementSuggestion.suggest(
            bitrate: 10_000_000,  // Exactly 10 Mbit/s (threshold)
            sourceSize: CGSize(width: 1920, height: 1080),
            pixelFormat: "yuv420p"
        )
        
        // At threshold, should not suggest enhancement
        #expect(suggestion.shouldEnhance == false)
    }
    
    @Test func veryLowBitrateAndResolution() {
        let suggestion = EnhancementSuggestion.suggest(
            bitrate: 1_000_000,  // 1 Mbit/s (very low)
            sourceSize: CGSize(width: 320, height: 180),  // Very low res
            pixelFormat: "yuv420p"
        )
        
        #expect(suggestion.shouldEnhance == true)
        #expect(suggestion.reason.contains("Low bitrate"))
    }
}
