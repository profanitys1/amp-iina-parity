// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// The user's overrides, and nothing else. A chord the file does not mention
// falls through to the compiled key handler, so every key that works today —
// including the looser Shift variants — keeps working without a file. A
// malformed chord or an unknown action name is skipped rather than fatal: a
// typo in a config file must not take working bindings down with it.

import Foundation
import OSLog

nonisolated struct KeyBindingTable {
    enum Override: Equatable {
        case bound(KeyBindingAction)
        /// The file maps this chord to "": the key does nothing.
        case unbound
    }

    private let overrides: [KeyChord: Override]

    static let empty = KeyBindingTable(overrides: [:])

    /// - Parameter overrides: chord string to action name; "" unbinds.
    init(overrides: [String: String]) {
        let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "keybindings")
        var parsed: [KeyChord: Override] = [:]
        for (chordString, actionName) in overrides {
            guard let chord = KeyChord(string: chordString) else {
                logger.warning("Ignoring unparseable key chord: \(chordString, privacy: .public)")
                continue
            }
            if actionName.isEmpty {
                parsed[chord] = .unbound
            } else if let action = KeyBindingAction(rawValue: actionName) {
                parsed[chord] = .bound(action)
            } else {
                logger.warning("Ignoring unknown action: \(actionName, privacy: .public)")
            }
        }
        self.overrides = parsed
    }

    init(fileData: Data) throws {
        self.init(overrides: try JSONDecoder().decode([String: String].self, from: fileData))
    }

    /// `nil` when the file says nothing about this chord.
    func override(for chord: KeyChord) -> Override? { overrides[chord] }
}
