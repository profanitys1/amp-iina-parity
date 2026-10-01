// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Foundation
@testable import Aagedal_Media_Player

struct EnhancementCacheTests {
    @Test func cacheStoresEnhancedVideo() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let cache = EnhancementCache(cacheDirectory: tempDir)
        let originalURL = tempDir.appendingPathComponent("test_original.mp4")
        let enhancedURL = tempDir.appendingPathComponent("test_enhanced.mp4")
        
        // Create dummy test files
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        try "enhanced".write(to: enhancedURL, atomically: true, encoding: .utf8)
        
        try await cache.store(
            originalURL: originalURL,
            enhancedURL: enhancedURL,
            parameters: EnhancementParameters(profile: .upscaleLight, bitrate: 2_000_000)
        )
        
        let cached = await cache.getEnhancedURL(for: originalURL)
        #expect(cached != nil)
        // Verify the cached file exists and is different from the original
        #expect(cached != originalURL)
        #expect(FileManager.default.fileExists(atPath: cached!.path))
    }
    
    @Test func cacheInvalidatesOnSourceChange() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let cache = EnhancementCache(cacheDirectory: tempDir)
        let originalURL = tempDir.appendingPathComponent("test_original_invalidate.mp4")
        let enhancedURL = tempDir.appendingPathComponent("test_enhanced_invalidate.mp4")
        
        // Create dummy test files
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        try "enhanced".write(to: enhancedURL, atomically: true, encoding: .utf8)
        
        // Store initial version
        try await cache.store(
            originalURL: originalURL,
            enhancedURL: enhancedURL,
            parameters: EnhancementParameters(profile: .upscaleLight, bitrate: 2_000_000)
        )
        
        // Modify source file (simulate by changing modification date)
        let futureDate = Date().addingTimeInterval(10)
        try FileManager.default.setAttributes(
            [.modificationDate: futureDate],
            ofItemAtPath: originalURL.path
        )
        
        let cached = await cache.getEnhancedURL(for: originalURL)
        #expect(cached == nil)  // Should be invalidated
    }
    
    @Test func cacheEvictsLRUWhenFull() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let cache = EnhancementCache(cacheDirectory: tempDir, maxSizeBytes: 100)  // Very small limit
        
        // Store multiple videos exceeding limit
        for i in 0..<5 {
            let originalURL = tempDir.appendingPathComponent("test_\(i).mp4")
            let enhancedURL = tempDir.appendingPathComponent("test_enhanced_\(i).mp4")
            
            // Create files with some size
            let content = String(repeating: "x", count: 30)
            try content.write(to: originalURL, atomically: true, encoding: .utf8)
            try content.write(to: enhancedURL, atomically: true, encoding: .utf8)
            
            try await cache.store(
                originalURL: originalURL,
                enhancedURL: enhancedURL,
                parameters: EnhancementParameters(profile: .upscaleLight, bitrate: 2_000_000)
            )
            
            // Small delay to ensure different timestamps
            try await Task.sleep(for: .milliseconds(100))
        }
        
        let totalSize = await cache.totalSize()
        #expect(totalSize <= 100)
    }
}
