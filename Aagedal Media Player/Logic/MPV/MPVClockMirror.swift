// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Holds the most recent playback clock sample so it can be read without
/// entering mpv's serial queue.
///
/// `mpv_get_property` is only safe while serialized on that queue, and taking
/// it with `queue.sync` from the main actor stalls the UI whenever the queue is
/// draining events or extracting a 4K screenshot. The event loop already sees
/// every `time-pos` change, so it records it here instead.
nonisolated final class MPVClockMirror: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval?

    func store(_ value: TimeInterval?) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func sample() -> TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
