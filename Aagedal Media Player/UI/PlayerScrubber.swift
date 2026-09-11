// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// The player-chrome scrubber: IINA's slim bar and 3x15 knob, with chapter
/// diamonds and a hover thumbnail. The inspection timeline in ControlsView is
/// a separate, far richer control and is untouched by this one.
struct PlayerScrubber: View {
    private static let barHeight: CGFloat = 3
    private static let knobWidth: CGFloat = 3
    private static let knobHeight: CGFloat = 15
    private static let knobRadius: CGFloat = 1
    private static let verticalPadding: CGFloat = 6

    let item: MediaItem?
    let chapters: [TrackSelectionController.ChapterOption]
    let currentTime: Double
    let onScrub: (Double) -> Void

    @StateObject private var thumbnail = TimelineThumbnailLoader()
    @State private var hoverX: CGFloat?
    @State private var isDragging = false

    private var duration: Double { item?.durationSeconds ?? 0 }

    private var progress: Double {
        guard duration > 0, currentTime.isFinite else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let knobX = max(0, min(width - Self.knobWidth, width * progress))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(height: Self.barHeight)

                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: knobX, height: Self.barHeight)

                ChapterTimelineMarkers(
                    chapters: chapters,
                    duration: duration,
                    width: width
                )

                RoundedRectangle(cornerRadius: Self.knobRadius)
                    .fill(.white)
                    .frame(width: Self.knobWidth, height: Self.knobHeight)
                    .offset(x: knobX)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            }
            .frame(height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        seek(toX: value.location.x, width: width)
                    }
                    .onEnded { value in
                        seek(toX: value.location.x, width: width)
                        isDragging = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverX = point.x
                    if let item, duration > 0 {
                        thumbnail.request(item: item, time: time(atX: point.x, width: width))
                    }
                case .ended:
                    hoverX = nil
                    thumbnail.hide()
                }
            }
            .overlay(alignment: .bottom) {
                if let hoverX, let image = thumbnail.image, let previewTime = thumbnail.imageTime {
                    thumbnailPreview(image: image, time: previewTime)
                        .offset(x: previewOffset(hoverX: hoverX, width: width), y: -34)
                }
            }
        }
        .frame(height: Self.knobHeight + Self.verticalPadding * 2)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue(TimecodeFormatter.formatTraditionalTime(currentTime))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onScrub(min(duration, currentTime + 5))
            case .decrement: onScrub(max(0, currentTime - 5))
            @unknown default: break
            }
        }
        .onChange(of: item?.id) { _, _ in
            thumbnail.hide(clearCache: true)
            hoverX = nil
        }
        .onDisappear { thumbnail.hide(clearCache: true) }
    }

    private func time(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, duration > 0 else { return 0 }
        return TimelineViewport(duration: duration).time(at: Double(x / width))
    }

    private func seek(toX x: CGFloat, width: CGFloat) {
        guard duration > 0 else { return }
        onScrub(time(atX: x, width: width))
    }

    /// Keeps the preview inside the card instead of hanging off an edge.
    private func previewOffset(hoverX: CGFloat, width: CGFloat) -> CGFloat {
        let previewWidth: CGFloat = 160
        let half = previewWidth / 2
        return max(half, min(width - half, hoverX)) - half
    }

    private func thumbnailPreview(image: CGImage, time: Double) -> some View {
        VStack(spacing: 2) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(TimecodeFormatter.formatTraditionalTime(time))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(4)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .allowsHitTesting(false)
    }
}
