// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Main window: drop zone when no file, player when file is loaded.

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var controller = PlayerController()
    @StateObject private var compareSession = CompareSessionController()
    @StateObject private var windowCoordinator = PlayerWindowCoordinator()
    @StateObject private var overlayController = PlayerOverlayController()
    @State private var timecodeMode: TimecodeDisplayMode = .relative
    @State private var isDropTargeted = false
    @State private var showInspector = false
    @State private var inspectorTab: InspectorTab = .playlist
    @StateObject private var loupe = InspectionLoupeState()
    @StateObject private var loupePrimaryCapture = LoupeFrameCapture()
    @StateObject private var loupeSecondaryCapture = LoupeFrameCapture()
    @State private var showLoupeControls = false
    @State private var isEditingTimecode = false
    @State private var isTimelineFocused = false
    @State private var isPlaybackControlsFocused = false
    @State private var showReviewNotes = false
    @State private var deferredComparisonAction = DeferredMainActorTask()
    @State private var showCompareModeCallout = false
    @State private var isToolbarControlFocused = false
    @State private var timecodeActivationTrigger: String?
    @AppStorage(AppSettings.showCursorHideHint.key)
    private var showCursorHideHint = AppSettings.showCursorHideHint.defaultValue
    @AppStorage(AppSettings.didShowCompareModeCallout.key)
    private var didShowCompareModeCallout = AppSettings.didShowCompareModeCallout.defaultValue
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @State private var updateBannerDismissed = false
    @State private var scopeWindowController: ScopeWindowController?
    @State private var showScopeOverlay = false
    @AppStorage(AppSettings.scopeBackground.key)
    private var scopeBackground = AppSettings.scopeBackground.defaultValue
    @State private var audioWaveformWindowController: AudioWaveformWindowController?
    @State private var showAudioWaveformOverlay = false
    @StateObject private var audioWaveformGenerator = AudioWaveformGenerator()
    @AppStorage(AppSettings.audioWaveformBackground.key)
    private var audioWaveformBackground = AppSettings.audioWaveformBackground.defaultValue

    private let rightEdgeWidth: CGFloat = 60

    private enum InspectorTab: String, CaseIterable, Identifiable {
        case playlist
        case metadata

        var id: String { rawValue }
        var title: String {
            switch self {
            case .playlist: "Playlist"
            case .metadata: "Metadata"
            }
        }
    }

    init() {}

    /// Allows native lifecycle checks to drive the same window hierarchy used
    /// in production, including the transition into and out of comparison.
    init(controller: PlayerController, compareSession: CompareSessionController) {
        _controller = StateObject(wrappedValue: controller)
        _compareSession = StateObject(wrappedValue: compareSession)
    }

    private var isMediaLoaded: Bool { controller.mediaItem != nil }
    private var nsWindow: NSWindow? { windowCoordinator.window }
    private var showOverlay: Bool { overlayController.isVisible }
    private var isControlInteractionActive: Bool {
        isEditingTimecode
            || isPlaybackControlsFocused
            || isToolbarControlFocused
            || showLoupeControls
            || showReviewNotes
            || showCompareModeCallout
    }

    private var videoAspectRatio: CGFloat? {
        // Keep one stable comparison canvas. Resizing the window as the view
        // mode changes can make MPV recreate its drawable and reload playback.
        controller.videoAspectRatio
    }

    private var videoSourceSize: NSSize? {
        controller.videoSourceSize
    }

    // MARK: - Body

    var body: some View {
        contentLayers
            .modifier(NotificationHandlers(
                controller: controller,
                compareSession: compareSession,
                nsWindow: nsWindow,
                isEditingTimecode: $isEditingTimecode,
                showInspector: $showInspector,
                scopeWindowController: $scopeWindowController,
                showScopeOverlay: $showScopeOverlay,
                audioWaveformWindowController: $audioWaveformWindowController,
                showAudioWaveformOverlay: $showAudioWaveformOverlay,
                audioWaveformGenerator: audioWaveformGenerator,
                timecodeMode: $timecodeMode,
                overlayController: overlayController,
                isMediaLoaded: isMediaLoaded,
                openFilePanel: openFilePanel,
                openFile: openFile,
                openPreviousFile: openPreviousFile,
                openNextFile: openNextFile,
                openCompareFilePanel: openCompareFilePanel,
                toggleLoupeControls: { showLoupeControls.toggle() },
                toggleReviewNotes: { showReviewNotes.toggle() },
                addSubtitle: { controller.addSubtitle(url: $0) }
            ))
    }

    private var inspectionCanvas: some View {
        GeometryReader { canvas in
            let geometry = CompareDisplayGeometry(
                canvasSize: canvas.size,
                primaryAspectRatio: controller.videoAspectRatio ?? controller.mediaItem?.videoDisplayAspectRatio.map { CGFloat($0) },
                secondaryAspectRatio: compareSession.secondaryController.videoAspectRatio
                    ?? compareSession.secondaryController.mediaItem?.videoDisplayAspectRatio.map { CGFloat($0) }
            )
            ZStack {
                if let item = controller.mediaItem {
                    // Keep A's native drawable mounted when comparison starts,
                    // stops, or replaces B. MPV binds wid once per context.
                    ComparePlayerView(
                        primaryController: controller,
                        compareSession: compareSession,
                        primaryWaveformGenerator: audioWaveformGenerator,
                        primaryItem: item,
                        showsAudioWaveform: showAudioWaveformOverlay,
                        isEditingTimecode: $isEditingTimecode,
                        isTimelineFocused: $isTimelineFocused,
                        isOverlayControlFocused: isControlInteractionActive,
                        isTextInputActive: showReviewNotes || showLoupeControls,
                        timecodeActivationTrigger: $timecodeActivationTrigger
                    )
                } else {
                    DropZoneView(isDropTargeted: isDropTargeted, onOpenFile: openFilePanel)
                }

                if loupe.isEnabled, controller.mediaItem?.presentationKind != .audioOnly, isMediaLoaded {
                    InspectionLoupeOverlay(
                        state: loupe,
                        primary: controller,
                        secondary: compareSession.secondaryController,
                        primaryCapture: loupePrimaryCapture,
                        secondaryCapture: loupeSecondaryCapture,
                        isComparing: compareSession.isActive,
                        geometry: geometry,
                        mode: compareSession.viewMode
                    )
                }
            }
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    loupe.follow(
                        location,
                        geometry: geometry,
                        isComparing: compareSession.isActive,
                        mode: compareSession.viewMode,
                        wipePosition: compareSession.wipePosition,
                        overlayBlend: compareSession.overlayBlend
                    )
                }
            }
        }
        .onChange(of: controller.mediaItem?.url) { _, _ in loupe.close() }
        .onChange(of: loupe.isEnabled) { _, enabled in
            if !enabled {
                loupePrimaryCapture.stop()
                loupeSecondaryCapture.stop()
            }
        }
    }

    // MARK: - Content Layers

    private var renderedContentLayers: some View {
        ZStack {
            inspectionCanvas

            // Layer 2: export/screenshot feedback (fades with overlay controls)
            MediaOperationFeedbackOverlay(controller: controller)
            .opacity(isMediaLoaded ? (showOverlay ? 1 : 0) : 1)
            .animation(.easeInOut(duration: 0.25), value: showOverlay)

            // Layer 3: update banner
            if updateChecker.updateAvailable, !updateBannerDismissed {
                UpdateAvailableBanner(
                    updateChecker: updateChecker,
                    isDismissed: $updateBannerDismissed
                )
            }

            // Layer 4: overlay controls
            overlayControls

            // Layer 5: audio waveform overlay (always visible when active, independent of controls)
            if showAudioWaveformOverlay,
               isMediaLoaded,
               controller.mediaItem?.presentationKind != .audioOnly,
               !audioWaveformGenerator.channelImages.isEmpty || audioWaveformGenerator.isGenerating || audioWaveformGenerator.error != nil {
                GeometryReader { geo in
                    VStack {
                        Spacer()
                        audioWaveformOverlay(containerHeight: geo.size.height)
                    }
                    .padding(.bottom, showOverlay ? 80 : 0)
                    .animation(.easeInOut(duration: 0.25), value: showOverlay)
                }
                .allowsHitTesting(true)
            }

            // Layer 6: scope overlay (sits above audio waveform when both active)
            if showScopeOverlay && isMediaLoaded {
                GeometryReader { geo in
                    let audioWaveformHeight = showAudioWaveformOverlay ? max(60, geo.size.height / 4) : 0
                    VStack {
                        Spacer()
                        scopeOverlay(containerHeight: geo.size.height)
                    }
                    .padding(.bottom, (showOverlay ? 80 : 0) + audioWaveformHeight)
                    .animation(.easeInOut(duration: 0.25), value: showOverlay)
                }
                .allowsHitTesting(false)
            }

            // Layer 7: right-edge cursor hide zone
            if isMediaLoaded && !showInspector {
                cursorHideZone
            }
        }
        .ignoresSafeArea()
        .focusedSceneValue(\.isMediaLoaded, isMediaLoaded)
        .focusedSceneValue(\.isCompareModeActive, compareSession.isActive)
        .focusedSceneValue(\.canOpenPreviousFile, windowCoordinator.canOpenPreviousFile)
        .focusedSceneValue(\.canOpenNextFile, windowCoordinator.canOpenNextFile)
        .frame(minWidth: 270, minHeight: 200)
        .background(Color.black)
        .background(
            WindowConfigurator(
                aspectRatio: videoAspectRatio,
                videoSourceSize: videoSourceSize,
                showTrafficLights: overlayController.isWindowHovered && !overlayController.isRightEdgeHovered,
                onWindowAvailable: { window in
                    windowCoordinator.accept(
                        window,
                        onClose: { [controller, compareSession, audioWaveformGenerator, loupePrimaryCapture, loupeSecondaryCapture] in
                            loupePrimaryCapture.stop()
                            loupeSecondaryCapture.stop()
                            Self.stopPlaybackForWindowClose(
                                controller: controller,
                                compareSession: compareSession,
                                audioWaveformGenerator: audioWaveformGenerator
                            )
                        }
                    )
                }
            )
        )
        .onHover { hovering in
            overlayController.setWindowHovered(
                hovering,
                isControlInteractionActive: isControlInteractionActive
            )
        }
        .inspector(isPresented: $showInspector) {
            VStack(spacing: 0) {
                Picker("", selection: $inspectorTab) {
                    ForEach(InspectorTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)

                Divider()

                switch inspectorTab {
                case .playlist:
                    PlaylistSidebarView(
                        urls: windowCoordinator.siblingMediaURLs,
                        currentIndex: windowCoordinator.siblingMediaIndex,
                        onSelect: { openFile(url: $0) }
                    )
                case .metadata:
                    if let item = controller.mediaItem {
                        MetadataInspectorView(
                            item: item,
                            useMPV: controller.useMPV,
                            trimIn: controller.trimIn,
                            trimOut: controller.trimOut,
                            isPresented: $showInspector
                        )
                    }
                }
            }
            .inspectorColumnWidth(min: 280, ideal: 360, max: 480)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            windowCoordinator.handleDrop(providers, controller: controller)
        }
        .alert(
            "Compare Mode",
            isPresented: Binding(
                get: { compareSession.loadError != nil },
                set: { if !$0 { compareSession.dismissLoadError() } }
            )
        ) {
            Button("OK") { compareSession.dismissLoadError() }
        } message: {
            Text(compareSession.loadError ?? "The comparison file could not be loaded.")
        }
        .modifier(CompareReviewRelinkPresentation(
            primaryController: controller,
            compareSession: compareSession,
            showReviewNotes: $showReviewNotes
        ))
    }

    private var observedContentLayers: some View {
        renderedContentLayers
        .onChange(of: controller.screenshotState) { _, state in
            switch state {
            case .succeeded:
                announce("Screenshot saved.")
            case .failed(let message):
                announce(message)
            case .idle, .saving:
                break
            }
        }
        .onChange(of: compareSession.secondaryController.mediaItem?.url) { _, _ in
            deferredComparisonAction.cancel()
        }
        .onChange(of: controller.mediaItem?.url) { _, _ in
            deferredComparisonAction.cancel()
        }
        .onChange(of: compareSession.isActive) { _, isActive in
            deferredComparisonAction.cancel()
            if !isActive {
                showReviewNotes = false
            } else {
                showCompareModeCallout = false
            }
        }
        .onChange(of: isMediaLoaded) { _, isLoaded in
            if isLoaded {
                presentCompareModeCalloutIfNeeded()
            } else {
                showCompareModeCallout = false
            }
        }
        .onChange(of: controller.trimExportState) { _, state in
            switch state {
            case .succeeded:
                announce("Trimmed file saved.")
            case .cancelled:
                announce("Export cancelled.")
            case .failed(let message):
                announce(message)
            case .idle, .warning, .preparing, .exporting, .cancelling:
                break
            }
        }
    }

    private var contentLayers: some View {
        observedContentLayers
        .onAppear {
            overlayController.install(
                isMediaLoaded: { controller.mediaItem != nil },
                isKeyWindow: { nsWindow?.isKeyWindow == true },
                isPlaying: { controller.isPlaying },
                isControlInteractionActive: { isControlInteractionActive }
            )
            windowCoordinator.configureWindowOpening { [openWindow] in
                openWindow(id: "player")
            }
        }
        .task {
            await windowCoordinator.consumePendingFile(
                controller: controller,
                onTimecodeModeChange: { timecodeMode = $0 },
                onMetadataLoaded: metadataDidLoad
            )
        }
        .onDisappear {
            deferredComparisonAction.cancel()
            loupePrimaryCapture.stop()
            loupeSecondaryCapture.stop()
            overlayController.tearDown()
            scopeWindowController?.close()
            scopeWindowController = nil
            if showScopeOverlay {
                controller.frameCapture.stopCapture()
                compareSession.secondaryController.frameCapture.stopCapture()
                showScopeOverlay = false
            }
            audioWaveformWindowController?.close()
            audioWaveformWindowController = nil
            showAudioWaveformOverlay = false
            Self.stopPlaybackForWindowClose(
                controller: controller,
                compareSession: compareSession,
                audioWaveformGenerator: audioWaveformGenerator
            )
            windowCoordinator.tearDown()
        }
    }

    // MARK: - Overlay Controls

    private var overlayControls: some View {
        VStack(spacing: 0) {
            if isMediaLoaded {
                topToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            if compareSession.isActive || compareSession.isLoading {
                inspectionControls
            } else {
                FloatingOSCView(
                    controller: controller,
                    onShowPlaylist: { showInspector = true },
                    onShowSettings: {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                )
                .transition(.opacity)
                .frame(height: 120)
            }
        }
        .onHover { hovering in
            overlayController.setControlsHovered(hovering)
        }
        .opacity(isMediaLoaded ? (showOverlay ? 1 : 0) : 1)
        .animation(.easeInOut(duration: 0.25), value: showOverlay)
    }

    /// Compare Mode keeps the full inspection bar: trim regions, review-note
    /// markers, comparison legend and timeline zoom all live here.
    private var inspectionControls: some View {
        ControlsView(
            controller: controller,
            compareSession: compareSession,
            item: controller.mediaItem,
            timecodeMode: $timecodeMode,
            isEditingTimecode: $isEditingTimecode,
            isTimelineFocused: $isTimelineFocused,
            isControlsFocused: $isPlaybackControlsFocused,
            timecodeActivationTrigger: $timecodeActivationTrigger
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .frame(minWidth: 20)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Scope Overlay

    private func scopeOverlay(containerHeight: CGFloat) -> some View {
        let targetHeight = max(80, containerHeight / 4)
        let isTransparent = scopeBackground == ScopeBackground.transparent.rawValue

        return ScopeView(
            primaryController: controller,
            secondaryController: compareSession.secondaryController,
            primaryFrameCapture: controller.frameCapture,
            secondaryFrameCapture: compareSession.secondaryController.frameCapture,
            compareSession: compareSession,
            isOverlay: true,
            transparentBackground: isTransparent
        )
        .frame(height: targetHeight)
        .clipped()
    }

    // MARK: - Audio Waveform Overlay

    private func audioWaveformOverlay(containerHeight: CGFloat) -> some View {
        // Target ~1/3 of the container; if window is too small, fill available space
        let targetHeight = max(60, containerHeight / 4)
        let isTransparent = audioWaveformBackground == AudioWaveformBackground.transparent.rawValue

        return AudioWaveformView(
            generator: audioWaveformGenerator,
            controller: controller,
            isOverlay: true,
            transparentBackground: isTransparent
        )
        .frame(height: targetHeight)
        .clipped()
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        PlayerTitleBar(title: controller.mediaItem?.url.lastPathComponent ?? "")
    }


    private var compareModeCallout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Compare two masters", systemImage: "rectangle.split.2x1")
                .font(.headline)

            Text(
                "Add source B to align it with this file, then inspect both with "
                    + "A/B switching, wipes, overlays, difference view, and one shared transport."
            )
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("Got It") {
                    showCompareModeCallout = false
                }

                Button("Choose Source B\u{2026}") {
                    showCompareModeCallout = false
                    deferredComparisonAction.schedule {
                        openCompareFilePanel()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func presentCompareModeCalloutIfNeeded() {
        guard isMediaLoaded,
              !compareSession.isActive,
              !didShowCompareModeCallout else { return }
        didShowCompareModeCallout = true
        showCompareModeCallout = true
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    private static func stopPlaybackForWindowClose(
        controller: PlayerController,
        compareSession: CompareSessionController,
        audioWaveformGenerator: AudioWaveformGenerator
    ) {
        audioWaveformGenerator.cancel()
        if compareSession.isActive {
            compareSession.pause(primary: controller)
        }
        compareSession.stop()
        controller.cancelMediaOperationsForWindowClose()
        controller.teardown()
    }

    // MARK: - Cursor Hide Zone

    private var cursorHideZone: some View {
        HStack {
            Spacer()
            ZStack {
                CursorHideZone { hovering in
                    overlayController.setRightEdgeHovered(
                        hovering,
                        isPlaying: { controller.isPlaying },
                        isControlInteractionActive: { isControlInteractionActive }
                    )
                }

                // Discoverability hint — visible with overlay, hidden with it
                if showCursorHideHint {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.white.opacity(0.25))
                        .overlay {
                            ZStack {
                                Image(systemName: "cursorarrow")
                                    .font(.system(size: 14))
                                // Diagonal slash through the cursor
                                Rectangle()
                                    .frame(width: 18, height: 1.5)
                                    .rotationEffect(.degrees(-45))
                            }
                            .foregroundStyle(.white.opacity(0.3))
                        }
                        .padding(6)
                        .opacity(showOverlay && !overlayController.isRightEdgeHovered ? 1 : 0)
                        .animation(.easeInOut(duration: 0.25), value: showOverlay)
                        .animation(.easeInOut(duration: 0.3), value: overlayController.isRightEdgeHovered)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: rightEdgeWidth)
        }
        .padding(.bottom, 80)
    }

    // MARK: - File Opening

    func openFilePanel() {
        windowCoordinator.openFilePanel(onSelection: openFile(url:))
    }

    func openFile(url: URL) {
        showReviewNotes = false
        if compareSession.isActive {
            compareSession.pause(primary: controller)
        }
        compareSession.stop()
        windowCoordinator.openFile(
            url,
            controller: controller,
            onTimecodeModeChange: { timecodeMode = $0 },
            onMetadataLoaded: metadataDidLoad
        )
    }

    func openPreviousFile() {
        guard let url = windowCoordinator.previousMediaURL() else { return }
        openFile(url: url)
    }

    func openNextFile() {
        guard let url = windowCoordinator.nextMediaURL() else { return }
        openFile(url: url)
    }

    private func metadataDidLoad() {
        if showAudioWaveformOverlay {
            generateAudioWaveform()
        }
    }

    private func openCompareFilePanel() {
        guard controller.mediaItem != nil else { return }
        didShowCompareModeCallout = true
        showCompareModeCallout = false
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = PlayerWindowCoordinator.supportedMediaTypes
        panel.message = "Choose a file to compare with source A"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        compareSession.loadSecondary(url, alignedWith: controller)
    }

    func generateAudioWaveform() {
        guard let item = controller.mediaItem,
              let metadata = item.metadata else { return }

        let trackIdx = controller.selectedAudioTrackOrderIndex
        guard trackIdx < controller.audioTrackOptions.count else { return }

        let option = controller.audioTrackOptions[trackIdx]
        let streamIndex = option.streamIndex
        let audioStreams = metadata.audioStreams
        guard streamIndex < audioStreams.count else { return }

        let stream = audioStreams[streamIndex]
        let channels = stream.channels ?? 2

        audioWaveformGenerator.generate(
            url: item.url,
            streamIndex: streamIndex,
            channels: channels,
            channelLayout: stream.channelLayout,
            duration: item.durationSeconds
        )
    }

}
