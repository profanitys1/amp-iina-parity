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
    @AppStorage(AppSettings.enhance.key)
    private var enhance = AppSettings.enhance.defaultValue
    @AppStorage(AppSettings.autoSelectSubtitles.key)
    private var autoSelectSubtitles = AppSettings.autoSelectSubtitles.defaultValue
    @AppStorage(AppSettings.hdrEnabled.key)
    private var hdrEnabled = AppSettings.hdrEnabled.defaultValue
    @AppStorage(AppSettings.loadDisplayICCProfile.key)
    private var loadDisplayICCProfile = AppSettings.loadDisplayICCProfile.defaultValue
    @AppStorage(AppSettings.toneMappingTargetPeakOverride.key)
    private var targetPeakOverride = AppSettings.toneMappingTargetPeakOverride.defaultValue

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
            Section("Enhancement") {
                Toggle("Enhance", isOn: $enhance)
                    .onChange(of: enhance) { _, newValue in
                        NotificationCenter.default.post(.setEnhance(newValue))
                    }
                Text("Picks a sharpening or neural upscaling shader from how much the picture is enlarged, and steps down when the GPU cannot keep up. Enhancement alters the image; leave it off for inspection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
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

                if profile != .off {
                    Text("A manual profile other than Faithful overrides Enhance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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

            Section("Colour") {
                Toggle("Show HDR as HDR", isOn: $hdrEnabled)
                Toggle("Use the Display's Colour Profile for SDR", isOn: $loadDisplayICCProfile)
                Stepper(targetPeakOverride == 0
                        ? "HDR Peak: From Display"
                        : "HDR Peak: \(targetPeakOverride) nits",
                        value: $targetPeakOverride, in: 0...10_000, step: 100)
                Text("HDR needs PQ or HLG with BT.2020 or Display P3 primaries, and a display with EDR headroom. Changes apply the next time a file is opened.")
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
                Text("Shaders cost GPU time per frame. With Enhance on, amp measures that cost while playing and drops to a lighter shader when a frame no longer fits.")
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
