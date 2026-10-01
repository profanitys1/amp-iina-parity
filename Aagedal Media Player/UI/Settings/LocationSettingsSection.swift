// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct LocationSettingsSection: View {
    @Binding var mode: SaveLocationMode
    @State private var folderName: String = "Desktop"

    let modeSetting: AppSetting<String>
    let bookmarkSetting: AppSetting<Data?>

    var body: some View {
        Section("Save Location") {
            LabeledContent("Location") {
                VStack(alignment: .trailing, spacing: 8) {
                    Picker("", selection: $mode) {
                        ForEach(SaveLocationMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: mode) { _, newValue in
                        UserDefaults.standard.set(newValue.rawValue, for: modeSetting)
                        if newValue == .custom {
                            ensureBookmark(setting: bookmarkSetting)
                        }
                    }

                    if mode == .custom {
                        HStack(spacing: 6) {
                            Text(folderName)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button("Choose\u{2026}") {
                                chooseDirectory()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            loadMode()
            folderName = folderNameFromBookmark()
        }
    }

    private func loadMode() {
        if let raw = UserDefaults.standard.string(forKey: modeSetting.key),
           let saved = SaveLocationMode(rawValue: raw) {
            mode = saved
        }
        if mode == .custom {
            ensureBookmark(setting: bookmarkSetting)
        }
    }

    private func ensureBookmark(setting: AppSetting<Data?>) {
        if UserDefaults.standard.data(forKey: setting.key) == nil {
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            if let data = try? desktop.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: setting.key)
            }
        }
    }

    private func folderNameFromBookmark() -> String {
        guard let url = SettingsView.resolveBookmark(setting: bookmarkSetting) else {
            return "Desktop"
        }
        return url.lastPathComponent
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a default folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(data, forKey: bookmarkSetting.key)
            folderName = url.lastPathComponent
        }
    }
}
