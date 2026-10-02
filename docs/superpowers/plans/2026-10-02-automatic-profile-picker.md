# Automatic Profile Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a file opens, amp picks the shader profile that fits the file's real quality and the GPU budget, with no prompt, and shows the choice in the badge as `Auto · <profile> · <reason>`.

**Architecture:** Pure value types (`SourceFacts`, `FrameStats`, `SourceClassifier`, `ProfilePicker`, `AutomaticSelection`) decide; an actor (`FrameAnalyzer`) measures eight luma frames with the bundled ffmpeg; `MPVPlayer` only gathers facts, applies the returned profile and steps down on GPU budget reports. `RenderProfile.automatic` becomes the app-wide default and replaces the Enhance toggle and the `RenderTier` ladder.

**Tech Stack:** Swift 6 (default MainActor isolation, pure types `nonisolated`), SwiftUI, Accelerate (vDSP), OSLog, bundled ffmpeg, MPVKit (mpv 0.41.0), XCTest and Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-02-automatic-profile-picker-design.md`

## Global Constraints

- Repo `/Users/filip/src/amp`, macOS 26 app. Both `Aagedal Media Player/` and `Aagedal Media Player Tests/` are Xcode file-system-synchronized groups: new `.swift` files there are compiled with no `project.pbxproj` edit.
- Every Swift file starts with `// Aagedal Media Player`, `// Copyright © 2026 Truls Aagedal`, `// SPDX-License-Identifier: GPL-3.0-or-later`. Logging: `Logger(subsystem: "com.aagedal.MediaPlayer", category: "<type name>")`.
- App target default isolation is MainActor, so pure value types and helpers are declared `nonisolated` (the test target is not MainActor by default).
- Budget: a profile fits when its estimated cost is at most 0.8 x the frame period (`ProfilePicker.budgetFraction = 0.8`). Cost reference: amp.app fullscreen, drawable 3448x1940, M1 Pro. Costs in ms per frame, 720p source / 1080p source: chroma 7.0/8.6, efficient 10.9/18.5, sharpen 11.7/11.7, upscaleLight 15.4/31.0, compressed 16.1/33.0, crisp 21.3/37.0. Not measured at both sizes, so left out of every chain: upscaleStrong (64.6 ms at 720p only), compressedGrain (1080p only), restore.
- Frame rate split: at most 30 fps uses the first column of the spec's mapping table, above 30 fps (16.7 ms frame at 60) the second.
- Analysis: 8 gray frames spread evenly, skipping the first and last 5 % of the file; files shorter than 2 s and analyses taking more than 5 s keep the metadata-only pick; results cached in memory by path, size and modification date.
- HDR (PQ/HLG) always stays Faithful. Topaz output (`videoai` or `videoai_provider` tag) never gets denoise/sharpen profiles.
- Test command (substitute the suite):
  `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/<Suite>"`
  The full suite takes about 10 minutes; `CompareLiveBackendTests` is known to be flaky under load. Run the full suite only in Task 8.
- Commits: `git add` the listed paths only (never `.omc/`), then `git commit -m "<message>"`. No attribution lines, no co-author trailer.
- On-device checks run only in `/Applications/amp.app`, never a standalone mpv.

---

## Verified facts this plan relies on

Each was checked against the real source, the real binary, or the upstream docs on 2026-10-02.

- **SwiftMediaMetadata does not expose arbitrary container or stream tags.** `MediaMetadata` (`Aagedal Media Player/Models/MediaMetadata.swift`) carries `comment` and `encoder: nil`; `VideoMetadata`/`VideoStream` in the package have no tag dictionary and no `videoai` string exists anywhere in the package or the app. So Topaz tags are read two other ways: mpv's `metadata/by-key/<key>` (container tags, immediate) and `ffmpeg -i` stderr (container and stream tags, in the analyzer). Both were run: MP4 keeps a custom container tag only with `-movflags +use_metadata_tags`; Matroska keeps stream tags and prints the key upper-case (`VIDEOAI_PROVIDER: Topaz`).
- **Bundled ffmpeg** (`Aagedal Media Player/Binaries/ffmpeg`): `-encoders` lists `pgm` and `rawvideo`, `-muxers` lists `image2pipe`, `-decoders` lists h264, hevc, prores, vp9, av1. `-ss <t> -i <file> -frames:v 1 -an -sn -pix_fmt gray -f image2pipe -c:v pgm -` writes `P5\n<w> <h>\n255\n` plus w x h bytes (1280x720 gave 921616 bytes). Using PGM means the output carries its own dimensions, so rotation and pixel aspect ratio need no separate bookkeeping.
- **`FFmpegService`** (`Logic/FFmpegService.swift`) is MainActor-isolated by default isolation: `static var ffmpegPath: String?` needs `await` from a nonisolated context. `static func runStreamingOutput(arguments: [String], onStandardOutputData: @escaping @Sendable (Data) -> Void) async throws` throws `FFmpegError.processFailed(String)` on a non-zero exit and `FFmpegError.cancelled` on cancellation. `SubprocessService.run(executableURL:arguments:outputLimit:standardOutputLimit:handle:onStandardOutputData:onStandardOutputLine:) async throws -> SubprocessResult` is `nonisolated`; its `standardError` keeps a bounded tail (`outputLimit`).
- **mpv 0.41.0 properties** (DOCS/man/input.rst at tag v0.41.0): `metadata/by-key/<key>`, `file-size` (bytes), `path`, `duration`, `container-fps`, `video-bitrate` (per-keyframe estimate, may be empty early), `frame-drop-count`, `vo-passes`, `video-params/gamma`, `video-params/pixelformat`, `video-params/hw-pixelformat`, `current-tracks/video/codec` (redirects to `track-list/N/codec`).
- **Accelerate**: `vDSP_vfltu8`, `vDSP_vsub`, `vDSP_vabs`, `vDSP_sve` are used in `FrameMath` and compiled and ran under Swift 6.4 in a scratch package with default MainActor isolation.
- **Test fixtures**: `Test Fixtures/Generated/` is git-ignored and `CompareLiveBackendTests` requires `schema=5` in its `MANIFEST.txt`, so this plan adds fixtures without changing the schema line.
- **Persistence**: `SettingsMigration` (`Logic/SettingsMigration.swift`) has `currentVersion = 1` and this machine's `com.aagedal.MediaPlayer` domain has `settingsVersion = 1`, so a version 1 to 2 step runs here. The earlier "faithful by default" `AppSettings.renderProfile` default changes to automatic at the user's request.
- **Test hosts**: `UserDefaults(suiteName:)` instances see defaults the app registered in the process, so a migration test must read what the suite itself stored (`persistentDomain(forName:)`), not `object(forKey:)`.

## Starting thresholds (replaced in Task 7 by the calibration the user approves)

Measured on 2026-10-02 with `FrameMath` on real frames, one 1080p H.264 frame: native 0.609 detail ratio, the same frame through a 2x down/up round trip 0.471; one 720p ProRes frame 0.661 native, 0.458 after the round trip. Blockiness on real frames was 1.06 to 1.42; a synthetic 8x8 block pattern gave 15. So the starting values are bits per pixel 0.05, blockiness 1.6, soft detail ratio 0.54. The `noise` statistic is computed and logged but no class uses it.

## Task map

1. SourceFacts, FrameStats, SourceClass, SourceClassifier
2. ProfilePicker with the cost table and fallback chains
3. FrameMath, FrameAnalyzer (ffmpeg frame extraction, cache) and fixtures
4. `RenderProfile.automatic`, default, settings migration
5. AutomaticSelection state machine
6. MPVPlayer wiring, Enhance and tier-ladder removal, badge, Settings UI
7. Calibration script, approved thresholds, on-device verification
8. Documentation and full-suite run

---

## Task 1: Classify sources from metadata and frame stats

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/SourceClassifier.swift`
- Test: `Aagedal Media Player Tests/SourceClassifierTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `nonisolated struct SourceFacts: Equatable, Sendable` with `var codec: String?`, `width: Int`, `height: Int`, `fps: Double`, `videoBitrate: Int64`, `bitDepth: Int?`, `isHDR: Bool`, `topazTag: String?`; `var sourcePixels: Double { get }`, `var bitsPerPixel: Double? { get }`, `static func bitDepth(pixelFormat: String?) -> Int?`, `static func topazTag(inFFmpegOutput text: String) -> String?`
  - `nonisolated struct FrameStats: Equatable, Sendable` with `var detailRatio: Double`, `blockiness: Double`, `noise: Double`
  - `nonisolated enum SourceClass: String, CaseIterable, Sendable { case hdr, topaz, compressed, soft, clean }`
  - `nonisolated struct SourceClassification: Equatable, Sendable { let sourceClass: SourceClass; let reason: String }`
  - `SourceClassifier.Thresholds` (`lowBitsPerPixel`, `blockiness`, `softDetailRatio`, `static let calibrated`) and `static func classify(_ facts: SourceFacts, _ stats: FrameStats?, thresholds: SourceClassifier.Thresholds = .calibrated) -> SourceClassification`

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/SourceClassifierTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Testing

struct SourceClassifierTests {
    private let thresholds = SourceClassifier.Thresholds(lowBitsPerPixel: 0.05, blockiness: 1.6, softDetailRatio: 0.54)

    private func facts(
        width: Int = 1920, height: Int = 1080, fps: Double = 25, bitrate: Int64 = 20_000_000,
        isHDR: Bool = false, topazTag: String? = nil
    ) -> SourceFacts {
        SourceFacts(codec: "h264", width: width, height: height, fps: fps, videoBitrate: bitrate,
                    bitDepth: 8, isHDR: isHDR, topazTag: topazTag)
    }

    private let healthy = FrameStats(detailRatio: 0.65, blockiness: 1.1, noise: 0.01)

    @Test func bitsPerPixelIsBitrateOverPixelsPerSecond() throws {
        let value = try #require(facts(width: 1280, height: 720, fps: 25, bitrate: 3_000_000).bitsPerPixel)
        #expect(abs(value - 3_000_000.0 / (1280 * 720 * 25)) < 1e-12)
    }

    @Test func bitsPerPixelNeedsEveryInput() {
        #expect(facts(bitrate: 0).bitsPerPixel == nil)
        #expect(facts(fps: 0).bitsPerPixel == nil)
        #expect(facts(width: 0).bitsPerPixel == nil)
    }

    @Test func hdrWinsOverEverything() {
        let result = SourceClassifier.classify(facts(bitrate: 500_000, isHDR: true, topazTag: "x"), healthy, thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .hdr, reason: "HDR"))
    }

    @Test func topazBeatsCompressedAndSoft() {
        let soft = FrameStats(detailRatio: 0.1, blockiness: 3, noise: 0)
        let result = SourceClassifier.classify(facts(bitrate: 500_000, topazTag: "Proteus"), soft, thresholds: thresholds)
        #expect(result.sourceClass == .topaz)
    }

    @Test func lowBitsPerPixelIsCompressedWithTheBitrateAsReason() {
        // 2.1 Mbit/s at 1920x1080x25 is 0.0405 bits per pixel.
        let result = SourceClassifier.classify(facts(bitrate: 2_100_000), nil, thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .compressed, reason: "2.1 Mbit/s"))
    }

    @Test func blockinessMakesACompressedSourceEvenAtAHighBitrate() {
        let blocky = FrameStats(detailRatio: 0.65, blockiness: 2.0, noise: 0)
        let result = SourceClassifier.classify(facts(), blocky, thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .compressed, reason: "blocky 2.0"))
    }

    @Test func lowDetailIsSoft() {
        let result = SourceClassifier.classify(facts(), FrameStats(detailRatio: 0.40, blockiness: 1.1, noise: 0), thresholds: thresholds)
        #expect(result == SourceClassification(sourceClass: .soft, reason: "soft 0.40"))
    }

    @Test func compressedBeatsSoft() {
        let both = FrameStats(detailRatio: 0.2, blockiness: 2.5, noise: 0)
        #expect(SourceClassifier.classify(facts(), both, thresholds: thresholds).sourceClass == .compressed)
    }

    @Test func everythingElseIsClean() {
        #expect(SourceClassifier.classify(facts(), healthy, thresholds: thresholds).sourceClass == .clean)
    }

    @Test func withoutStatsOnlyMetadataRulesApply() {
        // Soft-looking numbers cannot matter when there are none.
        #expect(SourceClassifier.classify(facts(), nil, thresholds: thresholds).sourceClass == .clean)
        #expect(SourceClassifier.classify(facts(bitrate: 0), nil, thresholds: thresholds).sourceClass == .clean)
    }

    @Test(arguments: [
        ("yuv420p", 8), ("nv12", 8), ("yuv420p10le", 10), ("p010le", 10), ("yuv422p12le", 12),
        ("gbrp16le", 16), ("gray16le", 16), ("yuv444p10", 10),
    ] as [(String, Int)])
    func readsBitDepthFromPixelFormat(format: String, depth: Int) {
        #expect(SourceFacts.bitDepth(pixelFormat: format) == depth)
    }

    @Test func unknownPixelFormatHasNoBitDepth() {
        #expect(SourceFacts.bitDepth(pixelFormat: nil) == nil)
        #expect(SourceFacts.bitDepth(pixelFormat: "") == nil)
    }

    @Test func findsTopazTagsInFFmpegOutput() {
        let container = "  Metadata:\n    encoder         : Lavf\n    videoai         : Enhanced using Proteus v4\n"
        #expect(SourceFacts.topazTag(inFFmpegOutput: container) == "Enhanced using Proteus v4")
        // Matroska prints stream tag keys upper-case.
        #expect(SourceFacts.topazTag(inFFmpegOutput: "    Metadata:\n      VIDEOAI_PROVIDER: Topaz\n") == "Topaz")
        #expect(SourceFacts.topazTag(inFFmpegOutput: "    encoder         : Lavf\n") == nil)
    }
}
```

- [ ] **Step 2: Run it and see it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/SourceClassifierTests"
```

Expected: the test target fails to compile with `error: cannot find 'SourceFacts' in scope` (and the same for `FrameStats`, `SourceClassifier`).

- [ ] **Step 3: Implement**

Create `Aagedal Media Player/Logic/MPV/SourceClassifier.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What amp knows about a file before it looks at any pixels.
nonisolated struct SourceFacts: Equatable, Sendable {
    var codec: String?
    var width: Int = 0
    var height: Int = 0
    var fps: Double = 0
    /// Video stream bitrate in bits per second; 0 when unknown.
    var videoBitrate: Int64 = 0
    var bitDepth: Int?
    var isHDR = false
    /// The text of a `videoai` or `videoai_provider` tag, when the file carries one.
    var topazTag: String?

    var sourcePixels: Double { Double(max(0, width)) * Double(max(0, height)) }

    /// Bits per pixel per frame; nil until bitrate, size and frame rate are all known.
    var bitsPerPixel: Double? {
        guard videoBitrate > 0, width > 0, height > 0, fps > 0 else { return nil }
        return Double(videoBitrate) / (Double(width) * Double(height) * fps)
    }

    /// Bit depth from an mpv or ffmpeg pixel format name such as `yuv420p10le`.
    static func bitDepth(pixelFormat: String?) -> Int? {
        guard let format = pixelFormat?.lowercased(), !format.isEmpty else { return nil }
        for (token, depth) in [("p010", 10), ("p210", 10), ("p410", 10), ("p016", 16), ("p216", 16), ("p416", 16)]
        where format.contains(token) {
            return depth
        }
        for depth in [16, 14, 12, 10, 9] where format.contains("p\(depth)") || format.contains("\(depth)le") || format.contains("\(depth)be") {
            return depth
        }
        return 8
    }

    /// The value of a `videoai` or `videoai_provider` tag in `ffmpeg -i` output.
    /// ffmpeg prints tags as `    key   : value`; Matroska upper-cases the key.
    static func topazTag(inFFmpegOutput text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "videoai" || key == "videoai_provider" else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? key : value
        }
        return nil
    }
}

/// Picture statistics averaged over the sampled frames.
nonisolated struct FrameStats: Equatable, Sendable {
    /// Residual after a 2x down/up round trip over the mean gradient. Low means little real fine detail.
    var detailRatio: Double
    /// Mean luma step across 8-pixel block boundaries over the mean step elsewhere. Well above 1 means visible blocking.
    var blockiness: Double
    /// Median local standard deviation of the flattest 10 % of 8x8 blocks, as a fraction of full scale.
    var noise: Double
}

nonisolated enum SourceClass: String, CaseIterable, Sendable {
    case hdr, topaz, compressed, soft, clean
}

nonisolated struct SourceClassification: Equatable, Sendable {
    let sourceClass: SourceClass
    /// Short text for the badge, for example `2.1 Mbit/s`.
    let reason: String
}

nonisolated enum SourceClassifier {
    nonisolated struct Thresholds: Equatable, Sendable {
        /// Below this many bits per pixel per frame a source counts as compressed.
        var lowBitsPerPixel: Double
        /// At or above this blockiness a source counts as compressed.
        var blockiness: Double
        /// Below this detail ratio a source counts as soft.
        var softDetailRatio: Double

        /// Starting values. Task 7 replaces them with the approved calibration.
        static let calibrated = Thresholds(lowBitsPerPixel: 0.05, blockiness: 1.6, softDetailRatio: 0.54)
    }

    /// Precedence: hdr, then topaz, then compressed, soft, clean. Without `stats` only
    /// the metadata rules apply.
    static func classify(
        _ facts: SourceFacts,
        _ stats: FrameStats?,
        thresholds: Thresholds = .calibrated
    ) -> SourceClassification {
        if facts.isHDR {
            return SourceClassification(sourceClass: .hdr, reason: "HDR")
        }
        if facts.topazTag != nil {
            return SourceClassification(sourceClass: .topaz, reason: "Topaz tag")
        }
        if let bitsPerPixel = facts.bitsPerPixel, bitsPerPixel < thresholds.lowBitsPerPixel {
            let megabits = Double(facts.videoBitrate) / 1_000_000
            return SourceClassification(sourceClass: .compressed, reason: String(format: "%.1f Mbit/s", megabits))
        }
        if let stats {
            if stats.blockiness >= thresholds.blockiness {
                return SourceClassification(sourceClass: .compressed, reason: String(format: "blocky %.1f", stats.blockiness))
            }
            if stats.detailRatio < thresholds.softDetailRatio {
                return SourceClassification(sourceClass: .soft, reason: String(format: "soft %.2f", stats.detailRatio))
            }
        }
        return SourceClassification(sourceClass: .clean, reason: "clean source")
    }
}
```

- [ ] **Step 4: Run it and see it pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`, all `SourceClassifierTests` pass.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/SourceClassifier.swift" "Aagedal Media Player Tests/SourceClassifierTests.swift"
git commit -m "Classify sources from metadata and frame stats"
```

---

## Task 2: Pick profiles from a cost table and fallback chains

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/ProfilePicker.swift`
- Test: `Aagedal Media Player Tests/ProfilePickerTests.swift`

**Interfaces:**
- Consumes: `SourceClass` (Task 1), `RenderProfile` (existing, `Logic/MPV/RenderProfile.swift`).
- Produces:
  - `ProfilePicker.Cost { let p720: Double; let p1080: Double }`, `static let costs: [RenderProfile: Cost]`
  - `static func chain(for sourceClass: SourceClass, fps: Double) -> [RenderProfile]`
  - `static func estimatedMilliseconds(profile: RenderProfile, sourcePixels: Double, drawablePixels: Double) -> Double?`
  - `static func pick(sourceClass: SourceClass, fps: Double, sourcePixels: Double, drawablePixels: Double, excluding: Set<RenderProfile> = []) -> RenderProfile`

Cost model: piecewise linear in source pixels through the two measurements (proportional below 720p and above 1080p), proportional to drawable pixels. This departs from the spec's single 1080p scaling because pure 1080p scaling underestimates 720p by up to 2x for chroma (3.8 ms estimated against 7.0 measured).

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/ProfilePickerTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Testing

struct ProfilePickerTests {
    private static let p720 = 1280.0 * 720
    private static let p1080 = 1920.0 * 1080
    private static let fullscreen = 3448.0 * 1940
    private static let windowed = 2560.0 * 1440

    private func pick(_ sourceClass: SourceClass, fps: Double, source: Double, drawable: Double,
                      excluding: Set<RenderProfile> = []) -> RenderProfile {
        ProfilePicker.pick(sourceClass: sourceClass, fps: fps, sourcePixels: source, drawablePixels: drawable,
                           excluding: excluding)
    }

    @Test func costsMatchTheMeasurementsAtTheAnchors() throws {
        let at720 = try #require(ProfilePicker.estimatedMilliseconds(profile: .compressed, sourcePixels: Self.p720, drawablePixels: Self.fullscreen))
        let at1080 = try #require(ProfilePicker.estimatedMilliseconds(profile: .compressed, sourcePixels: Self.p1080, drawablePixels: Self.fullscreen))
        #expect(abs(at720 - 16.1) < 1e-9)
        #expect(abs(at1080 - 33.0) < 1e-9)
    }

    @Test func costScalesWithDrawableAndSourcePixels() throws {
        let half = try #require(ProfilePicker.estimatedMilliseconds(profile: .sharpen, sourcePixels: Self.p1080, drawablePixels: Self.fullscreen / 2))
        #expect(abs(half - 5.85) < 1e-9)
        let fourK = try #require(ProfilePicker.estimatedMilliseconds(profile: .upscaleLight, sourcePixels: 3840.0 * 2160, drawablePixels: Self.fullscreen))
        #expect(abs(fourK - 31.0 * 4) < 1e-9)
    }

    @Test func unmeasuredProfilesHaveNoCost() {
        #expect(ProfilePicker.estimatedMilliseconds(profile: .upscaleStrong, sourcePixels: Self.p720, drawablePixels: Self.fullscreen) == nil)
    }

    @Test func chainsAreHeaviestFirstAndEndFaithful() {
        for sourceClass in SourceClass.allCases {
            for fps in [24.0, 60.0] {
                let chain = ProfilePicker.chain(for: sourceClass, fps: fps)
                #expect(chain.last == .off, "\(sourceClass) \(fps)")
                #expect(!chain.contains(.upscaleStrong))
            }
        }
        #expect(ProfilePicker.chain(for: .compressed, fps: 24) == [.compressed, .efficient, .sharpen, .chroma, .off])
    }

    @Test func topazNeverGetsDenoiseOrAdaptiveSharpen() {
        for fps in [24.0, 60.0] {
            let chain = ProfilePicker.chain(for: .topaz, fps: fps)
            #expect(Set(chain).isDisjoint(with: [.compressed, .compressedGrain, .crisp, .restore]))
        }
    }

    @Test func hdrStaysFaithful() {
        #expect(pick(.hdr, fps: 24, source: Self.p1080, drawable: Self.windowed) == .off)
    }

    @Test func compressedFallsBackWithFrameRateAndSize() {
        #expect(pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen) == .compressed)
        #expect(pick(.compressed, fps: 30, source: Self.p1080, drawable: Self.fullscreen) == .efficient)
        #expect(pick(.compressed, fps: 30, source: Self.p1080, drawable: Self.windowed) == .compressed)
        #expect(pick(.compressed, fps: 60, source: Self.p720, drawable: Self.fullscreen) == .efficient)
        #expect(pick(.compressed, fps: 60, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.compressed, fps: 60, source: Self.p1080, drawable: Self.windowed) == .efficient)
    }

    @Test func cleanAndTopazUseNeuralOnlyBelowThirtyFps() {
        #expect(pick(.clean, fps: 24, source: Self.p1080, drawable: Self.fullscreen) == .upscaleLight)
        #expect(pick(.clean, fps: 30, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.clean, fps: 60, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.topaz, fps: 60, source: Self.p720, drawable: Self.fullscreen) == .sharpen)
        #expect(pick(.topaz, fps: 24, source: Self.p720, drawable: Self.fullscreen) == .upscaleLight)
    }

    @Test func softUsesCrispWhenItFitsAndSharpenAbove30Fps() {
        #expect(pick(.soft, fps: 24, source: Self.p720, drawable: Self.fullscreen) == .crisp)
        #expect(pick(.soft, fps: 24, source: Self.p1080, drawable: Self.fullscreen) == .upscaleLight)
        #expect(pick(.soft, fps: 24, source: Self.p1080, drawable: Self.windowed) == .crisp)
        #expect(pick(.soft, fps: 60, source: Self.p1080, drawable: Self.fullscreen) == .sharpen)
    }

    @Test func fourKSourceFullscreenFallsAllTheWayToFaithful() {
        #expect(pick(.clean, fps: 30, source: 3840.0 * 2160, drawable: Self.fullscreen) == .off)
    }

    @Test func excludedProfilesAreSkippedButFaithfulNeverIs() {
        // Stepping down repeatedly walks the chain one fitting entry at a time.
        var excluded: Set<RenderProfile> = []
        var walked: [RenderProfile] = []
        while true {
            let next = pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen, excluding: excluded)
            walked.append(next)
            if next == .off { break }
            excluded.insert(next)
        }
        #expect(walked == [.compressed, .efficient, .sharpen, .chroma, .off])
        #expect(pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen, excluding: [.compressed]) == .efficient)
        let everything = Set(RenderProfile.allCases)
        #expect(pick(.compressed, fps: 24, source: Self.p720, drawable: Self.fullscreen, excluding: everything) == .off)
    }

    @Test func unknownSizesAndRateArePessimistic() {
        // 1080p, fullscreen, 30 fps: compressed (33 ms) does not fit 26.7 ms.
        #expect(pick(.compressed, fps: 0, source: 0, drawable: 0) == .efficient)
    }
}
```

- [ ] **Step 2: Run it and see it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/ProfilePickerTests"
```

Expected: compile failure `error: cannot find 'ProfilePicker' in scope`.

- [ ] **Step 3: Implement**

Create `Aagedal Media Player/Logic/MPV/ProfilePicker.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Chooses the heaviest shader profile of a class's fallback chain that fits the frame budget.
///
/// Costs are GPU milliseconds per frame measured in amp.app fullscreen (3448x1940 drawable)
/// on an M1 Pro with 720p and 1080p sources, for the profiles the chains use. Faithful needs no
/// entry: it is always accepted. `upscaleStrong` (64.6 ms at 720p, not measured at 1080p),
/// `compressedGrain` (measured at 1080p only) and `restore` appear in no chain.
nonisolated enum ProfilePicker {
    nonisolated struct Cost: Sendable {
        let p720: Double
        let p1080: Double
    }

    /// Share of the frame period a profile may use.
    static let budgetFraction = 0.8
    /// Above this the high-frame-rate chains apply. 30.5 keeps 30 and 29.97 fps on the normal chains.
    static let highFrameRate = 30.5
    /// Frame rate used when the container reports none.
    static let fallbackFPS = 30.0
    static let referenceDrawablePixels = 3448.0 * 1940.0
    static let pixels720p = 1280.0 * 720.0
    static let pixels1080p = 1920.0 * 1080.0

    static let costs: [RenderProfile: Cost] = [
        .chroma: Cost(p720: 7.0, p1080: 8.6),
        .efficient: Cost(p720: 10.9, p1080: 18.5),
        .sharpen: Cost(p720: 11.7, p1080: 11.7),
        .upscaleLight: Cost(p720: 15.4, p1080: 31.0),
        .compressed: Cost(p720: 16.1, p1080: 33.0),
        .crisp: Cost(p720: 21.3, p1080: 37.0),
    ]

    /// Heaviest first. Every chain ends in Faithful, which is always accepted.
    static func chain(for sourceClass: SourceClass, fps: Double) -> [RenderProfile] {
        let high = fps > highFrameRate
        switch sourceClass {
        case .hdr:
            return [.off]
        case .topaz, .clean:
            return high ? [.sharpen, .chroma, .off] : [.upscaleLight, .sharpen, .chroma, .off]
        case .compressed:
            return high ? [.efficient, .sharpen, .chroma, .off] : [.compressed, .efficient, .sharpen, .chroma, .off]
        case .soft:
            return high ? [.sharpen, .chroma, .off] : [.crisp, .upscaleLight, .sharpen, .chroma, .off]
        }
    }

    /// Milliseconds per frame, or nil when the profile has no measurement.
    ///
    /// The source-size term is piecewise linear through the 720p and 1080p measurements
    /// and proportional to pixels outside them; the drawable term is proportional to pixels.
    static func estimatedMilliseconds(
        profile: RenderProfile,
        sourcePixels: Double,
        drawablePixels: Double
    ) -> Double? {
        guard let cost = costs[profile] else { return nil }
        let base: Double
        if sourcePixels <= pixels720p {
            base = cost.p720 * sourcePixels / pixels720p
        } else if sourcePixels <= pixels1080p {
            base = cost.p720 + (cost.p1080 - cost.p720) * (sourcePixels - pixels720p) / (pixels1080p - pixels720p)
        } else {
            base = cost.p1080 * sourcePixels / pixels1080p
        }
        return base * drawablePixels / referenceDrawablePixels
    }

    /// The first profile of the class's chain that is not excluded and whose estimated cost fits
    /// the budget. Faithful is never excluded, so there is always an answer. Unknown sizes count
    /// as 1080p and fullscreen, the pessimistic case for the drawable.
    static func pick(
        sourceClass: SourceClass,
        fps: Double,
        sourcePixels: Double,
        drawablePixels: Double,
        excluding: Set<RenderProfile> = []
    ) -> RenderProfile {
        let rate = fps > 0 ? fps : fallbackFPS
        let budget = budgetFraction * 1000 / rate
        let source = sourcePixels > 0 ? sourcePixels : pixels1080p
        let drawable = drawablePixels > 0 ? drawablePixels : referenceDrawablePixels
        for profile in chain(for: sourceClass, fps: rate) {
            if profile == .off { return .off }
            guard !excluding.contains(profile),
                  let cost = estimatedMilliseconds(profile: profile, sourcePixels: source, drawablePixels: drawable),
                  cost <= budget else { continue }
            return profile
        }
        return .off
    }
}
```

- [ ] **Step 4: Run it and see it pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/ProfilePicker.swift" "Aagedal Media Player Tests/ProfilePickerTests.swift"
git commit -m "Pick render profiles from a GPU cost table and fallback chains"
```

---

## Task 3: Measure frame statistics with the bundled ffmpeg

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/FrameMath.swift`
- Create: `Aagedal Media Player/Logic/MPV/FrameAnalyzer.swift`
- Modify: `scripts/generate-test-fixtures.sh`
- Test: `Aagedal Media Player Tests/FrameMathTests.swift`, `Aagedal Media Player Tests/FrameAnalyzerIntegrationTests.swift`

**Interfaces:**
- Consumes: `FrameStats`, `SourceFacts.topazTag(inFFmpegOutput:)` (Task 1); `FFmpegService.ffmpegPath` and `FFmpegService.runStreamingOutput(arguments:onStandardOutputData:)`, `FFmpegError.cancelled`, `SubprocessService.run(executableURL:arguments:outputLimit:)` (existing).
- Produces:
  - `FrameMath.stats(luma: [UInt8], width: Int, height: Int) -> FrameStats?`, `FrameMath.average(_ frames: [FrameStats]) -> FrameStats?`, `FrameMath.sampleTimes(duration: Double, count: Int = FrameMath.frameCount) -> [Double]`, `FrameMath.parsePGM(_ data: Data) -> (luma: [UInt8], width: Int, height: Int)?`, `FrameMath.minimumDuration` (2.0), `FrameMath.frameCount` (8)
  - `nonisolated struct SourceAnalysis: Equatable, Sendable { var stats: FrameStats?; var topazTag: String? }`
  - `actor FrameAnalyzer { static let shared: FrameAnalyzer; func analyze(url: URL, duration: Double, timeout: Duration = .seconds(5)) async -> SourceAnalysis }`

Maths (all on 8-bit luma, in `Float`): detail ratio = mean absolute difference between the frame and its 2x2-box-downscaled, bilinear-upscaled copy, divided by the frame's mean absolute neighbour step; blockiness = mean step across 8-pixel column/row boundaries over the mean step elsewhere; noise = median standard deviation of the flattest 10 % of 8x8 blocks, divided by 255. Frames with a mean step below 0.25 grey levels (flat) carry no statistics.

- [ ] **Step 1: Write the failing maths test**

Create `Aagedal Media Player Tests/FrameMathTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import Testing

struct FrameMathTests {
    /// Deterministic generator so the synthetic frames are the same on every run.
    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let side = 256

    private static func gaussian(_ rng: inout SplitMix) -> Double {
        let u = Double.random(in: 0.000_1..<1, using: &rng)
        let v = Double.random(in: 0..<1, using: &rng)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }

    private static func clamp(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }

    private static func shading(_ x: Int, _ y: Int) -> Double { 90 + 60 * sin(Double(x) / 37) + 50 * cos(Double(y) / 29) }

    /// Independent noise at every pixel over a smooth shading: real fine detail.
    private static func sharpFrame() -> [UInt8] {
        var rng = SplitMix(state: 1)
        return (0..<side * side).map { clamp(shading($0 % side, $0 / side) + 40 * gaussian(&rng)) }
    }

    /// A 64x64 noise texture enlarged 4x with bilinear sampling: no detail above a quarter of Nyquist.
    private static func blurredUpscale() -> [UInt8] {
        var rng = SplitMix(state: 2)
        let small = 64
        let texture = (0..<small * small).map { _ in 128 + 40 * gaussian(&rng) }
        return (0..<side * side).map { i in
            let x = (Double(i % side) + 0.5) / 4 - 0.5
            let y = (Double(i / side) + 0.5) / 4 - 0.5
            let x0 = max(0, min(small - 2, Int(x.rounded(.down))))
            let y0 = max(0, min(small - 2, Int(y.rounded(.down))))
            let fx = max(0, min(1, x - Double(x0)))
            let fy = max(0, min(1, y - Double(y0)))
            let top = texture[y0 * small + x0] * (1 - fx) + texture[y0 * small + x0 + 1] * fx
            let bottom = texture[(y0 + 1) * small + x0] * (1 - fx) + texture[(y0 + 1) * small + x0 + 1] * fx
            return clamp(top * (1 - fy) + bottom * fy)
        }
    }

    /// Every 8x8 block a constant level: the signature of a coarse transform codec.
    private static func blockPattern() -> [UInt8] {
        var rng = SplitMix(state: 3)
        let blocks = side / 8
        let levels = (0..<blocks * blocks).map { _ in 128 + 30 * gaussian(&rng) }
        return (0..<side * side).map { clamp(levels[($0 / side / 8) * blocks + ($0 % side) / 8] + 2 * gaussian(&rng)) }
    }

    private static func flatWithNoise() -> [UInt8] {
        var rng = SplitMix(state: 4)
        return (0..<side * side).map { _ in clamp(128 + 6 * gaussian(&rng)) }
    }

    private static func smoothFrame() -> [UInt8] {
        (0..<side * side).map { clamp(shading($0 % side, $0 / side)) }
    }

    private func stats(_ frame: [UInt8]) throws -> FrameStats {
        try #require(FrameMath.stats(luma: frame, width: Self.side, height: Self.side))
    }

    @Test func blockPatternHasHighBlockiness() throws {
        #expect(try stats(Self.blockPattern()).blockiness > 5)
    }

    @Test func framesWithoutBlockingStayNearOne() throws {
        for frame in [Self.sharpFrame(), Self.smoothFrame(), Self.flatWithNoise()] {
            let value = try stats(frame).blockiness
            #expect(value > 0.9 && value < 1.15, "blockiness \(value)")
        }
    }

    @Test func blurredUpscaleHasLowerDetailRatioThanSharpDetail() throws {
        let sharp = try stats(Self.sharpFrame()).detailRatio
        let blurred = try stats(Self.blurredUpscale()).detailRatio
        #expect(blurred < sharp - 0.1, "blurred \(blurred) sharp \(sharp)")
    }

    @Test func gaussianNoiseGivesHighNoiseAndAFlatFrameDoesNot() throws {
        #expect(try stats(Self.flatWithNoise()).noise > 0.015)
        #expect(try stats(Self.smoothFrame()).noise < 0.005)
    }

    @Test func aFlatFrameCarriesNoStatistics() {
        let flat = [UInt8](repeating: 16, count: Self.side * Self.side)
        #expect(FrameMath.stats(luma: flat, width: Self.side, height: Self.side) == nil)
    }

    @Test func tinyOrShortFramesCarryNoStatistics() {
        #expect(FrameMath.stats(luma: [UInt8](repeating: 0, count: 64), width: 8, height: 8) == nil)
        #expect(FrameMath.stats(luma: [UInt8](repeating: 0, count: 10), width: 256, height: 256) == nil)
    }

    @Test func oddSizedFramesAreHandled() throws {
        let width = 257, height = 255
        let frame = (0..<width * height).map { UInt8(truncatingIfNeeded: ($0 * 2_654_435_761) >> 13) }
        #expect(FrameMath.stats(luma: frame, width: width, height: height) != nil)
    }

    @Test func averageIsTheMeanOfEachField() throws {
        let mean = try #require(FrameMath.average([
            FrameStats(detailRatio: 0.2, blockiness: 1, noise: 0.1),
            FrameStats(detailRatio: 0.4, blockiness: 3, noise: 0.3),
        ]))
        #expect(abs(mean.detailRatio - 0.3) < 1e-12)
        #expect(abs(mean.blockiness - 2) < 1e-12)
        #expect(abs(mean.noise - 0.2) < 1e-12)
        #expect(FrameMath.average([]) == nil)
    }

    @Test func sampleTimesSkipTheEndsAndAreEvenlySpread() {
        let times = FrameMath.sampleTimes(duration: 100)
        #expect(times.count == 8)
        #expect(abs(times[0] - 10.625) < 1e-9)
        #expect(abs(times[7] - 89.375) < 1e-9)
        for (a, b) in zip(times, times.dropFirst()) { #expect(abs((b - a) - 11.25) < 1e-9) }
    }

    @Test func shortOrUnknownDurationsGetNoSamples() {
        #expect(FrameMath.sampleTimes(duration: 1.99).isEmpty)
        #expect(FrameMath.sampleTimes(duration: 0).isEmpty)
        #expect(FrameMath.sampleTimes(duration: .nan).isEmpty)
        #expect(FrameMath.sampleTimes(duration: 2).count == 8)
    }

    @Test func parsesTheHeaderFFmpegWrites() throws {
        var data = Data("P5\n3 2\n255\n".utf8)
        data.append(contentsOf: [1, 2, 3, 4, 5, 6])
        let image = try #require(FrameMath.parsePGM(data))
        #expect(image.width == 3 && image.height == 2)
        #expect(image.luma == [1, 2, 3, 4, 5, 6])
    }

    @Test func rejectsTruncatedOrForeignData() {
        var data = Data("P5\n3 2\n255\n".utf8)
        data.append(contentsOf: [1, 2, 3])
        #expect(FrameMath.parsePGM(data) == nil)
        #expect(FrameMath.parsePGM(Data("P6\n1 1\n255\nabc".utf8)) == nil)
        #expect(FrameMath.parsePGM(Data()) == nil)
    }
}
```

- [ ] **Step 2: Run it and see it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/FrameMathTests"
```

Expected: compile failure `error: cannot find 'FrameMath' in scope`.

- [ ] **Step 3: Implement the maths**

Create `Aagedal Media Player/Logic/MPV/FrameMath.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Accelerate
import Foundation

/// Pure picture maths on 8-bit luma frames, plus the frame sampling plan and PGM parsing the
/// analyzer and the calibration script share.
nonisolated enum FrameMath {
    /// Files shorter than this are not analysed.
    static let minimumDuration = 2.0
    static let frameCount = 8

    /// Evenly spread timestamps in seconds, skipping the first and last 5 % of the file.
    static func sampleTimes(duration: Double, count: Int = frameCount) -> [Double] {
        guard duration.isFinite, duration >= minimumDuration, count > 0 else { return [] }
        return (0..<count).map { duration * (0.05 + 0.9 * (Double($0) + 0.5) / Double(count)) }
    }

    /// Parses a binary PGM (`P5`, maxval 255) as written by ffmpeg's `pgm` encoder.
    static func parsePGM(_ data: Data) -> (luma: [UInt8], width: Int, height: Int)? {
        let bytes = [UInt8](data)
        var index = 0
        func token() -> String? {
            while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09 { index += 1 }
            let start = index
            while index < bytes.count, !(bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09) { index += 1 }
            return start < index ? String(decoding: bytes[start..<index], as: UTF8.self) : nil
        }
        guard token() == "P5", let w = token().flatMap({ Int($0) }), let h = token().flatMap({ Int($0) }),
              token() == "255", w > 0, h > 0 else { return nil }
        index += 1 // the single whitespace byte after maxval
        guard bytes.count - index >= w * h else { return nil }
        return (Array(bytes[index..<(index + w * h)]), w, h)
    }

    static let minimumSide = 16
    static let flatGradient: Float = 0.25
    static let blockSize = 8

    static func stats(luma: [UInt8], width: Int, height: Int) -> FrameStats? {
        let w = width / 2 * 2
        let h = height / 2 * 2
        guard w >= minimumSide, h >= minimumSide, luma.count >= width * height else { return nil }
        var pixels = [Float](repeating: 0, count: w * h)
        luma.withUnsafeBufferPointer { src in
            pixels.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h {
                    vDSP_vfltu8(src.baseAddress! + y * width, 1, dst.baseAddress! + y * w, 1, vDSP_Length(w))
                }
            }
        }
        let steps = stepSums(pixels, width: w, height: h)
        let gradient = steps.meanAll
        guard gradient >= flatGradient else { return nil }
        return FrameStats(
            detailRatio: Double(residualMean(pixels, width: w, height: h) / gradient),
            blockiness: Double(steps.blockiness),
            noise: Double(flatBlockNoise(pixels, width: w, height: h) / 255)
        )
    }

    static func average(_ frames: [FrameStats]) -> FrameStats? {
        guard !frames.isEmpty else { return nil }
        let n = Double(frames.count)
        return FrameStats(
            detailRatio: frames.map(\.detailRatio).reduce(0, +) / n,
            blockiness: frames.map(\.blockiness).reduce(0, +) / n,
            noise: frames.map(\.noise).reduce(0, +) / n
        )
    }

    // MARK: Steps

    private struct Steps { var meanAll: Float; var blockiness: Float }

    /// Absolute neighbour differences. A step into column/row 8k is a block boundary.
    private static func stepSums(_ p: [Float], width w: Int, height h: Int) -> Steps {
        var boundary: Double = 0, other: Double = 0
        var boundaryCount = 0, otherCount = 0
        var diff = [Float](repeating: 0, count: w)
        p.withUnsafeBufferPointer { px in
            diff.withUnsafeMutableBufferPointer { d in
                for y in 0..<h {
                    let row = px.baseAddress! + y * w
                    // horizontal: d[i] = |row[i+1] - row[i]|
                    vDSP_vsub(row, 1, row + 1, 1, d.baseAddress!, 1, vDSP_Length(w - 1))
                    vDSP_vabs(d.baseAddress!, 1, d.baseAddress!, 1, vDSP_Length(w - 1))
                    var total: Float = 0, onBoundary: Float = 0
                    vDSP_sve(d.baseAddress!, 1, &total, vDSP_Length(w - 1))
                    let boundaries = (w - 1 - (blockSize - 1) + blockSize - 1) / blockSize
                    vDSP_sve(d.baseAddress! + (blockSize - 1), vDSP_Stride(blockSize), &onBoundary, vDSP_Length(boundaries))
                    boundary += Double(onBoundary); boundaryCount += boundaries
                    other += Double(total - onBoundary); otherCount += (w - 1) - boundaries
                    // vertical: step from row y-1 to y
                    if y > 0 {
                        let prev = px.baseAddress! + (y - 1) * w
                        vDSP_vsub(prev, 1, row, 1, d.baseAddress!, 1, vDSP_Length(w))
                        vDSP_vabs(d.baseAddress!, 1, d.baseAddress!, 1, vDSP_Length(w))
                        var sum: Float = 0
                        vDSP_sve(d.baseAddress!, 1, &sum, vDSP_Length(w))
                        if y % blockSize == 0 { boundary += Double(sum); boundaryCount += w }
                        else { other += Double(sum); otherCount += w }
                    }
                }
            }
        }
        let meanAll = Float((boundary + other) / Double(max(1, boundaryCount + otherCount)))
        let meanOther = other / Double(max(1, otherCount))
        let meanBoundary = boundary / Double(max(1, boundaryCount))
        let blockiness = meanOther < 1e-6 ? 1 : Float(meanBoundary / meanOther)
        return Steps(meanAll: meanAll, blockiness: blockiness)
    }

    // MARK: Detail

    /// Mean |frame - bilinear(box2x(frame))|.
    private static func residualMean(_ p: [Float], width w: Int, height h: Int) -> Float {
        let hw = w / 2, hh = h / 2
        var small = [Float](repeating: 0, count: hw * hh)
        for y in 0..<hh {
            for x in 0..<hw {
                let i = 2 * y * w + 2 * x
                small[y * hw + x] = (p[i] + p[i + 1] + p[i + w] + p[i + w + 1]) * 0.25
            }
        }
        var total: Double = 0
        for y in 0..<h {
            let sy = (Float(y) + 0.5) / 2 - 0.5
            let y0 = max(0, min(hh - 1, Int(sy.rounded(.down))))
            let y1 = min(hh - 1, y0 + 1)
            let fy = max(0, min(1, sy - Float(y0)))
            for x in 0..<w {
                let sx = (Float(x) + 0.5) / 2 - 0.5
                let x0 = max(0, min(hw - 1, Int(sx.rounded(.down))))
                let x1 = min(hw - 1, x0 + 1)
                let fx = max(0, min(1, sx - Float(x0)))
                let top = small[y0 * hw + x0] * (1 - fx) + small[y0 * hw + x1] * fx
                let bottom = small[y1 * hw + x0] * (1 - fx) + small[y1 * hw + x1] * fx
                total += Double(abs(p[y * w + x] - (top * (1 - fy) + bottom * fy)))
            }
        }
        return Float(total / Double(w * h))
    }

    // MARK: Noise

    /// Median standard deviation over the flattest 10 % of 8x8 blocks, in grey levels.
    private static func flatBlockNoise(_ p: [Float], width w: Int, height h: Int) -> Float {
        let bw = w / blockSize, bh = h / blockSize
        guard bw > 0, bh > 0 else { return 0 }
        var deviations = [Float]()
        deviations.reserveCapacity(bw * bh)
        for by in 0..<bh {
            for bx in 0..<bw {
                var sum: Float = 0, sumSquares: Float = 0
                for y in 0..<blockSize {
                    let base = (by * blockSize + y) * w + bx * blockSize
                    for x in 0..<blockSize {
                        let v = p[base + x]
                        sum += v; sumSquares += v * v
                    }
                }
                let n = Float(blockSize * blockSize)
                let mean = sum / n
                deviations.append(max(0, sumSquares / n - mean * mean).squareRoot())
            }
        }
        deviations.sort()
        let flattest = max(1, deviations.count / 10)
        return deviations[flattest / 2]
    }
}
```

- [ ] **Step 4: Run it and see it pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Verify the bundled ffmpeg can do what the analyzer needs**

```bash
FF="Aagedal Media Player/Binaries/ffmpeg"
"$FF" -hide_banner -encoders 2>&1 | rg " pgm "
"$FF" -hide_banner -muxers 2>&1 | rg "image2pipe"
"$FF" -hide_banner -decoders 2>&1 | rg " (h264|hevc|prores) "
```

Expected: one line each for `pgm`, `image2pipe`, and the three decoders. If `pgm` or `image2pipe` is missing, stop and report; the analyzer's frame source would then have to change to `-f rawvideo` plus dimensions from `SourceFacts`, which is a design change.

- [ ] **Step 6: Add the analysis fixtures to the generator**

In `scripts/generate-test-fixtures.sh`, replace:

```swift
printf '%s\n' \
    'Aagedal Media Player generated media fixtures' \
    'schema=5' \
```

with:

```swift
# FrameAnalyzer fixtures: a bitrate-starved encode (blocky), an ordinary encode carrying a
# Topaz container tag, a Matroska clip carrying a Topaz stream tag, and a clip shorter than
# the two seconds the analyzer needs. MP4 keeps custom container tags only with
# use_metadata_tags; Matroska keeps stream tags natively.
mkdir -p "$output_dir/analysis"
ffmpeg \
    -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=4" \
    -an -c:v libx264 -preset ultrafast -b:v 300k -pix_fmt yuv420p \
    -movflags +faststart "$output_dir/analysis/low-bitrate-720p.mp4"

ffmpeg \
    -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=4" \
    -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
    -metadata videoai="Enhanced using Proteus v4" \
    -movflags +faststart+use_metadata_tags "$output_dir/analysis/topaz-container.mp4"

ffmpeg \
    -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=4" \
    -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
    -metadata:s:v:0 videoai_provider=Topaz "$output_dir/analysis/topaz-stream.mkv"

ffmpeg \
    -f lavfi -i "testsrc2=size=1280x720:rate=24:duration=1" \
    -an -c:v libx264 -preset ultrafast -crf 28 -pix_fmt yuv420p \
    -movflags +faststart "$output_dir/analysis/short.mp4"

printf '%s\n' \
    'Aagedal Media Player generated media fixtures' \
    'schema=5' \
```

Then generate and check them (the script requires an ffmpeg with libx264, `/Users/filip/.local/bin/ffmpeg` on this Mac):

```bash
scripts/generate-test-fixtures.sh
ls -la "Test Fixtures/Generated/analysis"
rg "schema" "Test Fixtures/Generated/MANIFEST.txt"
```

Expected: four files (`low-bitrate-720p.mp4`, `short.mp4`, `topaz-container.mp4`, `topaz-stream.mkv`) and `schema=5` unchanged.

- [ ] **Step 7: Write the failing integration test**

Create `Aagedal Media Player Tests/FrameAnalyzerIntegrationTests.swift`. Debug builds are slow at the pixel maths (about 3 s for eight 720p frames), so every call passes a 60 s timeout; the production default stays 5 s.

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Foundation
import XCTest

/// Runs the bundled ffmpeg against the generated fixtures in `analysis/`
/// (scripts/generate-test-fixtures.sh). Debug builds are slow at the pixel maths, so these
/// calls use a long timeout; the production default is 5 s.
final class FrameAnalyzerIntegrationTests: XCTestCase {
    private let timeout = Duration.seconds(60)

    @MainActor
    private func fixture(_ name: String) throws -> URL {
        guard FFmpegService.ffmpegPath != nil else { throw XCTSkip("Bundled ffmpeg is unavailable.") }
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["MEDIA_FIXTURE_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appending(path: "Test Fixtures/Generated", directoryHint: .isDirectory)
        }
        guard FileManager.default.fileExists(atPath: directory.appending(path: "MANIFEST.txt").path) else {
            throw XCTSkip("Generated media fixtures are unavailable. Run scripts/generate-test-fixtures.sh or set MEDIA_FIXTURE_DIR.")
        }
        let url = directory.appending(path: "analysis/\(name)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("analysis/\(name) is missing. Re-run scripts/generate-test-fixtures.sh.")
        }
        return url
    }

    @MainActor
    func testMeasuresALowBitrateFixtureWithinBounds() async throws {
        let url = try fixture("low-bitrate-720p.mp4")
        let analysis = await FrameAnalyzer.shared.analyze(url: url, duration: 4, timeout: timeout)
        let stats = try XCTUnwrap(analysis.stats)
        XCTAssertTrue((0.3...1.5).contains(stats.detailRatio), "detailRatio \(stats.detailRatio)")
        XCTAssertTrue((2.0...20).contains(stats.blockiness), "blockiness \(stats.blockiness)")
        XCTAssertTrue((0...1).contains(stats.noise), "noise \(stats.noise)")
        XCTAssertNil(analysis.topazTag)
    }

    @MainActor
    func testStarvedEncodeIsBlockierThanAnOrdinaryOne() async throws {
        let starvedURL = try fixture("low-bitrate-720p.mp4")
        let ordinaryURL = try fixture("topaz-container.mp4")
        let starvedAnalysis = await FrameAnalyzer.shared.analyze(url: starvedURL, duration: 4, timeout: timeout)
        let ordinaryAnalysis = await FrameAnalyzer.shared.analyze(url: ordinaryURL, duration: 4, timeout: timeout)
        let starved = try XCTUnwrap(starvedAnalysis.stats)
        let ordinary = try XCTUnwrap(ordinaryAnalysis.stats)
        XCTAssertGreaterThan(starved.blockiness, ordinary.blockiness)
    }

    @MainActor
    func testReadsTheTopazTagFromContainerAndStream() async throws {
        let containerURL = try fixture("topaz-container.mp4")
        let streamURL = try fixture("topaz-stream.mkv")
        let container = await FrameAnalyzer.shared.analyze(url: containerURL, duration: 4, timeout: timeout)
        XCTAssertEqual(container.topazTag, "Enhanced using Proteus v4")
        let stream = await FrameAnalyzer.shared.analyze(url: streamURL, duration: 4, timeout: timeout)
        XCTAssertEqual(stream.topazTag, "Topaz")
    }

    @MainActor
    func testRepeatedAnalysisComesFromTheCache() async throws {
        let url = try fixture("low-bitrate-720p.mp4")
        let analyzer = FrameAnalyzer()
        let first = await analyzer.analyze(url: url, duration: 4, timeout: timeout)
        let started = ContinuousClock.now
        let second = await analyzer.analyze(url: url, duration: 4, timeout: timeout)
        XCTAssertEqual(first, second)
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(200))
    }

    @MainActor
    func testFilesShorterThanTwoSecondsGetNoStatistics() async throws {
        let url = try fixture("short.mp4")
        let analysis = await FrameAnalyzer.shared.analyze(url: url, duration: 1, timeout: timeout)
        XCTAssertNil(analysis.stats)
    }

    @MainActor
    func testTimeoutKeepsTheMetadataOnlyPick() async throws {
        let url = try fixture("low-bitrate-720p.mp4")
        let analysis = await FrameAnalyzer().analyze(url: url, duration: 4, timeout: .milliseconds(1))
        XCTAssertEqual(analysis, SourceAnalysis())
    }
}
```

- [ ] **Step 8: Run it and see it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/FrameAnalyzerIntegrationTests"
```

Expected: compile failure `error: cannot find 'FrameAnalyzer' in scope`.

- [ ] **Step 9: Implement the analyzer**

Create `Aagedal Media Player/Logic/MPV/FrameAnalyzer.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import OSLog
import os

/// What looking inside a file found. Both fields are nil when nothing could be read.
nonisolated struct SourceAnalysis: Equatable, Sendable {
    var stats: FrameStats?
    var topazTag: String?
}

/// Decodes a few frames with the bundled ffmpeg and measures them. It runs off the main actor,
/// is cancellable, and remembers results in memory keyed by path, size and modification date.
actor FrameAnalyzer {
    static let shared = FrameAnalyzer()

    /// Fewer usable frames than this and the statistics are not trusted.
    static let minimumUsableFrames = 4
    /// A decoded 8K gray frame is 33 MB; the streaming runner keeps nothing, this bounds the buffer.
    private static let maximumFrameBytes = 64 * 1024 * 1024

    private struct Fingerprint: Hashable {
        let path: String
        let size: Int
        let modified: Date
    }

    private enum AnalysisError: Error { case timedOut, ffmpegMissing }

    private var cache: [Fingerprint: SourceAnalysis] = [:]
    private let logger = Logger(subsystem: "com.aagedal.MediaPlayer", category: "FrameAnalyzer")

    /// Never throws: any failure is logged and returns an empty analysis, so the caller keeps
    /// its metadata-only pick. A cancelled call also returns an empty analysis; the caller
    /// must check `Task.isCancelled` before using the result.
    func analyze(url: URL, duration: Double, timeout: Duration = .seconds(5)) async -> SourceAnalysis {
        guard let before = Self.fingerprint(of: url) else {
            logger.info("Analysis skipped, cannot read \(url.lastPathComponent, privacy: .public)")
            return SourceAnalysis()
        }
        if let hit = cache[before] { return hit }
        guard let ffmpeg = await FFmpegService.ffmpegPath else {
            logger.info("Analysis skipped, bundled ffmpeg is missing")
            return SourceAnalysis()
        }
        do {
            let result = try await Self.withTimeout(timeout) {
                try await Self.measure(path: url.path, duration: duration, ffmpeg: ffmpeg)
            }
            guard Self.fingerprint(of: url) == before else {
                logger.info("Analysis discarded, \(url.lastPathComponent, privacy: .public) changed while it ran")
                return SourceAnalysis()
            }
            cache[before] = result
            return result
        } catch is CancellationError {
            return SourceAnalysis()
        } catch AnalysisError.timedOut {
            logger.info("Analysis of \(url.lastPathComponent, privacy: .public) timed out after \(timeout.components.seconds) s")
            return SourceAnalysis()
        } catch {
            logger.info("Analysis of \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return SourceAnalysis()
        }
    }

    // MARK: - Measuring

    private nonisolated static func fingerprint(of url: URL) -> Fingerprint? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        return Fingerprint(path: url.path, size: size, modified: modified)
    }

    private nonisolated static func withTimeout<T: Sendable>(
        _ timeout: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AnalysisError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw CancellationError() }
            return first
        }
    }

    private nonisolated static func measure(path: String, duration: Double, ffmpeg: String) async throws -> SourceAnalysis {
        let tag = try await topazTag(path: path, ffmpeg: ffmpeg)
        var frames: [FrameStats] = []
        for time in FrameMath.sampleTimes(duration: duration) {
            try Task.checkCancellation()
            guard let luma = try await decodeFrame(path: path, at: time, ffmpeg: ffmpeg),
                  let stats = FrameMath.stats(luma: luma.luma, width: luma.width, height: luma.height) else { continue }
            frames.append(stats)
        }
        return SourceAnalysis(
            stats: frames.count >= minimumUsableFrames ? FrameMath.average(frames) : nil,
            topazTag: tag
        )
    }

    /// `ffmpeg -i` prints container and stream tags to standard error; decoding zero frames
    /// is enough. The exit status is irrelevant here, so the output is read regardless.
    private nonisolated static func topazTag(path: String, ffmpeg: String) async throws -> String? {
        let result = try await SubprocessService.run(
            executableURL: URL(fileURLWithPath: ffmpeg),
            arguments: ["-hide_banner", "-nostdin", "-i", path, "-t", "0", "-f", "null", "-"],
            outputLimit: 1_048_576
        )
        return SourceFacts.topazTag(inFFmpegOutput: String(decoding: result.standardError, as: UTF8.self))
    }

    /// One 8-bit gray frame as PGM on a pipe, so the output carries its own dimensions
    /// (autorotation and pixel aspect ratio included). `-ss` before `-i` seeks the input.
    private nonisolated static func decodeFrame(
        path: String,
        at time: Double,
        ffmpeg: String
    ) async throws -> (luma: [UInt8], width: Int, height: Int)? {
        let buffer = OSAllocatedUnfairLock(initialState: Data())
        do {
            try await FFmpegService.runStreamingOutput(
                arguments: [
                    "-hide_banner", "-loglevel", "error", "-nostdin",
                    "-ss", String(format: "%.3f", time), "-i", path,
                    "-frames:v", "1", "-an", "-sn",
                    "-pix_fmt", "gray", "-f", "image2pipe", "-c:v", "pgm", "-",
                ],
                onStandardOutputData: { chunk in
                    buffer.withLock { data in
                        if data.count < maximumFrameBytes { data.append(chunk) }
                    }
                }
            )
        } catch FFmpegError.cancelled {
            throw CancellationError()
        } catch {
            return nil
        }
        return FrameMath.parsePGM(buffer.withLock { $0 })
    }
}
```

- [ ] **Step 10: Run both suites and see them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/FrameMathTests" -only-testing:"Aagedal Media Player Tests/FrameAnalyzerIntegrationTests"
```

Expected: `** TEST SUCCEEDED **`. Reference run on this Mac: the low-bitrate fixture reported detail 0.849, blockiness 3.41, noise 0.0; the ordinary encode blockiness 1.97; the Topaz container fixture tag `Enhanced using Proteus v4`; the Matroska stream fixture tag `Topaz`. If the fixtures are missing the integration tests report as skipped with the instruction to run the generator; that is a failed step, not a pass.

- [ ] **Step 11: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/FrameMath.swift" "Aagedal Media Player/Logic/MPV/FrameAnalyzer.swift" "Aagedal Media Player Tests/FrameMathTests.swift" "Aagedal Media Player Tests/FrameAnalyzerIntegrationTests.swift" scripts/generate-test-fixtures.sh
git commit -m "Measure frame statistics with the bundled ffmpeg"
```

---

## Task 4: Add RenderProfile.automatic, make it the default, migrate Enhance

The Enhance toggle, `AppSettings.enhance`, `AppCommand.setEnhance` and the `RenderTier` ladder are removed in Task 6, not here: `MPVPlayer` and `RenderTierTests` reference them, and `SettingsCoverageTests` fails if a registered key has no control in `UI/`. Removing them earlier would break the build.

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/RenderProfile.swift`
- Modify: `Aagedal Media Player/Logic/AppSettings.swift`
- Modify: `Aagedal Media Player/Logic/SettingsMigration.swift`
- Test: `Aagedal Media Player Tests/RenderProfileTests.swift`, `Aagedal Media Player Tests/SettingsMigrationTests.swift`, `Aagedal Media Player Tests/ProfilePickerTests.swift`

**Interfaces:**
- Consumes: `RenderProfile` (existing), `SettingsMigration` (existing, `currentVersion` 1).
- Produces: `RenderProfile.automatic` (first case, display name "Automatic", no shaders, no deband); `AppSettings.renderProfile.defaultValue == "automatic"`; `SettingsMigration.currentVersion == 2` whose step from version 1 turns a stored `enhance = true` with profile Faithful (or none) into `renderProfile = "automatic"` and always removes the `enhance` key.

- [ ] **Step 1: Write the failing tests**

In `Aagedal Media Player Tests/RenderProfileTests.swift`:

In `Aagedal Media Player Tests/RenderProfileTests.swift`, replace:

```swift
    func testDefaultProfileIsFaithful() {
        XCTAssertEqual(AppSettings.renderProfile.defaultValue, RenderProfile.off.rawValue)
    }
```

with:

```swift
    func testDefaultProfileIsAutomatic() {
        XCTAssertEqual(AppSettings.renderProfile.defaultValue, RenderProfile.automatic.rawValue)
    }

    func testAutomaticLoadsNoShadersItselfAndIsListedFirst() {
        XCTAssertEqual(RenderProfile.automatic.shaderFileNames, [])
        XCTAssertFalse(RenderProfile.automatic.enablesDeband)
        XCTAssertEqual(RenderProfile.allCases.first, .automatic)
        XCTAssertEqual(RenderProfile.automatic.displayName, "Automatic")
    }

    func testLibraryResolvesNameLists() throws {
        try writeShader("ravu-zoom-ar-r3.hook")
        let library = ShaderLibrary(directoryPath: shaderDirectory.path)
        let names = ["ravu-zoom-ar-r3.hook", "ArtCNN_C4F16.glsl"]
        XCTAssertEqual(library.shaderPaths(named: names).count, 1)
        XCTAssertTrue(library.shaderPaths(named: names).first?.hasSuffix("ravu-zoom-ar-r3.hook") == true)
        XCTAssertEqual(library.missingShaderNames(named: names), ["ArtCNN_C4F16.glsl"])
    }
```

In `Aagedal Media Player Tests/SettingsMigrationTests.swift`, replace the final closing brace of the class with the following (the helper reads what the suite itself stored, because the app registers a default for `enhance` in the test host):

```swift

    /// What this suite itself stores. `object(forKey:)` would also return a default the app
    /// registered for the key, which says nothing about whether the migration removed it.
    private func storedValue(_ key: String) -> Any? {
        defaults.persistentDomain(forName: suiteName)?[key]
    }

    func testEnhanceWithFaithfulBecomesAutomaticAndTheKeyIsRemoved() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(true, forKey: "enhance")
        defaults.set("off", forKey: "renderProfile")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "automatic")
        XCTAssertNil(storedValue("enhance"))
        XCTAssertEqual(defaults.integer(forKey: "settingsVersion"), SettingsMigration.currentVersion)
    }

    func testEnhanceWithNoStoredProfileEndsUpAutomatic() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(true, forKey: "enhance")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "automatic")
        XCTAssertNil(storedValue("enhance"))
    }

    func testEnhanceKeepsAManuallyChosenProfile() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(true, forKey: "enhance")
        defaults.set("compressed", forKey: "renderProfile")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "compressed")
        XCTAssertNil(storedValue("enhance"))
    }

    func testEnhanceOffLeavesFaithfulAndRemovesTheKey() {
        defaults.set(1, forKey: "settingsVersion")
        defaults.set(false, forKey: "enhance")
        defaults.set("off", forKey: "renderProfile")
        SettingsMigration.migrate(defaults)
        XCTAssertEqual(defaults.string(forKey: "renderProfile"), "off")
        XCTAssertNil(storedValue("enhance"))
    }
}
```

In `Aagedal Media Player Tests/ProfilePickerTests.swift`, replace the final closing brace of the struct with:

```swift
    @Test func automaticIsNeverCostedOrPicked() {
        #expect(ProfilePicker.estimatedMilliseconds(profile: .automatic, sourcePixels: Self.p720, drawablePixels: Self.fullscreen) == nil)
        for sourceClass in SourceClass.allCases {
            for fps in [24.0, 60.0] {
                #expect(!ProfilePicker.chain(for: sourceClass, fps: fps).contains(.automatic))
            }
        }
    }
}
```

- [ ] **Step 2: Run them and see them fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/RenderProfileTests" -only-testing:"Aagedal Media Player Tests/SettingsMigrationTests" -only-testing:"Aagedal Media Player Tests/ProfilePickerTests"
```

Expected: compile failure `error: type 'RenderProfile' has no member 'automatic'`.

- [ ] **Step 3: Implement**

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, replace:

```swift
/// The cases are ordered coolest to warmest: each step adds GPU work, so the
/// heavier profiles are worth spending only when the source actually needs the
/// reconstruction. Shader files are not bundled — they are read from a user
```

with:

```swift
/// `automatic` comes first: it picks one of the others for each file. The rest are
/// ordered coolest to warmest: each step adds GPU work, so the heavier profiles
/// are worth spending only when the source actually needs the reconstruction.
/// Shader files are not bundled — they are read from a user
```

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, replace:

```swift
    case off
    case chroma
```

with:

```swift
    case automatic
    case off
    case chroma
```

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, replace:

```swift
        case .off: "Faithful"
```

with:

```swift
        case .automatic: "Automatic"
        case .off: "Faithful"
```

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, replace:

```swift
        case .off: "No shaders.
```

with:

```swift
        case .automatic: "Looks at each file and picks the shader profile that fits its quality and your GPU, then steps down if a frame no longer fits. Choose Faithful for inspection."
        case .off: "No shaders.
```

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, replace:

```swift
        case .off:
            []
```

with:

```swift
        case .automatic, .off:
            []
```

In `Aagedal Media Player/Logic/AppSettings.swift`, replace:

```swift
static let renderProfile = AppSetting(key: "renderProfile", defaultValue: RenderProfile.off.rawValue)
```

with:

```swift
static let renderProfile = AppSetting(key: "renderProfile", defaultValue: RenderProfile.automatic.rawValue)
```

In `Aagedal Media Player/Logic/SettingsMigration.swift`, replace:

```swift
static let currentVersion = 1
```

with:

```swift
static let currentVersion = 2
```

In `Aagedal Media Player/Logic/SettingsMigration.swift`, replace:

```swift
        switch version {
        default:
            break
        }
```

with:

```swift
        switch version {
        case 1:
            // Enhance and its ratio ladder are replaced by the Automatic profile. Someone
            // who had Enhance on with Faithful selected gets Automatic; any other profile
            // they chose stays. The key is removed either way.
            let profile = defaults.string(forKey: "renderProfile")
            if defaults.bool(forKey: "enhance"), profile == nil || profile == RenderProfile.off.rawValue {
                defaults.set(RenderProfile.automatic.rawValue, forKey: "renderProfile")
            }
            defaults.removeObject(forKey: "enhance")
        default:
            break
        }
```

- [ ] **Step 4: Run them and see them pass**

Same command as Step 2, adding `-only-testing:"Aagedal Media Player Tests/SettingsCoverageTests"` and `-only-testing:"Aagedal Media Player Tests/RenderTierTests"` (both must still pass, which confirms nothing was removed early). Expected: `** TEST SUCCEEDED **`. This state was built and run in a scratch copy of the repo on 2026-10-02.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/RenderProfile.swift" "Aagedal Media Player/Logic/AppSettings.swift" "Aagedal Media Player/Logic/SettingsMigration.swift" "Aagedal Media Player Tests/RenderProfileTests.swift" "Aagedal Media Player Tests/SettingsMigrationTests.swift" "Aagedal Media Player Tests/ProfilePickerTests.swift"
git commit -m "Add the Automatic render profile as the default and migrate Enhance"
```

---

## Task 5: Hold the Automatic selection state in a testable value type

**Files:**
- Create: `Aagedal Media Player/Logic/MPV/AutomaticSelection.swift`
- Test: `Aagedal Media Player Tests/AutomaticSelectionTests.swift`

**Interfaces:**
- Consumes: `SourceFacts`, `FrameStats`, `SourceClassification`, `SourceClassifier` (Task 1); `ProfilePicker.pick` (Task 2); `RenderProfile.automatic`/`displayName` (Task 4).
- Produces:
  - `nonisolated struct AutomaticSelection: Equatable, Sendable`, `init(thresholds: SourceClassifier.Thresholds = .calibrated)`
  - `AutomaticSelection.Choice: Equatable, Sendable { let profile: RenderProfile; let classification: SourceClassification; let isSteppedDown: Bool; var badgeText: String { get } }`
  - `private(set) var facts: SourceFacts`, `private(set) var stats: FrameStats?`, `private(set) var current: Choice?`
  - `mutating func beginFile(facts: SourceFacts) -> Choice`, `mutating func update(facts: SourceFacts, stats: FrameStats?) -> Choice`, `mutating func setDrawable(pixels: Double) -> Choice`, `mutating func stepDown() -> Choice?`, `mutating func markActiveProfileBroken() -> Choice?`

A step-down rules the active profile out for the rest of the file (`rejected`); a libplacebo failure also rules it out for the life of the player (`broken`). Because rejections are profiles, not chain positions, they stay valid if analysis later changes the class.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/AutomaticSelectionTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

@testable import Aagedal_Media_Player
import Testing

struct AutomaticSelectionTests {
    private static let fullscreen = 3448.0 * 1940
    private static let windowed = 2560.0 * 1440
    private let thresholds = SourceClassifier.Thresholds(lowBitsPerPixel: 0.05, blockiness: 1.6, softDetailRatio: 0.54)

    private func selection(drawable: Double = fullscreen) -> AutomaticSelection {
        var selection = AutomaticSelection(thresholds: thresholds)
        _ = selection.setDrawable(pixels: drawable)
        return selection
    }

    private func facts(width: Int = 1280, height: Int = 720, fps: Double = 24, bitrate: Int64 = 20_000_000,
                       topazTag: String? = nil) -> SourceFacts {
        SourceFacts(codec: "h264", width: width, height: height, fps: fps, videoBitrate: bitrate,
                    bitDepth: 8, isHDR: false, topazTag: topazTag)
    }

    private let soft = FrameStats(detailRatio: 0.3, blockiness: 1.1, noise: 0)
    private let healthy = FrameStats(detailRatio: 0.65, blockiness: 1.1, noise: 0)

    @Test func metadataAloneGivesTheFirstPick() {
        var selection = selection()
        let choice = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(choice.profile == .compressed)
        #expect(choice.classification == SourceClassification(sourceClass: .compressed, reason: "0.6 Mbit/s"))
        #expect(choice.badgeText == "Auto · Compressed movie · 0.6 Mbit/s")
        #expect(selection.current == choice)
    }

    @Test func statsThatChangeTheClassChangeThePick() {
        var selection = selection()
        #expect(selection.beginFile(facts: facts()).profile == .upscaleLight)
        let refined = selection.update(facts: facts(), stats: soft)
        #expect(refined.profile == .crisp)
        #expect(refined.classification.sourceClass == .soft)
    }

    @Test func statsThatKeepTheClassKeepThePick() {
        var selection = selection()
        let first = selection.beginFile(facts: facts())
        let second = selection.update(facts: facts(), stats: healthy)
        #expect(second.profile == first.profile)
        #expect(second.classification.sourceClass == .clean)
    }

    @Test func aTopazTagFoundLaterReclassifies() {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        let choice = selection.update(facts: facts(bitrate: 600_000, topazTag: "Proteus"), stats: nil)
        #expect(choice.classification.sourceClass == .topaz)
        #expect(choice.profile == .upscaleLight)
    }

    @Test func aDrawableChangeRepicksWithTheSameStats() {
        var selection = selection()
        let source = facts(width: 1920, height: 1080, fps: 30, bitrate: 1_000_000)
        #expect(selection.beginFile(facts: source).profile == .efficient)
        #expect(selection.setDrawable(pixels: Self.windowed).profile == .compressed)
        #expect(selection.setDrawable(pixels: Self.fullscreen).profile == .efficient)
    }

    @Test func steppingDownWalksTheChainAndStopsAtFaithful() throws {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        var walked: [RenderProfile] = []
        while let next = selection.stepDown() { walked.append(next.profile) }
        #expect(walked == [.efficient, .sharpen, .chroma, .off])
        #expect(selection.current?.isSteppedDown == true)
        #expect(selection.stepDown() == nil)
    }

    @Test func aStepDownSurvivesStatsAndDrawableChangesButNotANewFile() {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(selection.stepDown()?.profile == .efficient)
        #expect(selection.update(facts: facts(bitrate: 600_000), stats: healthy).profile == .efficient)
        #expect(selection.setDrawable(pixels: Self.windowed).profile == .efficient)
        let next = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(next.profile == .compressed)
        #expect(next.isSteppedDown == false)
    }

    @Test func aBrokenProfileStaysExcludedAcrossFiles() {
        var selection = selection()
        _ = selection.beginFile(facts: facts(bitrate: 600_000))
        #expect(selection.markActiveProfileBroken()?.profile == .efficient)
        #expect(selection.beginFile(facts: facts(bitrate: 600_000)).profile == .efficient)
    }

    @Test func hdrNeverLeavesFaithfulAndCannotStepDown() {
        var selection = selection()
        var hdr = facts()
        hdr.isHDR = true
        let choice = selection.beginFile(facts: hdr)
        #expect(choice.profile == .off)
        #expect(choice.badgeText == "Auto · Faithful · HDR")
        #expect(selection.stepDown() == nil)
        #expect(selection.markActiveProfileBroken() == nil)
    }

    @Test func beforeAnythingIsKnownThePickIsPessimisticButValid() {
        var selection = AutomaticSelection(thresholds: thresholds)
        let choice = selection.beginFile(facts: SourceFacts())
        #expect(choice.profile == .sharpen)
    }
}
```

- [ ] **Step 2: Run it and see it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/AutomaticSelectionTests"
```

Expected: compile failure `error: cannot find 'AutomaticSelection' in scope`.

- [ ] **Step 3: Implement**

Create `Aagedal Media Player/Logic/MPV/AutomaticSelection.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The state behind the Automatic profile for one player: what is known about the file, what has
/// been rejected for it, and the profile that follows. It touches no mpv state, so the player only
/// applies the profile it returns.
nonisolated struct AutomaticSelection: Equatable, Sendable {
    nonisolated struct Choice: Equatable, Sendable {
        let profile: RenderProfile
        let classification: SourceClassification
        /// True once the GPU monitor or libplacebo has ruled out a heavier profile for this file.
        let isSteppedDown: Bool

        /// The badge text, for example `Auto · Compressed movie · 2.1 Mbit/s`.
        var badgeText: String {
            "Auto · \(profile.displayName) · \(classification.reason)" + (isSteppedDown ? " · stepped down" : "")
        }
    }

    private(set) var facts = SourceFacts()
    private(set) var stats: FrameStats?
    private(set) var current: Choice?
    private var drawablePixels = 0.0
    /// Profiles ruled out for the current file by the GPU budget.
    private var rejected: Set<RenderProfile> = []
    /// Profiles libplacebo refused to run. Kept for the life of the player.
    private var broken: Set<RenderProfile> = []
    private let thresholds: SourceClassifier.Thresholds

    init(thresholds: SourceClassifier.Thresholds = .calibrated) {
        self.thresholds = thresholds
    }

    /// A new file: metadata facts only, no stats yet, nothing rejected.
    mutating func beginFile(facts: SourceFacts) -> Choice {
        self.facts = facts
        stats = nil
        rejected = []
        return evaluate()
    }

    /// Analysis finished, or bitrate and tags became known. Facts replace the earlier ones.
    mutating func update(facts: SourceFacts, stats: FrameStats?) -> Choice {
        self.facts = facts
        self.stats = stats
        return evaluate()
    }

    /// The drawable changed size, in pixels. Rejections stay for the rest of the file.
    mutating func setDrawable(pixels: Double) -> Choice {
        drawablePixels = pixels
        return evaluate()
    }

    /// The GPU monitor reported over budget. Nil when already on Faithful.
    mutating func stepDown() -> Choice? {
        guard let active = current?.profile, active != .off else { return nil }
        rejected.insert(active)
        return evaluate()
    }

    /// libplacebo disabled the active profile's shaders. Nil when already on Faithful.
    mutating func markActiveProfileBroken() -> Choice? {
        guard let active = current?.profile, active != .off else { return nil }
        broken.insert(active)
        rejected.insert(active)
        return evaluate()
    }

    private mutating func evaluate() -> Choice {
        let classification = SourceClassifier.classify(facts, stats, thresholds: thresholds)
        let profile = ProfilePicker.pick(
            sourceClass: classification.sourceClass,
            fps: facts.fps,
            sourcePixels: facts.sourcePixels,
            drawablePixels: drawablePixels,
            excluding: broken.union(rejected)
        )
        let choice = Choice(profile: profile, classification: classification, isSteppedDown: !rejected.isEmpty)
        current = choice
        return choice
    }
}
```

- [ ] **Step 4: Run it and see it pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/AutomaticSelection.swift" "Aagedal Media Player Tests/AutomaticSelectionTests.swift"
git commit -m "Hold the Automatic profile selection in a testable value type"
```

---

## Task 6: Wire Automatic into MPVPlayer and remove the Enhance ladder

This task changes app code that has no unit seam (mpv, SwiftUI); its tests are the existing suites staying green plus the on-device checks in Task 7. Every edit below was applied to a scratch copy of the repo on 2026-10-02 (each `old` text matched exactly once), the app built, and the suites named in Step 8 passed.

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, `Aagedal Media Player/Logic/AppSettings.swift`, `Aagedal Media Player/Logic/AppCommand.swift`, `Aagedal Media Player/UI/ContentViewCommandHandlers.swift`, `Aagedal Media Player/UI/RenderSettingsView.swift`, `Aagedal Media Player/UI/RenderTierBadge.swift`, `Aagedal Media Player/UI/PlayerView.swift`
- Delete: `Aagedal Media Player/Logic/MPV/RenderTier.swift`, `Aagedal Media Player Tests/RenderTierTests.swift`
- `GPUBudgetMonitor.swift`, `EnhancementSuggestion.swift` and `EnhancementSuggestionView.swift` stay as they are: the banner already shows only while `renderProfile == .off` (`PlayerView.swift`).

**Interfaces:**
- Consumes: `AutomaticSelection` (Task 5), `FrameAnalyzer.shared.analyze(url:duration:)` and `SourceAnalysis` (Task 3), `SourceFacts` (Task 1), `GPUBudgetMonitor` (existing), `HDRTransferResolver.resolve(colorTransfer:)` (existing), `MPVProperty.duration`, `.containerFPS`, `.videoBitrate`, `.videoParamsDw`, `.videoParamsDh`, `.videoParamsGamma`, `.videoParamsPixelFormat`, `.videoParamsHWPixelFormat` (existing).
- Produces on `MPVPlayer`: `@Published private(set) var renderProfile: RenderProfile` (the Settings choice, may be `.automatic`), `@Published private(set) var activeProfile: RenderProfile` (what is applied), `@Published private(set) var automaticChoice: AutomaticSelection.Choice?`; `func setRenderProfile(_ profile: RenderProfile)` unchanged in signature. Removes `setEnhanceEnabled`, `activeTier`, `isTierSteppedDown`.

- [ ] **Step 1: Remove the Enhance setting, command, handler and Settings toggle**

The Profile picker stays; its section is renamed "Shader Profile" and the "overrides Enhance" note goes.

In `Aagedal Media Player/Logic/AppSettings.swift`, delete:

```swift
    /// Picks a shader tier automatically from the upscale ratio and GPU
    /// headroom. Off by default so the picture stays faithful to the source.
    static let enhance = AppSetting(key: "enhance", defaultValue: false)
```

In `Aagedal Media Player/Logic/AppSettings.swift`, delete:

```swift
            enhance.key: enhance.defaultValue,
```

In `Aagedal Media Player/Logic/AppCommand.swift`, delete:

```swift
    case setEnhance(Bool)
```

In `Aagedal Media Player/UI/ContentViewCommandHandlers.swift`, delete:

```swift
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand,
                      case .setEnhance(let enabled) = command else { return }
                // Global preference, like the render profile: every window follows it.
                controller.mpvPlayer?.setEnhanceEnabled(enabled)
            }
```

In `Aagedal Media Player/UI/RenderSettingsView.swift`, delete:

```swift
    @AppStorage(AppSettings.enhance.key)
    private var enhance = AppSettings.enhance.defaultValue
```

In `Aagedal Media Player/UI/RenderSettingsView.swift`, replace:

```swift
        RenderProfile(rawValue: renderProfileRaw) ?? .off
```

with:

```swift
        RenderProfile(rawValue: renderProfileRaw) ?? .automatic
```

In `Aagedal Media Player/UI/RenderSettingsView.swift`, replace:

```swift
            Section("Enhancement") {
                Toggle("Enhance", isOn: $enhance)
                    .onChange(of: enhance) { _, newValue in
                        NotificationCenter.default.post(.setEnhance(newValue))
                    }
                Text("Picks a sharpening or neural upscaling shader from how much the picture is enlarged, and steps down when the GPU cannot keep up. Enhancement alters the image; leave it off for inspection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
```

with:

```swift
            Section("Shader Profile") {
```

In `Aagedal Media Player/UI/RenderSettingsView.swift`, delete:

```swift
                if profile != .off {
                    Text("A manual profile other than Faithful overrides Enhance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
```

In `Aagedal Media Player/UI/RenderSettingsView.swift`, replace:

```swift
With Enhance on, amp measures that cost while playing and drops to a lighter shader when a frame no longer fits.
```

with:

```swift
With Automatic, amp measures that cost while playing and drops to a lighter shader when a frame no longer fits.
```

- [ ] **Step 2: Update the badge and the player view animations**

The badge shows `Auto · <profile> · <reason>` for Automatic (also when the pick is Faithful, so a reason such as HDR is visible), the profile name for a manual profile, and nothing for Faithful.

In `Aagedal Media Player/UI/RenderTierBadge.swift`, replace:

```swift
/// Names the shaders changing the picture: a manual profile, or the
/// automatic tier Enhance picked.
```

with:

```swift
/// Names the shaders changing the picture: a manual profile, or the
/// profile Automatic picked with the reason, for example `Auto · Compressed movie · 2.1 Mbit/s`.
```

In `Aagedal Media Player/UI/RenderTierBadge.swift`, replace:

```swift
        ShaderLibrary(directoryPath: shaderDirectory)
            .missingShaderNames(named: RenderTier.allCases.flatMap(\.shaderFileNames))
```

with:

```swift
        ShaderLibrary(directoryPath: shaderDirectory)
            .missingShaderNames(for: player.activeProfile)
```

In `Aagedal Media Player/UI/RenderTierBadge.swift`, replace:

```swift
    /// Nil when nothing alters the picture.
    private var label: String? {
        if player.renderProfile != .off { return player.renderProfile.displayName }
        if player.isTierSteppedDown { return "\(player.activeTier.displayName) · stepped down" }
        return player.activeTier != .faithful ? player.activeTier.displayName : nil
    }
```

with:

```swift
    /// Nil when nothing alters the picture. Under Automatic the badge stays up even on
    /// Faithful, so the reason (for example HDR) is visible.
    private var label: String? {
        if player.renderProfile == .automatic { return player.automaticChoice?.badgeText }
        return player.renderProfile == .off ? nil : player.renderProfile.displayName
    }
```

In `Aagedal Media Player/UI/PlayerView.swift`, replace:

```swift
                        .animation(.easeInOut(duration: 0.25), value: mpvPlayer.activeTier)
                        .animation(.easeInOut(duration: 0.25), value: mpvPlayer.isTierSteppedDown)
```

with:

```swift
                        .animation(.easeInOut(duration: 0.25), value: mpvPlayer.activeProfile)
                        .animation(.easeInOut(duration: 0.25), value: mpvPlayer.automaticChoice)
```

- [ ] **Step 3: Update the stale ShaderLibrary comment**

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, replace:

```swift
    /// Existing paths for `names`, in the given order. Shared by the manual
    /// profiles and the automatic tiers.
```

with:

```swift
    /// Existing paths for `names`, in the given order.
```

- [ ] **Step 4: Edit MPVPlayer, small changes**

These cancel analysis when a file is replaced or the player stops or is destroyed, call the new selection on file load, rename the reselection hook, replace the published state and make `setRenderProfile` apply either a concrete profile or the Automatic pick.

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
        tierReselection?.cancel()
        budgetSampling?.cancel()
        guard mpv != nil else { return }
```

with:

```swift
        automaticReselection?.cancel()
        automaticAnalysis?.cancel()
        budgetSampling?.cancel()
        guard mpv != nil else { return }
```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
        guard mpv != nil else {
            logger.info("MPV not initialized yet, storing pending load for: \(url.lastPathComponent)")
```

with:

```swift
        automaticAnalysis?.cancel()
        automaticAnalysis = nil
        guard mpv != nil else {
            logger.info("MPV not initialized yet, storing pending load for: \(url.lastPathComponent)")
```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
        command("stop")
        resetTimePosCoalescing()
```

with:

```swift
        command("stop")
        automaticAnalysis?.cancel()
        automaticAnalysis = nil
        resetTimePosCoalescing()
```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
                        // A new file gets the whole ladder back. Broken tiers stay excluded.
                        self.tierFloor = .fsrcnnx
                        self.reselectTier()
                        self.refreshBudgetMonitor()
```

with:

```swift
                        self.beginAutomaticSelection()
                        self.refreshBudgetMonitor()
```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
                                    self.scheduleTierReselection()
```

with:

```swift
                                    self.scheduleAutomaticReselection()
```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
    /// The shader stack currently applied to the render path.
    @Published private(set) var renderProfile: RenderProfile = .off

    /// The automatic tier in effect. `.faithful` whenever Enhance is off or a
    /// manual profile other than Faithful is chosen.
    @Published private(set) var activeTier: RenderTier = .faithful

    /// True when the GPU monitor forced a lighter tier than the ratio allows.
    @Published private(set) var isTierSteppedDown = false

    /// The heaviest tier allowed after GPU step-downs. Reset for each file.
    private var tierFloor: RenderTier = .fsrcnnx
    /// Tiers whose shaders libplacebo rejected. Kept for this player's lifetime.
    private var brokenTiers: Set<RenderTier> = []
    private var drawableSize: CGSize = .zero
    private var displayRefreshRate: Double = 0
    private var budgetMonitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
    private var tierReselection: Task<Void, Never>?
    private var budgetSampling: Task<Void, Never>?
```

with:

```swift
    /// The profile chosen in Settings. `.automatic` means one is picked for each file.
    @Published private(set) var renderProfile: RenderProfile = .automatic

    /// The profile whose shaders are applied now: `renderProfile` when it is concrete, the
    /// Automatic pick otherwise, and `.off` until a file has loaded.
    @Published private(set) var activeProfile: RenderProfile = .off

    /// The Automatic pick with its class and reason, for the badge. Nil unless Automatic is selected.
    @Published private(set) var automaticChoice: AutomaticSelection.Choice?

    private var automaticSelection = AutomaticSelection()
    private var automaticAnalysis: Task<Void, Never>?
    private var drawableSize: CGSize = .zero
    private var displayRefreshRate: Double = 0
    private var budgetMonitor = GPUBudgetMonitor(sourceFPS: 0, displayFPS: 0)
    private var automaticReselection: Task<Void, Never>?
    private var budgetSampling: Task<Void, Never>?
```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
        let profile = RenderProfile(rawValue: stored) ?? .off
        renderProfile = profile
```

with:

```swift
        let profile = RenderProfile(rawValue: stored) ?? .automatic
        renderProfile = profile
        activeProfile = profile == .automatic ? .off : profile
```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace:

```swift
        applyShaderStack(
            paths: shaderLibrary.shaderPaths(for: profile),
            scaleOptions: profile.scaleOptions,
            deband: profile.enablesDeband
        )
        activeTier = .faithful
        isTierSteppedDown = false
        updateBudgetSampling()
        reselectTier()
    }
```

with:

```swift
        automaticAnalysis?.cancel()
        automaticAnalysis = nil
        guard profile == .automatic else {
            automaticChoice = nil
            apply(profile: profile)
            return
        }
        // Switching to Automatic mid-file: pick from what is known, then look inside the file.
        if isFileLoaded {
            beginAutomaticSelection()
        } else {
            apply(profile: .off)
        }
    }

    /// Applies a concrete profile's shaders and scaler options to the running player.
    private func apply(profile: RenderProfile) {
        activeProfile = profile
        applyShaderStack(
            paths: shaderLibrary.shaderPaths(for: profile),
            scaleOptions: profile.scaleOptions,
            deband: profile.enablesDeband
        )
        refreshBudgetMonitor()
        updateBudgetSampling()
    }
```

- [ ] **Step 5: Replace the "Automatic Enhancement" region of MPVPlayer**

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, replace the region that starts at the line `    // MARK: - Automatic Enhancement` and ends just before the line `    /// Reads on mpv's queue: `vo-passes` blocks until the VO thread answers,` (that line and everything after it stay). The text to replace, exactly as it is in the file now:

```swift
    // MARK: - Automatic Enhancement

    func setEnhanceEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, for: AppSettings.enhance)
        reselectTier()
    }

    private func drawableSizeDidChange(_ size: CGSize) {
        drawableSize = size
        scheduleTierReselection()
    }

    /// A live window resize reports many sizes. Swapping shaders on each one
    /// would recompile them repeatedly, so wait for the size to settle.
    private func scheduleTierReselection() {
        tierReselection?.cancel()
        tierReselection = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.reselectTier()
        }
    }

    private func reselectTier() {
        guard mpv != nil, renderProfile == .off else { return }

        var target = RenderTier.faithful
        var steppedDown = false
        var ratioText = "unknown"

        // HDR content (PQ/HLG) bypasses enhancement tiers. The shaders in the
        // ladder were designed for SDR luma; how they behave on PQ or HLG luma
        // has not been measured. Until that measurement exists, stay faithful.
        let isHDR = HDRTransferResolver.resolve(colorTransfer: videoGamma) != .sdr

        if !isHDR,
           UserDefaults.standard.value(for: AppSettings.enhance),
           let source = videoSourceSize,
           let ratio = TierSelector.upscaleRatio(source: source, drawable: drawableSize) {
            ratioText = String(format: "%.3f", ratio)
            let library = shaderLibrary
            let fullChroma = TierSelector.hasFullResolutionChroma(
                pixelFormat: getString("video-params/hw-pixelformat") ?? getString("video-params/pixelformat")
            )
            let available = Set(RenderTier.allCases.filter { tier in
                !brokenTiers.contains(tier)
                    && !(tier == .chroma && fullChroma)
                    && library.missingShaderNames(named: tier.requiredShaderFileNames).isEmpty
            })
            target = TierSelector.select(ratio: ratio, available: available, floor: tierFloor)
            steppedDown = target < TierSelector.select(ratio: ratio, available: available, floor: .fsrcnnx)
        } else if isHDR {
            ratioText = "HDR (no enhancement)"
        }
        isTierSteppedDown = steppedDown
        guard target != activeTier else { return }

        activeTier = target
        applyShaderStack(
            paths: shaderLibrary.shaderPaths(named: target.shaderFileNames),
            scaleOptions: target.scaleOptions,
            deband: false
        )
        refreshBudgetMonitor()
        logger.info("Render tier: \(target.displayName, privacy: .public) ratio=\(ratioText, privacy: .public) drawable=\(Int(self.drawableSize.width))x\(Int(self.drawableSize.height))")
        updateBudgetSampling()
    }

    /// A new budget for the current file: its frame rate and a clean drop history.
    private func refreshBudgetMonitor() {
        budgetMonitor = GPUBudgetMonitor(sourceFPS: getDouble("container-fps"), displayFPS: displayRefreshRate)
    }

    private func stepDownTier(reason: String) {
        guard activeTier != .faithful else { return }
        tierFloor = activeTier.steppedDown
        logger.notice("Render tier \(self.activeTier.displayName, privacy: .public) stepped down: \(reason, privacy: .public)")
        reselectTier()
    }

    private func handleShaderFailure() {
        guard activeTier != .faithful else { return }
        brokenTiers.insert(activeTier)
        stepDownTier(reason: "libplacebo disabled a shader hook")
    }

    /// Samples once a second while a non-faithful tier or a manual profile is
    /// active. Only tiers step down; manual profiles just log their GPU time
    /// (`log stream --level debug --predicate 'category == "MPVPlayer"'`).
    private func updateBudgetSampling() {
        guard activeTier != .faithful || renderProfile != .off else {
            budgetSampling?.cancel()
            budgetSampling = nil
            return
        }
        guard budgetSampling == nil else { return }
        logger.debug("GPU sampling started")
        budgetSampling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                guard self.isPlaying, let sample = await self.readBudgetSample() else { continue }
                self.logger.debug("GPU \(self.renderProfile.rawValue, privacy: .public)/\(self.activeTier.displayName, privacy: .public): \(sample.timing?.totalMilliseconds ?? -1, format: .fixed(precision: 2), privacy: .public) ms samples=\(sample.timing?.minimumSampleCount ?? 0) drops=\(sample.droppedFrames) drawable=\(Int(self.drawableSize.width))x\(Int(self.drawableSize.height))")
                guard self.activeTier != .faithful else { continue }
                if self.budgetMonitor.evaluate(sample) == .overBudget {
                    self.stepDownTier(reason: "over GPU budget")
                }
            }
        }
    }
```

with:

```swift
    // MARK: - Automatic Profile

    /// A new file under Automatic: pick from metadata now, then look inside the file.
    private func beginAutomaticSelection() {
        guard mpv != nil, renderProfile == .automatic else { return }
        automaticAnalysis?.cancel()
        // The drawable size is known before the first file; the selection has not seen it yet.
        _ = automaticSelection.setDrawable(pixels: drawableSize.width * drawableSize.height)
        applyAutomatic(automaticSelection.beginFile(facts: currentSourceFacts(topazTag: nil)))
        startAnalysis()
    }

    /// What mpv knows about the loaded file. `topazTag` is the tag already found, if any.
    private func currentSourceFacts(topazTag: String?) -> SourceFacts {
        let duration = getDouble(MPVProperty.duration)
        var bitrate = Int64(getInt(MPVProperty.videoBitrate))
        if bitrate <= 0, duration > 0 {
            // `video-bitrate` fills in per keyframe and can still be empty at load. The file size
            // over the duration includes audio, which errs towards "not compressed".
            let bytes = getInt("file-size")
            if bytes > 0 { bitrate = Int64(Double(bytes) * 8 / duration) }
        }
        let width = videoSourceSize.map { Int($0.width) } ?? getInt(MPVProperty.videoParamsDw)
        let height = videoSourceSize.map { Int($0.height) } ?? getInt(MPVProperty.videoParamsDh)
        let pixelFormat = getString(MPVProperty.videoParamsHWPixelFormat) ?? getString(MPVProperty.videoParamsPixelFormat)
        return SourceFacts(
            codec: getString("current-tracks/video/codec"),
            width: width,
            height: height,
            fps: getDouble(MPVProperty.containerFPS),
            videoBitrate: bitrate,
            bitDepth: SourceFacts.bitDepth(pixelFormat: pixelFormat),
            isHDR: HDRTransferResolver.resolve(colorTransfer: getString(MPVProperty.videoParamsGamma) ?? videoGamma) != .sdr,
            topazTag: topazTag ?? getString("metadata/by-key/videoai") ?? getString("metadata/by-key/videoai_provider")
        )
    }

    /// Reads a few frames off the main actor, then re-picks with the statistics. A result for a
    /// file that has since been replaced is dropped: loading cancels this task.
    private func startAnalysis() {
        guard let path = getString("path"), FileManager.default.fileExists(atPath: path) else { return }
        let url = URL(fileURLWithPath: path)
        let duration = getDouble(MPVProperty.duration)
        automaticAnalysis = Task { [weak self] in
            let analysis = await FrameAnalyzer.shared.analyze(url: url, duration: duration)
            guard !Task.isCancelled, let self, self.renderProfile == .automatic else { return }
            self.finishAnalysis(analysis)
        }
    }

    private func finishAnalysis(_ analysis: SourceAnalysis) {
        let facts = currentSourceFacts(topazTag: analysis.topazTag ?? automaticSelection.facts.topazTag)
        if let stats = analysis.stats {
            logger.info("Frame stats: detail=\(stats.detailRatio, format: .fixed(precision: 3), privacy: .public) blockiness=\(stats.blockiness, format: .fixed(precision: 3), privacy: .public) noise=\(stats.noise, format: .fixed(precision: 4), privacy: .public)")
        } else {
            logger.info("No frame stats, keeping the metadata pick")
        }
        applyAutomatic(automaticSelection.update(facts: facts, stats: analysis.stats))
    }

    /// Publishes the choice for the badge and applies its shaders only when the profile changed.
    private func applyAutomatic(_ choice: AutomaticSelection.Choice) {
        automaticChoice = choice
        guard choice.profile != activeProfile else { return }
        logger.info("Automatic profile: \(choice.profile.displayName, privacy: .public) (\(choice.classification.sourceClass.rawValue, privacy: .public), \(choice.classification.reason, privacy: .public)) drawable=\(Int(self.drawableSize.width))x\(Int(self.drawableSize.height))")
        apply(profile: choice.profile)
    }

    private func drawableSizeDidChange(_ size: CGSize) {
        drawableSize = size
        scheduleAutomaticReselection()
    }

    /// A live window resize reports many sizes. Swapping shaders on each one
    /// would recompile them repeatedly, so wait for the size to settle.
    private func scheduleAutomaticReselection() {
        automaticReselection?.cancel()
        automaticReselection = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.reselectAutomatic()
        }
    }

    /// Re-picks with the same statistics for the new drawable. Facts are refreshed too, because
    /// the bitrate and source size may have become known since the file loaded.
    private func reselectAutomatic() {
        guard mpv != nil, renderProfile == .automatic, isFileLoaded else { return }
        let facts = currentSourceFacts(topazTag: automaticSelection.facts.topazTag)
        _ = automaticSelection.update(facts: facts, stats: automaticSelection.stats)
        applyAutomatic(automaticSelection.setDrawable(pixels: drawableSize.width * drawableSize.height))
    }

    /// A new budget for the current file: its frame rate and a clean drop history.
    private func refreshBudgetMonitor() {
        budgetMonitor = GPUBudgetMonitor(sourceFPS: getDouble("container-fps"), displayFPS: displayRefreshRate)
    }

    /// The GPU monitor reported over budget: rule out the active profile for the rest of the file.
    private func stepDownAutomatic(reason: String) {
        guard let choice = automaticSelection.stepDown() else { return }
        logger.notice("Automatic profile stepped down to \(choice.profile.displayName, privacy: .public): \(reason, privacy: .public)")
        applyAutomatic(choice)
    }

    private func handleShaderFailure() {
        guard renderProfile == .automatic, let choice = automaticSelection.markActiveProfileBroken() else { return }
        logger.notice("Automatic profile moved to \(choice.profile.displayName, privacy: .public): libplacebo disabled a shader hook")
        applyAutomatic(choice)
    }

    /// Samples once a second while any shader profile is active. Under Automatic an
    /// over-budget reading steps the profile down; a manual profile just logs its GPU time
    /// (`log stream --level debug --predicate 'subsystem == "com.aagedal.MediaPlayer"'`).
    private func updateBudgetSampling() {
        guard activeProfile != .off else {
            budgetSampling?.cancel()
            budgetSampling = nil
            return
        }
        guard budgetSampling == nil else { return }
        logger.debug("GPU sampling started")
        budgetSampling = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                guard self.isPlaying, let sample = await self.readBudgetSample() else { continue }
                self.logger.debug("GPU \(self.renderProfile.rawValue, privacy: .public)/\(self.activeProfile.rawValue, privacy: .public): \(sample.timing?.totalMilliseconds ?? -1, format: .fixed(precision: 2), privacy: .public) ms samples=\(sample.timing?.minimumSampleCount ?? 0) drops=\(sample.droppedFrames) drawable=\(Int(self.drawableSize.width))x\(Int(self.drawableSize.height))")
                guard self.renderProfile == .automatic else { continue }
                if self.budgetMonitor.evaluate(sample) == .overBudget {
                    self.stepDownAutomatic(reason: "over GPU budget")
                }
            }
        }
    }
```

What the new code does, for review: `beginAutomaticSelection` feeds the selection the drawable size and the metadata facts, applies the first pick and starts the analysis task; `startAnalysis` runs `FrameAnalyzer` off the main actor and drops the result if loading cancelled the task; `applyAutomatic` publishes the choice for the badge and re-applies shaders only when the profile differs from `activeProfile`; a drawable change re-picks after 300 ms with the same stats; an over-budget `GPUBudgetMonitor` verdict calls `stepDown`, a libplacebo failure calls `markActiveProfileBroken`; the once-a-second `GPU <profile>/<active>: X ms samples=N drops=D drawable=WxH` debug log now runs whenever any non-Faithful profile is active, including Automatic.

- [ ] **Step 6: Delete the tier ladder and its tests**

```bash
git rm "Aagedal Media Player/Logic/MPV/RenderTier.swift" "Aagedal Media Player Tests/RenderTierTests.swift"
```

`RenderTierTests.libraryResolvesNameLists` is already covered by `RenderProfileTests.testLibraryResolvesNameLists` (Task 4); `RenderTierTests.enhanceIsOffByDefault` is obsolete because the key is gone.

- [ ] **Step 7: Check nothing references the removed code, then build**

```bash
rg -n "RenderTier\b|TierSelector|activeTier|isTierSteppedDown|setEnhance|AppSettings\.enhance|reselectTier|scheduleTierReselection|tierFloor|brokenTiers" "Aagedal Media Player" "Aagedal Media Player Tests"
xcodebuild build -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```

Expected: `rg` prints nothing (exit status 1); the build ends with `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Run the affected suites**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/RenderProfileTests" -only-testing:"Aagedal Media Player Tests/SettingsMigrationTests" -only-testing:"Aagedal Media Player Tests/SettingsCoverageTests" -only-testing:"Aagedal Media Player Tests/GPUBudgetMonitorTests" -only-testing:"Aagedal Media Player Tests/EnhancementSuggestionTests" -only-testing:"Aagedal Media Player Tests/SourceClassifierTests" -only-testing:"Aagedal Media Player Tests/ProfilePickerTests" -only-testing:"Aagedal Media Player Tests/FrameMathTests" -only-testing:"Aagedal Media Player Tests/AutomaticSelectionTests" -only-testing:"Aagedal Media Player Tests/FrameAnalyzerIntegrationTests"
```

Expected: `** TEST SUCCEEDED **`. `SettingsCoverageTests` passing confirms every remaining registered key still has a control in `UI/`.

- [ ] **Step 9: Commit**

```bash
git add -A "Aagedal Media Player" "Aagedal Media Player Tests"
git commit -m "Wire the Automatic profile into the player and remove the Enhance ladder"
```

---

## Task 7: Calibrate thresholds and verify on device

**Files:**
- Create: `scripts/calibrate-profile-picker.sh`, `scripts/calibrate-profile-picker/main.swift`
- Modify (after the user approves): `Aagedal Media Player/Logic/MPV/SourceClassifier.swift`

**Interfaces:**
- Consumes: `SourceClassifier.classify`, `SourceFacts`, `FrameMath` (compiled straight from the app sources, so the output is what the app computes).
- Produces: a tab-separated table on standard output, one row per video: `file, codec, size, fps, kbit_s, bits_per_pixel, bit_depth, hdr, topaz, detail, blockiness, noise, class, reason`. Numbers only; no frame is written or shown. Needs `ffmpeg` and `ffprobe` on `PATH` (or `FFMPEG`/`FFPROBE`); on this Mac both are in `/Users/filip/.local/bin`.

- [ ] **Step 1: Write the calibration program**

Create `scripts/calibrate-profile-picker/main.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Prints, for every video under the given folders, the facts amp reads from metadata, the frame
// statistics, and the class the shipped classifier gives it. Numbers only: no frame is saved or
// shown. Built by scripts/calibrate-profile-picker.sh from the app's own SourceClassifier.swift
// and FrameMath.swift, so the output is what the app would compute.

import Foundation

let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "mts", "m2ts", "ts", "mxf"]

func tool(_ name: String, environment key: String) -> String {
    if let override = ProcessInfo.processInfo.environment[key], !override.isEmpty { return override }
    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    probe.arguments = [name]
    let pipe = Pipe()
    probe.standardOutput = pipe
    try? probe.run()
    probe.waitUntilExit()
    let path = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
        FileHandle.standardError.write(Data("\(name) not found; set \(key)\n".utf8))
        exit(1)
    }
    return path
}

let ffmpeg = tool("ffmpeg", environment: "FFMPEG")
let ffprobe = tool("ffprobe", environment: "FFPROBE")

func run(_ executable: String, _ arguments: [String]) -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return Data() }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
}

func number(_ value: Any?) -> Double? {
    if let string = value as? String { return Double(string) }
    return (value as? NSNumber)?.doubleValue
}

func frameRate(_ value: Any?) -> Double {
    guard let text = value as? String else { return 0 }
    let parts = text.split(separator: "/").compactMap { Double($0) }
    if parts.count == 2, parts[1] > 0 { return parts[0] / parts[1] }
    return parts.first ?? 0
}

func probe(_ path: String) -> (facts: SourceFacts, duration: Double)? {
    let data = run(ffprobe, ["-v", "error", "-select_streams", "v:0",
                             "-show_entries", "stream=codec_name,width,height,avg_frame_rate,bit_rate,pix_fmt,color_transfer:stream_tags:format=duration,bit_rate:format_tags",
                             "-of", "json", path])
    guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let stream = (root["streams"] as? [[String: Any]])?.first else { return nil }
    let format = root["format"] as? [String: Any] ?? [:]
    let duration = number(format["duration"]) ?? 0
    let bitrate = number(stream["bit_rate"]) ?? number(format["bit_rate"]) ?? 0
    let transfer = (stream["color_transfer"] as? String) ?? ""
    var tags: [String: Any] = (format["tags"] as? [String: Any]) ?? [:]
    tags.merge((stream["tags"] as? [String: Any]) ?? [:]) { first, _ in first }
    let topaz = tags.first { ["videoai", "videoai_provider"].contains($0.key.lowercased()) }.map { "\($0.value)" }
    let facts = SourceFacts(
        codec: stream["codec_name"] as? String,
        width: Int(number(stream["width"]) ?? 0),
        height: Int(number(stream["height"]) ?? 0),
        fps: frameRate(stream["avg_frame_rate"]),
        videoBitrate: Int64(bitrate),
        bitDepth: SourceFacts.bitDepth(pixelFormat: stream["pix_fmt"] as? String),
        isHDR: transfer == "smpte2084" || transfer == "arib-std-b67",
        topazTag: topaz
    )
    return (facts, duration)
}

func stats(_ path: String, duration: Double) -> FrameStats? {
    var frames: [FrameStats] = []
    for time in FrameMath.sampleTimes(duration: duration) {
        let data = run(ffmpeg, ["-hide_banner", "-loglevel", "error", "-nostdin", "-ss", String(format: "%.3f", time),
                                "-i", path, "-frames:v", "1", "-an", "-sn", "-pix_fmt", "gray",
                                "-f", "image2pipe", "-c:v", "pgm", "-"])
        if let image = FrameMath.parsePGM(data), let value = FrameMath.stats(luma: image.luma, width: image.width, height: image.height) {
            frames.append(value)
        }
    }
    return frames.count >= 4 ? FrameMath.average(frames) : nil
}

func files(under folder: String) -> [String] {
    let root = (folder as NSString).expandingTildeInPath
    guard let walker = FileManager.default.enumerator(atPath: root) else { return [] }
    var found: [String] = []
    for case let relative as String in walker where videoExtensions.contains((relative as NSString).pathExtension.lowercased()) {
        found.append((root as NSString).appendingPathComponent(relative))
    }
    return found.sorted()
}

let folders = CommandLine.arguments.count > 1
    ? Array(CommandLine.arguments.dropFirst())
    : ["~/Downloads/Movies", "~/Downloads/whatsapp", "~/Downloads/Archives/Movies"]

print(["file", "codec", "size", "fps", "kbit_s", "bits_per_pixel", "bit_depth", "hdr", "topaz",
       "detail", "blockiness", "noise", "class", "reason"].joined(separator: "\t"))
for folder in folders {
    for path in files(under: folder) {
        guard let (facts, duration) = probe(path) else { continue }
        let measured = stats(path, duration: duration)
        let result = SourceClassifier.classify(facts, measured)
        let columns: [String] = [
            path,
            facts.codec ?? "-",
            "\(facts.width)x\(facts.height)",
            String(format: "%.3f", facts.fps),
            String(format: "%.0f", Double(facts.videoBitrate) / 1000),
            facts.bitsPerPixel.map { String(format: "%.4f", $0) } ?? "-",
            facts.bitDepth.map(String.init) ?? "-",
            facts.isHDR ? "yes" : "no",
            facts.topazTag == nil ? "no" : "yes",
            measured.map { String(format: "%.3f", $0.detailRatio) } ?? "-",
            measured.map { String(format: "%.3f", $0.blockiness) } ?? "-",
            measured.map { String(format: "%.4f", $0.noise) } ?? "-",
            result.sourceClass.rawValue,
            result.reason,
        ]
        print(columns.joined(separator: "\t"))
        fflush(stdout)
    }
}
```

- [ ] **Step 2: Write the wrapper script**

Create `scripts/calibrate-profile-picker.sh`:

```bash
#!/bin/bash

# Aagedal Media Player
# Copyright © 2026 Truls Aagedal
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints facts, frame statistics and the resulting class for every video under the given
# folders (default: ~/Downloads/Movies, ~/Downloads/whatsapp, ~/Downloads/Archives/Movies).
# Tab-separated numbers only; no frame is written to disk or shown. The classifier and the
# frame maths are compiled from the app's own sources, so the output matches the app.
#
# Usage: scripts/calibrate-profile-picker.sh [folder]   (any number of folders)
# Environment: FFMPEG and FFPROBE override the binaries found on PATH.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repository_dir="$(cd "$script_dir/.." && pwd)"
logic_dir="$repository_dir/Aagedal Media Player/Logic/MPV"
workspace_dir="$(mktemp -d "${TMPDIR:-/tmp}/aagedal-calibrate.XXXXXX")"
trap 'rm -rf "$workspace_dir"' EXIT

swiftc -O -o "$workspace_dir/calibrate" \
    "$logic_dir/SourceClassifier.swift" \
    "$logic_dir/FrameMath.swift" \
    "$script_dir/calibrate-profile-picker/main.swift"

"$workspace_dir/calibrate" "$@"
```

```bash
chmod +x scripts/calibrate-profile-picker.sh
shellcheck scripts/calibrate-profile-picker.sh
shfmt -i 4 -d scripts/calibrate-profile-picker.sh
```

Expected: no output from either linter (both were run clean on this script).

- [ ] **Step 3: Smoke-test on one folder**

```bash
scripts/calibrate-profile-picker.sh "$HOME/Downloads/Movies/other" | head -5
```

Expected: a header row and data rows with 14 tab-separated columns each, for example a 1080p row with `clean` or `compressed` in column 13. This was run on 2026-10-02 against that folder.

- [ ] **Step 4: Run it over the three folders from the spec**

```bash
scripts/calibrate-profile-picker.sh > "$TMPDIR/profile-picker-calibration.tsv"
column -t -s $'\t' "$TMPDIR/profile-picker-calibration.tsv" | head -80
```

The folders are `~/Downloads/Movies`, `~/Downloads/whatsapp` and `~/Downloads/Archives/Movies`. The table stays in `$TMPDIR`; it contains the user's file names and is not committed.

- [ ] **Step 5: Stop for the user's approval of the thresholds**

Show the user the table summarised by class, with the three current starting thresholds (`lowBitsPerPixel` 0.05, `blockiness` 1.6, `softDetailRatio` 0.54) and which rows each would flip. Do not edit any threshold until the user has approved specific values in chat. The classes the user expects for named files decide the values; record their answer.

- [ ] **Step 6: Fix the approved thresholds in code**

In `Aagedal Media Player/Logic/MPV/SourceClassifier.swift`, change the three numbers in this one line to the approved values, keeping the argument labels:

```swift
        static let calibrated = Thresholds(lowBitsPerPixel: 0.05, blockiness: 1.6, softDetailRatio: 0.54)
```

and change the doc comment above it from "Starting values. Task 7 replaces them with the approved calibration." to "Set from the calibration run the user approved on <date of approval>." The unit tests pass explicit `Thresholds` values, so they do not change. Re-run the calibration and confirm the classes in column 13 match what the user approved, then:

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/SourceClassifierTests" -only-testing:"Aagedal Media Player Tests/AutomaticSelectionTests"
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit the script, then the thresholds**

```bash
git add scripts/calibrate-profile-picker.sh scripts/calibrate-profile-picker
git commit -m "Add a calibration script for the profile picker"
git add "Aagedal Media Player/Logic/MPV/SourceClassifier.swift"
git commit -m "Set the classifier thresholds from the approved calibration"
```

- [ ] **Step 8: Build and install into /Applications/amp.app**

```bash
xcodebuild build -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -configuration Release -destination platform=macOS -derivedDataPath /private/tmp/amp-dd CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
osascript -e 'quit app id "com.aagedal.MediaPlayer"'
rm -rf /Applications/amp.app && cp -R "/private/tmp/amp-dd/Build/Products/Release/Aagedal Media Player.app" /Applications/amp.app
defaults write com.aagedal.MediaPlayer renderProfile -string automatic
defaults read com.aagedal.MediaPlayer renderProfile
```

Expected: `** BUILD SUCCEEDED **`, then `automatic`. (This machine currently stores `chroma` for this key; the write sets it to the new default.)

- [ ] **Step 9: Prepare the one file per class**

Pick one real file per class from the Step 4 table (hdr, compressed, soft, clean) and use `hdr10-test.mp4` from `~/Downloads/Movies` if the table has no other HDR row. For the two Topaz cases generate files with the same tags the analyzer reads:

```bash
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1920x1080:rate=24:duration=20" -an -c:v libx264 -preset ultrafast -crf 20 -pix_fmt yuv420p -metadata:s:v:0 videoai_provider=Topaz /private/tmp/topaz-24.mkv
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1920x1080:rate=60:duration=20" -an -c:v libx264 -preset ultrafast -crf 20 -pix_fmt yuv420p -metadata:s:v:0 videoai_provider=Topaz /private/tmp/topaz-60.mkv
```

- [ ] **Step 10: Check each class (windowed), reading the log**

Start the log capture and keep its pid (never `pkill -f` with a pattern that appears in your own command; that kills the agent shell):

```bash
/usr/bin/log stream --level debug --style compact --predicate 'subsystem == "com.aagedal.MediaPlayer"' > /private/tmp/amp-auto.log 2>&1 &
echo $! > /private/tmp/amp-auto.pid
```

For each file: `open -a /Applications/amp.app "<file>"`, wait 10 s, then:

```bash
rg "Automatic profile:|Frame stats:|No frame stats" /private/tmp/amp-auto.log | tail -3
```

Expected per class (a screenshot of the badge, top left of the picture, must read the same text):

| File | Expected log line and badge |
|---|---|
| HDR file, opened first after launch | no `Automatic profile` line (Faithful is already active); badge `Auto · Faithful · HDR` |
| `/private/tmp/topaz-24.mkv` | `Automatic profile: Neural upscale — light (topaz, Topaz tag)`; badge `Auto · Neural upscale — light · Topaz tag` |
| a compressed row from the table | `Compressed movie` or `Efficient upscale` depending on size and window, class `compressed` |
| a soft row | `Crisp` or `Neural upscale — light` depending on size and window, class `soft` |
| a clean row | `Neural upscale — light` (at most 30 fps) or `Sharpened upscale` (above 30 fps) |

If a class lands on a different profile than its row says, copy the log lines to the user rather than adjusting code.

- [ ] **Step 11: 60 fps Topaz lands on a light profile**

Open `/private/tmp/topaz-60.mkv` and run the `rg` from Step 10. Expected: `Automatic profile: Sharpened upscale (topaz, Topaz tag)`.

- [ ] **Step 12: Fullscreen GPU run shows no sustained drops**

Open the compressed file, wait about 7 s, then use the menu item Playback, Toggle Fullscreen (it is disabled earlier; fullscreen is not restored on relaunch). Play for 60 s, then:

```bash
rg -o "GPU automatic/[A-Za-z]+: [0-9.]+ ms samples=[0-9]+ drops=[0-9]+ drawable=[0-9x]+" /private/tmp/amp-auto.log | tail -70
rg "stepped down" /private/tmp/amp-auto.log
```

Expected: the `drops=` value grows by at most 2 across the 60 s of samples taken after the first 30 samples, `drawable=3448x1940` appears (fullscreen on the built-in display), and any `stepped down` line is reported to the user with the profile it landed on. Then stop the capture: `kill "$(cat /private/tmp/amp-auto.pid)"`.

- [ ] **Step 13: Manual overrides still work**

In Settings, Rendering, Shader Profile, pick Faithful: the badge disappears and, for a low-bitrate file, the Enhancement Available banner appears. Pick Compressed movie: the badge reads `Compressed movie`. Pick Automatic again: the badge returns to `Auto · <profile> · <reason>` within a second. Report each result; nothing to commit.

---

## Task 8: Documentation and full-suite run

**Files:**
- Modify: `README.md`, `CHANGELOG.md`

- [ ] **Step 1: Update the README and CHANGELOG**

In `README.md`, replace:

```swift
### Enhancement suggestion

Low-bitrate (<10 Mbit/s) or low-resolution videos show a banner. **Enhance Now**
applies a real-time shader profile from your mpv shader folder; change it any
time in Settings → Rendering → Profile.
```

with:

```swift
### Automatic shader profile

By default amp looks at each file when it opens and picks a real-time shader
profile from your mpv shader folder: HDR stays Faithful, Topaz-enhanced files
(tagged `videoai`) get a light upscaler, low-bitrate or blocky files get
Compressed movie, soft upscaled files get Crisp, and everything else gets a
neural or sharpened upscale. Above 30 fps it picks lighter profiles. The pick
fits 80 % of the frame period at the current window size, is refined after eight
frames have been measured, follows window and fullscreen changes, and steps down
for the rest of the file if the GPU cannot keep up. The badge names the choice,
for example `Auto · Compressed movie · 2.1 Mbit/s`. Choose any other profile in
Settings → Rendering → Shader Profile to override it; Faithful turns processing
off for inspection.

### Enhancement suggestion

While Faithful is selected, low-bitrate (<10 Mbit/s) or low-resolution videos
show a banner. **Enhance Now** applies a real-time shader profile from your mpv
shader folder; change it any time in Settings → Rendering → Shader Profile.
```

In `CHANGELOG.md`, replace:

```swift
- An opt-in **Enhance** mode that picks a sharpening or neural upscaling shader tier from how much the picture is enlarged, steps down to a lighter tier when the GPU cannot keep up, and shows a badge naming the active tier. Shaders come only from the user's mpv shader folder; nothing is bundled, and the default render path stays faithful to the source.
```

with:

```swift
- An **Automatic** shader profile, now the default, that picks a real-time profile for each file from its metadata (HDR, Topaz tag, bits per pixel, frame rate) and eight measured frames (detail, blockiness, noise), fits it to 80 % of the frame period at the current window size, follows window and fullscreen changes, and steps down for the rest of the file when the GPU cannot keep up. The badge reads `Auto · <profile> · <reason>`. Shaders come only from the user's mpv shader folder; nothing is bundled. Choose Faithful in Settings → Rendering for inspection. This replaces the earlier Enhance toggle; a stored Enhance setting with Faithful selected becomes Automatic.
```

- [ ] **Step 2: Check the docs for stale Enhance wording**

```bash
rg -n -i "Enhance toggle|Settings → Rendering → Profile|opt-in \*\*Enhance\*\*" README.md CHANGELOG.md docs/*.md
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Document the Automatic shader profile"
```

- [ ] **Step 4: Full suite**

Run in the background (about 10 minutes):

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$TMPDIR/amp-full-suite.log" 2>&1
rg "Test Suite 'All tests'|TEST (SUCCEEDED|FAILED)|failed" "$TMPDIR/amp-full-suite.log" | head
```

Expected: `** TEST SUCCEEDED **`. If only `CompareLiveBackendTests` fails, rerun that suite alone (`-only-testing:"Aagedal Media Player Tests/CompareLiveBackendTests"`) before calling it a regression; it is known to be flaky under load.

---

## Self-review against the spec

- Behaviour: Automatic in Settings (Task 4, 6), applies without asking (Task 6), badge `Auto · <profile> · <reason>` (Tasks 5, 6), Enhance toggle and ladder removed with `GPUBudgetMonitor` kept (Task 6), migration and new default (Task 4).
- Classes and mapping: hdr > topaz > compressed > soft > clean (Task 1), chains per class and frame-rate column (Task 2).
- Components 1 to 6: `SourceFacts`/`FrameStats` (Task 1), `FrameAnalyzer` with eight frames, 5 % skips, detail/blockiness/noise, cache, cancellation and off-main-actor work (Task 3), `SourceClassifier` with nil stats (Task 1), `ProfilePicker` with 0.8 budget (Task 2), player wiring: metadata pick, analysis refine, re-apply only on change, drawable re-pick, budget step-down (Tasks 5, 6).
- Thresholds from a calibration run with the user's approval (Task 7).
- Error handling: no ffmpeg, decode failure, short file, 5 s timeout, file changed during analysis (Task 3); missing shader file keeps `ShaderLibrary` behaviour (unchanged).
- Testing: classifier, picker at 24/30/60 fps, 720p/1080p, windowed/fullscreen, synthetic frames, fixture integration, on-device (Tasks 1 to 3, 7).
- Out of scope respected: no 25 fps resample fix, no models, no HDR enhancement, no disk cache.

## Decisions where the spec was open

1. **Topaz tag source.** SwiftMediaMetadata exposes no tags, so the tag comes from mpv `metadata/by-key/videoai` or `videoai_provider` at load and from `ffmpeg -i` output in the analyzer (Tasks 3, 6).
2. **Cost estimate.** Piecewise linear in source pixels through both measured columns instead of scaling the 1080p figure alone (Task 2).
3. **Table entries.** Only profiles that appear in a chain and have both measurements are in the cost table; compressedGrain, restore and upscaleStrong are out of every chain.
4. **Enhance removal moves to Task 6** (with the player rewrite), because earlier removal breaks the build; the spec's component 6 and its Settings UI change land together there. Component 6 is split into the pure `AutomaticSelection` (Task 5, unit tested) and the player glue (Task 6).
5. **Step-down** rules out the active profile for the rest of the file (a set of profiles), not a chain position, so it stays correct if analysis changes the class later.
6. **Badge** stays visible under Automatic even when the pick is Faithful, so the reason (for example HDR) shows.
7. **Frame rate edge cases.** 30.5 fps is the boundary for the above-30-fps chains so 30 and 29.97 fps use the normal chains; an unknown frame rate counts as 30 fps; an unknown source or drawable size counts as 1080p and fullscreen.
8. **Bitrate.** mpv's `video-bitrate` can be empty at load; the first pick falls back to file size x 8 / duration, and the post-analysis re-pick and every drawable re-pick read the facts again.
9. **`noise`** is computed, logged and available to the calibration script, but no class uses it; the spec defines no noise rule.
10. **Two budgets coexist.** The picker fits profiles to 0.8 x the frame period (spec). The existing `GPUBudgetMonitor` keeps its own measured threshold of 0.5 x the period of the slower of source and display. A pick near the picker's limit (for example Compressed movie on a 1080p 24 fps file fullscreen: 33.0 ms estimated against a 33.3 ms limit) can therefore be stepped down by the monitor once it has 30 warm samples. Task 7 Step 12 shows how often that happens; changing either number is a separate decision for the user.
11. **Fixtures** are added without changing the `schema=5` line that `CompareLiveBackendTests` requires.
12. **Settings label.** The Profile section is renamed "Shader Profile" and the "overrides Enhance" note is removed.
