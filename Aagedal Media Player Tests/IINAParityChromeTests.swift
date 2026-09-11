// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import XCTest
@testable import Aagedal_Media_Player

/// Measures the real chrome views rather than their constants: the floating
/// card is located in a rendered bitmap and its stored position is read back
/// through the same `UserDefaults` keys the app writes.
@MainActor
final class IINAParityChromeTests: XCTestCase {
    private static let hostWidth: CGFloat = 1000
    private static let hostHeight: CGFloat = 600

    /// The two stored fractions belong to the installed app: `FloatingOSCView`
    /// reads them through `@AppStorage` with no `store:`, which is
    /// `UserDefaults.standard` in `com.aagedal.MediaPlayer` while the test host
    /// runs inside the app. They are saved before every write and restored in
    /// `tearDown`.
    private nonisolated(unsafe) static var savedPositionHorizontal: Any?
    private nonisolated(unsafe) static var savedPositionVertical: Any?

    override func setUp() {
        super.setUp()
        Self.capturePositionKeys()
    }

    override func tearDown() {
        Self.restorePositionKeys()
        super.tearDown()
    }

    func testComposedChromeWritesItsRenderingEvidence() throws {
        // The evidence root of this change set; an override keeps the helper
        // usable from a different checkout.
        let configured = ProcessInfo.processInfo.environment["CHROME_EVIDENCE_DIR"]
        let directory = URL(fileURLWithPath: configured.flatMap { $0.isEmpty ? nil : $0 }
            ?? "/Users/filip/.omo/evidence/amp-iina-parity-continuation/chrome")

        let written = try writeChromeEvidence(to: directory)
        XCTAssertEqual(written.count, 2)
        for url in written {
            let size = try XCTUnwrap(
                FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
            )
            XCTAssertGreaterThan(size, 10_000, "\(url.lastPathComponent) is not a rendered chrome image.")
            let image = try XCTUnwrap(NSImage(contentsOf: url))
            XCTAssertEqual(image.size.width, Self.hostWidth * (url.lastPathComponent.contains("2x") ? 2 : 1))
        }
    }

    // MARK: - Card geometry

    func testFloatingCardIsWidthBoundedAndKeepsItsCornerRadius() throws {
        let card = FloatingOSCView(controller: try makeLoadedController(),
                                   onShowPlaylist: {}, onShowSettings: {})

        // 1000 - 16 stays above the 460 pt ceiling, so the card is exactly 460.
        let wide = try render(card, width: Self.hostWidth, height: Self.hostHeight)
        let wideTop = try cardTopEdge(wide)
        XCTAssertEqual(try run(wide, row: wideTop + 12, threshold: 240).count, 460,
                       "The card must be capped at its 460 pt width on a wide host.")
        XCTAssertEqual(try run(wide, row: wideTop + 60, threshold: 240).count, 460,
                       "The card keeps its capped width through its body.")

        // The rounded corner is measured six points below the top edge: a 12 pt
        // radius leaves 460 - 4 there, a 6 pt radius only 460 - 8. Scoped to
        // macOS 26+ because that is the corner the app draws for this host.
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) {
            let corner = try run(wide, row: wideTop + 6, threshold: 240).count
            XCTAssertEqual(Double(corner), 456, accuracy: 4,
                           "macOS 26+ renders the card's 12 pt corner.")
        }

        // 210 - 16 is below the 200 pt floor, so the floor wins: exactly 200 pt.
        // A 220 pt host would give 204, which is why this host is 210.
        let narrow = try render(card, width: 209, height: Self.hostHeight)
        let narrowTop = try cardTopEdge(narrow)
        XCTAssertEqual(try run(narrow, row: narrowTop + 12, threshold: 240).count, 200,
                       "The card must not shrink below its 200 pt floor.")
        XCTAssertEqual(try run(narrow, row: narrowTop + 60, threshold: 240).count, 200,
                       "The clamped card keeps its 200 pt floor through its body.")
    }

    // MARK: - Stored position

    func testFloatingCardOriginFollowsTheStoredHorizontalFraction() throws {
        let card = FloatingOSCView(controller: try makeLoadedController(),
                                   onShowPlaylist: {}, onShowSettings: {})
        // The card is 460 wide inside a 1000 pt host, so it has 540 pt of travel.
        let travel = Self.hostWidth - 460

        for fraction in [0.0, 0.5, 1.0] {
            UserDefaults.standard.set(fraction, forKey: AppSettings.controlBarPositionHorizontal.key)
            UserDefaults.standard.set(AppSettings.controlBarPositionVertical.defaultValue,
                                      forKey: AppSettings.controlBarPositionVertical.key)
            AppSettings.registerDefaults(in: .standard)

            let image = try render(card, width: Self.hostWidth, height: Self.hostHeight)
            let row = try cardTopEdge(image) + 60
            let span = try run(image, row: row, threshold: 240)
            XCTAssertEqual(span.count, 460,
                           "The card must keep its width at fraction \(fraction).")
            XCTAssertEqual(CGFloat(span.start), travel * CGFloat(fraction), accuracy: 2,
                           "Stored fraction \(fraction) must place the card at its stored x-origin.")
        }
    }

    // MARK: - Rendering evidence

    /// Writes the composed ordinary-playback chrome to `directory` at 1x and 2x
    /// for the visual evidence of todo 10. Rendering happens in-process, so the
    /// images need no screen-recording grant.
    @discardableResult
    func writeChromeEvidence(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = ChromeEvidenceComposition(
            controller: try makeLoadedController(),
            siblings: ["source-a.mov", "source-b.mov", "relative-a.mov"]
                .map { directory.appending(path: $0) },
            currentIndex: 0
        )

        var written: [URL] = []
        for scale: CGFloat in [1, 2] {
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: Self.hostWidth, height: Self.hostHeight)
            renderer.scale = scale
            guard let image = renderer.cgImage else {
                throw ChromeEvidenceError.renderFailed(scale: scale)
            }
            let url = directory.appending(path: "chrome-\(Int(scale))x.png")
            try write(image, to: url)
            written.append(url)
        }
        return written
    }

    enum ChromeEvidenceError: Error {
        case renderFailed(scale: CGFloat)
    }

    private struct ChromeEvidenceComposition: View {
        let controller: PlayerController
        let siblings: [URL]
        let currentIndex: Int?

        var body: some View {
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [Color(white: 0.12), Color(white: 0.22), Color(white: 0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(siblings.enumerated()), id: \.element) { index, url in
                            HStack(spacing: 6) {
                                Text(index == currentIndex ? "▶" : "▪")
                                    .font(.system(size: 10))
                                    .foregroundStyle(index == currentIndex ? Color.accentColor : .secondary)
                                    .frame(width: 14)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .fontWeight(index == currentIndex ? .semibold : .regular)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(height: 30)
                            .padding(.horizontal, 8)
                            .background(index == currentIndex ? Color.accentColor.opacity(0.18) : .clear)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: 220)
                    .background(Color.black.opacity(0.35))
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    FloatingOSCView(controller: controller, onShowPlaylist: {}, onShowSettings: {})
                        .frame(height: 120)
                }
            }
        }
    }

    // MARK: - Fixtures

    private func makeLoadedController() throws -> PlayerController {
        let url = try fixtureURL()
        let controller = PlayerController()
        var item = PlayerWindowCoordinator.makeMediaItem(for: url)
        item.durationSeconds = 12
        item.hasVideoStream = true
        controller.loadMedia(item)
        return controller
    }

    private func fixtureURL() throws -> URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        let repository = sourceFile.deletingLastPathComponent().deletingLastPathComponent()
        let url = repository.appending(path: "Test Fixtures/Generated/compare/source-a.mov")
        // Fail, never skip: the fixture tree is generated by
        // scripts/generate-test-fixtures.sh and these assertions are the reason
        // it exists.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "Compare fixtures are unavailable: \(url.path)")
        return url
    }

    // MARK: - Bitmap helpers

    private struct Span {
        let start: Int
        let end: Int
        var count: Int { end - start + 1 }
    }

    private struct InkBounds {
        let left: Int
        let top: Int
        let bottom: Int
        let width: Int
    }

    private func render(_ view: some View, width: CGFloat, height: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return try XCTUnwrap(renderer.cgImage, "ImageRenderer produced no image.")
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let representation = NSBitmapImageRep(cgImage: image)
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    /// Copies the render into a known sRGB RGBA layout. `NSBitmapImageRep`
    /// colour access can apply a display profile, so the bytes are read through
    /// an explicitly tagged context instead.
    private func bytes(of image: CGImage) throws -> (data: [UInt8], width: Int, height: Int, stride: Int) {
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

    private func alpha(_ data: [UInt8], x: Int, y: Int, stride: Int) -> Int {
        Int(data[y * stride + x * 4 + 3])
    }

    private func run(_ image: CGImage, row: Int, threshold: Int) throws -> Span {
        let (data, width, height, stride) = try bytes(of: image)
        XCTAssertTrue((0..<height).contains(row), "Row \(row) is outside the \(height) pt render.")
        var start = -1
        var end = -1
        for x in 0..<width where alpha(data, x: x, y: row, stride: stride) > threshold {
            if start < 0 { start = x }
            end = x
        }
        XCTAssertGreaterThanOrEqual(start, 0, "Nothing was drawn on row \(row).")
        return Span(start: start, end: end)
    }

    /// The card's first fully opaque row. The shadow under the card is opaque
    /// too, so the top edge is the first row whose opaque run reaches the card's
    /// own width rather than the wider shadow silhouette.
    private func cardTopEdge(_ image: CGImage) throws -> Int {
        let (data, width, height, stride) = try bytes(of: image)
        var widest = 0
        var perRow = [Int](repeating: 0, count: height)
        for y in 0..<height {
            var start = -1
            var end = -1
            for x in 0..<width where alpha(data, x: x, y: y, stride: stride) > 240 {
                if start < 0 { start = x }
                end = x
            }
            perRow[y] = end < 0 ? 0 : end - start + 1
            widest = max(widest, perRow[y])
        }
        XCTAssertGreaterThan(widest, 150, "No card was rendered.")
        return perRow.firstIndex(where: { $0 >= widest - 1 }) ?? -1
    }

    private func inkBounds(_ image: CGImage, threshold: Double) throws -> InkBounds {
        let (data, width, height, stride) = try bytes(of: image)
        var left = -1
        var right = -1
        var top = -1
        var bottom = -1
        for y in 0..<height {
            for x in 0..<width where luminance(data, x: x, y: y, stride: stride) > threshold {
                if left < 0 || x < left { left = x }
                if right < 0 || x > right { right = x }
                if top < 0 { top = y }
                bottom = y
            }
        }
        XCTAssertGreaterThanOrEqual(top, 0, "No text was drawn.")
        return InkBounds(left: left, top: top, bottom: bottom, width: right - left + 1)
    }

    /// Bounding box of the pixels that differ between two renders of the same
    /// size, which isolates a drawn subject from its unchanging background.
    private func differenceBounds(
        _ first: CGImage, _ second: CGImage, channelTolerance: Int
    ) throws -> InkBounds {
        let (a, width, height, strideA) = try bytes(of: first)
        let (b, otherWidth, otherHeight, strideB) = try bytes(of: second)
        XCTAssertEqual(width, otherWidth)
        XCTAssertEqual(height, otherHeight)
        var left = -1
        var right = -1
        var top = -1
        var bottom = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = y * strideA + x * 4
                let j = y * strideB + x * 4
                let change = abs(Int(a[i]) - Int(b[j]))
                    + abs(Int(a[i + 1]) - Int(b[j + 1]))
                    + abs(Int(a[i + 2]) - Int(b[j + 2]))
                guard change > channelTolerance else { continue }
                if left < 0 || x < left { left = x }
                if right < 0 || x > right { right = x }
                if top < 0 { top = y }
                bottom = y
            }
        }
        XCTAssertGreaterThanOrEqual(top, 0, "The subject drew nothing.")
        return InkBounds(left: left, top: top, bottom: bottom, width: right - left + 1)
    }

    private func luminance(_ data: [UInt8], x: Int, y: Int, stride: Int) -> Double {
        let index = y * stride + x * 4
        return 0.2126 * Double(data[index]) / 255
            + 0.7152 * Double(data[index + 1]) / 255
            + 0.0722 * Double(data[index + 2]) / 255
    }

    // MARK: - Defaults isolation

    private nonisolated static func capturePositionKeys() {
        savedPositionHorizontal = UserDefaults.standard
            .object(forKey: AppSettings.controlBarPositionHorizontal.key)
        savedPositionVertical = UserDefaults.standard
            .object(forKey: AppSettings.controlBarPositionVertical.key)
    }

    private nonisolated static func restorePositionKeys() {
        restore(savedPositionHorizontal, forKey: AppSettings.controlBarPositionHorizontal.key)
        restore(savedPositionVertical, forKey: AppSettings.controlBarPositionVertical.key)
    }

    private nonisolated static func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
