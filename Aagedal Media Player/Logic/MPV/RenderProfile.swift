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
    case sharpen
    case upscaleLight
    case upscaleStrong
    case restore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: "Faithful"
        case .chroma: "Chroma reconstruction"
        case .sharpen: "Sharpened upscale"
        case .upscaleLight: "Neural upscale — light"
        case .upscaleStrong: "Neural upscale — strong"
        case .restore: "Restoration"
        }
    }

    var summary: String {
        switch self {
        case .off: "No shaders. Plain resampling that stays true to the source — use this for inspection."
        case .chroma: "Infers 4:2:0 chroma edges from luma. Alters colour detail; cheap at any resolution."
        case .sharpen: "Sharper scaler plus SSimSuperRes. Alters the image; adds ringing-free edge contrast."
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
        case .sharpen:
            ["SSimSuperRes.glsl"]
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

    /// Main-scaler options that differ per profile. Every profile sets every
    /// key, so switching never leaves a previous profile's value behind.
    ///
    /// Only `.sharpen` departs from mpv's defaults. SSimSuperRes is a
    /// POSTKERNEL supplement to the scaler, so it is paired with the sharper
    /// `ewa_lanczossharp`; antiringing stays 0 because the shader does its own.
    /// `scaler-resizes-only=no` enables subpixel-offset correction, which the
    /// shader needs because it samples against `NATIVE_CROPPED`. Neural
    /// prescalers emit at or above target size, so `scale` barely runs for them.
    var scaleOptions: [String: String] {
        self == .sharpen
            ? ["scale": "ewa_lanczossharp", "scaler-resizes-only": "no"]
            : ["scale": "lanczos", "scaler-resizes-only": "yes"]
    }
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
        shaderPaths(named: profile.shaderFileNames)
    }

    /// Shader names `profile` asks for that the directory does not contain.
    func missingShaderNames(for profile: RenderProfile) -> [String] {
        missingShaderNames(named: profile.shaderFileNames)
    }

    /// Existing paths for `names`, in the given order. Shared by the manual
    /// profiles and the automatic tiers.
    func shaderPaths(named names: [String]) -> [String] {
        names.compactMap { name in
            let path = directory.appending(path: name).path(percentEncoded: false)
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    /// The subset of `names` the directory does not contain.
    func missingShaderNames(named names: [String]) -> [String] {
        names.filter { name in
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
