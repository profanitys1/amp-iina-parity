// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Decides how large a backward-decode buffer to ask mpv for.
///
/// mpv's documentation is explicit that this is a remedy for reversal queue
/// overflow, not a default: the buffer exists to bound resource use, and a
/// file that never overflows should never pay for one that does. The app
/// previously set 4 GiB on every player up front.
nonisolated enum ReverseBufferPolicy {
    /// Ascending sizes, applied one step per reported overflow.
    static let ladder = ["1GiB", "2GiB", "4GiB"]

    /// The size to apply after `currentIndex` overflows, or `nil` when the
    /// ladder is exhausted and mpv should keep its own default.
    static func next(currentIndex: Int) -> String? {
        let next = currentIndex + 1
        guard ladder.indices.contains(next) else { return nil }
        return ladder[next]
    }

    /// The ladder position a value corresponds to, or `nil` if the value did
    /// not come from this policy.
    static func index(ofBufferValue value: String) -> Int? {
        ladder.firstIndex(of: value)
    }
}
