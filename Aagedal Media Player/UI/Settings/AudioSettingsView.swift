// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AudioSettingsView: View {
    @AppStorage(AppSettings.audioWaveformDisplayMode.key)
    private var displayMode = AppSettings.audioWaveformDisplayMode.defaultValue
    @AppStorage(AppSettings.audioWaveformBackground.key)
    private var background = AppSettings.audioWaveformBackground.defaultValue
    @AppStorage(AppSettings.audioWaveformColor.key)
    private var waveformColor = AppSettings.audioWaveformColor.defaultValue
    @AppStorage(AppSettings.showAllMonoWaveforms.key)
    private var showAllMonoWaveforms = AppSettings.showAllMonoWaveforms.defaultValue
    @AppStorage(AppSettings.audioWaveformBoost.key)
    private var waveformBoost = AppSettings.audioWaveformBoost.defaultValue
    @AppStorage(AppSettings.automaticAudioOnlyWaveform.key)
    private var automaticAudioOnlyWaveform = AppSettings.automaticAudioOnlyWaveform.defaultValue

    var body: some View {
        Form {
            Section("Audio Waveform") {
                Toggle("Show automatically for audio-only files", isOn: $automaticAudioOnlyWaveform)
                Text("Audio-only files use the waveform as their main playback surface. Turn this off for a simpler title-only presentation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Display Mode") {
                    Picker("", selection: $displayMode) {
                        ForEach(AudioWaveformDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                }
                Text("Overlay renders the waveform over the video. Separate window opens a floating panel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if displayMode == AudioWaveformDisplayMode.overlay.rawValue {
                    LabeledContent("Background") {
                        Picker("", selection: $background) {
                            ForEach(AudioWaveformBackground.allCases, id: \.self) { bg in
                                Text(bg.label).tag(bg.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Transparent lets the video show through the waveform.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Color") {
                    Picker("", selection: $waveformColor) {
                        ForEach(AudioWaveformColor.allCases, id: \.self) { c in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(c.swiftUIColor)
                                    .frame(width: 10, height: 10)
                                Text(c.label)
                            }
                            .tag(c.rawValue)
                        }
                    }
                    .labelsHidden()
                }

                LabeledContent("Boost") {
                    HStack(spacing: 8) {
                        Slider(value: $waveformBoost, in: 0...100, step: 1)
                        Text("\(Int(waveformBoost))")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                }
                Text("Amplifies quiet parts of the waveform while keeping peaks unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show all waveforms for multi-mono files", isOn: $showAllMonoWaveforms)
                Text("When enabled, files containing only mono tracks show all track waveforms at once instead of just the selected track.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
