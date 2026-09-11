// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A named GLSL shader stack applied to the gpu-next render path.
///
/// The cases are ordered coolest to warmest: each step adds GPU work, so the
/// heavier profiles are worth spending only when the source actually needs the
/// reconstruction. Shader files are not bundled — they are read from a user
/// shader directory so the same library can be shared with a standalone mpv.
nonisolated enum RenderProfile: String, CaseIterable, Sendable, Identifiable {
    case off
    case chroma
    case upscaleLight
    case upscaleStrong
    case restore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "Off"
        case .chroma: "Chroma reconstruction"
        case .upscaleLight: "Neural upscale — light"
        case .upscaleStrong: "Neural upscale — strong"
        case .restore: "Restoration"
        }
    }

    var summary: String {
        switch self {
        case .off: "No shaders. The plain gpu-next path."
        case .chroma: "Reconstructs 4:2:0 chroma from luma. Cheap at any resolution."
        case .upscaleLight: "Neural luma upscaling for sub-4K sources, plus chroma reconstruction."
        case .upscaleStrong: "Larger upscaling network. Best for sub-1080p sources, on AC power."
        case .restore: "Denoise, upscale and regrain rough standard-definition sources."
        }
    }

    /// Shader file names in load order, resolved against the shader directory.
    var shaderFileNames: [String] {
        switch self {
        case .off:
            []
        case .chroma:
            ["CfL_Prediction.glsl"]
        case .upscaleLight:
            ["ArtCNN_C4F16.glsl", "CfL_Prediction.glsl"]
        case .upscaleStrong:
            ["ArtCNN_C4F32.glsl", "CfL_Prediction.glsl"]
        case .restore:
            ["nlmeans.glsl", "ravu-zoom-ar-r3.hook", "CfL_Prediction.glsl", "noise_static_luma.hook"]
        }
    }

    /// Debanding only pays for itself on the low-bitrate sources the
    /// restoration profile targets; elsewhere it costs contrast for nothing.
    var enablesDeband: Bool { self == .restore }
}

/// Resolves shader file names to on-disk paths mpv can load.
nonisolated struct ShaderLibrary: Sendable {
    /// Where a standalone mpv install keeps its shaders. Sharing the directory
    /// means one library serves both players.
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/mpv/shaders", directoryHint: .isDirectory)
    }

    let directory: URL

    init(directoryPath: String = "") {
        let trimmed = directoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        directory = trimmed.isEmpty
            ? Self.defaultDirectory
            : URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Existing shader paths for `profile`, in load order.
    ///
    /// Missing files are dropped rather than failing the profile: a partial
    /// stack still improves the picture, and mpv would otherwise abort the
    /// whole list on the first unreadable path.
    func shaderPaths(for profile: RenderProfile) -> [String] {
        profile.shaderFileNames.compactMap { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    /// Shader names `profile` asks for that the directory does not contain.
    func missingShaderNames(for profile: RenderProfile) -> [String] {
        profile.shaderFileNames.filter { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            return !FileManager.default.fileExists(atPath: path)
        }
    }

    /// The value form mpv expects for `--glsl-shaders`.
    ///
    /// ponytail: `:` is mpv's list separator, so a shader directory containing
    /// a colon breaks the stack. Switch to per-path `change-list append` if
    /// anyone ever hits it.
    func shaderOptionValue(for profile: RenderProfile) -> String {
        shaderPaths(for: profile).joined(separator: ":")
    }
}
