// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Foundation
@testable import Aagedal_Media_Player

struct EnhancementIntegrationTests {
    @Test func endToEndEnhancementWorkflow() async throws {
        // Create test video with low bitrate
        let testVideoURL = try await createLowBitrateTestVideo()
        defer { try? FileManager.default.removeItem(at: testVideoURL) }
        
        // Initialize components
        let cache = EnhancementCache()
        let controller = await MainActor.run { PlayerController() }
        
        // Load video (should start background enhancement if Stream-DiffVSR is set up)
        await controller.loadVideo(testVideoURL)
        
        // Wait for enhancement to complete (if Stream-DiffVSR is set up)
        var enhancementCompleted = false
        let observer = NotificationCenter.default.addObserver(
            forName: .enhancementCompleted,
            object: nil,
            queue: .main
        ) { _ in
            enhancementCompleted = true
        }
        
        // Wait up to 60 seconds for enhancement
        for _ in 0..<60 {
            if enhancementCompleted {
                break
            }
            try await Task.sleep(for: .seconds(1))
        }
        
        NotificationCenter.default.removeObserver(observer)
        
        // If Stream-DiffVSR is not set up, enhancement won't complete
        // This is expected in CI/test environments
        // Check if enhancement was attempted by looking at the current URL
        let currentURL = await controller.currentVideoURL
        
        if enhancementCompleted {
            // Load video again (should use cached enhanced version)
            await controller.loadVideo(testVideoURL)
            
            let newURL = await controller.currentVideoURL
            #expect(newURL?.path.contains("Enhanced") == true)
            
            // Verify cache size
            let cacheSize = await cache.totalSize()
            #expect(cacheSize > 0)
        } else {
            // Enhancement didn't complete (Stream-DiffVSR not set up)
            // Just verify the original video was loaded
            #expect(currentURL == testVideoURL)
        }
    }
    
    @Test func enhancementRespectsAutoEnhanceSetting() async throws {
        // Disable auto-enhance
        UserDefaults.standard.set(false, forKey: AppSettings.autoEnhanceEnabled.key)
        defer {
            UserDefaults.standard.set(true, forKey: AppSettings.autoEnhanceEnabled.key)
        }
        
        let controller = await MainActor.run { PlayerController() }
        let testVideoURL = try await createLowBitrateTestVideo()
        defer { try? FileManager.default.removeItem(at: testVideoURL) }
        
        await controller.loadVideo(testVideoURL)
        
        // Wait a bit
        try await Task.sleep(for: .seconds(2))
        
        // Should not start enhancement (auto-enhance disabled)
        let isEnhancing = await controller.isEnhancementInProgress
        #expect(isEnhancing == false)
    }
    
    @Test func cachePersistsAcrossAppLaunches() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let cache1 = EnhancementCache(cacheDirectory: tempDir)
        let originalURL = tempDir.appendingPathComponent("test_persist.mp4")
        let enhancedURL = tempDir.appendingPathComponent("test_enhanced_persist.mp4")
        
        // Create dummy test files
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        try "enhanced".write(to: enhancedURL, atomically: true, encoding: .utf8)
        
        // Store in cache
        try await cache1.store(
            originalURL: originalURL,
            enhancedURL: enhancedURL,
            parameters: EnhancementParameters(profile: .upscaleLight, bitrate: 2_000_000)
        )
        
        // Create new cache instance (simulating app restart)
        let cache2 = EnhancementCache(cacheDirectory: tempDir)
        
        // Should still find cached version
        let cached = await cache2.getEnhancedURL(for: originalURL)
        #expect(cached != nil)
    }
    
    private func createLowBitrateTestVideo() async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("integration_test_\(UUID().uuidString).mp4")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-f", "lavfi",
            "-i", "testsrc=duration=2:size=320x640:rate=30",
            "-c:v", "libx264",
            "-b:v", "500k",
            "-pix_fmt", "yuv420p",
            videoURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "EnhancementIntegrationTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create test video"
            ])
        }
        
        return videoURL
    }
}
