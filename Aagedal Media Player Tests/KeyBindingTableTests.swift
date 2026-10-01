// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

final class KeyBindingTableTests: XCTestCase {
    private func chord(_ string: String) -> KeyChord { KeyChord(string: string)! }

    /// No file means no opinion: the compiled handler keeps every key.
    func testNoOverridesHasNoOpinion() {
        XCTAssertNil(KeyBindingTable(overrides: [:]).override(for: chord("p")))
    }

    func testOverrideBindsAnAction() {
        let table = KeyBindingTable(overrides: ["x": "togglePlayback"])
        XCTAssertEqual(table.override(for: chord("x")), .bound(.togglePlayback))
        XCTAssertNil(table.override(for: chord("p")))
    }

    /// Mapping a chord to nothing is how a default is removed.
    func testEmptyActionUnbinds() {
        let table = KeyBindingTable(overrides: ["p": ""])
        XCTAssertEqual(table.override(for: chord("p")), .unbound)
    }

    /// A typo must not take a working binding down with it.
    func testUnknownActionNameIsIgnored() {
        let table = KeyBindingTable(overrides: ["p": "teleport"])
        XCTAssertNil(table.override(for: chord("p")))
    }

    func testMalformedChordIsIgnored() {
        let table = KeyBindingTable(overrides: ["hyper+q": "reverse"])
        XCTAssertNil(table.override(for: chord("q")))
    }

    func testOverrideOnAModifiedChord() {
        let table = KeyBindingTable(overrides: ["shift+cmd+k": "clearAllTrim"])
        XCTAssertEqual(table.override(for: chord("cmd+shift+k")), .bound(.clearAllTrim))
    }

    func testDecodesTheFileFormat() throws {
        let data = Data(#"{ "x": "togglePlayback", "p": "" }"#.utf8)
        let table = try KeyBindingTable(fileData: data)
        XCTAssertEqual(table.override(for: chord("x")), .bound(.togglePlayback))
        XCTAssertEqual(table.override(for: chord("p")), .unbound)
    }

    // MARK: - Lookup

    private func lookup(_ table: KeyBindingTable, _ characters: String,
                        _ modifiers: NSEvent.ModifierFlags = [],
                        special: NSEvent.SpecialKey? = nil, wipe: Bool = false) -> KeyBindingTable.Override? {
        PlayerKeyMap.userOverride(characters: characters, specialKey: special,
                                  modifiers: modifiers, isWipeMode: wipe, table: table)
    }

    /// What the key monitor reports, not what the file spells, must match.
    func testLookupMatchesWhatTheMonitorReports() {
        let table = KeyBindingTable(overrides: ["shift+i": "clearAllTrim", "space": "", "left": "reverse"])
        XCTAssertEqual(lookup(table, "I", [.shift, .capsLock]), .bound(.clearAllTrim))
        XCTAssertEqual(lookup(table, " "), .unbound)
        XCTAssertEqual(lookup(table, "\u{F702}", special: .leftArrow), .bound(.reverse))
        XCTAssertNil(lookup(table, "i"))
    }

    /// The wipe owns the brackets while it shows, whatever the file says.
    func testWipeKeepsTheBrackets() {
        let table = KeyBindingTable(overrides: ["[": "togglePlayback"])
        XCTAssertNil(lookup(table, "[", wipe: true))
        XCTAssertEqual(lookup(table, "["), .bound(.togglePlayback))
    }
}
