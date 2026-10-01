// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Parameters used to enhance a video, stored alongside the enhanced file.
struct EnhancementParameters: Codable, Sendable {
    let profile: RenderProfile
    let bitrate: Int64
    let sourceWidth: CGFloat?
    let sourceHeight: CGFloat?
    let pixelFormat: String?
    
    init(profile: RenderProfile, bitrate: Int64, sourceSize: CGSize? = nil, pixelFormat: String? = nil) {
        self.profile = profile
        self.bitrate = bitrate
        self.sourceWidth = sourceSize?.width
        self.sourceHeight = sourceSize?.height
        self.pixelFormat = pixelFormat
    }
    
    var sourceSize: CGSize? {
        guard let width = sourceWidth, let height = sourceHeight else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// Metadata for an enhanced video file stored in the cache.
struct EnhancedVideoMetadata: Codable, Sendable {
    let originalPath: String
    let enhancedPath: String
    let originalModificationDate: Date
    let originalFileSize: Int64
    let enhancedFileSize: Int64
    let enhancementDate: Date
    let parameters: EnhancementParameters
    var lastAccessedDate: Date
    
    init(
        originalPath: String,
        enhancedPath: String,
        originalModificationDate: Date,
        originalFileSize: Int64,
        enhancedFileSize: Int64,
        enhancementDate: Date,
        parameters: EnhancementParameters,
        lastAccessedDate: Date = Date()
    ) {
        self.originalPath = originalPath
        self.enhancedPath = enhancedPath
        self.originalModificationDate = originalModificationDate
        self.originalFileSize = originalFileSize
        self.enhancedFileSize = enhancedFileSize
        self.enhancementDate = enhancementDate
        self.parameters = parameters
        self.lastAccessedDate = lastAccessedDate
    }
}
