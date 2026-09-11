// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// The ordinary-playback control card, following IINA's floating OSC geometry.
/// Compare Mode keeps using ControlsView, which carries the inspection tools
/// this card deliberately leaves out.
struct FloatingOSCView: View {
    private static let cardWidth: CGFloat = 460
    private static let minCardWidth: CGFloat = 200
    private static let cornerRadius: CGFloat = 12
    private static let buttonSide: CGFloat = 24
    private static let transportSpacing: CGFloat = 24
    private static let symbolSize: CGFloat = 14

    @ObservedObject var controller: PlayerController
    let onShowPlaylist: () -> Void
    let onShowSettings: () -> Void

    @AppStorage(AppSettings.controlBarPositionHorizontal.key)
    private var positionHorizontal = AppSettings.controlBarPositionHorizontal.defaultValue
    @AppStorage(AppSettings.controlBarPositionVertical.key)
    private var positionVertical = AppSettings.controlBarPositionVertical.defaultValue

    @State private var dragOrigin: CGPoint?
    @State private var cardSize: CGSize = .zero

    private var position: OSCPosition {
        OSCPosition(horizontal: positionHorizontal, vertical: positionVertical)
    }

    private var duration: Double { controller.mediaItem?.durationSeconds ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let origin = position.origin(in: geo.size, cardSize: resolvedCardSize(in: geo.size))

            card
                .frame(width: min(Self.cardWidth, max(Self.minCardWidth, geo.size.width - 16)))
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                .background(sizeReader)
                .offset(x: origin.x, y: origin.y)
                .gesture(dragGesture(in: geo.size))
        }
    }

    private var card: some View {
        VStack(spacing: 8) {
            topRow
                .padding(.top, 14)
                .padding(.horizontal, 12)

            scrubberRow
                .padding(.bottom, 8)
                .padding(.horizontal, 8)
        }
    }

    private var cardBackground: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.34))
    }

    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { cardSize = proxy.size }
                .onChange(of: proxy.size) { _, newSize in cardSize = newSize }
        }
    }

    private func resolvedCardSize(in videoSize: CGSize) -> CGSize {
        cardSize == .zero
            ? CGSize(width: Self.cardWidth, height: 67)
            : cardSize
    }

    // MARK: - Rows

    private var topRow: some View {
        HStack(spacing: 0) {
            volumeGroup
            Spacer(minLength: 8)
            transportGroup
            Spacer(minLength: 8)
            toolbarGroup
        }
    }

    private var scrubberRow: some View {
        HStack(spacing: 2) {
            timeLabel(controller.currentPlaybackTime)

            PlayerScrubber(
                item: controller.mediaItem,
                chapters: controller.chapterOptions,
                currentTime: controller.currentPlaybackTime,
                onScrub: { controller.seekTo($0) }
            )
            .padding(.horizontal, 2)

            timeLabel(duration)
        }
    }

    private func timeLabel(_ seconds: Double) -> some View {
        Text(TimecodeFormatter.formatTraditionalTime(seconds))
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: 46)
            .padding(.horizontal, 2)
    }

    // MARK: - Groups

    private var volumeGroup: some View {
        HStack(spacing: 4) {
            iconButton(volumeSymbolName, help: controller.isMuted ? "Unmute" : "Mute") {
                controller.isMuted.toggle()
            }

            PlaybackVolumeSlider(
                value: $controller.volume,
                onFocusChange: { _ in }
            )
            .frame(width: 60, height: 22)
        }
    }

    private var volumeSymbolName: String {
        if controller.isMuted || controller.volume == 0 { return "speaker.slash.fill" }
        if controller.volume < 34 { return "speaker.wave.1.fill" }
        if controller.volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private var transportGroup: some View {
        HStack(spacing: Self.transportSpacing) {
            iconButton("gobackward.10", help: "Back 10 seconds") {
                controller.seek(by: -10)
            }

            iconButton(controller.isPlaying ? "pause.fill" : "play.fill",
                       help: controller.isPlaying ? "Pause" : "Play",
                       pointSize: 16) {
                controller.togglePlayback()
            }

            iconButton("goforward.10", help: "Forward 10 seconds") {
                controller.seek(by: 10)
            }
        }
    }

    private var toolbarGroup: some View {
        HStack(spacing: 0) {
            iconButton("gearshape", help: "Settings", action: onShowSettings)
            iconButton("list.bullet.rectangle", help: "Playlist", action: onShowPlaylist)
            subtitleMenu
            iconButton("arrow.up.left.and.arrow.down.right", help: "Toggle full screen") {
                controller.toggleFullscreen()
            }
        }
    }

    private var subtitleMenu: some View {
        Menu {
            Button("Off") { controller.selectSubtitleTrack(at: -1) }
            ForEach(controller.subtitleTrackOptions) { option in
                Button(option.title) { controller.selectSubtitleTrack(at: option.position) }
            }
        } label: {
            Image(systemName: "captions.bubble.fill")
                .font(.system(size: Self.symbolSize, weight: .medium))
                .frame(width: Self.buttonSide, height: Self.buttonSide)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.white)
        .help("Subtitle track")
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        pointSize: CGFloat = FloatingOSCView.symbolSize,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: pointSize, weight: .medium))
                .frame(width: Self.buttonSide, height: Self.buttonSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Dragging

    private func dragGesture(in videoSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let size = resolvedCardSize(in: videoSize)
                if dragOrigin == nil {
                    dragOrigin = position.origin(in: videoSize, cardSize: size)
                }
                guard let dragOrigin else { return }

                let proposedX = Double(dragOrigin.x + value.translation.width)
                let snap = OSCPosition.snappedHorizontal(
                    forProposedX: proposedX,
                    videoWidth: Double(videoSize.width),
                    cardWidth: Double(size.width)
                )
                if snap.didSnap, positionHorizontal != 0.5 {
                    NSHapticFeedbackManager.defaultPerformer
                        .perform(.alignment, performanceTime: .drawCompleted)
                }
                positionHorizontal = snap.fraction

                let freeHeight = Double(max(0, videoSize.height - size.height - OSCPosition.bottomMargin))
                if freeHeight > 0 {
                    let proposedY = Double(dragOrigin.y + value.translation.height)
                    positionVertical = min(1, max(0, proposedY / freeHeight))
                }
            }
            .onEnded { _ in dragOrigin = nil }
    }
}
