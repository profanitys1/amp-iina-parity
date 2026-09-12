// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import os

/// A claim-once gate that is safe to touch from any thread.
///
/// Used for one-shot diagnostics, where the point is that the work happens
/// exactly once no matter how many callers race for it. `OSAllocatedUnfairLock`
/// carries the state rather than a bare `static var`, which had no
/// synchronization at all.
final class OneShotFlag: @unchecked Sendable {
    private let claimed = OSAllocatedUnfairLock(initialState: false)

    /// Returns `true` to exactly one caller per reset, `false` to the rest.
    nonisolated func claim() -> Bool {
        claimed.withLock { alreadyClaimed in
            guard !alreadyClaimed else { return false }
            alreadyClaimed = true
            return true
        }
    }

    nonisolated func reset() {
        claimed.withLock { $0 = false }
    }
}
