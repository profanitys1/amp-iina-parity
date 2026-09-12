// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What mpv is actually decoding with, as reported by `hwdec-current`.
///
/// The value is read-only from the app's point of view. It exists so a silent
/// fall back to software decoding — the outcome when VideoToolbox refuses a
/// codec — is visible rather than inferred from CPU load.
nonisolated struct HardwareDecodingStatus: Equatable, Sendable {
    /// The raw mpv value, or `nil` when no decoder is loaded yet.
    let mpvValue: String?

    /// mpv reports this when it is decoding in software.
    static let softwareValue = "no"

    static let unavailable = HardwareDecodingStatus(mpvValue: nil)

    init(mpvValue: String?) {
        let trimmed = mpvValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mpvValue = (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// True only for a real hardware decoder. `videotoolbox-copy` still
    /// decodes on the GPU; the copy is about where frames land.
    var isHardwareBacked: Bool {
        guard let mpvValue else { return false }
        return mpvValue != Self.softwareValue
    }

    var label: String {
        guard let mpvValue else { return "Not yet decoded" }
        if mpvValue == Self.softwareValue { return "Software decoding" }
        return "Hardware decoding (\(mpvValue))"
    }
}
