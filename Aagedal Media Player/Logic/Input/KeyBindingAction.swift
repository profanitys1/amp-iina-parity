// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The rebindable actions, and the defaults they start on. These names are
// written into the user's configuration file, so renaming a case breaks
// existing files — add a new case instead.
//
// Arrow keys are deliberately absent: their behaviour is a matrix of action
// and window routing across eight modifier combinations, and flattening it
// into chords would change multi-window behaviour. Compare Mode's wipe is
// absent for the same kind of reason — it is modal, so the same key means
// something different while wiping.

import Foundation

nonisolated enum KeyBindingAction: String, CaseIterable, Codable {
    case togglePlayback
    case toggleFullscreen
    case stepRateForward
    case stepRateBackward
    case stepFrameForward
    case stepFrameBackward
    case reverse
    case fastForward
    case slowReverse
    case slowForward
    case setTrimIn
    case clearTrimIn
    case jumpToTrimIn
    case setTrimOut
    case clearTrimOut
    case jumpToTrimOut
    case clearAllTrim
    case toggleCompareSource
}

nonisolated enum KeyBindingDefaults {
    /// Exactly the bindings the compiled key map had, so nothing is lost.
    static let table: [KeyChord: KeyBindingAction] = {
        var table: [KeyChord: KeyBindingAction] = [:]
        func bind(_ chord: String, _ action: KeyBindingAction) {
            guard let chord = KeyChord(string: chord) else {
                assertionFailure("Malformed default chord: \(chord)")
                return
            }
            table[chord] = action
        }
        bind("p", .togglePlayback)
        bind("k", .togglePlayback)
        bind("space", .togglePlayback)
        bind("f", .toggleFullscreen)
        bind("]", .stepRateForward)
        bind("[", .stepRateBackward)
        bind(".", .stepFrameForward)
        bind(",", .stepFrameBackward)
        bind("j", .reverse)
        bind("l", .fastForward)
        bind("alt+j", .slowReverse)
        bind("alt+l", .slowForward)
        bind("i", .setTrimIn)
        bind("alt+i", .clearTrimIn)
        bind("shift+i", .jumpToTrimIn)
        bind("o", .setTrimOut)
        bind("alt+o", .clearTrimOut)
        bind("shift+o", .jumpToTrimOut)
        bind("alt+x", .clearAllTrim)
        bind("b", .toggleCompareSource)
        return table
    }()
}
