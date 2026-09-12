// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Ported from IINA's InitialWindowController.swift (GPL-3.0), originally by lhc.
// https://github.com/iina/iina — the nib, metrics, colours and interaction
// behaviour are IINA's; the differences are noted where they occur:
//
//   * the file is routed through WindowManager instead of a PlayerCore
//   * the Open URL row is gone, the app has no network playback
//   * the Resume row is gone, the app stores no playback position
//   * the beta badge keeps its colour but has no explanatory popover
//   * theme follows the system rather than an app preference

import AppKit

fileprivate extension NSUserInterfaceItemIdentifier {
    static let openFile = NSUserInterfaceItemIdentifier("openFile")
}

/// Rounded highlight for a selected recent-file row.
fileprivate final class GrayHighlightRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        WelcomeColor.lastFileBackground.setFill()
        NSBezierPath(roundedRect: NSInsetRect(bounds, 0, 0), xRadius: 4, yRadius: 4).fill()
    }

    func setHoverHighlight() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = WelcomeColor.actionButtonBackgroundHover.cgColor
    }

    func unsetHoverHighlight() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = WelcomeColor.actionButtonBackground.cgColor
    }
}

final class InitialWindowController: NSWindowController {
    override var windowNibName: NSNib.Name { NSNib.Name("InitialWindowController") }

    private(set) var loaded = false

    @IBOutlet weak var recentFilesTableView: NSTableView!
    @IBOutlet weak var appIcon: NSImageView!
    @IBOutlet weak var versionLabel: NSTextField!
    @IBOutlet weak var visualEffectView: NSVisualEffectView!
    @IBOutlet weak var leftOverlayView: NSView!
    @IBOutlet weak var mainView: NSView!
    @IBOutlet weak var betaIndicatorView: BetaIndicatorView!
    @IBOutlet weak var betaTextField: NSTextField!
    @IBOutlet weak var recentFilesTableTopConstraint: NSLayoutConstraint!

    private var recentDocuments: [URL] = []
    private var currentlyHoveredRow: GrayHighlightRowView?

    override func windowDidLoad() {
        super.windowDidLoad()
        loaded = true

        appIcon.unregisterDraggedTypes()
        appIcon.image = NSApp.applicationIconImage

        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.isMovableByWindowBackground = true
        window?.contentView?.registerForDraggedTypes([.fileURL, .URL, .string])

        mainView.wantsLayer = true

        versionLabel.stringValue = AppIdentity.versionDescription
        if let channel = AppIdentity.prereleaseChannel {
            betaTextField.stringValue = channel.uppercased()
            betaIndicatorView.isHidden = false
        } else {
            betaIndicatorView.isHidden = true
        }

        // Without a Resume row the table starts where IINA puts it when the
        // row is hidden.
        recentFilesTableTopConstraint.constant = 24

        recentFilesTableView.delegate = self
        recentFilesTableView.dataSource = self
        recentFilesTableView.action = #selector(onTableClicked)
        recentFilesTableView.addTrackingArea(
            NSTrackingArea(rect: recentFilesTableView.bounds,
                           options: [.activeInKeyWindow, .mouseMoved], owner: self, userInfo: nil))
        recentFilesTableView.addTrackingArea(
            NSTrackingArea(rect: recentFilesTableView.bounds,
                           options: [.activeInKeyWindow, .mouseEnteredAndExited], owner: self, userInfo: nil))

        setMaterial()
        reloadData()
    }

    private func setMaterial() {
        guard let window else { return }
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = window.effectiveAppearance.isDarkAppearance
            ? [NSColor.black.withAlphaComponent(0.4).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
            : [NSColor.black.withAlphaComponent(0.1).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        leftOverlayView.wantsLayer = true
        leftOverlayView.layer = gradientLayer
    }

    @objc private func onTableClicked() {
        openRecentItemFromTable(recentFilesTableView.clickedRow)
    }

    private func openRecentItemFromTable(_ rowIndex: Int) {
        guard recentDocuments.indices.contains(rowIndex) else { return }
        open(recentDocuments[rowIndex])
    }

    /// Hands the file to a player window and closes, the way IINA's
    /// `PlayerCore.load` calls `initialWindow.close()`.
    func open(_ url: URL) {
        WindowManager.shared.openInNewPlayerWindow(url)
        close()
    }

    func reloadData() {
        let manager = FileManager.default
        recentDocuments = NSDocumentController.shared.recentDocumentURLs
            .filter { manager.fileExists(atPath: $0.path) }
        recentFilesTableView.reloadData()
        if recentFilesTableView.numberOfRows > 0 {
            recentFilesTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }
}

// MARK: - Recent files table

extension InitialWindowController: NSTableViewDelegate, NSTableViewDataSource {
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        GrayHighlightRowView()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        recentDocuments.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        let url = recentDocuments[row]
        return [
            "filename": url.lastPathComponent,
            "docIcon": NSWorkspace.shared.icon(forFile: url.path),
        ] as [String: Any]
    }

    override func mouseMoved(with event: NSEvent) {
        let point = recentFilesTableView.convert(event.locationInWindow, from: nil)
        let rowIndex = recentFilesTableView.row(at: point)
        guard rowIndex >= 0,
              let rowView = recentFilesTableView.rowView(atRow: rowIndex, makeIfNecessary: false)
                  as? GrayHighlightRowView else {
            currentlyHoveredRow?.unsetHoverHighlight()
            currentlyHoveredRow = nil
            return
        }
        guard currentlyHoveredRow != rowView else { return }
        rowView.setHoverHighlight()
        currentlyHoveredRow?.unsetHoverHighlight()
        currentlyHoveredRow = rowView
    }

    override func mouseExited(with event: NSEvent) {
        currentlyHoveredRow?.unsetHoverHighlight()
        currentlyHoveredRow = nil
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            if recentFilesTableView.selectedRow >= 0 {
                openRecentItemFromTable(recentFilesTableView.selectedRow)
            } else if recentFilesTableView.numberOfRows > 0 {
                openRecentItemFromTable(0)
            }
        case 125: // Down
            if recentDocuments.isEmpty
                || recentFilesTableView.selectedRow >= recentFilesTableView.numberOfRows - 1 {
                super.keyDown(with: event)
            } else {
                recentFilesTableView.keyDown(with: event)
            }
        case 126: // Up
            if recentFilesTableView.selectedRow == 0 || recentDocuments.isEmpty {
                super.keyDown(with: event)
            } else {
                recentFilesTableView.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

// MARK: - Content view

/// Accepts dropped media, as IINA's `InitialWindowContentView` does.
final class InitialWindowContentView: NSView {
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        InitialWindowContentView.mediaURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = InitialWindowContentView.mediaURLs(from: sender)
        guard !urls.isEmpty else { return false }
        (window?.windowController as? InitialWindowController)?.close()
        WindowManager.shared.open(urls)
        return true
    }

    private static func mediaURLs(from sender: any NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
    }
}

// MARK: - Action row

/// IINA's `InitialWindowViewActionButton`: 6pt radius, background swapping on
/// hover and press.
final class InitialWindowViewActionButton: NSView {
    var normalBackground = WelcomeColor.actionButtonBackground {
        didSet { layer?.backgroundColor = normalBackground.cgColor }
    }
    var hoverBackground = WelcomeColor.actionButtonBackgroundHover
    var pressedBackground = WelcomeColor.actionButtonBackgroundPressed

    override nonisolated func awakeFromNib() {
        MainActor.assumeIsolated {
            wantsLayer = true
            layer?.cornerRadius = 6
            layer?.backgroundColor = normalBackground.cgColor
            addTrackingArea(NSTrackingArea(rect: bounds,
                                           options: [.activeInKeyWindow, .mouseEnteredAndExited],
                                           owner: self, userInfo: nil))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverBackground.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalBackground.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = pressedBackground.cgColor
        guard identifier == .openFile,
              let controller = window?.windowController as? InitialWindowController,
              let url = PlayerWindowCoordinator.presentOpenPanel() else { return }
        controller.open(url)
    }

    override func mouseUp(with event: NSEvent) {
        layer?.backgroundColor = hoverBackground.cgColor
    }
}

// MARK: - Prerelease badge

/// The badge keeps IINA's colour and 4pt radius. IINA attaches an explanatory
/// popover; there is no equivalent copy here, so it is just a label.
final class BetaIndicatorView: NSView {
    override nonisolated func awakeFromNib() {
        MainActor.assumeIsolated {
            wantsLayer = true
            layer?.cornerRadius = 4
            layer?.backgroundColor = WelcomeColor.betaLabel.cgColor
        }
    }
}

// MARK: - Colours

/// Exact values from IINA's `Assets.xcassets/Colors`.
nonisolated enum WelcomeColor {
    static var actionButtonBackground: NSColor { .clear }

    static var actionButtonBackgroundHover: NSColor {
        dynamic(light: NSColor(srgbWhite: 0.65, alpha: 0.25),
                dark: NSColor(srgbWhite: 0, alpha: 0.25))
    }

    static var actionButtonBackgroundPressed: NSColor {
        dynamic(light: NSColor(srgbWhite: 0.65, alpha: 0.35),
                dark: NSColor(srgbWhite: 0, alpha: 0.35))
    }

    static var lastFileBackground: NSColor {
        dynamic(light: NSColor(srgbWhite: 0.15, alpha: 0.1),
                dark: NSColor(srgbWhite: 1, alpha: 0.1))
    }

    static var betaLabel: NSColor {
        dynamic(light: NSColor(srgbRed: 1, green: 0.55, blue: 0.2, alpha: 1),
                dark: NSColor(srgbRed: 1, green: 0.65, blue: 0.25, alpha: 1))
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

private extension NSColor {
    nonisolated convenience init(srgbWhite white: CGFloat, alpha: CGFloat) {
        self.init(srgbRed: white, green: white, blue: white, alpha: alpha)
    }
}

extension NSAppearance {
    var isDarkAppearance: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
