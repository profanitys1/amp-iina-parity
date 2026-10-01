// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(AppSettings.allowMultipleWindows.key)
    private var allowMultipleWindows = AppSettings.allowMultipleWindows.defaultValue
    @AppStorage(AppSettings.syncPlaybackControls.key)
    private var syncPlaybackControls = AppSettings.syncPlaybackControls.defaultValue
    @AppStorage(AppSettings.precisionScrubFactor.key)
    private var precisionScrubFactor = AppSettings.precisionScrubFactor.defaultValue
    @AppStorage(AppSettings.showTimelineDetails.key)
    private var showTimelineDetails = AppSettings.showTimelineDetails.defaultValue
    @AppStorage(AppSettings.openAtSourceResolution.key)
    private var openAtSourceResolution = AppSettings.openAtSourceResolution.defaultValue
    @AppStorage(AppSettings.clampWindowToScreen.key)
    private var clampWindowToScreen = AppSettings.clampWindowToScreen.defaultValue
    @AppStorage(AppSettings.centerWindowAfterResize.key)
    private var centerWindowAfterResize = AppSettings.centerWindowAfterResize.defaultValue

    var body: some View {
        Form {
            Section("Windows") {
                Toggle("Allow Multiple Windows", isOn: $allowMultipleWindows)
                if allowMultipleWindows {
                    Toggle("Sync Transport Commands Across Windows", isOn: $syncPlaybackControls)
                    Text("Shares playback and navigation commands. Windows keep independent playback clocks and are not continuously frame-locked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Playback > Align Windows to Current Timecode Once seeks other windows once, using source timecode when both files have it, otherwise relative time. This works independently of transport sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("For two-file inspection, open a comparison file in Compare Mode to use a shared timeline and explicit alignment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Open Windows at Source Resolution", isOn: $openAtSourceResolution)
                if openAtSourceResolution {
                    Toggle("Limit Window Size to Screen", isOn: $clampWindowToScreen)
                    Toggle("Center Window on Screen", isOn: $centerWindowAfterResize)
                }
            }

            Section("Playback") {
                Toggle("Show Timeline Details", isOn: $showTimelineDetails)
                Text("Show chapters, review markers, and comparison overlap. Turn off for a minimal timeline; trim points remain visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Precision Scrub") {
                    HStack(spacing: 8) {
                        Slider(value: $precisionScrubFactor, in: 2...20, step: 1)
                        Text("\(Int(precisionScrubFactor))x slower")
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
