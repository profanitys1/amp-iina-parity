// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

/// Guards against a setting being added with no way to change it. Twenty keys
/// had drifted into that state before this existed.
final class SettingsCoverageTests: XCTestCase {
    /// Runtime state and one-shot flags, which are deliberately not preferences.
    private let notUserFacing: Set<String> = [
        "playbackVolume",
        "playbackMuted",
        "controlBarPositionHorizontal",
        "controlBarPositionVertical",
        "didShowCompareModeCallout",
        "didShowAutoUpdateNotice",
        "updateLastChecked",
        "updateCheckInterval",
        "settingsVersion",
        // The screen fill is the shipped open behaviour rather than a
        // preference; the key exists so tests can stop the configurator
        // resizing their capture host.
        "openMaximized",
    ]

    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    func testEveryUserFacingSettingHasAControl() throws {
        let ui = repository.appendingPathComponent("Aagedal Media Player/UI")
        let sources = try FileManager.default
            .subpathsOfDirectory(atPath: ui.path)
            .filter { $0.hasSuffix(".swift") }
            .map { try String(contentsOf: ui.appendingPathComponent($0), encoding: .utf8) }
            .joined()

        let missing = AppSettings.allKeys
            .filter { !notUserFacing.contains($0) && !sources.contains("AppSettings.\($0)") }
        XCTAssertTrue(missing.isEmpty,
                      "Settings with no control anywhere in UI/: \(missing.sorted().joined(separator: ", "))")
    }

    /// `allKeys` is built from the registration dictionary. A setting declared
    /// but never registered would otherwise slip past the coverage check.
    func testEveryDeclaredSettingIsListed() throws {
        let source = try String(
            contentsOf: repository.appendingPathComponent("Aagedal Media Player/Logic/AppSettings.swift"),
            encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"AppSetting(?:<[^>]+>)?\(key: "(\w+)""#)
        let declared = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            .compactMap { Range($0.range(at: 1), in: source).map { String(source[$0]) } }
        XCTAssertFalse(declared.isEmpty)
        let unlisted = Set(declared).subtracting(AppSettings.allKeys)
        XCTAssertTrue(unlisted.isEmpty, "Declared but not in allKeys: \(unlisted.sorted().joined(separator: ", "))")
    }
}
