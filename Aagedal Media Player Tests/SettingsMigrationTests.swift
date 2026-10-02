// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class SettingsMigrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsMigrationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// A fresh install is stamped with the current version and nothing is moved.
    func testFreshInstallIsStampedCurrent() {
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"),
                       SettingsMigration.currentVersion)
    }

    func testRenameMovesAValue() {
        defaults.set(42, forKey: "oldKey")
        SettingsMigration.rename(from: "oldKey", to: "newKey", in: defaults)
        XCTAssertEqual(defaults.integer(forKey: "newKey"), 42)
        XCTAssertNil(defaults.object(forKey: "oldKey"))
    }

    /// A value the user already set under the new name wins over the old one.
    func testRenameDoesNotClobberAnExistingValue() {
        defaults.set(1, forKey: "oldKey")
        defaults.set(2, forKey: "newKey")
        SettingsMigration.rename(from: "oldKey", to: "newKey", in: defaults)
        XCTAssertEqual(defaults.integer(forKey: "newKey"), 2)
        XCTAssertNil(defaults.object(forKey: "oldKey"))
    }

    func testRenameOfAbsentKeyIsHarmless() {
        SettingsMigration.rename(from: "missing", to: "target", in: defaults)
        XCTAssertNil(defaults.object(forKey: "target"))
    }

    /// Running twice must not repeat work.
    func testMigrationIsIdempotent() {
        SettingsMigration.migrate(defaults)
        let stamped = defaults.integer(forKey: "settingsVersion")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"), stamped)
    }

    /// A profile from a newer build must not be downgraded.
    func testFutureVersionIsLeftAlone() {
        defaults.set(SettingsMigration.currentVersion + 5, forKey: "settingsVersion")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"),
                       SettingsMigration.currentVersion + 5)
    }

    /// What this suite itself stores. `object(forKey:)` would also return a default the app
    /// registered for the key, which says nothing about whether the migration removed it.
    private func storedValue(_ key: String) -> Any? {
        defaults.persistentDomain(forName: suiteName)?[key]
    }

    func testEnhanceWithFaithfulBecomesAutomaticAndTheKeyIsRemoved() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(true, forKey: "enhance")
        defaults.set("off", forKey: "renderProfile")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "automatic")
        XCTAssertNil(storedValue("enhance"))
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"), SettingsMigration.currentVersion)
    }

    func testEnhanceWithNoStoredProfileEndsUpAutomatic() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(true, forKey: "enhance")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "automatic")
        XCTAssertNil(storedValue("enhance"))
    }

    func testEnhanceKeepsAManuallyChosenProfile() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(true, forKey: "enhance")
        defaults.set("compressed", forKey: "renderProfile")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "compressed")
        XCTAssertNil(storedValue("enhance"))
    }

    func testEnhanceOffLeavesFaithfulAndRemovesTheKey() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(false, forKey: "enhance")
        defaults.set("off", forKey: "renderProfile")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "off")
        XCTAssertNil(storedValue("enhance"))
    }
}
