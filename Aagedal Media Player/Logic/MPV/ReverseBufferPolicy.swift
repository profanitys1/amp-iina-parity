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
    /// Ascending pairs. Rung 1 must exceed mpv's own video default (1 GiB),
    /// which the app no longer sets, or the first climb would be a no-op.
    ///
    /// Both sizes move together because mpv emits the identical overflow line
    /// for a video and an audio overflow (`filters/f_decoder_wrapper.c`, where
    /// a `switch` on the stream type selects `video_reverse_size` or
    /// `audio_reverse_size` and then prints one shared message), so the caller
    /// cannot tell which buffer came up short.
    static let ladder: [(video: String, audio: String)] = [
        ("2GiB", "256MiB"),
        ("4GiB", "512MiB"),
    ]

    /// How long one raise suppresses the next. mpv prints the overflow line
    /// once per discarded frame and re-reads the option per enqueued frame, so
    /// without this the ladder would be consumed within a few frames of a
    /// single episode and the progressive climb would collapse into an instant
    /// jump to the top. Half a second is ample for a new size to take effect.
    static let cooldown: TimeInterval = 0.5

    /// The sizes to apply after `currentIndex` overflows, or `nil` when the
    /// ladder is exhausted and mpv should keep its own default.
    static func next(currentIndex: Int) -> (video: String, audio: String)? {
        let next = currentIndex + 1
        guard ladder.indices.contains(next) else { return nil }
        return ladder[next]
    }

    /// The ladder position a video value corresponds to, or `nil` if the value
    /// did not come from this policy.
    static func index(ofVideoValue value: String) -> Int? {
        ladder.firstIndex { $0.video == value }
    }

    /// True for mpv's reversal-queue overflow line. mpv emits the identical
    /// text for video and audio overflow, so the caller cannot tell which
    /// buffer is short and raises both.
    static func isOverflowLogLine(_ text: String) -> Bool {
        text.contains("Reversal queue overflow")
    }

    /// Whether an overflow line may be acted on, given how long ago the last
    /// one was acted on. `nil` means no raise has happened yet.
    static func canRaise(elapsedSinceLastRaise elapsed: TimeInterval?) -> Bool {
        guard let elapsed else { return true }
        return elapsed >= cooldown
    }
}
