// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// Picks the GLSL shader stack applied to the gpu-next render path.
///
/// Shaders are read from a directory rather than bundled so one library can be
/// shared with a standalone mpv install, and so a user can drop in newer
/// networks without waiting for an app release.
struct RenderSettingsView: View {
    @AppStorage(AppSettings.renderProfile.key)
    private var renderProfileRaw = AppSettings.renderProfile.defaultValue
    @AppStorage(AppSettings.shaderDirectory.key)
    private var shaderDirectory = AppSettings.shaderDirectory.defaultValue
    @AppStorage(AppSettings.autoSelectSubtitles.key)
    private var autoSelectSubtitles = AppSettings.autoSelectSubtitles.defaultValue

    private var profile: RenderProfile {
        RenderProfile(rawValue: renderProfileRaw) ?? .off
    }

    private var library: ShaderLibrary {
        ShaderLibrary(directoryPath: shaderDirectory)
    }

    private var missingShaderNames: [String] {
        library.missingShaderNames(for: profile)
    }

    var body: some View {
        Form {
            Section("Shaders") {
                Picker("Profile", selection: $renderProfileRaw) {
                    ForEach(RenderProfile.allCases) { candidate in
                        Text(candidate.displayName).tag(candidate.rawValue)
                    }
                }
                .onChange(of: renderProfileRaw) { _, newValue in
                    let selected = RenderProfile(rawValue: newValue) ?? .off
                    NotificationCenter.default.post(.setRenderProfile(selected))
                }

                Text(profile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !missingShaderNames.isEmpty {
                    Label(
                        "Not in the shader folder: \(missingShaderNames.joined(separator: ", "))",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)

                    Text("The remaining shaders in this profile still load.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shader Folder") {
                HStack {
                    Text(library.directory.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Choose…", action: chooseDirectory)
                    if !shaderDirectory.isEmpty {
                        Button("Reset") { shaderDirectory = "" }
                    }
                }

                Text("Defaults to ~/.config/mpv/shaders so an existing mpv shader library works unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Subtitles") {
                Toggle("Select a Subtitle Track Automatically", isOn: $autoSelectSubtitles)
                Text("Applies to files opened from now on. Turn this off for inspection work that needs a clean picture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Heat") {
                Text("Heavier profiles cost GPU time per frame. Chroma reconstruction is cheap at any resolution; the upscaling networks are sized for sub-4K and sub-1080p sources respectively.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = library.directory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        shaderDirectory = url.path(percentEncoded: false)
    }
}
