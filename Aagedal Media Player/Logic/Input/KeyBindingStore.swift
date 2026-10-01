// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Reads keybindings.json from Application Support. The file is absent on a
// fresh install, in which case the compiled defaults stand.

import Foundation
import OSLog

@MainActor
final class KeyBindingStore {
    static let shared = KeyBindingStore()

    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "keybindings")
    private(set) var table: KeyBindingTable = .empty

    var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Aagedal Media Player", isDirectory: true)
            .appendingPathComponent("keybindings.json")
    }

    private init() { reload() }

    func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            table = .empty
            return
        }
        do {
            table = try KeyBindingTable(fileData: data)
            logger.info("Loaded key binding overrides from \(self.fileURL.path, privacy: .public)")
        } catch {
            logger.error("keybindings.json could not be read, using defaults: \(error.localizedDescription, privacy: .public)")
            table = .empty
        }
    }

    /// Writes a file listing every default, ready to edit, if none exists yet.
    func writeDefaultFileIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var contents: [String: String] = [:]
        for (chord, action) in KeyBindingDefaults.table {
            contents[chord.stringValue] = action.rawValue
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(contents).write(to: fileURL, options: .atomic)
    }
}
