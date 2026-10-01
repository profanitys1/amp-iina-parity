// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// mpv's icc-profile-auto only works through MPV_RENDER_PARAM_ICC_PROFILE, which
// needs a render context. This app embeds mpv with wid=, so there is no render
// context and no way to hand mpv a profile in memory. Writing the display's
// profile to a file and pointing icc-profile at it is the route that works.

import CryptoKit
import Foundation

nonisolated struct DisplayICCProfileStore {
    let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.aagedal.MediaPlayer/ICCProfiles", isDirectory: true)) {
        self.directory = directory
    }

    /// Writes the profile if it is not already on disk, and returns its path.
    /// Named by content hash so an unchanged profile is written once.
    func url(for data: Data) throws -> URL {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let target = directory.appendingPathComponent("\(digest).icc")
        guard !FileManager.default.fileExists(atPath: target.path) else { return target }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return target
    }
}
