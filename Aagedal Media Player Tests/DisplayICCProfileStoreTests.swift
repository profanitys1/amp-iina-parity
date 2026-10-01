// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class DisplayICCProfileStoreTests: XCTestCase {
    private var store: DisplayICCProfileStore!

    override func setUp() {
        super.setUp()
        store = DisplayICCProfileStore(
            directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.directory)
        store = nil
        super.tearDown()
    }

    func testWritesProfileAndReturnsReadableURL() throws {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        let url = try store.url(for: data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    /// The same profile must not be rewritten — this runs on every screen change.
    func testSameProfileReusesTheSameFile() throws {
        let data = Data([0x0A, 0x0B])
        let first = try store.url(for: data)
        let second = try store.url(for: data)
        XCTAssertEqual(first, second)
    }

    func testDifferentProfilesGetDifferentFiles() throws {
        let first = try store.url(for: Data([0x01]))
        let second = try store.url(for: Data([0x02]))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), Data([0x01]))
        XCTAssertEqual(try Data(contentsOf: second), Data([0x02]))
    }
}
