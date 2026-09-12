// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class OneShotFlagTests: XCTestCase {
    func testFirstClaimWins() {
        let flag = OneShotFlag()
        XCTAssertTrue(flag.claim())
        XCTAssertFalse(flag.claim())
    }

    func testResetAllowsOneMoreClaim() {
        let flag = OneShotFlag()
        XCTAssertTrue(flag.claim())
        flag.reset()
        XCTAssertTrue(flag.claim())
        XCTAssertFalse(flag.claim())
    }

    /// Exactly one claimant must win, however hard the callers race.
    func testExactlyOneConcurrentClaimWins() async {
        for _ in 0..<50 {
            let flag = OneShotFlag()
            let winners = await withTaskGroup(of: Bool.self) { group -> Int in
                for _ in 0..<64 {
                    group.addTask { flag.claim() }
                }
                var count = 0
                for await won in group where won { count += 1 }
                return count
            }
            XCTAssertEqual(winners, 1, "a race let more than one claim through")
        }
    }
}
