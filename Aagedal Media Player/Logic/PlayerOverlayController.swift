// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Owns player-control overlay visibility and its AppKit event observers.

import AppKit
import Combine

@MainActor
final class PlayerOverlayController: ObservableObject {
    @Published private(set) var isVisible = true
    @Published private(set) var isWindowHovered = false
    @Published private(set) var isControlsHovered = false

    private var hideTask: Task<Void, Never>?
    private var mouseMoveMonitor: Any?
    private var keyDownMonitor: Any?
    private var mouseDownMonitor: Any?
    private var appActiveObserver: NSObjectProtocol?
    private let hideDelay: Duration

    /// Hardware key code used by AppKit for Tab, including Shift-Tab.
    private static let tabKeyCode: UInt16 = 48

    init(hideDelay: Duration = .seconds(2.5)) {
        self.hideDelay = hideDelay
    }

    func install(
        isMediaLoaded: @escaping @MainActor () -> Bool,
        isKeyWindow: @escaping @MainActor () -> Bool,
        isPlaying: @escaping @MainActor () -> Bool,
        isControlInteractionActive: @escaping @MainActor () -> Bool
    ) {
        removeObservers()

        mouseMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self,
                  isMediaLoaded(),
                  self.isWindowHovered,
                  isKeyWindow() else {
                return event
            }

            self.reveal()
            self.scheduleHide(
                isPlaying: isPlaying,
                isControlInteractionActive: isControlInteractionActive
            )
            return event
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  isMediaLoaded(),
                  event.keyCode == Self.tabKeyCode,
                  isKeyWindow() else {
                return event
            }

            self.revealForKeyboardNavigation()
            return event
        }

        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self, !self.isVisible else { return event }
            Self.hideCursorUntilMouseMoves()
            return event
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cancelScheduledHide()
                if isControlInteractionActive() {
                    self.reveal()
                }
            }
        }
    }

    func setWindowHovered(_ hovered: Bool, isControlInteractionActive: Bool) {
        isWindowHovered = hovered
        if !hovered && !isControlInteractionActive {
            hide()
        }
    }

    func setControlsHovered(_ hovered: Bool) {
        isControlsHovered = hovered
        if hovered {
            cancelScheduledHide()
        }
    }

    func reveal() {
        guard !isVisible else { return }
        isVisible = true
    }

    /// Keeps auto-hidden controls visible while Full Keyboard Access moves
    /// focus through them. The key event itself is returned to AppKit so normal
    /// Tab and Shift-Tab traversal still occurs.
    func revealForKeyboardNavigation() {
        reveal()
        cancelScheduledHide()
    }

    func hide() {
        isVisible = false
        cancelScheduledHide()
        Self.hideCursorUntilMouseMoves()
    }

    /// Hides the pointer over the whole picture whenever the controls are
    /// hidden, the way a player is expected to behave. AppKit brings it back
    /// on the next mouse move on its own.
    ///
    /// Re-arm it on mouse-down as well: since Big Sur a click without any
    /// movement makes the cursor reappear, contradicting the documented
    /// behaviour of `setHiddenUntilMouseMoves` (Apple FB11963121).
    static func hideCursorUntilMouseMoves() {
        NSCursor.setHiddenUntilMouseMoves(true)
    }

    func scheduleHide(
        isPlaying: @escaping @MainActor () -> Bool,
        isControlInteractionActive: @escaping @MainActor () -> Bool
    ) {
        cancelScheduledHide()
        guard !isControlsHovered, !isControlInteractionActive(), isPlaying() else { return }

        let hideDelay = hideDelay
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: hideDelay)
            guard !Task.isCancelled, let self else { return }
            if !self.isControlsHovered, !isControlInteractionActive(), isPlaying() {
                self.isVisible = false
                Self.hideCursorUntilMouseMoves()
            }
        }
    }

    func appDidResign(isMediaLoaded: Bool, isControlInteractionActive: Bool) {
        guard isMediaLoaded, !isControlInteractionActive else { return }
        hide()
    }

    func cancelScheduledHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    func tearDown() {
        cancelScheduledHide()
        removeObservers()
    }

    private func removeObservers() {
        if let mouseMoveMonitor {
            NSEvent.removeMonitor(mouseMoveMonitor)
            self.mouseMoveMonitor = nil
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
        if let mouseDownMonitor {
            NSEvent.removeMonitor(mouseDownMonitor)
            self.mouseDownMonitor = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
    }
}
