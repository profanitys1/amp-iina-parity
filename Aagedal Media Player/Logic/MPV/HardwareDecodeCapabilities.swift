// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from IINA's HardwareDecodeCapabilities.swift (GPL-3.0), by low-batt.
// https://github.com/iina/iina
//
// VTIsHardwareDecodeSupported is slow and must not run on the main thread, so
// the answers are gathered once on a background queue and cached. Unlike the
// original, an unprobed or unknown codec returns nil rather than trapping:
// "no opinion" is a safe answer, because the caller keeps the codec.

import CoreMedia
import Foundation
import OSLog
import VideoToolbox

nonisolated final class HardwareDecodeCapabilities: @unchecked Sendable {
    static let shared = HardwareDecodeCapabilities()

    /// mpv's codec names, mapped to the CoreMedia types that can satisfy them.
    /// h264 and hevc are absent on purpose: every supported Mac decodes them,
    /// and probing costs a long call for a foregone answer. ProRes RAW is
    /// absent because it never reaches mpv — it is routed to AVPlayer.
    private static let codecTypes: [String: [CMVideoCodecType]] = [
        "av1": [kCMVideoCodecType_AV1],
        "vp9": [kCMVideoCodecType_VP9],
        "prores": [
            kCMVideoCodecType_AppleProRes422,
            kCMVideoCodecType_AppleProRes422HQ,
            kCMVideoCodecType_AppleProRes422LT,
            kCMVideoCodecType_AppleProRes422Proxy,
            kCMVideoCodecType_AppleProRes4444,
            kCMVideoCodecType_AppleProRes4444XQ,
        ],
    ]

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "hwdec")
    private let lock = NSLock()
    /// A group, not the work item: a DispatchWorkItem may be waited on only once.
    private var probe: DispatchGroup?
    private var supported: [String: Bool] = [:]

    /// Starts probing on a background queue. Safe to call more than once.
    func beginProbing() {
        lock.lock()
        guard probe == nil else { lock.unlock(); return }
        let group = DispatchGroup()
        probe = group
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async(group: group) { [self] in
            var results: [String: Bool] = [:]
            for (codec, types) in Self.codecTypes {
                results[codec] = types.contains { type in
                    VTRegisterSupplementalVideoDecoderIfAvailable(type)
                    return VTIsHardwareDecodeSupported(type)
                }
            }
            lock.lock()
            supported = results
            lock.unlock()
            let summary = results.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
            logger.info("Hardware decode support: \(summary, privacy: .public)")
        }
    }

    /// Waits for a running probe, so the first caller may block briefly.
    /// - Returns: `nil` when this app has no opinion — the codec is not probed,
    ///   or probing has not been started.
    func isSupported(mpvCodec: String) -> Bool? {
        guard Self.codecTypes[mpvCodec] != nil else { return nil }
        lock.lock()
        let pending = probe
        lock.unlock()
        guard let pending else { return nil }
        pending.wait()
        lock.lock()
        defer { lock.unlock() }
        return supported[mpvCodec]
    }
}
