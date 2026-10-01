// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// One key plus its modifiers, in a form that survives a round trip through a
// configuration file. Modifier order is canonical on the way out so two
// spellings of the same chord compare equal.

import AppKit

nonisolated struct KeyChord: Hashable, Codable {
    struct Modifiers: OptionSet, Hashable, Codable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let control = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    let key: String
    let modifiers: Modifiers

    private static let modifierNames: [(String, Modifiers)] = [
        ("shift", .shift), ("ctrl", .control), ("alt", .option), ("cmd", .command),
    ]

    /// A switch, not a dictionary: `NSEvent.SpecialKey` is not Sendable.
    private static func name(of specialKey: NSEvent.SpecialKey) -> String? {
        switch specialKey {
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .upArrow: "up"
        case .downArrow: "down"
        default: nil
        }
    }

    init(key: String, modifiers: Modifiers) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    init?(string: String) {
        var parts = string.lowercased().split(separator: "+", omittingEmptySubsequences: false)
                          .map(String.init)
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        var modifiers: Modifiers = []
        for part in parts {
            guard let match = Self.modifierNames.first(where: { $0.0 == part }) else { return nil }
            modifiers.insert(match.1)
        }
        self.key = last
        self.modifiers = modifiers
    }

    var stringValue: String {
        let names = Self.modifierNames.filter { modifiers.contains($0.1) }.map(\.0)
        return (names + [key]).joined(separator: "+")
    }

    /// Builds a chord from what a key monitor actually reports. Flags beyond the
    /// four that matter — caps lock, function, numeric pad — are discarded, or a
    /// binding would stop matching on a keyboard that sets them.
    static func from(
        characters: String,
        specialKey: NSEvent.SpecialKey?,
        flags: NSEvent.ModifierFlags
    ) -> KeyChord? {
        var modifiers: Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }

        if let specialKey, let name = name(of: specialKey) {
            return KeyChord(key: name, modifiers: modifiers)
        }
        let trimmed = characters.lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed == " " { return KeyChord(key: "space", modifiers: modifiers) }
        return KeyChord(key: trimmed, modifiers: modifiers)
    }
}
