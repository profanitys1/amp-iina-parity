// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ScreenshotSettingsView: View {
    @State private var screenshotFormat: ScreenshotFormat = .jxl
    @AppStorage(AppSettings.screenshotJXLQuality.key)
    private var jxlQuality = AppSettings.screenshotJXLQuality.defaultValue
    @AppStorage(AppSettings.screenshotJPEGQuality.key)
    private var jpegQuality = AppSettings.screenshotJPEGQuality.defaultValue

    @State private var screenshotMode: SaveLocationMode = .custom

    var body: some View {
        Form {
            Section("Format") {
                LabeledContent("Format") {
                    Picker("", selection: $screenshotFormat) {
                        ForEach(ScreenshotFormat.allCases, id: \.self) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: screenshotFormat) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, for: AppSettings.screenshotFormat)
                    }
                }

                switch screenshotFormat {
                case .jxl:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $jxlQuality, in: 0...100, step: 1)
                            Text("\(Int(jxlQuality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                case .jpeg:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $jpegQuality, in: 0...100, step: 1)
                            Text("\(Int(jpegQuality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                case .png:
                    Text("PNG is always lossless.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LocationSettingsSection(
                mode: $screenshotMode,
                modeSetting: AppSettings.screenshotLocationMode,
                bookmarkSetting: AppSettings.screenshotSaveDirectory
            )
        }
        .formStyle(.grouped)
        .onAppear {
            screenshotFormat = SettingsView.selectedScreenshotFormat
        }
    }
}
