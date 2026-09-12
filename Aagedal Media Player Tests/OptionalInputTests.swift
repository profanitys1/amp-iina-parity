// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Aagedal_Media_Player

final class OptionalInputTests: XCTestCase {
    private let variableName = "AAGEDAL_OPTIONAL_INPUT_TEST"

    override func tearDown() {
        unsetenv(variableName)
        super.tearDown()
    }

    /// A missing variable must skip, not return an empty string the caller
    /// would then hand to file APIs.
    func testMissingVariableSkips() {
        unsetenv(variableName)
        XCTAssertThrowsError(try OptionalInput.require(variableName)) { error in
            XCTAssertTrue(error is XCTSkip, "Expected XCTSkip, got \(type(of: error))")
        }
    }

    /// An empty value is as useless as a missing one.
    func testEmptyVariableSkips() {
        setenv(variableName, "", 1)
        XCTAssertThrowsError(try OptionalInput.require(variableName)) { error in
            XCTAssertTrue(error is XCTSkip, "Expected XCTSkip, got \(type(of: error))")
        }
    }

    func testPresentVariableIsReturned() throws {
        setenv(variableName, "/tmp/example", 1)
        XCTAssertEqual(try OptionalInput.require(variableName), "/tmp/example")
    }
}
