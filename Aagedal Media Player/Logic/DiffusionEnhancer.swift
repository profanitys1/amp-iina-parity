// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os.log

/// Manages offline video enhancement using Stream-DiffVSR.
actor DiffusionEnhancer {
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "DiffusionEnhancer")
    
    private let appSupportDir: URL
    private let venvDir: URL
    private let enhanceScript: URL
    
    private var currentProcess: Process?
    
    enum EnhancementStatus: Equatable, Sendable {
        case pending
        case processing
        case completed
        case cancelled
        case failed(String)
    }
    
    struct EnhancementProgress: Sendable {
        let status: EnhancementStatus
        let fractionCompleted: Double
        let outputURL: URL?
    }
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.appSupportDir = appSupport.appendingPathComponent("amp", isDirectory: true)
        self.venvDir = appSupportDir.appendingPathComponent("stream-diffvsr-venv", isDirectory: true)
        self.enhanceScript = appSupportDir.appendingPathComponent("enhance_video.py")
    }
    
    /// Checks if Stream-DiffVSR is set up and ready to use.
    func isSetup() async -> Bool {
        let pythonPath = venvDir.appendingPathComponent("bin/python3")
        return FileManager.default.fileExists(atPath: pythonPath.path) &&
               FileManager.default.fileExists(atPath: enhanceScript.path)
    }
    
    /// Sets up Stream-DiffVSR environment by running the setup script.
    func setup() async throws {
        let setupScript = Bundle.main.path(forResource: "setup_stream_diffvsr", ofType: "sh")
            ?? "/Users/filip/src/amp/Scripts/setup_stream_diffvsr.sh"
        
        guard FileManager.default.fileExists(atPath: setupScript) else {
            throw EnhancementError.setupScriptNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [setupScript]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            logger.error("Setup failed: \(output)")
            throw EnhancementError.setupFailed(output)
        }
        
        logger.info("Stream-DiffVSR setup completed successfully")
    }
    
    /// Enhances a video using Stream-DiffVSR.
    func enhance(
        videoURL: URL,
        outputURL: URL?,
        scale: Int = 4,
        progressHandler: (@Sendable (EnhancementProgress) -> Void)? = nil
    ) async -> EnhancementProgress {
        guard await isSetup() else {
            let progress = EnhancementProgress(
                status: .failed("Stream-DiffVSR is not set up. Run setup first."),
                fractionCompleted: 0,
                outputURL: nil
            )
            progressHandler?(progress)
            return progress
        }
        
        let finalOutputURL = outputURL ?? generateOutputURL(for: videoURL)
        let pythonPath = venvDir.appendingPathComponent("bin/python3")
        
        let process = Process()
        process.executableURL = pythonPath
        process.arguments = [
            enhanceScript.path,
            "--input", videoURL.path,
            "--output", finalOutputURL.path,
            "--scale", String(scale),
            "--device", "mps",
            "--progress"
        ]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        
        currentProcess = process
        
        // Report initial progress
        let initialProgress = EnhancementProgress(
            status: .processing,
            fractionCompleted: 0,
            outputURL: nil
        )
        progressHandler?(initialProgress)
        
        do {
            try process.run()
            
            // Read progress output in background
            Task.detached { [weak self] in
                let handle = outputPipe.fileHandleForReading
                while true {
                    let data = handle.availableData
                    if data.isEmpty {
                        break
                    }
                    
                    if let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        if let progress = await self?.parseProgress(line) {
                            progressHandler?(progress)
                        }
                    }
                }
            }
            
            process.waitUntilExit()
            currentProcess = nil
            
            if Task.isCancelled {
                let progress = EnhancementProgress(
                    status: .cancelled,
                    fractionCompleted: 0,
                    outputURL: nil
                )
                progressHandler?(progress)
                return progress
            }
            
            guard process.terminationStatus == 0 else {
                let progress = EnhancementProgress(
                    status: .failed("Enhancement failed with exit code \(process.terminationStatus)"),
                    fractionCompleted: 0,
                    outputURL: nil
                )
                progressHandler?(progress)
                return progress
            }
            
            let progress = EnhancementProgress(
                status: .completed,
                fractionCompleted: 1.0,
                outputURL: finalOutputURL
            )
            progressHandler?(progress)
            return progress
            
        } catch {
            currentProcess = nil
            let progress = EnhancementProgress(
                status: .failed("Failed to start enhancement: \(error.localizedDescription)"),
                fractionCompleted: 0,
                outputURL: nil
            )
            progressHandler?(progress)
            return progress
        }
    }
    
    /// Cancels the current enhancement process.
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }
    
    private func generateOutputURL(for inputURL: URL) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let outputFilename = "\(filename)_enhanced_\(Int(Date().timeIntervalSince1970)).mp4"
        return tempDir.appendingPathComponent(outputFilename)
    }
    
    private func parseProgress(_ line: String) -> EnhancementProgress? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        if let status = json["status"] as? String {
            if status == "completed" {
                return EnhancementProgress(status: .completed, fractionCompleted: 1.0, outputURL: nil)
            } else if status == "failed" {
                let error = json["error"] as? String ?? "Unknown error"
                return EnhancementProgress(status: .failed(error), fractionCompleted: 0, outputURL: nil)
            }
        }
        
        if let fraction = json["fraction"] as? Double {
            return EnhancementProgress(status: .processing, fractionCompleted: fraction, outputURL: nil)
        }
        
        return nil
    }
    
    enum EnhancementError: Error, LocalizedError {
        case setupScriptNotFound
        case setupFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .setupScriptNotFound:
                return "Setup script not found"
            case .setupFailed(let output):
                return "Setup failed: \(output)"
            }
        }
    }
}
