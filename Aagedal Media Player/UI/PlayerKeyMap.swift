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

    // MARK: - Arrow keys

    /// What one arrow key asks for. Multi-window sync is a separate decision
    /// (`PlayerArrowRoute`), because the same action can be either local or
    /// broadcast depending on the modifiers.
    static func arrowAction(
        key: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags
    ) -> PlayerArrowAction? {
        arrowDecision(key: key, modifiers: modifiers)?.action
    }

    /// Whether the action stays in this window or is posted for the other
    /// windows, exactly as the monitor routed these keys before.
    static func arrowRoute(
        key: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags
    ) -> PlayerArrowRoute? {
        arrowDecision(key: key, modifiers: modifiers)?.route
    }

    /// The whole table in one place so the action and its route cannot drift
    /// apart. Cells:
    ///
    /// `←`/`→` — none `∓5 s` broadcast; `⇧` `∓10 s` broadcast; `⌥` one frame
    /// local; `⇧⌥` `∓10 s` local; `⌘` previous/next file; `⌃` and `⌃⌘` keep
    /// the plain broadcast seek (the control branch only owned Up/Down).
    ///
    /// `↑`/`↓` — none volume ±5 local (IINA's volume keys); `⇧` ∓10 frames
    /// broadcast (AMP's own jump); `⌥` volume ±1 local; `⇧⌥` ∓10 frames local,
    /// because Shift owns the frame jump and its Option variant stays in this
    /// window; `⌘` start/end broadcast, `⌘⌥` start/end local as before; `⌃`
    /// volume ±5 local, and `⌃⌘` stays there because the control branch wins.
    static func arrowDecision(
        key: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags
    ) -> PlayerArrowDecision? {
        let shift = modifiers.contains(.shift)
        let option = modifiers.contains(.option)
        let command = modifiers.contains(.command)
        let control = modifiers.contains(.control)

        switch key {
        case .leftArrow, .rightArrow:
            let forward = key == .rightArrow
            // IINA's playlist chords. Option keeps the old local ±10 s seek.
            if command, !control {
                return option
                    ? PlayerArrowDecision(action: .seekBy(forward ? 10 : -10), route: .local)
                    : PlayerArrowDecision(action: forward ? .nextFile : .previousFile, route: .broadcast)
            }
            if option {
                return shift
                    ? PlayerArrowDecision(action: .seekBy(forward ? 10 : -10), route: .local)
                    : PlayerArrowDecision(action: .stepFrames(forward ? 1 : -1), route: .local)
            }
            let seconds: Double = shift ? 10 : 5
            return PlayerArrowDecision(
                action: .seekBy(forward ? seconds : -seconds),
                route: .broadcast
            )
        case .upArrow, .downArrow:
            let up = key == .upArrow
            if control {
                return PlayerArrowDecision(action: .adjustVolume(up ? 5 : -5), route: .local)
            }
            if command {
                let action: PlayerArrowAction = up ? .seekToStart : .seekToEnd
                return PlayerArrowDecision(action: action, route: option ? .local : .broadcast)
            }
            // Shift owns the frame jump, and the Option variant of that jump
            // is the local one; only a bare Option means fine volume.
            if shift {
                return PlayerArrowDecision(
                    action: .stepFrames(up ? -10 : 10),
                    route: option ? .local : .broadcast
                )
            }
            if option {
                return PlayerArrowDecision(action: .adjustVolume(up ? 1 : -1), route: .local)
            }
            return PlayerArrowDecision(action: .adjustVolume(up ? 5 : -5), route: .local)
        default:
            return nil
        }
    }
}

/// What an arrow key asks the player window to do.
nonisolated enum PlayerArrowAction: Equatable {
    case seekBy(Double)
    case stepFrames(Int)
    case seekToStart
    case seekToEnd
    case adjustVolume(Int)
    case previousFile
    case nextFile
}

/// Where an arrow key's action applies: this window only, or every window
/// through the transport notification.
nonisolated enum PlayerArrowRoute: Equatable {
    case local
    case broadcast
}

/// One arrow cell: the action plus the route it takes.
nonisolated struct PlayerArrowDecision: Equatable {
    let action: PlayerArrowAction
    let route: PlayerArrowRoute
}
