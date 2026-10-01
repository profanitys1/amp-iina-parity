// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class KeyBindingDefaultsTests: XCTestCase {
    private func action(_ chord: String) -> KeyBindingAction? {
        guard let chord = KeyChord(string: chord) else { return nil }
        return KeyBindingDefaults.table[chord]
    }

    /// Every binding the compiled map had must still be a default.
    func testTransportDefaults() {
        XCTAssertEqual(action("p"), .togglePlayback)
        XCTAssertEqual(action("k"), .togglePlayback)
        XCTAssertEqual(action("space"), .togglePlayback)
        XCTAssertEqual(action("f"), .toggleFullscreen)
        XCTAssertEqual(action("j"), .reverse)
        XCTAssertEqual(action("l"), .fastForward)
        XCTAssertEqual(action("alt+j"), .slowReverse)
        XCTAssertEqual(action("alt+l"), .slowForward)
    }

    func testRateAndFrameDefaults() {
        XCTAssertEqual(action("["), .stepRateBackward)
        XCTAssertEqual(action("]"), .stepRateForward)
        XCTAssertEqual(action("."), .stepFrameForward)
        XCTAssertEqual(action(","), .stepFrameBackward)
    }

    func testTrimDefaults() {
        XCTAssertEqual(action("i"), .setTrimIn)
        XCTAssertEqual(action("alt+i"), .clearTrimIn)
        XCTAssertEqual(action("shift+i"), .jumpToTrimIn)
        XCTAssertEqual(action("o"), .setTrimOut)
        XCTAssertEqual(action("alt+o"), .clearTrimOut)
        XCTAssertEqual(action("shift+o"), .jumpToTrimOut)
        XCTAssertEqual(action("alt+x"), .clearAllTrim)
    }

    func testCompareDefault() {
        XCTAssertEqual(action("b"), .toggleCompareSource)
    }

    /// Command and control are the menu's territory; the monitor must not claim them.
    func testCommandAndControlAreNotBound() {
        XCTAssertNil(action("cmd+i"))
        XCTAssertNil(action("ctrl+i"))
        XCTAssertNil(action("cmd+p"))
    }

    /// Every action must be reachable, or it cannot be triggered at all.
    func testEveryActionHasADefault() {
        let bound = Set(KeyBindingDefaults.table.values)
        for action in KeyBindingAction.allCases {
            XCTAssertTrue(bound.contains(action), "\(action.rawValue) has no default chord")
        }
    }
}
