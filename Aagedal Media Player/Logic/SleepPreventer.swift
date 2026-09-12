// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keeps the display awake while a video is playing.

import Foundation
import os

/// Holds a `ProcessInfo` activity for as long as some window is playing.
///
/// Video playback needs the display itself kept awake; audio-only playback only
/// needs the machine kept awake, so it takes the weaker assertion and lets the
/// screen saver start. IINA arrived at the same split, having moved off
/// `IOPMAssertionCreateWithName` because power management proved unreliable —
/// `beginActivity` reports no status either, so the outstanding assertion is
/// only observable through `pmset -g assertions`.
@MainActor
final class SleepPreventer {
    static let shared = SleepPreventer()

    private struct PlaybackState {
        var isPlaying: Bool
        var isAudioOnly: Bool
    }

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "sleep")
    private var states: [ObjectIdentifier: PlaybackState] = [:]
    private var activityToken: NSObjectProtocol?
    private var allowsScreenSaver = false

    /// Whether an activity is currently outstanding. `beginActivity` reports no
    /// status, so this is the only way to observe it short of `pmset`.
    var isHoldingAssertion: Bool { activityToken != nil }

    private init() {}

    /// Records one player's contribution. Safe to call on every state change.
    func update(for owner: AnyObject, isPlaying: Bool, isAudioOnly: Bool) {
        states[ObjectIdentifier(owner)] = PlaybackState(isPlaying: isPlaying, isAudioOnly: isAudioOnly)
        apply()
    }

    /// Drops a player that is going away, so a closed window cannot hold the
    /// display awake forever.
    func forget(_ owner: AnyObject) {
        states.removeValue(forKey: ObjectIdentifier(owner))
        apply()
    }

    private func apply() {
        guard UserDefaults.standard.value(for: AppSettings.preventDisplaySleep) else {
            endActivity()
            return
        }
        let playing = states.values.filter(\.isPlaying)
        guard !playing.isEmpty else {
            endActivity()
            return
        }
        // Any video window outranks an audio-only one: the display has to stay on.
        beginActivity(allowingScreenSaver: playing.allSatisfy(\.isAudioOnly))
    }

    private func beginActivity(allowingScreenSaver: Bool) {
        if activityToken != nil {
            guard allowsScreenSaver != allowingScreenSaver else { return }
            endActivity()
        }
        allowsScreenSaver = allowingScreenSaver
        let options: ProcessInfo.ActivityOptions = allowingScreenSaver
            ? .idleSystemSleepDisabled
            : .idleDisplaySleepDisabled
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: options,
            reason: "Aagedal Media Player playback is in progress"
        )
        logger.info("\(allowingScreenSaver ? "Preventing system sleep" : "Preventing display sleep", privacy: .public)")
    }

    private func endActivity() {
        guard let activityToken else { return }
        ProcessInfo.processInfo.endActivity(activityToken)
        self.activityToken = nil
        logger.info("Released the sleep assertion")
    }
}
