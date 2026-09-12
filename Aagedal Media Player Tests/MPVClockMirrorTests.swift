// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVClockMirrorTests: XCTestCase {
    func testStartsEmpty() {
        XCTAssertNil(MPVClockMirror().sample())
    }

    func testReturnsTheLastStoredValue() {
        let mirror = MPVClockMirror()
        mirror.store(1.5)
        mirror.store(2.25)
        XCTAssertEqual(mirror.sample(), 2.25)
    }

    /// Clearing must be observable, so a torn-down player cannot report the
    /// previous file's clock to a caller that has not re-loaded yet.
    func testStoringNilClears() {
        let mirror = MPVClockMirror()
        mirror.store(3.0)
        mirror.store(nil)
        XCTAssertNil(mirror.sample())
    }

    /// The event thread writes while the main actor reads. Run both hard and
    /// assert only that the reader never sees a partial value.
    func testConcurrentWritersAndReadersAgree() async {
        let mirror = MPVClockMirror()
        let values = (0..<1_000).map { TimeInterval($0) / 10 }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for value in values { mirror.store(value) }
            }
            group.addTask {
                for _ in 0..<1_000 {
                    if let sampled = mirror.sample() {
                        XCTAssertTrue(sampled >= 0 && sampled <= values.last!, "torn read: \(sampled)")
                    }
                }
            }
        }
        XCTAssertEqual(mirror.sample(), values.last)
    }
}
