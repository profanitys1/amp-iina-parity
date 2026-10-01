// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ScopeSettingsView: View {
    @AppStorage(AppSettings.scopeDisplayMode.key)
    private var displayMode = AppSettings.scopeDisplayMode.defaultValue
    @AppStorage(AppSettings.scopeBackground.key)
    private var background = AppSettings.scopeBackground.defaultValue
    @AppStorage(AppSettings.scopeResolution.key)
    private var resolution = AppSettings.scopeResolution.defaultValue
    @AppStorage(AppSettings.scopeFrameRate.key)
    private var frameRate = AppSettings.scopeFrameRate.defaultValue

    var body: some View {
        Form {
            Section("Display") {
                LabeledContent("Display Mode") {
                    Picker("", selection: $displayMode) {
                        ForEach(ScopeDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                Text("Overlay renders scopes over the video. Separate window opens a floating panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if displayMode == ScopeDisplayMode.overlay.rawValue {
                    LabeledContent("Background") {
                        Picker("", selection: $background) {
                            ForEach(ScopeBackground.allCases, id: \.self) { bg in
                                Text(bg.label).tag(bg.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Transparent lets the video show through the scopes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Rendering") {
                LabeledContent("Resolution") {
                    Picker("", selection: $resolution) {
                        ForEach(ScopeResolution.allCases, id: \.self) { r in
                            Text(r.label).tag(r.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                Text("Higher resolution shows more detail but uses more CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Performance") {
                LabeledContent("Update Rate") {
                    HStack(spacing: 8) {
                        Slider(value: $frameRate, in: 5...30, step: 1)
                        Text("\(Int(frameRate)) fps")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                Text("How often scopes refresh. Lower values reduce CPU usage. Changes apply when scopes are reopened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
