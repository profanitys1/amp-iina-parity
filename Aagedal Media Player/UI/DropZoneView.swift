// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Shown when no media file is loaded: branding on the left, the ways into a
// file on the right. Modelled on IINA's initial window, which puts the recent
// files one click away instead of behind the File menu.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DropZoneView: View {
    let isDropTargeted: Bool
    let onOpenFile: () -> Void
    let onOpenRecent: (URL) -> Void

    @State private var recents: [URL] = []

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (build \(build))"
    }

    var body: some View {
        HStack(spacing: 0) {
            brandingColumn
            Divider()
            actionsColumn
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .padding(12)
        )
        .onAppear(perform: reloadRecents)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            reloadRecents()
        }
    }

    private var brandingColumn: some View {
        VStack(spacing: 12) {
            Spacer()
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
                    .accessibilityHidden(true)
            }
            Text(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Aagedal Media Player")
                .font(.title3.weight(.medium))
            Text(versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(width: 220)
        .frame(maxHeight: .infinity)
    }

    private var actionsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpenFile) {
                Label("Open\u{2026}", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(WelcomeRowButtonStyle())
            .keyboardShortcut("o", modifiers: .command)

            if recents.isEmpty {
                Spacer()
                Text(isDropTargeted ? "Drop to open" : "Drop a media file here")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Divider()
                    .padding(.vertical, 6)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(recents, id: \.self) { url in
                            Button { onOpenRecent(url) } label: {
                                Label {
                                    Text(url.deletingPathExtension().lastPathComponent)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } icon: {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(WelcomeRowButtonStyle())
                            .help(url.path)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func reloadRecents() {
        let manager = FileManager.default
        recents = NSDocumentController.shared.recentDocumentURLs
            .filter { manager.fileExists(atPath: $0.path) }
    }
}

/// Flat full-width row that only paints a background under the pointer, so the
/// list reads as a list rather than a stack of buttons.
private struct WelcomeRowButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : (isHovered ? 0.08 : 0)))
            )
            .onHover { isHovered = $0 }
    }
}
