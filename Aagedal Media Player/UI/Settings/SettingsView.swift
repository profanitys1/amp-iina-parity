// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

enum SaveLocationMode: String, CaseIterable {
    case original = "original"
    case custom = "custom"
    case ask = "ask"

    var label: String {
        switch self {
        case .original: "Next to Original"
        case .custom: "Custom Folder"
        case .ask: "Ask Every Time"
        }
    }
}

enum AudioWaveformColor: String, CaseIterable {
    case pink = "FF2D78"
    case blue = "4A9EE5"
    case red = "E54A4A"
    case green = "4AE57A"
    case white = "FFFFFF"

    var label: String {
        switch self {
        case .pink: "Pink"
        case .blue: "Blue"
        case .red: "Red"
        case .green: "Green"
        case .white: "White"
        }
    }

    /// Hex color string for ffmpeg (without #).
    var ffmpegHex: String { rawValue }

    /// SwiftUI preview color.
    var swiftUIColor: Color {
        let hex = rawValue
        let r = Double(Int(hex.prefix(2), radix: 16) ?? 0) / 255.0
        let g = Double(Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0) / 255.0
        let b = Double(Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

enum AudioWaveformDisplayMode: String, CaseIterable {
    case window = "window"
    case overlay = "overlay"

    var label: String {
        switch self {
        case .window: "Separate Window"
        case .overlay: "Overlay"
        }
    }
}


enum AudioWaveformBackground: String, CaseIterable {
    case black = "black"
    case transparent = "transparent"

    var label: String {
        switch self {
        case .black: "Black"
        case .transparent: "Transparent"
        }
    }
}

enum ScopeDisplayMode: String, CaseIterable {
    case window = "window"
    case overlay = "overlay"

    var label: String {
        switch self {
        case .window: "Separate Window"
        case .overlay: "Overlay"
        }
    }
}

enum ScopeBackground: String, CaseIterable {
    case black = "black"
    case transparent = "transparent"

    var label: String {
        switch self {
        case .black: "Black"
        case .transparent: "Transparent"
        }
    }
}

enum ScopeResolution: Int, CaseIterable {
    case low = 360
    case standard = 720
    case high = 1080
    case ultra = 1440

    var label: String {
        switch self {
        case .low: "Low (360)"
        case .standard: "Standard (720)"
        case .high: "High (1080)"
        case .ultra: "Ultra (1440)"
        }
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }

            ScreenshotSettingsView()
                .tabItem { Label("Screenshots", systemImage: "camera") }

            ExportSettingsView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }

            RenderSettingsView()
                .tabItem { Label("Rendering", systemImage: "sparkles") }

            ScopeSettingsView()
                .tabItem { Label("Scopes", systemImage: "waveform") }

            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "waveform.path") }

            KeyboardShortcutsView()
                .tabItem { Label("Shortcuts", systemImage: "command") }

            UpdateSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
        }
        .frame(width: 480, height: 500)
    }

    // MARK: - Static Resolution

    static var selectedScreenshotFormat: ScreenshotFormat {
        let raw = UserDefaults.standard.value(for: AppSettings.screenshotFormat)
        return ScreenshotFormat(rawValue: raw) ?? .jxl
    }

    static var selectedTrimExportFormat: TrimExportFormat {
        let raw = UserDefaults.standard.value(for: AppSettings.trimExportFormat)
        return TrimExportFormat(rawValue: raw) ?? .copy
    }

    static func resolvedScreenshotDirectory(sourceURL: URL) -> URL? {
        resolvedDirectory(
            modeSetting: AppSettings.screenshotLocationMode,
            bookmarkSetting: AppSettings.screenshotSaveDirectory,
            defaultMode: .custom,
            sourceURL: sourceURL
        )
    }

    static func resolvedTrimDirectory(sourceURL: URL) -> URL? {
        resolvedDirectory(
            modeSetting: AppSettings.trimLocationMode,
            bookmarkSetting: AppSettings.trimSaveDirectory,
            defaultMode: .ask,
            sourceURL: sourceURL
        )
    }

    private static func resolvedDirectory(
        modeSetting: AppSetting<String>,
        bookmarkSetting: AppSetting<Data?>,
        defaultMode: SaveLocationMode,
        sourceURL: URL
    ) -> URL? {
        let raw = UserDefaults.standard.value(for: modeSetting)
        let mode = SaveLocationMode(rawValue: raw) ?? defaultMode

        switch mode {
        case .original:
            return sourceURL.deletingLastPathComponent()
        case .custom:
            return resolveBookmark(setting: bookmarkSetting) ?? desktopURL()
        case .ask:
            return nil
        }
    }

    static func resolveBookmark(setting: AppSetting<Data?>) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: setting.key) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            if let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: setting.key)
            }
        }

        return url
    }

    private static func desktopURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    }
}
