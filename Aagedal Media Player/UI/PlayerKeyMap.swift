// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The character-key half of the key layer, kept free of the view so every key
// and modifier combination can be checked on its own.

import AppKit

/// What one bare character key asks the player window to do.
enum PlayerCharacterAction: Equatable {
    case stepRate(forward: Bool)
    case stepFrames(Int)
    case togglePlayback
    case toggleFullscreen
    /// Compare Mode's wipe, nudged by a fraction of the picture width.
    case nudgeWipe(by: Double)
}

/// Maps the characters the key monitor sees onto player actions.
nonisolated enum PlayerKeyMap {
    /// Compare Mode keeps `[`/`]` for its wipe, 2 % at a time and 10 % with
    /// Shift, exactly as it did before the rate keys existed.
    static let wipeStep = 0.02
    static let wipeShiftStep = 0.1

    /// `nil` means the monitor must not consume the key.
    ///
    /// `character` is what `NSEvent.charactersIgnoringModifiers` reports, so a
    /// shifted `[` arrives as `{` and is folded back here; the modifier flags
    /// decide whether that shift means a larger wipe step.
    static func characterAction(
        _ character: String,
        modifiers: NSEvent.ModifierFlags,
        isWipeMode: Bool
    ) -> PlayerCharacterAction? {
        let commandModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard modifiers.intersection(commandModifiers).isEmpty else { return nil }

        let lower = character.lowercased()
        let isWipeKey = lower == "[" || lower == "]" || character == "{" || character == "}"

        if isWipeMode, isWipeKey {
            let step = modifiers.contains(.shift) ? wipeShiftStep : wipeStep
            let backwards = lower == "[" || character == "{"
            return .nudgeWipe(by: backwards ? -step : step)
        }

        switch lower {
        case "[", "{":
            return .stepRate(forward: false)
        case "]", "}":
            return .stepRate(forward: true)
        case ".":
            return .stepFrames(1)
        case ",":
            return .stepFrames(-1)
        case "p":
            return .togglePlayback
        case "f":
            return .toggleFullscreen
        default:
            return nil
        }
    }
}
