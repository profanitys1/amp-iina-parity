// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A named GLSL shader stack applied to the gpu-next render path.
///
/// `automatic` comes first: it picks one of the others for each file. The rest are
/// ordered coolest to warmest: each step adds GPU work, so the heavier profiles
/// are worth spending only when the source actually needs the reconstruction.
/// Shader files are not bundled — they are read from a user
/// shader directory so the same library can be shared with a standalone mpv.
nonisolated enum RenderProfile: String, CaseIterable, Sendable, Identifiable, Codable {
    case automatic
    case off
    case chroma
    case efficient
    case sharpen
    case upscaleLight
    case compressed
    case compressedGrain
    case crisp
    case upscaleStrong
    case restore

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .off: "Faithful"
        case .chroma: "Chroma reconstruction"
        case .efficient: "Efficient upscale"
        case .sharpen: "Sharpened upscale"
        case .upscaleLight: "Neural upscale — light"
        case .compressed: "Compressed movie"
        case .crisp: "Crisp"
        case .upscaleStrong: "Neural upscale — strong"
        case .compressedGrain: "Compressed movie + grain"
        case .restore: "Restoration"
        }
    }

    var summary: String {
        switch self {
        case .automatic: "Looks at each file and picks the shader profile that fits its quality and your GPU, then steps down if a frame no longer fits. Choose Faithful for inspection."
        case .off: "No shaders. Plain resampling that stays true to the source — use this for inspection."
        case .chroma: "Infers 4:2:0 chroma edges from luma. Alters colour detail; cheap at any resolution."
        case .efficient: "Small FSRCNNX doubler with KrigBilateral chroma. Light enough for battery."
        case .sharpen: "Sharper scaler plus SSimSuperRes. Alters the image; adds ringing-free edge contrast."
        case .upscaleLight: "Neural luma upscaling for sub-4K sources, plus chroma reconstruction."
        case .compressed: "Debands, then upscales with ArtCNN's denoise-and-sharpen model. Scored best on compressed video. For streaming and messaging-app clips."
        case .crisp: "ArtCNN's denoise-and-sharpen model plus adaptive sharpening. For soft but clean-ish sources."
        case .upscaleStrong: "Larger upscaling network. Best for sub-1080p sources, on AC power."
        case .compressedGrain: "Compressed movie plus fine luma grain, which hides leftover blocking and the smooth \"plastic\" look."
        case .restore: "Denoise, upscale and regrain rough standard-definition sources."
        }
    }

    /// Shader file names in load order, resolved against the shader directory.
    var shaderFileNames: [String] {
        switch self {
        case .automatic, .off:
            []
        case .chroma:
            ["CfL_Prediction.glsl"]
        case .efficient:
            ["FSRCNNX_x2_8-0-4-1.glsl", "KrigBilateral.glsl"]
        case .sharpen:
            ["SSimSuperRes.glsl"]
        case .upscaleLight:
            ["ArtCNN_C4F16.glsl", "CfL_Prediction.glsl"]
        // hdeband runs first and replaces mpv's own deband (its author's
        // instruction), so these profiles keep `enablesDeband` false.
        case .compressed:
            ["hdeband.glsl", "ArtCNN_C4F16_DS.glsl", "CfL_Prediction.glsl"]
        case .crisp:
            ["ArtCNN_C4F16_DS.glsl", "CfL_Prediction.glsl", "adaptive-sharpen.glsl"]
        case .upscaleStrong:
            ["ArtCNN_C4F32.glsl", "CfL_Prediction.glsl"]
        case .compressedGrain:
            ["hdeband.glsl", "ArtCNN_C4F16_DS.glsl", "CfL_Prediction.glsl", "noise_static_luma.hook"]
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

    /// Existing paths for `names`, in the given order.
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
