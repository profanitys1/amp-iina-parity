// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Moves stored preferences forward across upgrades. This exists before any key
// is renamed on purpose: without it, renaming a key silently resets whatever
// the user had chosen, and there is no way to notice after the fact.
//
// To add a migration: raise currentVersion by one, and add a case to the switch
// for the version being migrated FROM.

import Foundation
import OSLog

nonisolated enum SettingsMigration {
    static let versionKey = "settingsVersion"

    /// Raise by one whenever a step is added below.
    static let currentVersion = 1

    private static let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "settings")

    static func migrate(_ defaults: UserDefaults = .standard) {
        let stored = defaults.integer(forKey: versionKey)

        // A profile written by a newer build: leave it alone rather than
        // rewriting keys this build does not understand.
        guard stored < currentVersion else { return }

        // A first run has nothing to move; stamping it means later upgrades
        // know where they started from.
        guard stored > 0 else {
            defaults.set(currentVersion, forKey: versionKey)
            return
        }

        for version in stored..<currentVersion {
            apply(version: version, in: defaults)
        }
        defaults.set(currentVersion, forKey: versionKey)
        logger.info("Migrated preferences from version \(stored, privacy: .public) to \(currentVersion, privacy: .public)")
    }

    /// One step, migrating away from `version`.
    private static func apply(version: Int, in defaults: UserDefaults) {
        switch version {
        default:
            break
        }
    }

    /// Moves a value to a new key, keeping whatever is already there.
    static func rename(from old: String, to new: String, in defaults: UserDefaults = .standard) {
        guard let value = defaults.object(forKey: old) else { return }
        if defaults.object(forKey: new) == nil {
            defaults.set(value, forKey: new)
        }
        defaults.removeObject(forKey: old)
    }
}
