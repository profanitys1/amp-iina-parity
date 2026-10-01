// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Narrows mpv's hwdec-codecs list to what this Mac can actually decode in
// hardware. Modelled on IINA's adjustCodecWhiteList (MPVController.swift:201).
// Asking VideoToolbox to hardware-decode something it cannot leaves mpv falling
// back silently, with no diagnostic and worse performance than saying so.

import Foundation

nonisolated enum MPVCodecWhitelist {
    /// - Parameter isSupported: `true` keep, `false` drop, `nil` when this app
    ///   has no opinion — an unknown codec is kept rather than guessed at.
    /// - Returns: the narrowed list, or `nil` when nothing changed.
    static func narrowed(
        _ whitelist: String,
        isSupported: (String) -> Bool?
    ) -> String? {
        let codecs = whitelist
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !codecs.isEmpty else { return nil }

        let kept = codecs.filter { isSupported($0) != false }
        return kept.count == codecs.count ? nil : kept.joined(separator: ",")
    }
}
