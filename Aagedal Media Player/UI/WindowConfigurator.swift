// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// NSViewRepresentable that configures the NSWindow for video playback:
// aspect ratio lock, traffic light visibility, background colour.

import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    static let baseMinWidth: CGFloat = 690
    static let baseMinHeight: CGFloat = 540

    let aspectRatio: CGFloat?
    let videoSourceSize: NSSize?
    let showTrafficLights: Bool
    var onWindowAvailable: ((NSWindow) -> Void)?

    /// Native fullscreen reveals and hides its own titlebar, so hover must not
    /// fade the traffic lights there: AppKit slides the titlebar down over a
    /// view amp already made transparent, and the dots arrive invisible.
    nonisolated static func trafficLightAlpha(showTrafficLights: Bool, isFullScreen: Bool) -> CGFloat {
        (showTrafficLights || isFullScreen) ? 1 : 0
    }

    /// Only the first media load in a window fills the screen. Later loads —
    /// folder next/previous, a mid-file resolution change — leave the size the
    /// user picked alone.
    nonisolated static func shouldMaximize(
        hasMaximizedForMedia: Bool,
        isFullScreen: Bool,
        openMaximized: Bool
    ) -> Bool {
        openMaximized && !hasMaximizedForMedia && !isFullScreen
    }

    /// Once a window has filled the screen its size belongs to the user, so
    /// neither a later source change nor a fullscreen exit may reshape it.
    nonisolated static func mayResizeToSource(
        hasMaximizedForMedia: Bool,
        openMaximized: Bool
    ) -> Bool {
        !(openMaximized && hasMaximizedForMedia)
    }

    nonisolated static func minContentSize(for ratio: CGFloat?) -> NSSize {
        guard let ratio, ratio > 0 else {
            return NSSize(width: baseMinWidth, height: baseMinHeight)
        }
        return NSSize(
            width: max(baseMinWidth, baseMinHeight * ratio),
            height: max(baseMinHeight, baseMinWidth / ratio)
        )
    }

    final class Coordinator: NSObject {
        var lastAspectRatio: CGFloat?
        var savedAspectRatio: CGFloat?
        var lastSourceSize: NSSize?
        weak var observedWindow: NSWindow?
        nonisolated(unsafe) var willEnterFullScreen: NSObjectProtocol?
        nonisolated(unsafe) var didEnterFullScreen: NSObjectProtocol?
        nonisolated(unsafe) var didExitFullScreen: NSObjectProtocol?
        /// Set for the duration of the enter transition. `styleMask` does not
        /// carry `.fullScreen` until the animation finishes, so without this a
        /// SwiftUI update mid-transition would read "not fullscreen" and fade
        /// the traffic lights out again.
        var isEnteringFullScreen = false
        var lastTrafficLightAlpha: CGFloat = 0
        /// Hover state at the last SwiftUI update, so exiting fullscreen can
        /// restore the fade instead of leaving the dots pinned visible.
        var lastShowTrafficLights = false
        /// Sticky per window: the first media load owns the screen fill.
        var hasMaximizedForMedia = false

        deinit {
            if let token = willEnterFullScreen { NotificationCenter.default.removeObserver(token) }
            if let token = didEnterFullScreen { NotificationCenter.default.removeObserver(token) }
            if let token = didExitFullScreen { NotificationCenter.default.removeObserver(token) }
        }

        func applyTrafficLightAlpha(_ window: NSWindow, animated: Bool = true) {
            let alpha = lastTrafficLightAlpha
            for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(buttonType),
                   let container = button.superview {
                    if container.alphaValue != alpha {
                        if animated {
                            NSAnimationContext.runAnimationGroup { ctx in
                                ctx.duration = 0.2
                                container.animator().alphaValue = alpha
                            }
                        } else {
                            container.alphaValue = alpha
                        }
                    }
                    break
                }
            }
        }

        /// Set contentMinSize based on the aspect ratio (or base values if nil).
        func applyMinSize(_ window: NSWindow, ratio: CGFloat?) {
            window.contentMinSize = WindowConfigurator.minContentSize(for: ratio)
        }

        /// Fill the screen with the picture. The aspect lock has to go first:
        /// AppKit reshapes setFrame to the locked ratio and would letterbox the
        /// window rather than the picture. The minimum drops to the base size
        /// for the same reason — a portrait source asks for a minimum taller
        /// than the screen, which blocks the fill outright.
        ///
        /// The target is `visibleFrame`, not `frame`. AppKit's
        /// `constrainFrameRect` clamps a titled window to the visible area, so
        /// the menu bar and Dock stay reachable. Asking for the full screen
        /// rect with no aspect lock raises an NSException inside
        /// `-[NSWindow _reallySetFrame:]` and takes the app down.
        func maximize(_ window: NSWindow) {
            window.contentAspectRatio = .zero
            applyMinSize(window, ratio: nil)
            guard let screen = window.screen ?? NSScreen.main else { return }
            window.setFrame(screen.visibleFrame, display: true, animate: false)
        }

        /// Sizes the window for a freshly loaded source. The first load in a
        /// window fills the screen; every later load leaves that size alone,
        /// because by then it is the size the user chose.
        func applyInitialSize(
            _ window: NSWindow,
            ratio: CGFloat,
            sourceSize: NSSize?,
            isFullScreen: Bool,
            openMaximized: Bool
        ) {
            if WindowConfigurator.shouldMaximize(
                hasMaximizedForMedia: hasMaximizedForMedia,
                isFullScreen: isFullScreen,
                openMaximized: openMaximized
            ) {
                hasMaximizedForMedia = true
                maximize(window)
                return
            }
            guard WindowConfigurator.mayResizeToSource(
                hasMaximizedForMedia: hasMaximizedForMedia,
                openMaximized: openMaximized
            ) else { return }

            applyMinSize(window, ratio: ratio)
            window.contentAspectRatio = NSSize(width: ratio, height: 1)
            guard let contentView = window.contentView else { return }

            let frame = window.frame
            let titlebarHeight = frame.height - contentView.bounds.height

            let useSourceResolution = UserDefaults.standard.value(for: AppSettings.openAtSourceResolution)

            var newWidth: CGFloat
            var newHeight: CGFloat

            if useSourceResolution,
               let sourceSize,
               sourceSize.width > 0, sourceSize.height > 0 {
                // Size to source resolution at 1:1 pixels (divide by backing scale for Retina)
                let backingScale = window.backingScaleFactor
                newWidth = sourceSize.width / backingScale
                newHeight = sourceSize.height / backingScale
                if UserDefaults.standard.value(for: AppSettings.clampWindowToScreen),
                   let screen = window.screen ?? NSScreen.main {
                    let maxFrame = screen.visibleFrame
                    let maxW = maxFrame.width * 0.9
                    let maxH = (maxFrame.height - titlebarHeight) * 0.9
                    if newWidth > maxW || newHeight > maxH {
                        let scale = min(maxW / newWidth, maxH / newHeight)
                        newWidth *= scale
                        newHeight *= scale
                    }
                }
            } else {
                // Default: adjust height from current width
                newWidth = contentView.bounds.width
                if ratio < 0.75 {
                    newWidth = min(newWidth, 380)
                }
                newHeight = newWidth / ratio
            }

            let totalHeight = newHeight + titlebarHeight
            let centerAfterResize = UserDefaults.standard.value(for: AppSettings.centerWindowAfterResize)
            let origin: NSPoint
            if centerAfterResize,
               let screen = window.screen ?? NSScreen.main {
                let visibleFrame = screen.visibleFrame
                origin = NSPoint(
                    x: visibleFrame.midX - newWidth / 2,
                    y: visibleFrame.midY - totalHeight / 2
                )
            } else {
                origin = NSPoint(
                    x: frame.origin.x,
                    y: frame.origin.y + frame.height - totalHeight
                )
            }
            window.setFrame(
                NSRect(x: origin.x, y: origin.y, width: newWidth, height: totalHeight),
                display: true, animate: false
            )
        }

        func observeWindow(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            observedWindow = window

            willEnterFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isEnteringFullScreen = true
                    self.savedAspectRatio = self.lastAspectRatio
                    self.lastAspectRatio = nil
                    window.contentResizeIncrements = NSSize(width: 1, height: 1)
                    // Fade the dots back in before AppKit takes the titlebar
                    // over: whatever hover left behind would otherwise ride
                    // into fullscreen and reveal as a transparent titlebar.
                    self.lastTrafficLightAlpha = 1
                    self.applyTrafficLightAlpha(window, animated: false)
                }
            }

            didEnterFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    // The style mask now carries .fullScreen, so updateNSView
                    // keeps the dots opaque on its own from here.
                    self?.isEnteringFullScreen = false
                }
            }

            didExitFullScreen = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isEnteringFullScreen = false
                    if let ratio = self.savedAspectRatio, ratio > 0 {
                        self.lastAspectRatio = ratio
                        // A maximized window is screen-shaped and its size now
                        // belongs to the user, so re-locking the ratio there
                        // would only fight the next manual resize.
                        if !self.hasMaximizedForMedia {
                            window.contentAspectRatio = NSSize(width: ratio, height: 1)
                        }
                    }
                    self.lastTrafficLightAlpha = WindowConfigurator.trafficLightAlpha(
                        showTrafficLights: self.lastShowTrafficLights,
                        isFullScreen: false
                    )
                    self.applyTrafficLightAlpha(window)
                }
            }
        }
    }

    final class ConfiguratorNSView: NSView {
        weak var coordinator: Coordinator?
        var onWindowAvailable: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let coordinator else { return }
            coordinator.observeWindow(window)
            window.isRestorable = false
            window.setFrameAutosaveName("")
            window.backgroundColor = .black
            // Video runs edge to edge under a transparent titlebar; the traffic
            // lights float over the picture and fade with the overlay controls.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            coordinator.applyTrafficLightAlpha(window, animated: false)
            // Set initial minimum size (base values; updated when video loads).
            coordinator.applyMinSize(window, ratio: nil)

            // Force a consistent default size after SwiftUI finishes its layout pass.
            DispatchQueue.main.async {
                let defaultW: CGFloat = 711
                let defaultH: CGFloat = 400
                let titlebarHeight = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)
                let totalHeight = defaultH + titlebarHeight
                let origin = NSPoint(
                    x: window.frame.origin.x,
                    y: window.frame.origin.y + window.frame.height - totalHeight
                )
                window.setFrame(NSRect(x: origin.x, y: origin.y, width: defaultW, height: totalHeight),
                                display: false)
            }

            onWindowAvailable?(window)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ConfiguratorNSView {
        let view = ConfiguratorNSView()
        view.setFrameSize(.zero)
        view.coordinator = context.coordinator
        view.onWindowAvailable = onWindowAvailable
        return view
    }

    func updateNSView(_ nsView: ConfiguratorNSView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
        guard let window = nsView.window else { return }
        onWindowAvailable?(window)
        let coordinator = context.coordinator

        coordinator.observeWindow(window)

        let ratio = aspectRatio
        let sourceSize = videoSourceSize
        let showsTrafficLights = showTrafficLights
        // The enter transition counts as fullscreen too: the style mask only
        // acquires .fullScreen once the animation completes, and an update
        // landing mid-transition would otherwise fade the dots back out.
        let isFullScreen = window.styleMask.contains(.fullScreen)
            || coordinator.isEnteringFullScreen
        let trafficLightAlpha = Self.trafficLightAlpha(
            showTrafficLights: showsTrafficLights,
            isFullScreen: isFullScreen
        )
        let openMaximized = UserDefaults.standard.value(for: AppSettings.openMaximized)

        DispatchQueue.main.async {
            coordinator.lastShowTrafficLights = showsTrafficLights

            // Aspect ratio and min size — only apply when not in fullscreen,
            // and only when the ratio actually changes.
            if !isFullScreen {
                if let ratio, ratio > 0 {
                    let ratioChanged = coordinator.lastAspectRatio != ratio
                    let sourceSizeChanged = sourceSize != nil && sourceSize != coordinator.lastSourceSize

                    if ratioChanged || sourceSizeChanged {
                        coordinator.lastAspectRatio = ratio
                        coordinator.savedAspectRatio = ratio
                        coordinator.lastSourceSize = sourceSize
                        coordinator.applyInitialSize(
                            window,
                            ratio: ratio,
                            sourceSize: sourceSize,
                            isFullScreen: isFullScreen,
                            openMaximized: openMaximized
                        )
                    }
                } else {
                    if coordinator.lastAspectRatio != nil {
                        coordinator.lastAspectRatio = nil
                        coordinator.savedAspectRatio = nil
                        coordinator.lastSourceSize = nil
                        window.contentResizeIncrements = NSSize(width: 1, height: 1)
                        coordinator.applyMinSize(window, ratio: nil)
                    }
                }
            }

            coordinator.lastTrafficLightAlpha = trafficLightAlpha
            coordinator.applyTrafficLightAlpha(window)
        }
    }
}
