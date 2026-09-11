// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The filename strip over the picture. Matches IINA's title bar: 40pt tall,
/// inset to clear the traffic lights, with a hairline bottom border.
struct PlayerTitleBar: View {
    /// IINA's own inset for the title container from the leading edge.
    private static let trafficLightClearance: CGFloat = 86
    private static let barHeight: CGFloat = 40

    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            TransportSyncStatusView()
        }
        .padding(.leading, Self.trafficLightClearance)
        .padding(.trailing, 12)
        .frame(height: Self.barHeight)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now playing: \(title)")
    }
}
