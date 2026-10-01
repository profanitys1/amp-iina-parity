// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ExportSettingsView: View {
    @AppStorage(AppSettings.trimExportFormat.key)
    private var formatRaw = AppSettings.trimExportFormat.defaultValue

    @AppStorage(AppSettings.gifFrameRate.key)
    private var gifFrameRate = AppSettings.gifFrameRate.defaultValue
    @AppStorage(AppSettings.gifWidth.key)
    private var gifWidth = AppSettings.gifWidth.defaultValue
    @AppStorage(AppSettings.avifWidth.key)
    private var avifWidth = AppSettings.avifWidth.defaultValue
    @AppStorage(AppSettings.h264Width.key)
    private var h264Width = AppSettings.h264Width.defaultValue
    @AppStorage(AppSettings.h265Width.key)
    private var h265Width = AppSettings.h265Width.defaultValue

    @AppStorage(AppSettings.avifQuality.key)
    private var avifQuality = AppSettings.avifQuality.defaultValue
    @AppStorage(AppSettings.avifSpeed.key)
    private var avifSpeed = AppSettings.avifSpeed.defaultValue

    @AppStorage(AppSettings.h264Quality.key)
    private var h264Quality = AppSettings.h264Quality.defaultValue
    @AppStorage(AppSettings.h265Quality.key)
    private var h265Quality = AppSettings.h265Quality.defaultValue

    @State private var trimMode: SaveLocationMode = .ask

    private var format: TrimExportFormat {
        TrimExportFormat(rawValue: formatRaw) ?? .copy
    }

    private var widthBinding: Binding<Int> {
        switch format {
        case .copy: .constant(0)
        case .gif: $gifWidth
        case .animatedAVIF: $avifWidth
        case .hardwareH264: $h264Width
        case .hardwareH265: $h265Width
        }
    }

    var body: some View {
        Form {
            Section("Format") {
                Picker("Format", selection: $formatRaw) {
                    ForEach(TrimExportFormat.allCases, id: \.self) { f in
                        Text(f.label).tag(f.rawValue)
                    }
                }

                switch format {
                case .copy:
                    Text("Fast and lossless, but the trim start may move to the preceding keyframe. The source container is preserved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .gif:
                    LabeledContent("Frame Rate") {
                        HStack(spacing: 8) {
                            Slider(value: $gifFrameRate, in: 5...30, step: 1)
                            Text("\(Int(gifFrameRate)) fps")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }

                case .animatedAVIF:
                    LabeledContent("Quality (CRF)") {
                        HStack(spacing: 8) {
                            Slider(value: $avifQuality, in: 0...63, step: 1)
                            Text("\(Int(avifQuality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                    Text("Lower values = higher quality.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent("Speed") {
                        HStack(spacing: 8) {
                            Slider(value: $avifSpeed, in: 0...8, step: 1)
                            Text("\(Int(avifSpeed))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }

                case .hardwareH264:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $h264Quality, in: 1...100, step: 1)
                            Text("\(Int(h264Quality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                    Text("Frame-accurate trim. Re-encodes video as H.264 and audio as AAC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .hardwareH265:
                    LabeledContent("Quality") {
                        HStack(spacing: 8) {
                            Slider(value: $h265Quality, in: 1...100, step: 1)
                            Text("\(Int(h265Quality))")
                                .monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                    Text("Frame-accurate trim. Re-encodes video as H.265 and audio as AAC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if format != .copy {
                    LabeledContent("Short Side") {
                        Picker("", selection: widthBinding) {
                            ForEach(ExportWidthPreset.allCases, id: \.self) { p in
                                Text(p.label).tag(p.rawValue)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Limits the shortest side in pixels. The other side scales proportionally. Videos already within the limit are not upscaled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LocationSettingsSection(
                mode: $trimMode,
                modeSetting: AppSettings.trimLocationMode,
                bookmarkSetting: AppSettings.trimSaveDirectory
            )
        }
        .formStyle(.grouped)
    }
}
