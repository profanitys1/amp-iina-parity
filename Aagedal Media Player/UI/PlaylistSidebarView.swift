// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The media files beside the current one, in the same Finder-natural order
/// the Previous/Next File commands walk. This is a view onto the folder, not a
/// queue: there is nothing to reorder and nothing to persist.
struct PlaylistSidebarView: View {
    private static let rowHeight: CGFloat = 30

    let urls: [URL]
    let currentIndex: Int?
    let onSelect: (URL) -> Void

    var body: some View {
        if urls.isEmpty {
            ContentUnavailableView(
                "No Other Media",
                systemImage: "list.bullet.rectangle",
                description: Text("This folder holds no other playable files.")
            )
        } else {
            List(Array(urls.enumerated()), id: \.element) { index, url in
                row(url: url, isCurrent: index == currentIndex)
                    .frame(height: Self.rowHeight)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(url) }
            }
            .listStyle(.inset)
        }
    }

    private func row(url: URL, isCurrent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isCurrent ? "play.fill" : "film")
                .font(.system(size: 10))
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                .frame(width: 14)

            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(url.lastPathComponent)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}
