// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest
@testable import Aagedal_Media_Player

/// Behavioural coverage for the chrome this branch introduced: which control
/// bar the window shows in each mode, the folder sidebar's rows, the stored
/// position of the floating card, and the subtitle the app selects when it
/// opens a file that carries one.
///
/// The views are hosted in a real borderless window and captured from AppKit's
/// display cache, because `ImageRenderer` draws none of the platform-backed
/// chrome (`List`, the material card) - it renders its unsupported-content
/// placeholder instead. The mode switch is then measured against a per-mode
/// reference: the ordinary render against a `FloatingOSCView`-only capture and
/// the comparison render against an `inspectionControls`-only capture. A bare
/// "the two renders differ" check would also pass if the two branches were
/// swapped, which is why each mode has its own expected occupant.
@MainActor
final class PlayerChromeBehaviourTests: XCTestCase {
    private static let hostSize = CGSize(width: 1000, height: 600)

    /// The card writes these through `@AppStorage` with no `store:`, which is
    /// `UserDefaults.standard` in the installed app's domain while this test
    /// host runs inside it (`com.aagedal.MediaPlayer`). They are saved before
    /// every write and restored in `tearDown`.
    private nonisolated(unsafe) static var savedPositionHorizontal: Any?
    private nonisolated(unsafe) static var savedPositionVertical: Any?
    private nonisolated(unsafe) static var savedOpenAtSourceResolution: Any?

    override func setUp() {
        super.setUp()
        Self.capturePositionKeys()
    }

    override func tearDown() {
        Self.restorePositionKeys()
        super.tearDown()
    }

    // MARK: - Mode switch

    func testTheWindowShowsTheCardWithoutASessionAndTheInspectionBarWithOne() async throws {
        let fixtures = try fixtureDirectory()
        let primary = PlayerController()
        var item = PlayerWindowCoordinator.makeMediaItem(for: fixtures.appending(path: "compare/source-a.mov"))
        item.durationSeconds = 12
        item.hasVideoStream = true
        primary.loadMedia(item)

        let session = CompareSessionController()
        let content = ContentView(controller: primary, compareSession: session)
        let window = HostedChrome(content, size: Self.hostSize)
        defer {
            window.close()
            session.stop()
            primary.teardown()
        }
        try await window.settle()
        let size = Self.hostSize

        // References for the two possible occupants of the window's bottom edge.
        // Each is hosted the way the window hosts it - one component anchored
        // to the bottom edge of the same sized window - so the comparison is
        // between the same layout, not between a bar and its own root view.
        let cardWindow = HostedChrome(
            BottomAnchored {
                FloatingOSCView(controller: primary, onShowPlaylist: {}, onShowSettings: {})
                    .frame(height: 120)
            },
            size: size
        )
        defer { cardWindow.close() }
        try await cardWindow.settle()
        let cardReference = try cardWindow.capture(at: size).chromeWidth()

        let barWindow = HostedChrome(BottomAnchored { content.inspectionControls }, size: size)
        defer { barWindow.close() }
        try await barWindow.settle()
        let barReference = try barWindow.capture(at: size).chromeWidth()
        XCTAssertGreaterThan(barReference, cardReference + 100,
                             "The two reference components must be distinguishable by width.")

        // No session: the window's bottom edge carries the floating card.
        let ordinary = try window.capture(at: size).chromeWidth()
        XCTAssertEqual(ordinary, cardReference, accuracy: 6,
                       "Ordinary playback must draw the floating card.")

        // Active session: the same window must carry the inspection bar instead.
        session.loadSecondary(fixtures.appending(path: "compare/source-b.mov"), alignedWith: primary)
        let activated = await waitUntil { session.isActive }
        XCTAssertTrue(activated, "The comparison session never activated.")

        try await window.settle()
        let comparing = try window.capture(at: size).chromeWidth()
        XCTAssertEqual(comparing, barReference, accuracy: 12,
                       "Compare Mode must draw the inspection bar.")
        XCTAssertGreaterThan(comparing, cardReference + 100,
                             "Compare Mode must not draw the floating card.")
    }

    // MARK: - Sidebar

    func testThePlaylistSidebarRendersOneRowPerFileAndMarksTheCurrentOne() async throws {
        let urls = ["alpha.mov", "beta.mov", "gamma.mov"].map { URL(fileURLWithPath: "/tmp/\($0)") }

        for currentIndex in [0, 1, 2] {
            let sidebar = PlaylistSidebarView(
                urls: urls, currentIndex: currentIndex, onSelect: { _ in }
            )
            let window = HostedChrome(sidebar, size: CGSize(width: 320, height: 400))
            defer { window.close() }
            try await window.settle()
            let capture = try window.capture(at: CGSize(width: 320, height: 400))

            let rows = try capture.contentRows()
            XCTAssertEqual(rows.count, urls.count,
                           "The sidebar must render one row per supplied file (index \(currentIndex)).")
            let marked = try rows.enumerated().filter { try capture.rowHasAccentInk($0.element) }
            XCTAssertEqual(marked.count, 1,
                           "Exactly one row carries the accent marking (index \(currentIndex)).")
            XCTAssertEqual(marked.first?.offset, currentIndex,
                           "The marked row must be the one at currentIndex.")
        }
    }

    // MARK: - Stored position

    func testTheStoredCardPositionRoundTripsThroughTheSettingsKeys() {
        let videoSize = Self.hostSize
        let cardSize = CGSize(width: 460, height: 67)

        for (horizontal, vertical) in [(0.0, 0.0), (0.25, 0.5), (1.0, 1.0)] {
            UserDefaults.standard.set(horizontal, forKey: AppSettings.controlBarPositionHorizontal.key)
            UserDefaults.standard.set(vertical, forKey: AppSettings.controlBarPositionVertical.key)
            AppSettings.registerDefaults(in: .standard)

            let stored = OSCPosition(
                horizontal: UserDefaults.standard.double(forKey: AppSettings.controlBarPositionHorizontal.key),
                vertical: UserDefaults.standard.double(forKey: AppSettings.controlBarPositionVertical.key)
            )
            XCTAssertEqual(stored.horizontal, horizontal, accuracy: 0.0001)
            XCTAssertEqual(stored.vertical, vertical, accuracy: 0.0001)

            let origin = stored.origin(in: videoSize, cardSize: cardSize)
            XCTAssertEqual(origin.x, (videoSize.width - cardSize.width) * CGFloat(horizontal), accuracy: 0.5)
            XCTAssertEqual(
                origin.y,
                (videoSize.height - cardSize.height - OSCPosition.bottomMargin) * CGFloat(vertical),
                accuracy: 0.5
            )
        }
    }

    // MARK: - Subtitles

    func testAutoSelectSubtitlesIsRegisteredAndDefaultsToTrue() throws {
        XCTAssertTrue(AppSettings.autoSelectSubtitles.defaultValue,
                      "Ordinary viewing must ask mpv for the file's own subtitles.")

        let suiteName = "PlayerChromeBehaviourTests.subtitleDefaults"
        let probe = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        probe.removePersistentDomain(forName: suiteName)
        AppSettings.registerDefaults(in: probe)
        XCTAssertEqual(probe.object(forKey: AppSettings.autoSelectSubtitles.key) as? Bool, true)
        probe.removePersistentDomain(forName: suiteName)
    }

    func testOpeningAFileWithASubtitleTrackSelectsItAtRuntime() async throws {
        let url = try fixtureDirectory().appending(path: "chapters-subtitles-long-gop.mkv")
        let controller = PlayerController(proResRAWDetector: { _, _ in false })
        var item = PlayerWindowCoordinator.makeMediaItem(for: url)
        item.durationSeconds = 5
        item.hasVideoStream = true
        controller.loadMedia(item)
        defer { controller.teardown() }

        let mounted = await waitUntil { controller.mpvPlayer != nil }
        XCTAssertTrue(mounted, "The MPV backend was never constructed for the subtitle fixture.")
        let mpv = try XCTUnwrap(controller.mpvPlayer)

        // mpv reports a selected track once it has a video output, so the probe
        // attaches the same disposable layer the live-backend tests use.
        let layer = MPVMetalLayer()
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        layer.drawableSize = CGSize(width: 320, height: 180)
        mpv.attachDrawable(layer)

        let selected = await waitUntil(timeout: 30) { mpv.currentSubtitleTrackIndex > 0 }
        XCTAssertTrue(selected,
                      "The generated subtitle fixture must select its own subtitle track, "
                      + "not stay at sid=\(mpv.currentSubtitleTrackIndex).")
    }

    // MARK: - Dropped URLs

    func testTheDroppedURLSplitSeparatesSubtitlesFromMedia() {
        let mixed = ["clip.mp4", "subs.srt", "captions.ass", "SHOUTING.SRT", "notes.txt"]
            .map { URL(fileURLWithPath: "/tmp/drop/\($0)") }

        let split = PlayerWindowCoordinator.splitDroppedURLs(mixed)
        XCTAssertEqual(split.subtitles.map(\.lastPathComponent),
                       ["subs.srt", "captions.ass", "SHOUTING.SRT"])
        XCTAssertEqual(split.media.map(\.lastPathComponent), ["clip.mp4", "notes.txt"])

        let subtitlesOnly = ["one.srt", "two.ass"].map { URL(fileURLWithPath: "/tmp/drop/\($0)") }
        XCTAssertEqual(PlayerWindowCoordinator.splitDroppedURLs(subtitlesOnly).media, [])
        XCTAssertEqual(PlayerWindowCoordinator.splitDroppedURLs(subtitlesOnly).subtitles.count, 2)

        let mediaOnly = ["one.mov", "two.mp4"].map { URL(fileURLWithPath: "/tmp/drop/\($0)") }
        XCTAssertEqual(PlayerWindowCoordinator.splitDroppedURLs(mediaOnly).subtitles, [])
        XCTAssertEqual(PlayerWindowCoordinator.splitDroppedURLs(mediaOnly).media.count, 2)
    }

    // MARK: - Fixtures

    private func fixtureDirectory() throws -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository.appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        let manifest = directory.appending(path: "MANIFEST.txt")
        let contents = try? String(contentsOf: manifest, encoding: .utf8)
        XCTAssertTrue(contents?.split(whereSeparator: \.isNewline).contains("schema=5") == true,
                      "The schema=5 fixture tree is unavailable: run scripts/generate-test-fixtures.sh")
        return directory
    }

    private func waitUntil(
        timeout: TimeInterval = 20,
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    // MARK: - Defaults isolation

    private nonisolated static func capturePositionKeys() {
        savedPositionHorizontal = UserDefaults.standard
            .object(forKey: AppSettings.controlBarPositionHorizontal.key)
        savedPositionVertical = UserDefaults.standard
            .object(forKey: AppSettings.controlBarPositionVertical.key)
        savedOpenAtSourceResolution = UserDefaults.standard
            .object(forKey: AppSettings.openAtSourceResolution.key)
        // The window configurator would otherwise resize the hosting window to
        // the 320x180 fixture clip, leaving the chrome no room to differ.
        UserDefaults.standard.set(false, forKey: AppSettings.openAtSourceResolution.key)
    }

    private nonisolated static func restorePositionKeys() {
        restore(savedPositionHorizontal, forKey: AppSettings.controlBarPositionHorizontal.key)
        restore(savedPositionVertical, forKey: AppSettings.controlBarPositionVertical.key)
        restore(savedOpenAtSourceResolution, forKey: AppSettings.openAtSourceResolution.key)
    }

    private nonisolated static func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

/// The window's own overlay container: a component pinned to the bottom edge
/// of the full-size window, which is the layout both modes share.
private struct BottomAnchored<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
        }
    }
}

// MARK: - Hosted capture

/// One SwiftUI view hosted in a borderless window and captured through AppKit's
/// display cache, so platform-backed subviews are drawn.
@MainActor
private final class HostedChrome {
    private let window: NSWindow
    private let container = NSView(frame: .zero)
    private let hosting: NSHostingView<AnyView>

    init(_ view: some View, size: CGSize) {
        hosting = NSHostingView(rootView: AnyView(view))
        // Both of these keep the hosting view from resizing the window to its
        // content's fitting size: the chrome has to be measured at a size both
        // modes share, not at a height the view picks for itself.
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        // A plain container is the window's content view so the hosting view's
        // own sizing can never drive the window frame.
        container.frame = CGRect(origin: .zero, size: size)
        container.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = container
        hosting.layoutSubtreeIfNeeded()
    }

    func close() {
        window.contentView = nil
        window.close()
    }

    /// Gives SwiftUI the run-loop turns it needs to lay out and draw.
    func settle() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
        window.displayIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        hosting.layoutSubtreeIfNeeded()
    }

    /// Pins the window to `size` and reads it back without yielding to the run
    /// loop: the window configurator resizes the host window to the loaded
    /// media on its own next pass, and the chrome has to be measured at a size
    /// the two modes share.
    func capture(at size: CGSize) throws -> ChromeCapture {
        // Pinned at the AppKit level: the configurator's aspect ratio and a
        // view's own fitting size would otherwise each resize the window, and
        // both modes have to be measured at one shared size.
        window.contentAspectRatio = .zero
        window.contentMinSize = size
        window.contentMaxSize = size
        window.setContentSize(size)
        window.displayIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(hosting.bounds.width, size.width, accuracy: 1,
                       "The hosting window did not keep the size the chrome is measured at: "
                       + "\(window.frame) \(hosting.fittingSize) \(window.contentMinSize) \(window.contentMaxSize)")
        XCTAssertEqual(hosting.bounds.height, size.height, accuracy: 1,
                       "The hosting window did not keep the size the chrome is measured at: "
                       + "\(window.frame) \(hosting.fittingSize) \(window.contentMinSize) \(window.contentMaxSize)")

        let representation = try XCTUnwrap(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds),
            "AppKit produced no display cache for the hosted view."
        )
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        let image = try XCTUnwrap(representation.cgImage, "The display cache held no image.")
        return ChromeCapture(image: image, size: hosting.bounds.size)
    }
}

/// A captured window content image with its size in points.
private struct ChromeCapture {
    let image: CGImage
    let size: CGSize

    /// The player's own background is pure black, so any pixel above the black
    /// floor belongs to a control surface, its border or its content.
    private static let blackFloor = 0.02
    /// Antialiasing can leave a one-pixel gap inside a drawn surface.
    private static let gapTolerance = 2

    /// The widest drawn run in the bottom 45 % of the window, in points. This is
    /// the silhouette of whichever control bar occupies that edge.
    func chromeWidth() throws -> CGFloat {
        let (data, width, height, stride) = try bytes()
        var widest = 0
        for y in (height * 55 / 100)..<height {
            var runStart = -1
            var lastInk = -1
            for x in 0..<width where luminance(data, x: x, y: y, stride: stride) > Self.blackFloor {
                if runStart >= 0 && x - lastInk > Self.gapTolerance {
                    widest = max(widest, lastInk - runStart + 1)
                    runStart = x
                }
                if runStart < 0 { runStart = x }
                lastInk = x
            }
            if runStart >= 0 { widest = max(widest, lastInk - runStart + 1) }
        }
        XCTAssertGreaterThan(widest, 0, "No chrome was drawn in the bottom of the window.")
        return CGFloat(widest) / scale
    }

    /// One band per sidebar row: rows of text ink, with the gaps a glyph's own
    /// shape leaves inside a row closed up. The band count is the row count.
    func contentRows() throws -> [Band] {
        let (data, width, height, stride) = try bytes()
        var samples = [Double]()
        samples.reserveCapacity(width * height)
        for y in 0..<height {
            for x in 0..<width {
                samples.append(luminance(data, x: x, y: y, stride: stride))
            }
        }
        samples.sort()
        let background = samples[samples.count / 2]

        // Text ink is bright and dense; row separators are faint and sparse by
        // comparison, so they stay below the floor.
        let inkFloor = Int(20 * min(scale, 2) * min(scale, 2))
        let mergeGap = Int(10 * min(scale, 2))

        var rows = [Band]()
        var open: Band?
        for y in 0..<height {
            var ink = 0
            for x in 0..<width where abs(luminance(data, x: x, y: y, stride: stride) - background) > 0.15 {
                ink += 1
            }
            guard ink >= inkFloor else { continue }
            if let current = open, y - current.last <= mergeGap {
                open = Band(first: current.first, last: y)
            } else {
                if let current = open { rows.append(current) }
                open = Band(first: y, last: y)
            }
        }
        if let current = open { rows.append(current) }
        return rows
    }

    /// True when the row holds accent-coloured ink: the row at `currentIndex`
    /// draws a `play.fill` glyph in the system accent colour while every other
    /// row uses the neutral `film` glyph and plain primary text.
    func rowHasAccentInk(_ row: Band) throws -> Bool {
        let (data, width, _, stride) = try bytes()
        for y in row.first...row.last {
            for x in 0..<width {
                let index = y * stride + x * 4
                let channels = [Int(data[index]), Int(data[index + 1]), Int(data[index + 2])]
                guard let high = channels.max(), let low = channels.min() else { continue }
                if high - low > 25 && high > 60 { return true }
            }
        }
        return false
    }

    private var scale: CGFloat {
        let ratio = CGFloat(image.width) / max(size.width, 1)
        return ratio > 0 ? ratio : 1
    }

    private func bytes() throws -> (data: [UInt8], width: Int, height: Int, stride: Int) {
        let width = image.width
        let height = image.height
        let stride = width * 4
        var data = [UInt8](repeating: 0, count: stride * height)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: stride, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (data, width, height, stride)
    }

    private func luminance(_ data: [UInt8], x: Int, y: Int, stride: Int) -> Double {
        let index = y * stride + x * 4
        return 0.2126 * Double(data[index]) / 255
            + 0.7152 * Double(data[index + 1]) / 255
            + 0.0722 * Double(data[index + 2]) / 255
    }
}

private struct Band {
    let first: Int
    let last: Int
}
