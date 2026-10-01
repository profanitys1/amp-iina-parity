// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct KeyboardShortcutsView: View {
    @AppStorage(AppSettings.precisionScrubFactor.key)
    private var precisionScrubFactor = AppSettings.precisionScrubFactor.defaultValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                shortcutSection("Playback", shortcuts: [
                    ("Space / P", "Play / Pause"),
                    ("K", "Pause"),
                    ("J", "Reverse (press again to increase speed)"),
                    ("L", "Fast Forward (press again to increase speed)"),
                    ("M", "Mute / Unmute"),
                    ("F / \u{2303}\u{2318}F", "Toggle fullscreen"),
                    ("[ / ]", "Playback rate down / up by 0.5 (outside Compare wipe mode)"),
                ])

                shortcutSection("Navigation", shortcuts: [
                    ("\u{2190} / \u{2192}", "Seek back / forward 5 seconds"),
                    ("\u{21E7}\u{2190} / \u{21E7}\u{2192}", "Seek back / forward 10 seconds"),
                    ("\u{2325}\u{2190} / \u{2325}\u{2192}", "Step back / forward one frame"),
                    (". / ,", "Step one frame forward / back"),
                    ("\u{2191} / \u{2193}", "Volume up / down 5"),
                    ("\u{2325}\u{2191} / \u{2325}\u{2193}", "Volume up / down 1"),
                    ("\u{21E7}\u{2191} / \u{21E7}\u{2193}", "Jump back / forward 10 frames"),
                    ("\u{2318}\u{2191} / \u{2318}\u{2193}", "Jump to start / end"),
                    ("\u{2318}[ / \u{2318}]", "Previous / next file in folder"),
                    ("\u{2318}\u{2190} / \u{2318}\u{2192}", "Previous / next file in folder"),
                    ("\u{2325}Drag", "Precision scrub (\(Int(precisionScrubFactor))x slower)"),
                ])

                shortcutSection("Trim", shortcuts: [
                    ("I", "Set trim in"),
                    ("O", "Set trim out"),
                    ("\u{21E7}I", "Jump to trim in"),
                    ("\u{21E7}O", "Jump to trim out"),
                    ("\u{2325}I", "Clear trim in"),
                    ("\u{2325}O", "Clear trim out"),
                    ("\u{2325}X", "Clear all trim points"),
                    ("\u{2318}E", "Export trim"),
                ])

                shortcutSection("Compare Mode", shortcuts: [
                    ("B", "Toggle source A / B"),
                    ("[ / ]", "Move wipe 2% (while the wipe is showing)"),
                    ("\u{21E7}[ / ]", "Move wipe 10% (while the wipe is showing)"),
                ])

                shortcutSection("General", shortcuts: [
                    ("\u{2318}N", "New window (multi-window mode)"),
                    ("\u{21E7}\u{2318}S", "Align windows to current timecode once"),
                    ("\u{2318}W", "Close window"),
                    ("\u{2318}S", "Screenshot"),
                    ("T", "Cycle timecode display"),
                    ("\u{2318}I", "Toggle inspector"),
                    ("\u{2318}O", "Open file"),
                    ("\u{21E7}\u{2318}O", "Open subtitle file"),
                    ("\u{21E7}\u{2318}D", "Open comparison file"),
                    ("\u{21E7}\u{2318}L", "Inspection loupe"),
                    ("\u{21E7}\u{2318}N", "Comparison review notes"),
                    ("\u{21E7}\u{2318}W", "Toggle video scopes"),
                    ("\u{21E7}\u{2318}A", "Audio waveform"),
                    ("\u{21E7}\u{2318}R", "Reload player"),
                    ("\u{2318},", "Settings"),
                ])
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func shortcutSection(_ title: String, shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)

            ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, shortcut in
                HStack {
                    Text(shortcut.0)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 80, alignment: .trailing)

                    Text(shortcut.1)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
