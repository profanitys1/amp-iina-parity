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

    /// A nil optional is the shape a missing bundled resource arrives in.
    func testMissingOptionalSkips() {
        XCTAssertThrowsError(try OptionalInput.require(path: nil, what: "the bundled ffmpeg")) { error in
            XCTAssertTrue(error is XCTSkip, "Expected XCTSkip, got \(type(of: error))")
        }
    }

    func testPresentOptionalIsReturned() throws {
        XCTAssertEqual(try OptionalInput.require(path: "/bin/ls", what: "a binary"), "/bin/ls")
    }

    /// An empty path is as useless as a nil one, and `Bundle.path(forResource:)`
    /// is not guaranteed to answer with nil rather than an empty string.
    func testEmptyOptionalPathSkips() {
        XCTAssertThrowsError(try OptionalInput.require(path: "", what: "the bundled ffmpeg")) { error in
            XCTAssertTrue(error is XCTSkip, "Expected XCTSkip, got \(type(of: error))")
        }
    }
}
