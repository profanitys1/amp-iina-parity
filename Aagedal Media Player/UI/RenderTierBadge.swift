// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Names the shaders changing the picture: a manual profile, or the
/// automatic tier Enhance picked.
struct RenderTierBadge: View {
    @ObservedObject var player: MPVPlayer
    @AppStorage(AppSettings.shaderDirectory.key)
    private var shaderDirectory = AppSettings.shaderDirectory.defaultValue

    private var missingShaderNames: [String] {
        ShaderLibrary(directoryPath: shaderDirectory)
            .missingShaderNames(named: RenderTier.allCases.flatMap(\.shaderFileNames))
    }

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    /// Nil when nothing alters the picture.
    private var label: String? {
        if player.renderProfile != .off { return player.renderProfile.displayName }
        if player.isTierSteppedDown { return "\(player.activeTier.displayName) · stepped down" }
        return player.activeTier != .faithful ? player.activeTier.displayName : nil
    }

    var body: some View {
        if let label {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(reduceTransparency ? 1 : 0.75))
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .help(missingShaderNames.isEmpty
                  ? "Shaders are altering the picture."
                  : "Not in the shader folder: \(missingShaderNames.joined(separator: ", "))")
            .accessibilityLabel("Enhancement: \(label)")
            .accessibilityHint(missingShaderNames.isEmpty
                               ? "Video is being processed with the \(label) shaders"
                               : "Some shaders are missing from the folder")
            .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1.0 : 0.95)))
        }
    }
}
