// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

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
}
