// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import OSLog
import os

/// What looking inside a file found. Both fields are nil when nothing could be read.
nonisolated struct SourceAnalysis: Equatable, Sendable {
    var stats: FrameStats?
    var topazTag: String?
}

/// Decodes a few frames with the bundled ffmpeg and measures them. It runs off the main actor,
/// is cancellable, and remembers results in memory keyed by path, size and modification date.
actor FrameAnalyzer {
    static let shared = FrameAnalyzer()

    /// Fewer usable frames than this and the statistics are not trusted.
    static let minimumUsableFrames = 4
    /// A decoded 8K gray frame is 33 MB; the streaming runner keeps nothing, this bounds the buffer.
    private static let maximumFrameBytes = 64 * 1024 * 1024

    private struct Fingerprint: Hashable {
        let path: String
        let size: Int
        let modified: Date
    }

    private enum AnalysisError: Error { case timedOut, ffmpegMissing }

    private var cache: [Fingerprint: SourceAnalysis] = [:]
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "FrameAnalyzer")

    /// Never throws: any failure is logged and returns an empty analysis, so the caller keeps
    /// its metadata-only pick. A cancelled call also returns an empty analysis; the caller
    /// must check `Task.isCancelled` before using the result.
    func analyze(url: URL, duration: Double, timeout: Duration = .seconds(5)) async -> SourceAnalysis {
        guard let before = Self.fingerprint(of: url) else {
            logger.info("Analysis skipped, cannot read \(url.lastPathComponent, privacy: .public)")
            return SourceAnalysis()
        }
        if let hit = cache[before] { return hit }
        guard let ffmpeg = await FFmpegService.ffmpegPath else {
            logger.info("Analysis skipped, bundled ffmpeg is missing")
            return SourceAnalysis()
        }
        do {
            let result = try await Self.withTimeout(timeout) {
                try await Self.measure(path: url.path, duration: duration, ffmpeg: ffmpeg)
            }
            guard Self.fingerprint(of: url) == before else {
                logger.info("Analysis discarded, \(url.lastPathComponent, privacy: .public) changed while it ran")
                return SourceAnalysis()
            }
            cache[before] = result
            return result
        } catch is CancellationError {
            return SourceAnalysis()
        } catch AnalysisError.timedOut {
            logger.info("Analysis of \(url.lastPathComponent, privacy: .public) timed out after \(timeout.components.seconds) s")
            return SourceAnalysis()
        } catch {
            logger.info("Analysis of \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return SourceAnalysis()
        }
    }

    // MARK: - Measuring

    private nonisolated static func fingerprint(of url: URL) -> Fingerprint? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        return Fingerprint(path: url.path, size: size, modified: modified)
    }

    private nonisolated static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AnalysisError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    private nonisolated static func measure(path: String, duration: Double, ffmpeg: String) async throws -> SourceAnalysis {
        let tag = try await topazTag(path: path, ffmpeg: ffmpeg)
        var frames: [FrameStats] = []
        for time in FrameMath.sampleTimes(duration: duration) {
            try Task.checkCancellation()
            guard let luma = try await decodeFrame(path: path, at: time, ffmpeg: ffmpeg),
                  let stats = FrameMath.stats(luma: luma.luma, width: luma.width, height: luma.height) else { continue }
            frames.append(stats)
        }
        return SourceAnalysis(
            stats: frames.count >= minimumUsableFrames ? FrameMath.average(frames) : nil,
            topazTag: tag
        )
    }

    /// `ffmpeg -i` prints container and stream tags to standard error; decoding zero frames
    /// is enough. The exit status is irrelevant here, so the output is read regardless.
    private nonisolated static func topazTag(path: String, ffmpeg: String) async throws -> String? {
        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: ffmpeg),
            arguments: ["-hide_banner", "-nostdin", "-i", path, "-t", "0", "-f", "null", "-"],
            outputLimit: 1_048_576
        )
        return SourceFacts.topazTag(inFFmpegOutput: String(decoding: result.standardError, as: UTF8.self))
    }

    /// One 8-bit gray frame as PGM on a pipe, so the output carries its own dimensions
    /// (autorotation and pixel aspect ratio included). `-ss` before `-i` seeks the input.
    private nonisolated static func decodeFrame(
        path: String,
        at time: Double,
        ffmpeg: String
    ) async throws -> (luma: [UInt8], width: Int, height: Int)? {
        let buffer = OSAllocatedUnfairLock(initialState: Data())
        do {
            try await FFmpegService.runStreamingOutput(
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-nostdin",
                    "-ss", String(format: "%.3f", time), "-i", path,
                    "-frames:v", "1", "-an", "-sn",
                    "-pix_fmt", "gray", "-f", "image2pipe", "-c:v", "pgm", "-",
                ],
                onStandardOutputData: { chunk in
                    buffer.withLock { data in
                        if data.count < maximumFrameBytes { data.append(chunk) }
                    }
                }
            )
        } catch FFmpegError.cancelled {
            throw CancellationError()
        } catch {
            return nil
        }
        return FrameMath.parsePGM(buffer.withLock { $0 })
    }
}
