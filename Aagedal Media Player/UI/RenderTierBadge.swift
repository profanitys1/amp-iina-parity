// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Names the shaders changing the picture: a manual profile, or the
/// profile Automatic picked with the reason, for example `Auto · Compressed movie · 2.1 Mbit/s`.
struct RenderTierBadge: View {
    @ObservedObject var player: MPVPlayer
    @AppStorage(AppSettings.shaderDirectory.key)
    private var shaderDirectory = AppSettings.shaderDirectory.defaultValue

    private var missingShaderNames: [String] {
        ShaderLibrary(directoryPath: shaderDirectory)
            .missingShaderNames(for: player.activeProfile)
    }

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    /// Nil when nothing alters the picture. Under Automatic the badge stays up even on
    /// Faithful, so the reason (for example HDR) is visible.
    private var label: String? {
        if player.renderProfile == .automatic { return player.automaticChoice?.badgeText }
        return player.renderProfile == .off ? nil : player.renderProfile.displayName
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
