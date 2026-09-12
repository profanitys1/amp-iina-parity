// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class AppIdentityTests: XCTestCase {
    func testReleaseVersionHasNoChannel() {
        XCTAssertNil(AppIdentity.prereleaseChannel(for: "1.6.1"))
    }

    func testBetaSuffixIsRecognised() {
        XCTAssertEqual(AppIdentity.prereleaseChannel(for: "1.5.0-beta1"), "beta")
    }

    func testBuildMetadataSuffixIsRecognised() {
        XCTAssertEqual(AppIdentity.prereleaseChannel(for: "1.5.0+g1a2b3c"), "g")
    }

    func testLeadingVeeIsIgnored() {
        XCTAssertNil(AppIdentity.prereleaseChannel(for: "v2.0.0"))
    }
}
