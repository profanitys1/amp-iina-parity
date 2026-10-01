// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

final class KeyChordTests: XCTestCase {
    func testBareCharacterRoundTrips() throws {
        let chord = try XCTUnwrap(KeyChord(string: "f"))
        XCTAssertEqual(chord.key, "f")
        XCTAssertTrue(chord.modifiers.isEmpty)
        XCTAssertEqual(chord.stringValue, "f")
    }

    func testModifiersParseInAnyOrderAndRenderCanonically() throws {
        let a = try XCTUnwrap(KeyChord(string: "cmd+shift+o"))
        let b = try XCTUnwrap(KeyChord(string: "shift+cmd+o"))
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.stringValue, "shift+cmd+o")
    }

    func testNamedKeysParse() throws {
        XCTAssertEqual(try XCTUnwrap(KeyChord(string: "left")).key, "left")
        XCTAssertEqual(try XCTUnwrap(KeyChord(string: "space")).key, "space")
    }

    func testUppercaseInputIsNormalised() throws {
        XCTAssertEqual(try XCTUnwrap(KeyChord(string: "CMD+F")), try XCTUnwrap(KeyChord(string: "cmd+f")))
    }

    func testEmptyStringIsRejected() {
        XCTAssertNil(KeyChord(string: ""))
        XCTAssertNil(KeyChord(string: "cmd+"))
    }

    func testUnknownModifierIsRejected() {
        XCTAssertNil(KeyChord(string: "hyper+f"))
    }

    func testFromEventComponents() throws {
        let chord = try XCTUnwrap(KeyChord.from(characters: "F", specialKey: nil,
                                                flags: [.shift, .command]))
        XCTAssertEqual(chord.stringValue, "shift+cmd+f")
    }

    func testArrowFromSpecialKey() throws {
        let chord = try XCTUnwrap(KeyChord.from(characters: "", specialKey: .leftArrow, flags: []))
        XCTAssertEqual(chord.stringValue, "left")
    }

    /// Only the four modifiers that matter are recorded; caps lock and function
    /// must not make a chord fail to match.
    func testIrrelevantFlagsAreIgnored() throws {
        let chord = try XCTUnwrap(KeyChord.from(characters: "p", specialKey: nil,
                                                flags: [.capsLock, .function, .numericPad]))
        XCTAssertEqual(chord.stringValue, "p")
    }
}
