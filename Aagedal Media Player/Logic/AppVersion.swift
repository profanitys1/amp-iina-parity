// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Pure helpers for normalizing and comparing release version strings.
/// Kept separate from UpdateChecker so version behavior can be tested without
/// constructing update services or making network requests.
enum AppVersion {
    nonisolated static func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        normalized(candidate).compare(normalized(current), options: .numeric) == .orderedDescending
    }
}

/// Bundle identity for anything that displays the app to the user.
///
/// IINA shows `version (build N)` for prereleases and a bare version for
/// releases, with a coloured channel badge on anything that is not a release
/// (`InitialWindowController.swift:120-133`). Channel is inferred from the
/// version string, since the app ships no separate build-type marker.
nonisolated enum AppIdentity {
    static var name: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Aagedal Media Player"
    }

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// "beta", "alpha", "rc"… when the version carries a prerelease suffix.
    static func prereleaseChannel(for version: String) -> String? {
        let normalized = AppVersion.normalized(version).lowercased()
        guard let separator = normalized.firstIndex(where: { $0 == "-" || $0 == "+" }) else {
            return nil
        }
        let suffix = normalized[normalized.index(after: separator)...]
        let channel = suffix.prefix { $0.isLetter }
        return channel.isEmpty ? "beta" : String(channel)
    }

    static var prereleaseChannel: String? { prereleaseChannel(for: shortVersion) }

    static var versionDescription: String {
        prereleaseChannel == nil ? shortVersion : "\(shortVersion) (build \(build))"
    }
}
