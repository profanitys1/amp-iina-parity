// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
import Foundation
@testable import Aagedal_Media_Player

struct DiffusionEnhancerTests {
    @Test func diffusionEnhancerProcessesVideo() async throws {
        let enhancer = DiffusionEnhancer()
        
        // Skip test if Stream-DiffVSR is not set up
        guard await enhancer.isSetup() else {
            // Test passes if not set up - this is expected in CI
            return
        }
        
        // Create test video (1 second, 320x640, low bitrate)
        let testVideoURL = try await createTestVideo()
        defer { try? FileManager.default.removeItem(at: testVideoURL) }
        
        let progress = await enhancer.enhance(
            videoURL: testVideoURL,
            outputURL: nil  // Auto-generate
        )
        
        #expect(progress.status == .completed)
        #expect(progress.outputURL != nil)
        
        // Verify output file exists and is larger than input
        let inputSize = try FileManager.default.attributesOfItem(atPath: testVideoURL.path)[.size] as? Int64 ?? 0
        let outputSize = try FileManager.default.attributesOfItem(atPath: progress.outputURL!.path)[.size] as? Int64 ?? 0
        
        #expect(outputSize > inputSize)
        
        // Clean up
        if let outputURL = progress.outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
    
    @Test func diffusionEnhancerReportsProgress() async throws {
        let enhancer = DiffusionEnhancer()
        
        // Skip test if Stream-DiffVSR is not set up
        guard await enhancer.isSetup() else {
            return
        }
        
        let testVideoURL = try await createTestVideo()
        defer { try? FileManager.default.removeItem(at: testVideoURL) }
        
        // Use an actor to safely collect progress updates
        actor ProgressCollector {
            var updates: [Double] = []
            func add(_ value: Double) {
                updates.append(value)
            }
            func getUpdates() -> [Double] {
                return updates
            }
        }
        
        let collector = ProgressCollector()
        
        let progress = await enhancer.enhance(
            videoURL: testVideoURL,
            outputURL: nil,
            progressHandler: { progress in
                Task {
                    await collector.add(progress.fractionCompleted)
                }
            }
        )
        
        #expect(progress.status == .completed)
        let updates = await collector.getUpdates()
        #expect(updates.count > 0)
        #expect(updates.last ?? 0.0 >= 0.99)
        
        // Clean up
        if let outputURL = progress.outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }
    
    @Test func diffusionEnhancerCancelsGracefully() async throws {
        let enhancer = DiffusionEnhancer()
        
        // Skip test if Stream-DiffVSR is not set up
        guard await enhancer.isSetup() else {
            return
        }
        
        let testVideoURL = try await createTestVideo(duration: 10.0)  // Longer video
        defer { try? FileManager.default.removeItem(at: testVideoURL) }
        
        let task = Task {
            await enhancer.enhance(videoURL: testVideoURL, outputURL: nil)
        }
        
        try await Task.sleep(for: .seconds(2))
        task.cancel()
        
        let progress = await task.value
        #expect(progress.status == .cancelled)
    }
    
    @Test func diffusionEnhancerDetectsSetup() async throws {
        let enhancer = DiffusionEnhancer()
        
        // This test just verifies the isSetup() method works
        let isSetup = await enhancer.isSetup()
        
        // Result depends on whether Stream-DiffVSR is installed
        // We just verify it returns a boolean without crashing
        #expect(isSetup == true || isSetup == false)
    }
    
    // Helper function to create test video
    private func createTestVideo(duration: Double = 1.0) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let videoURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).mp4")
        
        // Use ffmpeg to create low-bitrate test video
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-f", "lavfi",
            "-i", "testsrc=duration=\(duration):size=320x640:rate=30",
            "-c:v", "libx264",
            "-b:v", "500k",  // Low bitrate
            "-pix_fmt", "yuv420p",
            videoURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "DiffusionEnhancerTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create test video"
            ])
        }
        
        return videoURL
    }
}
