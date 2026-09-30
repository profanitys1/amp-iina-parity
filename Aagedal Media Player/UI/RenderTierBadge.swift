// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Names the automatic shader tier while Enhance is changing the picture.
struct RenderTierBadge: View {
    @ObservedObject var player: MPVPlayer
    @AppStorage(AppSettings.shaderDirectory.key)
    private var shaderDirectory = AppSettings.shaderDirectory.defaultValue

    private var missingShaderNames: [String] {
        ShaderLibrary(directoryPath: shaderDirectory)
            .missingShaderNames(named: RenderTier.allCases.flatMap(\.shaderFileNames))
    }

    var body: some View {
        if player.activeTier != .faithful || player.isTierSteppedDown {
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                Text(player.isTierSteppedDown
                     ? "\(player.activeTier.displayName) · stepped down"
                     : player.activeTier.displayName)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.75))
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .help(missingShaderNames.isEmpty
                  ? "Enhance is altering the picture."
                  : "Not in the shader folder: \(missingShaderNames.joined(separator: ", "))")
            .accessibilityLabel("Enhancement: \(player.activeTier.displayName)")
        }
    }
}
