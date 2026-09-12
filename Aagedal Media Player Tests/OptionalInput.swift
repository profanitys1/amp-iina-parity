// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest

/// Reads an environment variable that some suites cannot run without.
///
/// Returning early instead would report the suite as passed while it asserted
/// nothing, which is how a green run can overstate what was covered. Skipping
/// keeps that distinction visible in the test report.
nonisolated enum OptionalInput {
    static func require(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("Set \(name) to run this suite.")
        }
        return value
    }

    /// Reads a resource whose absence is an environment problem, not a defect.
    static func require(path: String?, what: String) throws -> String {
        guard let path, !path.isEmpty else {
            throw XCTSkip("\(what) is unavailable in this build.")
        }
        return path
    }
}
