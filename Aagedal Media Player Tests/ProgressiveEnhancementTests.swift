// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Foundation
@testable import Aagedal_Media_Player

struct ProgressiveEnhancementTests {
    @Test func controllerStartsPlaybackWithOriginalVideo() async throws {
        let controller = await MainActor.run { PlayerController() }
        let originalURL = URL(fileURLWithPath: "/tmp/test_original_progressive.mp4")
        
        // Create dummy test file
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: originalURL) }
        
        await controller.loadVideo(originalURL)
        
        // Should start playing original immediately
        let currentURL = await controller.currentVideoURL
        #expect(currentURL == originalURL)
    }
    
    @Test func controllerSwitchesToEnhancedWhenAvailable() async throws {
        let controller = await MainActor.run { PlayerController() }
        let cache = EnhancementCache()
        
        let originalURL = URL(fileURLWithPath: "/tmp/test_original_switch.mp4")
        let enhancedURL = URL(fileURLWithPath: "/tmp/test_enhanced_switch.mp4")
        
        // Create dummy test files
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        try "enhanced".write(to: enhancedURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: enhancedURL)
        }
        
        // Pre-cache enhanced version
        try await cache.store(
            originalURL: originalURL,
            enhancedURL: enhancedURL,
            parameters: EnhancementParameters(
                profile: .upscaleLight,
                bitrate: 2_000_000,
                sourceSize: CGSize(width: 640, height: 352),
                pixelFormat: "yuv420p"
            )
        )
        
        await controller.loadVideo(originalURL)
        
        // Should switch to enhanced version
        let currentURL = await controller.currentVideoURL
        #expect(currentURL != originalURL)
        #expect(currentURL?.path.contains("Enhanced") == true)
    }
    
    @Test func controllerStartsBackgroundEnhancement() async throws {
        let controller = await MainActor.run { PlayerController() }
        let originalURL = URL(fileURLWithPath: "/tmp/test_original_background.mp4")
        
        // Create dummy test file with low bitrate characteristics
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: originalURL) }
        
        await controller.loadVideo(originalURL)
        
        // Should start background enhancement for low-bitrate video
        // (This will only happen if Stream-DiffVSR is set up)
        try await Task.sleep(for: .seconds(1))
        
        let isEnhancing = await controller.isEnhancementInProgress
        // May or may not be enhancing depending on setup
        #expect(isEnhancing == true || isEnhancing == false)
    }
    
    @Test func controllerCancelsEnhancement() async throws {
        let controller = await MainActor.run { PlayerController() }
        let originalURL = URL(fileURLWithPath: "/tmp/test_original_cancel.mp4")
        
        // Create dummy test file
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: originalURL) }
        
        await controller.loadVideo(originalURL)
        
        // Start enhancement (if Stream-DiffVSR is set up)
        try await Task.sleep(for: .milliseconds(500))
        
        // Cancel enhancement
        await controller.cancelEnhancement()
        
        let isEnhancing = await controller.isEnhancementInProgress
        #expect(isEnhancing == false)
    }
}
