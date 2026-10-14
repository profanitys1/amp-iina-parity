# AMP: VLC behaviour, IINA look, engine fixes: implementation plan

> For agentic workers: execute task by task, in order. Every task gives the real code or the exact edit and its anchor (`file:line` on branch `iina-parity` @ `ff2b69a`). Part 1 is pure logic and is implemented in the cloud session. Parts 2–5 need Xcode on the Mac.

## Context

An earlier agent ("antigravity") broke AMP. Its work was reverted and saved on branch `antigravity-wip` (`d0e6c7d`). The user then asked for AMP to behave like VLC 3 for macOS and look like IINA 1.5, while keeping AMP's pro features.

### Binding decisions (user, HANDOFF §2/§8)

- Behaviour follows VLC, the look follows IINA, and AMP's features stay.
- The keymap can be switched between "VLC" (the default) and "AMP Pro".
- Double-click fills the screen and stays windowed. In native fullscreen it exits fullscreen instead.
- A single click does nothing; dragging more than 3 pt moves the window.
- The minimum window stays 690×540.
- The title stays hidden.
- The controls auto-hide while paused.
- The floating controller sits 10 % of the video height above the bottom.
- **Subtitles are out of scope.** Existing subtitle behaviour stays untouched.

### Evidence

Every fact below comes from a primary source. The sources are in `docs/research/2026-10-13-vlc-iina-parity/`:
- `verified-*.md`, `vlc-macos-behaviour-catalog.md`
- the round-two answers `2026-10-14-round2-answers.md`, which were checked by adversarial verifiers
- the fork patch `0005-moltenvk-display-fps-resize.patch`

Gemini's claims were kept only where a source confirmed them. The rejected ones are listed at the end.

### Most important finding (A1)

On the MPVKit fork, mpv's display sync never engages. Nothing answers `VOCTRL_GET_DISPLAY_FPS`, so `display-fps` is 0, the vsync interval stays at 0, and `handle_display_sync_frame` returns early. As a result, `video-sync=display-resample` and `interpolation=yes` are silently inactive in every render profile. Patch 0005 (Part 5.1) fixes this. It also fixes the stale destination rectangle after a programmatic resize ("B1") at its root.

## Global constraints

- Build settings:
  - The app target uses `SWIFT_VERSION 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES` (`project.pbxproj` L388-392, L422-426). Deployment target is macOS 26.0.
  - The test target has no default isolation.
- Pure helpers are `nonisolated` and import exactly the modules whose members they use. CoreGraphics geometry needs `import CoreGraphics`, as in `Logic/LoupeGeometry.swift` and `Models/OSCPosition.swift`.
- `@MainActor` test classes must use `override func setUp() async throws`, as in `CompareLiveBackendTests.swift` L71. Otherwise, mark individual test methods `@MainActor`, as `AppCommandTests` does.
- Framework callbacks (rules from verified C3, tested on Swift 6.2.4, 6.3.3 and 6.4.1):
  - A closure literal passed to a non-concurrency-checked API is inferred `@MainActor` and traps when called off the main thread.
  - For any callback whose thread is undocumented, use `{ @Sendable … in Task { @MainActor in … } }`.
  - Keep `queue: .main` on NotificationCenter observers that use `MainActor.assumeIsolated`.
  - Keep `.receive(on: DispatchQueue.main)` before every Combine sink fed from a background thread.
  - Never pass a closure stored in a variable to a framework callback: that compiles to a silent data race.
- New file header:
  ```
  // Aagedal Media Player
  // Copyright © 2026 Truls Aagedal
  // SPDX-License-Identifier: GPL-3.0-or-later
  ```
- Every new `AppSetting` goes into `defaultsDictionary`, and is referenced as `AppSettings.<name>` under `UI/` or listed in `SettingsCoverageTests.notUserFacing`.
- New files join targets automatically (file-system synchronized groups).
- Commits use plain `git commit -m "…"` with no attribution lines (HANDOFF §2). No new package dependencies. Metal API validation stays off.
- Test command (Mac):
  ```
  xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/<Class>"
  ```
  After each Part: full suite, `xcodebuild analyze`, and a Release build installed to `/Applications/amp.app` (HANDOFF §6.5).

---

# Part 1 — Pure logic (cloud session)

### 1.1 Volume cap 125 % (VLC `macosx-max-volume`)

Replace the body of `Aagedal Media Player/Logic/PlaybackVolume.swift`:
```swift
// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// UI percentages represent linear amplitude, matching AVPlayer.volume.
nonisolated enum PlaybackVolume {
    /// VLC's macOS maximum (`macosx-max-volume`, default 125).
    static let maxPercent: Double = 125

    static func mpvValue(for percent: Double) -> Double {
        let amplitude = percent.isFinite ? min(maxPercent, max(0, percent)) / 100 : 1
        // mpv 0.41 audio_get_gain cubes volume/100. Invert that curve so
        // 50% means half amplitude instead of one eighth (-18 dB).
        // https://github.com/mpv-player/mpv/blob/v0.41.0/player/audio.c
        // 125 % maps to 107.72, inside mpv's default volume-max of 130.
        return 100 * cbrt(amplitude)
    }
}
```
In `PlaybackVolumeTests.swift`, change L15 to `XCTAssertEqual(PlaybackVolume.mpvValue(for: 200), 100 * cbrt(1.25), accuracy: 1e-12)`, then add:
```swift
        XCTAssertEqual(PlaybackVolume.mpvValue(for: 125), 107.7217, accuracy: 1e-4)
        XCTAssertEqual(pow(PlaybackVolume.mpvValue(for: 125) / 100, 3), 1.25, accuracy: 1e-12)
```
Commit: `Raise the playback volume cap to VLC's 125 percent`

### 1.2 `ScrollStepAccumulator` (VLC wheel)

Source: `vlc-master-VLCVoutView.m.txt` L239-303. VLC loops on `while (ABS(cumulated) >= threshold)` and re-arms its 0.4 s timer after every event the axis lock does not drop, including events below the direction threshold.

`Aagedal Media Player/Logic/Input/ScrollStepAccumulator.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's scroll-wheel accumulator, copied from VLCVoutView.m (scrollWheel:,
// resetScrollWheelDirection). VLC's 0.4 s NSTimer becomes a timestamp
// comparison. Like VLC, an event dropped by the axis lock does not re-arm it.

import Foundation

nonisolated struct ScrollStepAccumulator: Sendable {
    nonisolated enum Step: Equatable, Sendable {
        case volumeUp
        case volumeDown
        case seekForward
        case seekBackward
    }

    static let xThreshold = 0.8
    static let yThreshold = 1.0
    static let directionThreshold = 0.05
    static let resetInterval: TimeInterval = 0.4

    /// 1 = last accepted axis was Y, -1 = X, 0 = none (VLC's i_lastScrollWheelDirection).
    private var lastDirection = 0
    private var cumulatedX = 0.0
    private var cumulatedY = 0.0
    private var timerArmedAt: TimeInterval?

    init() {}

    mutating func steps(
        deltaX: Double,
        deltaY: Double,
        isDirectionInverted: Bool,
        isMouseWheel: Bool,
        timestamp: TimeInterval
    ) -> [Step] {
        if let armed = timerArmedAt, timestamp - armed >= Self.resetInterval {
            reset()
        }

        var dx = isDirectionInverted ? -deltaX : deltaX
        var dy = isDirectionInverted ? -deltaY : deltaY
        let absX = abs(dx)
        let absY = abs(dy)

        // A mouse wheel has lower sensitivity: every notch scrolls at least once.
        if isMouseWheel, absY < Self.yThreshold { dy = dy > 0 ? Self.yThreshold : -Self.yThreshold }
        if isMouseWheel, absX < Self.xThreshold { dx = dx > 0 ? Self.xThreshold : -Self.xThreshold }

        var result: [Step] = []
        if absY > Self.directionThreshold {
            if lastDirection < 0 { return [] }
            lastDirection = 1
            cumulatedY += dy
            let step: Step = cumulatedY < 0 ? .volumeDown : .volumeUp
            while abs(cumulatedY) >= Self.yThreshold {
                cumulatedY -= cumulatedY > 0 ? Self.yThreshold : -Self.yThreshold
                result.append(step)
            }
        } else if absX > Self.directionThreshold {
            if lastDirection > 0 { return [] }
            lastDirection = -1
            cumulatedX += dx
            // KEY_MOUSEWHEELRIGHT jumps forward, KEY_MOUSEWHEELLEFT back.
            let step: Step = cumulatedX < 0 ? .seekForward : .seekBackward
            while abs(cumulatedX) >= Self.xThreshold {
                cumulatedX -= cumulatedX > 0 ? Self.xThreshold : -Self.xThreshold
                result.append(step)
            }
        }
        timerArmedAt = timestamp
        return result
    }

    mutating func reset() {
        lastDirection = 0
        cumulatedX = 0
        cumulatedY = 0
        timerArmedAt = nil
    }
}
```
`Aagedal Media Player Tests/ScrollStepAccumulatorTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class ScrollStepAccumulatorTests: XCTestCase {
    private func feed(_ acc: inout ScrollStepAccumulator, dx: Double = 0, dy: Double = 0,
                      inverted: Bool = false, wheel: Bool = false, at t: TimeInterval) -> [ScrollStepAccumulator.Step] {
        acc.steps(deltaX: dx, deltaY: dy, isDirectionInverted: inverted, isMouseWheel: wheel, timestamp: t)
    }

    func testAMouseWheelNotchAlwaysFiresOneStep() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dy: 0.1, wheel: true, at: 0), [.volumeUp])
        XCTAssertEqual(feed(&acc, dy: -0.1, wheel: true, at: 1), [.volumeDown])
    }

    func testTrackpadDeltasAccumulateUntilTheThreshold() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dy: 0.3, at: 0.00), [])
        XCTAssertEqual(feed(&acc, dy: 0.3, at: 0.05), [])
        XCTAssertEqual(feed(&acc, dy: 0.3, at: 0.10), [])
        XCTAssertEqual(feed(&acc, dy: 0.3, at: 0.15), [.volumeUp])
    }

    func testALargeDeltaFiresSeveralSteps() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dy: 2.5, at: 0), [.volumeUp, .volumeUp])
    }

    func testNaturalScrollingIsInvertedBackToVLCDirections() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dy: -1, inverted: true, at: 0), [.volumeUp])
    }

    func testHorizontalNegativeSeeksForwardAndPositiveBack() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dx: -0.8, at: 0), [.seekForward])
        var other = ScrollStepAccumulator()
        XCTAssertEqual(feed(&other, dx: 1.6, at: 0), [.seekBackward, .seekBackward])
    }

    func testTheOtherAxisIsLockedOutUntilThePauseExpires() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dy: 1, at: 0), [.volumeUp])
        XCTAssertEqual(feed(&acc, dx: -1, at: 0.2), [], "X is blocked while Y owns the gesture")
        XCTAssertEqual(feed(&acc, dx: -1, at: 0.45), [.seekForward],
                       "the dropped event did not re-arm the timer, so 0.45 s after the last Y the lock is gone")
    }

    func testTheResetAlsoClearsAPartialAccumulation() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dy: 0.9, at: 0), [])
        XCTAssertEqual(feed(&acc, dy: 0.2, at: 0.5), [], "0.9 was discarded after 0.4 s of silence")
    }

    func testDeltasBelowTheDirectionThresholdDoNothing() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dx: 0.04, dy: 0.04, at: 0), [])
    }

    func testASubThresholdEventStillReArmsTheLockLikeVLC() {
        var acc = ScrollStepAccumulator()
        XCTAssertEqual(feed(&acc, dy: 1, at: 0), [.volumeUp])
        XCTAssertEqual(feed(&acc, dx: 0.01, dy: 0.01, at: 0.3), [], "VLCVoutView.m:296-302 re-arms after the if/else")
        XCTAssertEqual(feed(&acc, dx: -1, at: 0.6), [], "0.3 s after the re-arm, Y still owns the gesture")
        XCTAssertEqual(feed(&acc, dx: -1, at: 0.75), [.seekForward])
    }
}
```
Commit: `Add VLC's scroll-wheel step accumulator`

### 1.3 `WindowSizing` (fill test, ⌘0–⌘2 geometry, restore)

VLC 3 Half/Normal/Double set the vout zoom to 0.5/1/2 at 1:1 source pixels. ⌘3 "Fit to Screen" is AppKit's standard zoom to `visibleFrame` with the aspect not kept, toggling back to the previous frame (verified D2). In AMP that is the same action as double-click (`toggleFillScreen`), so there is no `fit` preset.

`Aagedal Media Player/Logic/WindowSizing.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Window geometry for VLC's Half / Normal / Double sizes, the windowed screen
// fill and its restore, without a window so every case is testable. Frames are
// window frames; with the hidden title bar the title bar height is 0.

import CoreGraphics
import Foundation

nonisolated enum WindowSizePreset: String, CaseIterable, Sendable {
    case half
    case normal
    case double

    /// Scale of the source's 1:1-pixel size (VLC's vout zoom 0.5 / 1 / 2).
    var scale: CGFloat {
        switch self {
        case .half: 0.5
        case .normal: 1
        case .double: 2
        }
    }
}

nonisolated enum WindowSizing {
    static let fillTolerance: CGFloat = 2

    /// The frame covers `visible` within two points on every edge.
    static func isFilling(frame: CGRect, visible: CGRect) -> Bool {
        abs(frame.minX - visible.minX) <= fillTolerance
            && abs(frame.minY - visible.minY) <= fillTolerance
            && abs(frame.maxX - visible.maxX) <= fillTolerance
            && abs(frame.maxY - visible.maxY) <= fillTolerance
    }

    /// The frame for `preset`: the source at 1:1 physical pixels
    /// (`sourceSize / backingScale`) times the preset scale, or the current
    /// width times the scale when the source size is unknown.
    static func presetFrame(
        preset: WindowSizePreset,
        ratio: CGFloat,
        sourceSize: CGSize?,
        backingScale: CGFloat,
        titlebarHeight: CGFloat,
        minimumContent: CGSize,
        visible: CGRect,
        currentFrame: CGRect
    ) -> CGRect {
        let width: CGFloat
        if let sourceSize, sourceSize.width > 0, backingScale > 0 {
            width = sourceSize.width / backingScale * preset.scale
        } else {
            width = currentFrame.width * preset.scale
        }
        return fitted(width: width, ratio: ratio, titlebarHeight: titlebarHeight,
                      minimumContent: minimumContent, visible: visible, anchor: currentFrame)
    }

    /// `width` at `ratio`, grown to `minimumContent`, shrunk to `visible`, rounded.
    /// The anchor's top-left corner stays put, pulled back inside `visible`.
    static func fitted(
        width: CGFloat,
        ratio: CGFloat,
        titlebarHeight: CGFloat,
        minimumContent: CGSize,
        visible: CGRect,
        anchor: CGRect
    ) -> CGRect {
        let ratio = ratio.isFinite && ratio > 0 ? ratio : 16.0 / 9.0
        let maxWidth = visible.width
        let maxHeight = max(1, visible.height - titlebarHeight)
        var width = max(1, width.isFinite ? width : maxWidth)
        var height = width / ratio

        if width < minimumContent.width || height < minimumContent.height {
            let grow = max(minimumContent.width / width, minimumContent.height / height)
            width *= grow
            height *= grow
        }
        if width > maxWidth {
            width = maxWidth
            height = width / ratio
        }
        if height > maxHeight {
            height = maxHeight
            width = height * ratio
        }
        width = width.rounded()
        height = height.rounded()

        let totalHeight = height + titlebarHeight
        let x = min(max(anchor.minX, visible.minX), visible.maxX - width)
        let y = min(max(anchor.maxY - totalHeight, visible.minY), visible.maxY - totalHeight)
        return CGRect(x: x, y: y, width: width, height: totalHeight)
    }
}
```
`Aagedal Media Player Tests/WindowSizingTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics
import XCTest
@testable import Aagedal_Media_Player

final class WindowSizingTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 40, width: 1728, height: 1080)
    private let noMinimum = CGSize(width: 1, height: 1)

    private func frame(_ preset: WindowSizePreset, source: CGSize? = CGSize(width: 1920, height: 1080),
                       minimum: CGSize? = nil, current: CGRect = CGRect(x: 100, y: 400, width: 800, height: 450)) -> CGRect {
        WindowSizing.presetFrame(preset: preset, ratio: 16.0 / 9.0, sourceSize: source, backingScale: 2,
                                 titlebarHeight: 0, minimumContent: minimum ?? noMinimum,
                                 visible: visible, currentFrame: current)
    }

    func testFillingAllowsTwoPointsOfSlack() {
        XCTAssertTrue(WindowSizing.isFilling(frame: visible.insetBy(dx: 1, dy: 1), visible: visible))
        XCTAssertFalse(WindowSizing.isFilling(frame: visible.insetBy(dx: 3, dy: 0), visible: visible))
    }

    func testNormalIsOnePhysicalPixelPerSourcePixel() {
        XCTAssertEqual(frame(.normal).size, CGSize(width: 960, height: 540))
    }

    func testHalfAndDoubleScaleNormal() {
        XCTAssertEqual(frame(.half).size, CGSize(width: 480, height: 270))
        XCTAssertEqual(frame(.double).size, CGSize(width: 1728, height: 972), "1920 would overflow; clamped to the visible width")
    }

    func testTheMinimumGrowsTheWindowKeepingTheRatio() {
        XCTAssertEqual(frame(.half, minimum: CGSize(width: 690, height: 540)).size, CGSize(width: 960, height: 540))
    }

    func testTheTopLeftCornerStaysPutInsideTheScreen() {
        let f = frame(.normal)
        XCTAssertEqual(f.minX, 100)
        XCTAssertEqual(f.maxY, 850)
        let pushed = frame(.normal, current: CGRect(x: 1500, y: 900, width: 200, height: 100))
        XCTAssertEqual(pushed.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(pushed.maxY, visible.maxY)
    }

    func testWithoutASourceSizeTheCurrentWidthIsScaled() {
        XCTAssertEqual(frame(.half, source: nil).size, CGSize(width: 400, height: 225))
    }

    func testFittedKeepsTheWidthAndFollowsANewRatio() {
        let saved = CGRect(x: 100, y: 400, width: 800, height: 450)
        let f = WindowSizing.fitted(width: saved.width, ratio: 4.0 / 3.0, titlebarHeight: 0,
                                    minimumContent: noMinimum, visible: visible, anchor: saved)
        XCTAssertEqual(f, CGRect(x: 100, y: 250, width: 800, height: 600))
    }

    func testANonFiniteWidthFallsBackToTheScreen() {
        let f = WindowSizing.fitted(width: .infinity, ratio: 16.0 / 9.0, titlebarHeight: 0,
                                    minimumContent: noMinimum, visible: visible, anchor: visible)
        XCTAssertEqual(f.size, CGSize(width: 1728, height: 972))
    }
}
```
Commit: `Add window size preset and screen fill geometry`

### 1.4 `VLCKeyMap` (VLC 3 macOS default hotkeys, subtitles excluded)

Source: VLC `src/libvlc-module.c` `#if defined(__APPLE__)`. Esc leaves fullscreen only, and does nothing when windowed (verified D5). ⌘F and ⌘0–⌘3 are menu key equivalents.

`Aagedal Media Player/Logic/Input/VLCKeyMap.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's macOS default hotkeys (src/libvlc-module.c, `#if defined(__APPLE__)`).
// ⌘F and ⌘0–⌘3 are menu key equivalents, so they are not listed here.
// Subtitle keys (s, ⌥s, ⇧s, h, j) are out of scope.

import Foundation

nonisolated enum VLCKeyAction: Equatable, Sendable {
    case stop
    case previousFile
    case nextFile
    case seek(Double)
    case adjustVolume(Double)
    case toggleMute
    case faster
    case slower
    case nextFrame
    case cycleAspectRatio
    case cycleCrop
    case nextAudioTrack
    case showPosition
    case audioDelay(Double)
    case toggleDeinterlace
    case leaveFullscreen
}

nonisolated enum VLCKeyMap {
    static let delayStep = 0.05
    static let volumeStep = 5.0

    static func action(for chord: KeyChord) -> VLCKeyAction? {
        let m = chord.modifiers
        switch chord.key {
        case "left", "right":
            let sign: Double = chord.key == "right" ? 1 : -1
            switch m {
            case [.command]: return sign > 0 ? .nextFile : .previousFile
            case [.command, .control]: return .seek(3 * sign)
            case [.command, .option]: return .seek(10 * sign)
            case [.command, .shift]: return .seek(60 * sign)
            case [.command, .shift, .option]: return .seek(300 * sign)
            default: return nil
            }
        case "up":
            return m == [.command] ? .adjustVolume(volumeStep) : nil
        case "down":
            switch m {
            case [.command]: return .adjustVolume(-volumeStep)
            case [.command, .option]: return .toggleMute
            default: return nil
            }
        case "\u{1b}":
            return m.isEmpty ? .leaveFullscreen : nil
        case "=":
            return m == [.command] ? .faster : nil
        case "-":
            return m == [.command] ? .slower : nil
        case ".":
            return m == [.command] ? .stop : nil
        default:
            guard m.isEmpty else { return nil }
            switch chord.key {
            case "e": return .nextFrame
            case "a": return .cycleAspectRatio
            case "c": return .cycleCrop
            case "l": return .nextAudioTrack
            case "t": return .showPosition
            case "f": return .audioDelay(-delayStep)
            case "g": return .audioDelay(delayStep)
            case "d": return .toggleDeinterlace
            default: return nil
            }
        }
    }
}
```
`Aagedal Media Player Tests/VLCKeyMapTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class VLCKeyMapTests: XCTestCase {
    private func action(_ chord: String) throws -> VLCKeyAction? {
        VLCKeyMap.action(for: try XCTUnwrap(KeyChord(string: chord)))
    }

    func testJumpSizesFollowVLCsMacDefaults() throws {
        XCTAssertEqual(try action("cmd+ctrl+right"), .seek(3))
        XCTAssertEqual(try action("cmd+ctrl+left"), .seek(-3))
        XCTAssertEqual(try action("alt+cmd+right"), .seek(10))
        XCTAssertEqual(try action("shift+cmd+left"), .seek(-60))
        XCTAssertEqual(try action("shift+alt+cmd+right"), .seek(300))
        XCTAssertEqual(try action("cmd+left"), .previousFile)
        XCTAssertEqual(try action("cmd+right"), .nextFile)
    }

    func testPlainArrowsAreNotHotkeys() throws {
        XCTAssertNil(try action("left"))
        XCTAssertNil(try action("up"))
        XCTAssertNil(try action("shift+right"))
    }

    func testVolumeMuteRateStop() throws {
        XCTAssertEqual(try action("cmd+up"), .adjustVolume(5))
        XCTAssertEqual(try action("cmd+down"), .adjustVolume(-5))
        XCTAssertEqual(try action("alt+cmd+down"), .toggleMute)
        XCTAssertEqual(try action("cmd+="), .faster)
        XCTAssertEqual(try action("cmd+-"), .slower)
        XCTAssertEqual(try action("cmd+."), .stop)
    }

    func testLetterKeys() throws {
        XCTAssertEqual(try action("e"), .nextFrame)
        XCTAssertEqual(try action("a"), .cycleAspectRatio)
        XCTAssertEqual(try action("c"), .cycleCrop)
        XCTAssertEqual(try action("l"), .nextAudioTrack)
        XCTAssertEqual(try action("t"), .showPosition)
        XCTAssertEqual(try action("f"), .audioDelay(-0.05))
        XCTAssertEqual(try action("g"), .audioDelay(0.05))
        XCTAssertEqual(try action("d"), .toggleDeinterlace)
    }

    func testSubtitleKeysAreOutOfScope() throws {
        XCTAssertNil(try action("s"))
        XCTAssertNil(try action("j"))
        XCTAssertNil(try action("h"))
    }

    func testEscapeOnlyLeavesFullscreenWithoutModifiers() {
        XCTAssertEqual(VLCKeyMap.action(for: KeyChord(key: "\u{1b}", modifiers: [])), .leaveFullscreen)
        XCTAssertNil(VLCKeyMap.action(for: KeyChord(key: "\u{1b}", modifiers: [.command])))
    }

    func testMenuOwnedChordsAreLeftToTheMenu() throws {
        XCTAssertNil(try action("cmd+f"))
        XCTAssertNil(try action("cmd+1"))
    }
}
```
Commit: `Add VLC's macOS hotkey table`

### 1.5 `VLCVideoChoices` (aspect and crop lists, cycling, mpv crop, displayed ratio)

Sources:
- VLC's lists: `src/video_output/vout_intf.c`.
- mpv semantics: verified B1–B3. Crop and override both apply to the unrotated frame. An override sets the display aspect of the full w×h. `video-crop` takes only `WxH+X+Y`: a ratio string parses as an x:y inset. `""` clears the crop and restores the container crop. libplacebo needs no even sizes.

`Aagedal Media Player/Logic/VLCVideoChoices.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's aspect-ratio and crop menus (src/video_output/vout_intf.c) mapped onto
// mpv. mpv crops before rotating and applies video-aspect-override to the full
// unrotated frame, so on-screen choices are inverted for quarter turns. A crop
// is written as WxH+X+Y in source pixels; a ratio string would be parsed as an
// x:y inset.

import Foundation

nonisolated struct VLCVideoChoice: Equatable, Sendable {
    /// What the OSD and the menu show.
    let title: String
    /// VLC's ratio string, `nil` for Default.
    let ratio: String?
}

/// The source frame as mpv reports it (`video-params/*`).
nonisolated struct VideoFrameGeometry: Equatable, Sendable {
    var width: Int
    var height: Int
    /// The container crop (`video-params/crop-*`), when smaller than the frame.
    var baseX = 0
    var baseY = 0
    var baseWidth: Int?
    var baseHeight: Int?
    /// `video-params/par`, read while `video-aspect-override` is `no`.
    var naturalPixelAspect: Double
    /// `video-params/rotate` in degrees.
    var rotation: Int

    var isQuarterTurn: Bool {
        let r = ((rotation % 360) + 360) % 360
        return r == 90 || r == 270
    }
}

nonisolated enum VLCVideoChoices {
    static let aspectRatios: [VLCVideoChoice] = [
        VLCVideoChoice(title: "Default", ratio: nil),
        VLCVideoChoice(title: "16:9", ratio: "16:9"),
        VLCVideoChoice(title: "4:3", ratio: "4:3"),
        VLCVideoChoice(title: "1:1", ratio: "1:1"),
        VLCVideoChoice(title: "16:10", ratio: "16:10"),
        VLCVideoChoice(title: "2.21:1", ratio: "221:100"),
        VLCVideoChoice(title: "2.35:1", ratio: "235:100"),
        VLCVideoChoice(title: "2.39:1", ratio: "239:100"),
        VLCVideoChoice(title: "5:4", ratio: "5:4"),
    ]

    static let crops: [VLCVideoChoice] = [
        VLCVideoChoice(title: "Default", ratio: nil),
        VLCVideoChoice(title: "16:10", ratio: "16:10"),
        VLCVideoChoice(title: "16:9", ratio: "16:9"),
        VLCVideoChoice(title: "4:3", ratio: "4:3"),
        VLCVideoChoice(title: "1.85:1", ratio: "185:100"),
        VLCVideoChoice(title: "2.21:1", ratio: "221:100"),
        VLCVideoChoice(title: "2.35:1", ratio: "235:100"),
        VLCVideoChoice(title: "2.39:1", ratio: "239:100"),
        VLCVideoChoice(title: "5:3", ratio: "5:3"),
        VLCVideoChoice(title: "5:4", ratio: "5:4"),
        VLCVideoChoice(title: "1:1", ratio: "1:1"),
    ]

    /// The index after `index`, wrapping; an index outside the list restarts at 0 (VLC).
    static func nextIndex(after index: Int, count: Int, forward: Bool = true) -> Int {
        guard count > 0, (0..<count).contains(index) else { return 0 }
        return (index + (forward ? 1 : count - 1)) % count
    }

    /// `16:9` → 1.777…, `221:100` → 2.21.
    static func ratioValue(_ ratio: String) -> Double? {
        let parts = ratio.split(separator: ":")
        guard parts.count == 2, let w = Double(parts[0]), let h = Double(parts[1]), w > 0, h > 0 else { return nil }
        return w / h
    }

    /// The value for mpv's `video-aspect-override` (unrotated): `no`, the VLC
    /// ratio string, or its reciprocal for a quarter turn.
    static func mpvAspect(for choice: VLCVideoChoice, geometry: VideoFrameGeometry) -> String {
        guard let ratio = choice.ratio, let value = ratioValue(ratio) else { return "no" }
        return geometry.isQuarterTurn ? String(1 / value) : ratio
    }

    /// The display aspect of the full unrotated frame mpv will use.
    static func fullFrameRatio(aspect: VLCVideoChoice, geometry: VideoFrameGeometry) -> Double? {
        guard geometry.width > 0, geometry.height > 0 else { return nil }
        if let ratio = aspect.ratio, let value = ratioValue(ratio) {
            return geometry.isQuarterTurn ? 1 / value : value
        }
        let par = geometry.naturalPixelAspect.isFinite && geometry.naturalPixelAspect > 0 ? geometry.naturalPixelAspect : 1
        return Double(geometry.width) * par / Double(geometry.height)
    }

    /// mpv `video-crop` for `crop` under `aspect`: `""` when nothing is cut,
    /// else `WxH+X+Y`, centred inside the container crop.
    static func mpvCrop(for crop: VLCVideoChoice, aspect: VLCVideoChoice, geometry g: VideoFrameGeometry) -> String {
        guard let ratio = crop.ratio, let onScreen = ratioValue(ratio),
              let full = fullFrameRatio(aspect: aspect, geometry: g) else { return "" }
        let bw = g.baseWidth ?? g.width
        let bh = g.baseHeight ?? g.height
        guard bw > 0, bh > 0 else { return "" }
        // The base region's own display aspect, in unrotated space.
        let base = full * (Double(bw) / Double(g.width)) / (Double(bh) / Double(g.height))
        let target = g.isQuarterTurn ? 1 / onScreen : onScreen
        var cw = bw
        var ch = bh
        if base > target {
            cw = Int((Double(bw) * target / base).rounded())
        } else {
            ch = Int((Double(bh) * base / target).rounded())
        }
        cw = min(max(cw, 1), bw)
        ch = min(max(ch, 1), bh)
        if cw == bw && ch == bh { return "" }
        let x = g.baseX + (bw - cw) / 2
        let y = g.baseY + (bh - ch) / 2
        return "\(cw)x\(ch)+\(x)+\(y)"
    }

    /// The picture's on-screen aspect after `aspect` and `crop`, for the window.
    static func displayedRatio(crop: VLCVideoChoice, aspect: VLCVideoChoice, geometry g: VideoFrameGeometry) -> Double? {
        if let ratio = crop.ratio, let value = ratioValue(ratio) { return value }
        guard let full = fullFrameRatio(aspect: aspect, geometry: g) else { return nil }
        let bw = Double(g.baseWidth ?? g.width)
        let bh = Double(g.baseHeight ?? g.height)
        let base = full * (bw / Double(g.width)) / (bh / Double(g.height))
        return g.isQuarterTurn ? 1 / base : base
    }
}
```
`Aagedal Media Player Tests/VLCVideoChoicesTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class VLCVideoChoicesTests: XCTestCase {
    private let hd = VideoFrameGeometry(width: 1920, height: 1080, naturalPixelAspect: 1, rotation: 0)
    private var aspectDefault: VLCVideoChoice { VLCVideoChoices.aspectRatios[0] }
    private func crop(_ title: String) -> VLCVideoChoice { VLCVideoChoices.crops.first { $0.title == title }! }
    private func aspect(_ title: String) -> VLCVideoChoice { VLCVideoChoices.aspectRatios.first { $0.title == title }! }

    func testListsMatchVLC() {
        XCTAssertEqual(VLCVideoChoices.aspectRatios.map(\.title),
                       ["Default", "16:9", "4:3", "1:1", "16:10", "2.21:1", "2.35:1", "2.39:1", "5:4"])
        XCTAssertEqual(VLCVideoChoices.crops.map(\.title),
                       ["Default", "16:10", "16:9", "4:3", "1.85:1", "2.21:1", "2.35:1", "2.39:1", "5:3", "5:4", "1:1"])
    }

    func testCyclingWrapsAndRestartsWhenUnknown() {
        XCTAssertEqual(VLCVideoChoices.nextIndex(after: 0, count: 9), 1)
        XCTAssertEqual(VLCVideoChoices.nextIndex(after: 8, count: 9), 0)
        XCTAssertEqual(VLCVideoChoices.nextIndex(after: 0, count: 9, forward: false), 8)
        XCTAssertEqual(VLCVideoChoices.nextIndex(after: 42, count: 9), 0)
    }

    func testCropToAWiderRatioCutsHeight() {
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("2.35:1"), aspect: aspectDefault, geometry: hd), "1920x817+0+131")
    }

    func testCropToANarrowerRatioCutsWidth() {
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("4:3"), aspect: aspectDefault, geometry: hd), "1440x1080+240+0")
    }

    func testAnamorphicCropUsesThePixelAspect() {
        let dvd = VideoFrameGeometry(width: 720, height: 480, naturalPixelAspect: 32.0 / 27.0, rotation: 0)
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("4:3"), aspect: aspectDefault, geometry: dvd), "540x480+90+0")
    }

    func testAQuarterTurnCropsInUnrotatedPixels() {
        let portrait = VideoFrameGeometry(width: 1920, height: 1080, naturalPixelAspect: 1, rotation: 90)
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("4:3"), aspect: aspectDefault, geometry: portrait), "810x1080+555+0")
        XCTAssertEqual(VLCVideoChoices.mpvAspect(for: aspect("4:3"), geometry: portrait), String(0.75))
    }

    func testCropUnderAnAspectOverrideUsesTheOverride() {
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("16:9"), aspect: aspect("4:3"), geometry: hd), "1920x810+0+135")
    }

    func testCropStaysInsideTheContainerCrop() {
        let padded = VideoFrameGeometry(width: 1920, height: 1088, baseX: 0, baseY: 0, baseWidth: 1920, baseHeight: 1080,
                                        naturalPixelAspect: 1, rotation: 0)
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("2.35:1"), aspect: aspectDefault, geometry: padded), "1920x817+0+131")
    }

    func testNothingToCutClearsTheCrop() {
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("16:9"), aspect: aspectDefault, geometry: hd), "")
        XCTAssertEqual(VLCVideoChoices.mpvCrop(for: crop("Default"), aspect: aspectDefault, geometry: hd), "")
        XCTAssertEqual(VLCVideoChoices.mpvAspect(for: aspectDefault, geometry: hd), "no")
        XCTAssertEqual(VLCVideoChoices.mpvAspect(for: aspect("2.21:1"), geometry: hd), "221:100")
    }

    func testDisplayedRatioFollowsCropThenAspectThenSource() {
        XCTAssertEqual(VLCVideoChoices.displayedRatio(crop: crop("2.35:1"), aspect: aspectDefault, geometry: hd)!, 2.35, accuracy: 1e-9)
        XCTAssertEqual(VLCVideoChoices.displayedRatio(crop: crop("Default"), aspect: aspect("4:3"), geometry: hd)!, 4.0 / 3.0, accuracy: 1e-9)
        XCTAssertEqual(VLCVideoChoices.displayedRatio(crop: crop("Default"), aspect: aspectDefault, geometry: hd)!, 16.0 / 9.0, accuracy: 1e-9)
        let portrait = VideoFrameGeometry(width: 1920, height: 1080, naturalPixelAspect: 1, rotation: 270)
        XCTAssertEqual(VLCVideoChoices.displayedRatio(crop: crop("Default"), aspect: aspectDefault, geometry: portrait)!, 9.0 / 16.0, accuracy: 1e-9)
    }
}
```
How the expected values are derived:
- 2.35 crop of 1080p: 1080·(16/9)/2.35 = 817.02 → 817, y = 131.
- 4:3 crop of 1080p: 1920·(4/3)/(16/9) = 1440, x = 240.
- Anamorphic DVD: F = 720·(32/27)/480 = 16/9, so 720·(4/3)/(16/9) = 540, x = 90.
- Quarter turn: target 3/4, so 1920·0.75/(16/9) = 810, x = 555.
- 4:3 override with a 16:9 crop: F = 4/3, so 1080·(4/3)/(16/9) = 810, y = 135.
- Padded 1920×1088 with a 1920×1080 container crop: the full frame is 1920/1088, and the base region is 1920/1088 · 1088/1080 = 16/9, so the crop is 817 high at y = 131.

Commit: `Add VLC aspect and crop choices mapped to mpv`

### 1.6 Resume rules and store (VLC continue playback)

Verified D3 (`VLCInputManager.m` L691-764):
- Store a position only when the duration is at least 3 min, it is not (<5 % and <60 s), and it is not (>95 % and <60 s remaining).
- Otherwise remove the entry.
- Keep the last 30 items.
- Positions are local existing files only.

`Aagedal Media Player/Logic/ResumePosition.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's "Continue playback" rules (VLCInputManager.m, 3.0.x): which positions
// are worth storing, and the last 30 of them keyed by file path.

import Foundation

nonisolated enum ResumeMode: String, CaseIterable, Sendable {
    case ask
    case always
    case never
}

nonisolated enum ResumePolicy {
    static let minimumDuration: TimeInterval = 180
    static let minimumStoreFraction = 0.05
    static let maximumStoreFraction = 0.95
    static let minimumStoreTime: TimeInterval = 60
    static let minimumRemainingTime: TimeInterval = 60
    static let capacity = 30
    /// VLC's resume dialog counts down from 10 and then restarts.
    static let offerSeconds = 10

    static func shouldStore(position: TimeInterval, duration: TimeInterval) -> Bool {
        guard position.isFinite, duration.isFinite, position >= 0, duration >= minimumDuration else { return false }
        let fraction = position / duration
        if fraction < minimumStoreFraction && position < minimumStoreTime { return false }
        if fraction > maximumStoreFraction && duration - position < minimumRemainingTime { return false }
        return true
    }
}

/// A value type over UserDefaults so it needs no actor and no shared instance.
nonisolated struct ResumePositionStore {
    static let positionsKey = "resumePositions"
    static let orderKey = "resumePositionOrder"

    static var standard: ResumePositionStore { ResumePositionStore(defaults: .standard) }

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private static func key(for url: URL) -> String { url.standardizedFileURL.path }

    private var positions: [String: Double] {
        defaults.dictionary(forKey: Self.positionsKey) as? [String: Double] ?? [:]
    }

    private var order: [String] {
        defaults.stringArray(forKey: Self.orderKey) ?? []
    }

    /// Stores `position`, or forgets the file when VLC would not store it.
    func save(url: URL, position: TimeInterval, duration: TimeInterval) {
        guard url.isFileURL else { return }
        guard ResumePolicy.shouldStore(position: position, duration: duration) else {
            remove(url: url)
            return
        }
        let key = Self.key(for: url)
        var positions = positions
        var order = order.filter { $0 != key }
        positions[key] = position.rounded(.down)
        order.insert(key, at: 0)
        while order.count > ResumePolicy.capacity {
            positions.removeValue(forKey: order.removeLast())
        }
        defaults.set(positions, forKey: Self.positionsKey)
        defaults.set(order, forKey: Self.orderKey)
    }

    func position(for url: URL) -> TimeInterval? {
        positions[Self.key(for: url)]
    }

    func remove(url: URL) {
        let key = Self.key(for: url)
        var positions = positions
        guard positions.removeValue(forKey: key) != nil else { return }
        defaults.set(positions, forKey: Self.positionsKey)
        defaults.set(order.filter { $0 != key }, forKey: Self.orderKey)
    }

    /// The most recently stored file that still exists, for the welcome window.
    func mostRecent(fileManager: FileManager = .default) -> (url: URL, position: TimeInterval)? {
        let positions = positions
        for key in order where fileManager.fileExists(atPath: key) {
            if let position = positions[key] { return (URL(fileURLWithPath: key), position) }
        }
        return nil
    }
}
```
`Aagedal Media Player Tests/ResumePositionTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class ResumePositionTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ResumePositionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testVLCsStoreRules() {
        XCTAssertFalse(ResumePolicy.shouldStore(position: 100, duration: 179), "shorter than 3 minutes")
        XCTAssertFalse(ResumePolicy.shouldStore(position: 30, duration: 3600), "under 5 % and under 60 s")
        XCTAssertTrue(ResumePolicy.shouldStore(position: 61, duration: 3600), "under 5 % but past 60 s")
        XCTAssertTrue(ResumePolicy.shouldStore(position: 15, duration: 200), "7.5 % in, though under 60 s")
        XCTAssertFalse(ResumePolicy.shouldStore(position: 3550, duration: 3600), "over 95 % with under 60 s left")
        XCTAssertTrue(ResumePolicy.shouldStore(position: 3400, duration: 3600), "94.4 % in")
        XCTAssertFalse(ResumePolicy.shouldStore(position: .nan, duration: 3600))
    }

    func testSaveReadRemove() {
        let store = ResumePositionStore(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/a.mov")
        store.save(url: url, position: 600.7, duration: 3600)
        XCTAssertEqual(store.position(for: url), 600, "VLC stores whole seconds")
        store.save(url: url, position: 10, duration: 3600)
        XCTAssertNil(store.position(for: url), "a position VLC would not store clears the entry")
    }

    func testOnlyTheLastThirtyAreKept() {
        let store = ResumePositionStore(defaults: defaults)
        for i in 0..<31 {
            store.save(url: URL(fileURLWithPath: "/tmp/\(i).mov"), position: 600, duration: 3600)
        }
        XCTAssertNil(store.position(for: URL(fileURLWithPath: "/tmp/0.mov")))
        XCTAssertEqual(store.position(for: URL(fileURLWithPath: "/tmp/30.mov")), 600)
    }
}
```
Commit: `Add VLC's resume position rules and store`

### 1.7 `PlayerOSDMessage` (IINA OSD text model; subtitles excluded)

`TimecodeFormatter.formatTraditionalTime` (`UI/TimecodeFormatter.swift` L334) already formats `[h:]mm:ss` and `--:--`. Make it callable from nonisolated code. At L334, change `static func formatTraditionalTime` to `nonisolated static func formatTraditionalTime`. It is pure: it uses only `String(format:)`.

`Aagedal Media Player/Logic/PlayerOSDMessage.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// IINA's on-screen messages (OSDMessage.swift, en.lproj/Localizable.strings)
// for the actions VLC's keys and wheel trigger. Text only; PlayerOSDView draws it.

import Foundation

nonisolated enum PlayerOSDMessage: Equatable, Sendable {
    case pause(position: Double, duration: Double)
    case resume(position: Double, duration: Double)
    case seek(position: Double, duration: Double)
    case volume(Double, max: Double)
    case mute
    case unmute
    case speed(Double)
    case aspect(String)
    case crop(String)
    case deinterlace(Bool)
    case audioDelay(Double)
    case audioTrack(String)
    case nextFrame
    case stop
    case screenshot

    /// IINA's `groupedStringUpTo6Decimals`.
    static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: value as NSNumber) ?? "NaN"
    }

    private static func time(_ seconds: Double) -> String {
        TimecodeFormatter.formatTraditionalTime(seconds)
    }

    var text: String {
        switch self {
        case .pause: "Pause"
        case .resume: "Resume"
        case let .seek(position, duration): Self.time(position) + " / " + Self.time(duration)
        case let .volume(value, _): "Volume: " + String(format: "%.0f", value)
        case .mute: "Mute"
        case .unmute: "Unmute"
        case let .speed(value): "Speed: \(Self.decimal(value))x"
        case let .aspect(title): "Aspect Ratio: \(title)"
        case let .crop(title): "Crop: \(title == "Default" ? "None" : title)"
        case let .deinterlace(on): "Deinterlace: \(on ? "On" : "Off")"
        case let .audioDelay(value): value == 0
            ? "Audio Delay: No Delay"
            : "Audio Delay: \(Self.decimal(abs(value)))s \(value > 0 ? "Later" : "Earlier")"
        case let .audioTrack(title): "Audio: \(title)"
        case .nextFrame: "Next Frame"
        case .stop: "Stop"
        case .screenshot: "Screenshot Captured"
        }
    }

    /// The second line IINA shows under Pause and Resume.
    var secondaryText: String? {
        switch self {
        case let .pause(position, duration), let .resume(position, duration):
            Self.time(position) + " / " + Self.time(duration)
        default: nil
        }
    }

    /// 0…1 for the accent bar, `nil` for none.
    var progress: Double? {
        switch self {
        case let .seek(position, duration): duration > 0 ? min(max(position / duration, 0), 1) : nil
        case let .volume(value, max): max > 0 ? min(value / max, 1) : nil
        // IINA's toPercent(value, 10): (v + 10) / 20, clamped.
        case let .audioDelay(value): min(max(value + 10, 0), 20) / 20
        default: nil
        }
    }

    /// IINA splits at the first colon and drops it: prefix 18 pt secondary,
    /// the rest (leading space kept) 20 pt primary. Seek splits at " / ".
    var split: (prefix: String?, value: String, suffix: String?) {
        if case .seek = self, let range = text.range(of: " / ") {
            return (nil, String(text[..<range.lowerBound]), String(text[range.lowerBound...]))
        }
        switch self {
        case .volume, .speed, .aspect, .crop, .deinterlace, .audioDelay, .audioTrack:
            guard let colon = text.firstIndex(of: ":") else { return (nil, text, nil) }
            return (String(text[..<colon]), String(text[text.index(after: colon)...]), nil)
        default:
            return (nil, text, nil)
        }
    }
}
```
`Aagedal Media Player Tests/PlayerOSDMessageTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class PlayerOSDMessageTests: XCTestCase {
    func testIINAStrings() {
        XCTAssertEqual(PlayerOSDMessage.volume(80.4, max: 125).text, "Volume: 80")
        XCTAssertEqual(PlayerOSDMessage.volume(100, max: 125).progress, 0.8)
        XCTAssertEqual(PlayerOSDMessage.speed(1.5).text, "Speed: 1.5x")
        XCTAssertEqual(PlayerOSDMessage.aspect("Default").text, "Aspect Ratio: Default")
        XCTAssertEqual(PlayerOSDMessage.crop("Default").text, "Crop: None")
        XCTAssertEqual(PlayerOSDMessage.deinterlace(true).text, "Deinterlace: On")
        XCTAssertEqual(PlayerOSDMessage.audioDelay(0).text, "Audio Delay: No Delay")
        XCTAssertEqual(PlayerOSDMessage.audioDelay(0.05).text, "Audio Delay: 0.05s Later")
        XCTAssertEqual(PlayerOSDMessage.audioDelay(-0.1).text, "Audio Delay: 0.1s Earlier")
        XCTAssertEqual(PlayerOSDMessage.audioDelay(-10).progress, 0)
        XCTAssertEqual(PlayerOSDMessage.audioDelay(0).progress, 0.5)
        XCTAssertEqual(PlayerOSDMessage.audioTrack("English").text, "Audio: English")
        XCTAssertEqual(PlayerOSDMessage.seek(position: 83, duration: 296).text, "01:23 / 04:56")
        XCTAssertEqual(PlayerOSDMessage.seek(position: 3661, duration: 7322).text, "1:01:01 / 2:02:02")
        XCTAssertEqual(PlayerOSDMessage.pause(position: 83, duration: 296).secondaryText, "01:23 / 04:56")
    }

    func testColonSplitDropsTheColon() {
        let split = PlayerOSDMessage.volume(80, max: 125).split
        XCTAssertEqual(split.prefix, "Volume")
        XCTAssertEqual(split.value, " 80")
        let seek = PlayerOSDMessage.seek(position: 83, duration: 296).split
        XCTAssertNil(seek.prefix)
        XCTAssertEqual(seek.value, "01:23")
        XCTAssertEqual(seek.suffix, " / 04:56")
        XCTAssertNil(PlayerOSDMessage.mute.split.prefix)
    }
}
```
Commit: `Add IINA's on-screen message text model`

### 1.8 `JumpToTimeParser`

`Aagedal Media Player/Logic/JumpToTimeParser.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Parses the Jump to Time field: seconds ("90"), m:ss or h:mm:ss, with optional
// fractional seconds. Returns nil for anything else.

import Foundation

nonisolated enum JumpToTimeParser {
    static func seconds(from text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (index, part) in parts.enumerated() {
            let isLast = index == parts.count - 1
            let value: Double?
            if isLast {
                value = Double(String(part))
            } else {
                value = Int(String(part)).map(Double.init)
            }
            guard !part.isEmpty, let value, value.isFinite, value >= 0 else { return nil }
            if index > 0, value >= 60 { return nil }
            total = total * 60 + value
        }
        return total
    }
}
```
`Aagedal Media Player Tests/JumpToTimeParserTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class JumpToTimeParserTests: XCTestCase {
    func testAcceptedForms() {
        XCTAssertEqual(JumpToTimeParser.seconds(from: "90"), 90)
        XCTAssertEqual(JumpToTimeParser.seconds(from: "1:30"), 90)
        XCTAssertEqual(JumpToTimeParser.seconds(from: " 1:02:03.5 "), 3723.5)
    }

    func testRejectedForms() {
        XCTAssertNil(JumpToTimeParser.seconds(from: ""))
        XCTAssertNil(JumpToTimeParser.seconds(from: "1:60"))
        XCTAssertNil(JumpToTimeParser.seconds(from: "a:10"))
        XCTAssertNil(JumpToTimeParser.seconds(from: "1:2:3:4"))
        XCTAssertNil(JumpToTimeParser.seconds(from: "-5"))
        XCTAssertNil(JumpToTimeParser.seconds(from: "1.5:00"))
    }
}
```
Commit: `Add the Jump to Time parser`

### 1.9 `IINAStyle` tokens

`Aagedal Media Player/UI/IINAStyle.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// IINA 1.5 values (docs/research/2026-10-13-vlc-iina-parity/verified-iina.md),
// each checked against IINA's source. Adapted from IINA
// (https://github.com/iina/iina), Copyright © 2017-2026 Collider LI et al., GPL-3.0.

import CoreGraphics
import Foundation

nonisolated enum IINAStyle {
    // Timing
    static let uiFade: TimeInterval = 0.25
    static let controlBarAutoHide: TimeInterval = 2.5
    static let osdHold: TimeInterval = 1.0
    static let osdFadeOut: TimeInterval = 0.5
    static let sidebarSlide: TimeInterval = 0.24
    static let sidebarTabPush: TimeInterval = 0.3

    // OSC
    static let oscCornerRadius: CGFloat = 12
    static let oscVolumeSliderWidth: CGFloat = 70
    static let oscVolumeLeading: CGFloat = 4
    static let oscVolumeTrailing: CGFloat = 6
    static let oscSpeedLabelWidth: CGFloat = 30
    static let oscSpeedLabelFontSize: CGFloat = 10
    static let oscTimeFontSize: CGFloat = 11

    // OSD
    static let osdCornerRadius: CGFloat = 16
    static let osdPaddingH: CGFloat = 16
    static let osdPaddingV: CGFloat = 8
    static let osdEdge: CGFloat = 8
    static let osdTextSize: CGFloat = 20
    static let osdPrefixSize: CGFloat = 18
    static let osdSecondarySize: CGFloat = 11
    static let osdBarFrameHeight: CGFloat = 12
    static let osdBarHeight: CGFloat = 4
    static let osdBarRadius: CGFloat = 3

    // Play slider (dark appearance)
    static let sliderPlayedAlpha = 0.30
    static let sliderUnplayedAlpha = 0.10
    static let knobIdleAlpha = 0.80
    static let knobActiveAlpha = 0.98
    static let knobGap: CGFloat = 1
    static let thumbnailWidth: CGFloat = 120
    static let thumbnailRadius: CGFloat = 4
    static let hoverPillPadding: CGFloat = 4
    static let hoverGap: CGFloat = 5

    // Volume slider
    static let volumeNotchWidth: CGFloat = 2
    static let volumeBarRadius: CGFloat = 1.5

    // Buffer indicator
    static let bufferWidth: CGFloat = 150
    static let bufferSpacing: CGFloat = 4

    // Sidebar
    static let sidebarWidth: CGFloat = 360
    static let sidebarHeaderHeight: CGFloat = 52
    static let sidebarCloseButton: CGFloat = 36

    /// IINA's VolumeButton symbol: slash only when muted, `speaker.fill` at 0.
    static func volumeSymbol(volume: Double, isMuted: Bool) -> String {
        if isMuted { return "speaker.slash.fill" }
        if volume <= 0 { return "speaker.fill" }
        if volume <= 33 { return "speaker.wave.1.fill" }
        if volume <= 66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    /// IINA's speed labels: left `%.2fx` below 1, right 3 significant digits above 1, none at 1.
    static func speedLabels(_ speed: Double) -> (left: String?, right: String?) {
        if speed < 1 { return (String(format: "%.2fx", speed), nil) }
        if speed > 1 {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: "en_US")
            formatter.numberStyle = .decimal
            formatter.usesSignificantDigits = true
            formatter.maximumSignificantDigits = 3
            return (nil, (formatter.string(from: speed as NSNumber) ?? "\(speed)") + "x")
        }
        return (nil, nil)
    }
}
```
`Aagedal Media Player Tests/IINAStyleTests.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class IINAStyleTests: XCTestCase {
    func testVolumeSymbols() {
        XCTAssertEqual(IINAStyle.volumeSymbol(volume: 50, isMuted: true), "speaker.slash.fill")
        XCTAssertEqual(IINAStyle.volumeSymbol(volume: 0, isMuted: false), "speaker.fill")
        XCTAssertEqual(IINAStyle.volumeSymbol(volume: 33, isMuted: false), "speaker.wave.1.fill")
        XCTAssertEqual(IINAStyle.volumeSymbol(volume: 34, isMuted: false), "speaker.wave.2.fill")
        XCTAssertEqual(IINAStyle.volumeSymbol(volume: 125, isMuted: false), "speaker.wave.3.fill")
    }

    func testSpeedLabels() {
        XCTAssertEqual(IINAStyle.speedLabels(0.5).left, "0.50x")
        XCTAssertEqual(IINAStyle.speedLabels(1.5).right, "1.5x")
        XCTAssertEqual(IINAStyle.speedLabels(1.25).right, "1.25x")
        XCTAssertNil(IINAStyle.speedLabels(1).left)
        XCTAssertNil(IINAStyle.speedLabels(1).right)
    }
}
```
Commit: `Add IINA style tokens`

**Part 1 checkpoint (Mac):** run the 8 new test classes, plus `PlaybackVolumeTests`, `TimecodeFormatterTests` and `SettingsCoverageTests`.

---

# Part 2 — Quick fixes (Mac)

**2.1 Scrubber uses throttled seeks.**
- `UI/PlayerScrubber.swift`: add `var onEndScrub: ((Double) -> Void)? = nil` after `let onScrub`.
- In the drag gesture's `.onEnded`, use `let time = time(atX: value.location.x, width: width); if let onEndScrub, duration > 0 { onEndScrub(time) } else { seek(toX: value.location.x, width: width) }; isDragging = false`.
- The accessibility adjustable action calls `(onEndScrub ?? onScrub)`.
- `UI/FloatingOSCView.swift` L104-109: pass `onScrub: { controller.scrub(to: $0) }, onEndScrub: { controller.endScrubbing(at: $0) }`.

Commit: `Throttle floating-controller scrubbing like the compare bar`

**2.2 Align windows uses the exact time.** In `UI/ContentViewCommandHandlers.swift` L503, change to `let relTime = controller.playbackTimeSnapshot()`. Commit: `Align windows to the exact playback time`

**2.3 Enhance Now applies to this window only.**
- `Logic/MPV/MPVPlayer.swift` L1335: change the signature to `func setRenderProfile(_ profile: RenderProfile, persist: Bool = true)`, and write the setting only `if persist`.
- `UI/PlayerView.swift` L127: replace the post with `controller.mpvPlayer?.setRenderProfile(suggestion.recommendedProfile, persist: false)`.
- Add `.onChange(of: item.url) { _, _ in enhancementSuggestionDismissed = false }` on the body ZStack.

Commit: `Apply Enhance Now to the current window only`

**2.4 Forget the compare secondary.** In `ContentView.swift`, at `stopPlaybackForWindowClose` after `SleepPreventer.shared.forget(controller)`, add `SleepPreventer.shared.forget(compareSession.secondaryController)`. Commit: `Forget the compare secondary on window close`

**2.5 Panel observers.** Applies to `UI/Scopes/ScopeWindowController.swift` and `UI/AudioWaveformWindowController.swift`.
- Declare both observer properties as `nonisolated(unsafe) private var`.
- Make `nonisolated deinit` remove both observers.
- `close()` calls `panel?.close()` when a panel exists; its willClose observer runs `cleanup()`. Otherwise it calls `cleanup()` directly. Today it runs `cleanup()` twice (L121-127 with L138).

Commit: `Remove panel observers on release and clean up once`

**2.6 FrameAnalyzer caches failures.** In `Logic/MPV/FrameAnalyzer.swift`:
- On `catch AnalysisError.timedOut` (L61), store `cache[before] = SourceAnalysis()`.
- Before each insert, `if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }`. Dictionary order is unspecified, so evicting "the first key" could evict the newest entry.

Commit: `Cache failed frame analyses`

**2.7 Subprocess stdin.** In `Logic/SubprocessService.swift`, after `process.arguments = arguments` (L89), add `process.standardInput = FileHandle.nullDevice`. Commit: `Give subprocesses an empty stdin`

**2.8 Comments.**
- `MPVPlayer.swift` L1377 and L1385 call KrigBilateral "trained on 4:2:0". It is an analytic kriging filter tuned for 4:2:0, not a network.
- L346-350: `hwdec-extra-frames` only affects APIs that preallocate surfaces.
- `MPVVideoView.swift` L375-383: `vo->dwidth/dheight` are written only by `ra_vk_ctx_resize` (`vulkan/context.c` L497-498), not inside acquire (verified A3).

Commit: `Correct shader, hwdec and resize comments`

**2.9 Key guard.** In `UI/PlayerView.swift` L247, change to `if isEditingTimecode || isTextInputActive || NSApp.keyWindow?.firstResponder is NSTextView { return false }`. Commit: `Never take keys from a focused text field`

---

# Part 3 — VLC behaviour (Mac)

### 3.1 AppCommand: window-targeted commands

The key window is not guaranteed after `makeKeyAndOrderFront`, and a right-click may not make a window key (C5 UNSETTLED). Commands from the video surface and from media keys therefore name their window, following the existing `openFile(URL, targetWindow:)` pattern.

In `Logic/AppCommand.swift`, replace the cases:
```swift
    case openPreviousFile(targetWindow: NSWindow? = nil)
    case openNextFile(targetWindow: NSWindow? = nil)
    case captureScreenshot(targetWindow: NSWindow? = nil)
    case reloadPlayer(targetWindow: NSWindow? = nil)
```
Then add after `case openSubtitleFile`:
```swift
    /// VLC's double-click and Fit to Screen (⌘3): fill the visible screen,
    /// staying windowed; again restores the previous frame.
    case toggleFillScreen(targetWindow: NSWindow? = nil)
    case setWindowSize(WindowSizePreset)
    /// VLC's autoresize after an aspect or crop change: the window takes the
    /// picture's new shape at the given on-screen ratio.
    case fitWindowToVideo(ratio: CGFloat, targetWindow: NSWindow?)
    case toggleFloatOnTop
    case stop
    case jumpToTime
```
A case with an associated value is no longer a value without parentheses. Change these call sites:
- `Aagedal_Media_PlayerApp.swift` L111 `.openPreviousFile()`, L117 `.openNextFile()`, L124 `.captureScreenshot()`, L290 `.reloadPlayer()`.
- `UI/PlayerView.swift` L420 `.openPreviousFile()`, L422 `.openNextFile()`.
- `Logic/MPV/MPVVideoView.swift` L394 `.reloadPlayer()`.

`case .x = command` patterns keep compiling.

In `Logic/WindowManager.swift`, after `isActiveWindow`:
```swift
    /// A command aimed at `target` reaches only that window; an untargeted one
    /// reaches the active window.
    func shouldHandle(window: NSWindow?, target: NSWindow?) -> Bool {
        if let target { return target === window }
        return isActiveWindow(window)
    }
```
In `UI/ContentViewCommandHandlers.swift`, the handlers for `.openPreviousFile` (L114), `.openNextFile` (L120), `.captureScreenshot` (L132) and `.reloadPlayer` (L564) bind the target and guard with it. For example:
```swift
                guard let command = notification.appCommand,
                      case let .openPreviousFile(targetWindow) = command,
                      WindowManager.shared.shouldHandle(window: nsWindow, target: targetWindow) else { return }
                openPreviousFile()
```
`.reloadPlayer` additionally coalesces bursts. MPVVideoView's growth reload and WindowConfigurator's resize reload can both fire for one resize. Add to that handler struct `@State private var reloadCoalescer = DeferredMainActorTask()`, then:
```swift
                guard let command = notification.appCommand,
                      case let .reloadPlayer(targetWindow) = command,
                      WindowManager.shared.shouldHandle(window: nsWindow, target: targetWindow),
                      isMediaLoaded else { return }
                reloadCoalescer.schedule(after: .milliseconds(100)) {
                    compareSession.reload(primary: controller)
                }
```
Test, in `WindowManagerTests`, `@MainActor`:
```swift
    func testATargetedCommandReachesOnlyItsWindow() {
        let a = NSWindow(), b = NSWindow()
        XCTAssertTrue(WindowManager.shared.shouldHandle(window: a, target: a))
        XCTAssertFalse(WindowManager.shared.shouldHandle(window: b, target: a))
    }
```
Commit: `Target window-scoped commands at their window`

### 3.2 PlayerController: OSD, VLC actions, aspect and crop

**MPV setup.** In `Logic/MPV/MPVPlayer.swift` `setupMPV`, after the `deinterlace` option (L1246), add the line below. Verified B2: both options are global and survive `loadfile`. Restoring them after `uninit_video_chain` costs no refresh seek.
```swift
        // Aspect and crop are per-file choices (VLC); mpv keeps them across loadfile otherwise.
        checkError(mpv_set_option_string(mpv, "reset-on-next-file", "video-aspect-override,video-crop"), context: "reset-on-next-file")
```
After `seekRelative` (L557), add:
```swift
    /// mpv's frame-step: show the next frame, then pause.
    func frameStep() {
        command("frame-step")
    }

    /// The source frame as mpv reports it, for VLC's aspect and crop choices.
    func videoFrameGeometry(naturalPixelAspect: Double) -> VideoFrameGeometry? {
        let width = Int(getDouble("video-params/w"))
        let height = Int(getDouble("video-params/h"))
        guard width > 0, height > 0 else { return nil }
        let cropW = Int(getDouble("video-params/crop-w"))
        let cropH = Int(getDouble("video-params/crop-h"))
        let hasBase = cropW > 0 && cropH > 0 && (cropW < width || cropH < height)
        return VideoFrameGeometry(
            width: width, height: height,
            baseX: hasBase ? Int(getDouble("video-params/crop-x")) : 0,
            baseY: hasBase ? Int(getDouble("video-params/crop-y")) : 0,
            baseWidth: hasBase ? cropW : nil,
            baseHeight: hasBase ? cropH : nil,
            naturalPixelAspect: naturalPixelAspect,
            rotation: Int(getDouble(MPVProperty.videoParamsRotate)))
    }
```

**PlayerController state.** In `Logic/PlayerController.swift`, after `let frameCapture = FrameCapture()` (L211):
```swift
    let osd = PlayerOSD()
    /// VLC aspect and crop menu positions; reset per file (mpv resets with reset-on-next-file).
    @Published var aspectChoiceIndex = 0
    @Published var cropChoiceIndex = 0
    /// The picture's on-screen ratio while an aspect or crop choice is active.
    var choiceDisplayRatio: CGFloat?
    /// `video-params/par` captured while no aspect override was set.
    var naturalPixelAspect: Double?
```
In `loadMedia`, inside `if previousURL != item.url || !isReady {` after `mediaOperations.clearTrimPoints()`, reset the per-file state:
```swift
            aspectChoiceIndex = 0
            cropChoiceIndex = 0
            choiceDisplayRatio = nil
            naturalPixelAspect = nil
```

**Aspect sink.** In the mpv aspect sink (L682-691), change the assignment to `self.videoAspectRatio = self.choiceDisplayRatio ?? ratio`, so the window keeps the chosen shape.

**Volume.** Change the clamps at L43, L230 and L845 from `0...100` to `0...PlaybackVolume.maxPercent`. In `Logic/PlayerBackendAdapter.swift` L49, AVPlayer's volume is 0…1, so use `set { player.volume = Float(min(newValue, 100) / 100) }`.

**OSD hooks.**
- `adjustVolume(by:)`, after the clamp: `osd.show(.volume(volume, max: PlaybackVolume.maxPercent))`.
- `toggleMute()`, after the toggle: `osd.show(isMuted ? .mute : .unmute)`.
- `seek(by:)`, after `seekTo(...)`: `osd.show(.seek(position: currentPlaybackTime, duration: item.durationSeconds))`. `seekTo` sets `currentPlaybackTime` synchronously (L1255).
- `stepRate(forward:)`, after `currentPlaybackSpeed = backendAdapter.rate`: `osd.show(.speed(Double(currentPlaybackSpeed)))`.
- `togglePlayback()`, inside `if let backendAdapter {` after the play/pause branch:
  ```swift
            let position = currentPlaybackTime
            let duration = mediaItem?.durationSeconds ?? 0
            osd.show(wasPaused ? .resume(position: position, duration: duration) : .pause(position: position, duration: duration))
  ```

**New file `Logic/PlayerController+VLC.swift`:**
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's per-key actions on the mpv backend. Each shows IINA's OSD text.

import AppKit

extension PlayerController {
    func stop() {
        pause()
        seekTo(0)
        osd.show(.stop)
    }

    /// VLC's E: pause, then show the next frame.
    func frameStepForward() {
        pause()
        if useMPV, let mpvPlayer {
            mpvPlayer.frameStep()
        } else {
            seekByFrames(1)
        }
        osd.show(.nextFrame)
    }

    func adjustAudioDelay(by delta: Double) {
        guard useMPV, let mpvPlayer else { return }
        let value = ((mpvPlayer.getDouble("audio-delay") + delta) * 1000).rounded() / 1000
        mpvPlayer.setString("audio-delay", String(value))
        osd.show(.audioDelay(value))
    }

    func resetAudioDelay() {
        guard useMPV, let mpvPlayer else { return }
        mpvPlayer.setString("audio-delay", "0")
        osd.show(.audioDelay(0))
    }

    /// VLC hotkeys.c ACTIONID_DEINTERLACE: off turns it on; on or auto turns it off.
    func toggleDeinterlace() {
        guard useMPV, let mpvPlayer else { return }
        let on = mpvPlayer.getString("deinterlace") == "no"
        mpvPlayer.setString("deinterlace", on ? "yes" : "no")
        osd.show(.deinterlace(on))
    }

    func cycleAudioTrack() {
        let positions = audioTrackOptions.map(\.position)
        guard let first = positions.first else { return }
        let next = positions.firstIndex(of: selectedAudioTrackOrderIndex)
            .map { positions[($0 + 1) % positions.count] } ?? first
        selectAudioTrack(at: next)
        osd.show(.audioTrack(audioTrackOptions.first { $0.position == next }?.title ?? ""))
    }

    func showPositionOSD() {
        osd.show(.seek(position: playbackTimeSnapshot(), duration: mediaItem?.durationSeconds ?? 0))
    }

    // MARK: - Aspect and crop (VLC vout_intf.c lists)

    func selectAspectChoice(_ index: Int) {
        guard VLCVideoChoices.aspectRatios.indices.contains(index) else { return }
        applyVideoChoices(aspect: index, crop: cropChoiceIndex)
        osd.show(.aspect(VLCVideoChoices.aspectRatios[index].title))
    }

    func cycleAspectRatio() {
        selectAspectChoice(VLCVideoChoices.nextIndex(after: aspectChoiceIndex, count: VLCVideoChoices.aspectRatios.count))
    }

    func selectCropChoice(_ index: Int) {
        guard VLCVideoChoices.crops.indices.contains(index) else { return }
        applyVideoChoices(aspect: aspectChoiceIndex, crop: index)
        osd.show(.crop(VLCVideoChoices.crops[index].title))
    }

    func cycleCrop() {
        selectCropChoice(VLCVideoChoices.nextIndex(after: cropChoiceIndex, count: VLCVideoChoices.crops.count))
    }

    /// Writes both mpv options from the VLC choices, then reshapes the window
    /// to the picture's new ratio (VLC macosx-video-autoresize, verified D4).
    private func applyVideoChoices(aspect: Int, crop: Int) {
        guard useMPV, let mpvPlayer else { return }
        // video-params/par is the PAR mpv uses only while no override is set.
        if naturalPixelAspect == nil, aspectChoiceIndex == 0 {
            let par = mpvPlayer.getDouble("video-params/par")
            naturalPixelAspect = par > 0 ? par : 1
        }
        guard let geometry = mpvPlayer.videoFrameGeometry(naturalPixelAspect: naturalPixelAspect ?? 1) else { return }
        let aspectChoice = VLCVideoChoices.aspectRatios[aspect]
        let cropChoice = VLCVideoChoices.crops[crop]
        if aspect != aspectChoiceIndex {
            mpvPlayer.setString("video-aspect-override", VLCVideoChoices.mpvAspect(for: aspectChoice, geometry: geometry))
        }
        mpvPlayer.setString("video-crop", VLCVideoChoices.mpvCrop(for: cropChoice, aspect: aspectChoice, geometry: geometry))
        aspectChoiceIndex = aspect
        cropChoiceIndex = crop
        guard let ratio = VLCVideoChoices.displayedRatio(crop: cropChoice, aspect: aspectChoice, geometry: geometry) else { return }
        choiceDisplayRatio = aspect == 0 && crop == 0 ? nil : CGFloat(ratio)
        videoAspectRatio = CGFloat(ratio)
        NotificationCenter.default.post(.fitWindowToVideo(ratio: CGFloat(ratio), targetWindow: playerView?.window))
    }
}
```
A paused aspect or crop change triggers an exact refresh seek inside mpv (verified B1). AMP handles no `MPV_EVENT_SEEK`, so nothing else needs changing.

Commit: `Add VLC's per-key player actions with IINA OSD text`

### 3.3 OSD model and view

`Logic/PlayerOSD.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// IINA's OSD timing: shown at once, replaced in place, held 1 s, faded out over
// 0.5 s. VoiceOver hears only the settled message.

import SwiftUI

final class PlayerOSD: ObservableObject {
    @Published private(set) var message: PlayerOSDMessage?
    private let hide = DeferredMainActorTask()
    private let announcement = DeferredMainActorTask()

    func show(_ message: PlayerOSDMessage) {
        self.message = message
        hide.schedule(after: .seconds(IINAStyle.osdHold)) { [weak self] in
            withAnimation(.easeOut(duration: IINAStyle.osdFadeOut)) { self?.message = nil }
        }
        let text = message.text
        announcement.schedule(after: .milliseconds(400)) {
            AccessibilityNotification.Announcement(text).post()
        }
    }
}
```
`UI/PlayerOSDView.swift`. `Text + Text` is deprecated at macOS 26 (Apple doc JSON), so it uses interpolation:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// IINA's OSDView: glass r16, 16/8 padding, 20 pt value, 18 pt prefix, 11 pt
// second line, 4 pt accent bar in a 12 pt frame.

import SwiftUI

struct PlayerOSDView: View {
    @ObservedObject var osd: PlayerOSD
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let message = osd.message {
            VStack(alignment: .leading, spacing: 0) {
                title(message)
                if let secondary = message.secondaryText {
                    Text(secondary)
                        .font(.system(size: IINAStyle.osdSecondarySize).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let progress = message.progress {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: IINAStyle.osdBarRadius)
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * progress, height: IINAStyle.osdBarHeight)
                            .frame(maxHeight: .infinity)
                    }
                    .frame(height: IINAStyle.osdBarFrameHeight)
                }
            }
            .padding(.horizontal, IINAStyle.osdPaddingH)
            .padding(.vertical, IINAStyle.osdPaddingV)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: IINAStyle.osdCornerRadius).fill(.black)
                }
            }
            .modifier(OSDGlass(enabled: !reduceTransparency))
            .environment(\.colorScheme, .dark)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func title(_ message: PlayerOSDMessage) -> Text {
        let split = message.split
        let prefix = Text(verbatim: split.prefix ?? "")
            .font(.system(size: IINAStyle.osdPrefixSize).monospacedDigit())
            .foregroundStyle(.secondary)
        let value = Text(verbatim: split.value)
            .font(.system(size: IINAStyle.osdTextSize).monospacedDigit())
            .foregroundStyle(.primary)
        let suffix = Text(verbatim: split.suffix ?? "")
            .font(.system(size: IINAStyle.osdPrefixSize).monospacedDigit())
            .foregroundStyle(.secondary)
        return Text("\(prefix)\(value)\(suffix)")
    }
}

private struct OSDGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.glassEffect(.regular, in: .rect(cornerRadius: IINAStyle.osdCornerRadius))
        } else {
            content
        }
    }
}
```
Mount it in `UI/PlayerView.swift` `overlayIndicators` (L215-236). The outer `VStack {` becomes `VStack(alignment: .leading, spacing: IINAStyle.osdEdge) {`. Keep the existing `HStack` row, then add `PlayerOSDView(osd: controller.osd)` before the trailing `Spacer()`. AMP has no title bar, so the OSD sits under the indicator row, clear of the traffic lights.

Commit: `Show IINA's on-screen messages`

### 3.4 Video mouse surface

`UI/ClosureMenuItem.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, isChecked: Bool = false, isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = isChecked ? .on : .off
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() { handler() }
}
```
`UI/VideoMouseSurface.swift` handles three things:
- **Drag.** `performDrag(with:)` "returns right away, and a mouse-up event may not get sent" (Apple doc). The drag state is therefore reset only by the next single click.
- **Context menu.** It acts on its own window and controller (C5).
- **Wheel.** It acts on this window's player.
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's video surface (VLCVoutView.m): a click does nothing, dragging past 3 pt
// moves the window (IINA's threshold), a double-click toggles the windowed
// screen fill, a right-click opens VLC's video menu, the wheel changes volume
// (Y) and jumps 3 s (X).

import AppKit
import SwiftUI

struct VideoMouseSurface: NSViewRepresentable {
    let controller: PlayerController

    func makeNSView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: SurfaceView, context: Context) {
        nsView.controller = controller
    }

    final class SurfaceView: NSView {
        static let dragThreshold: CGFloat = 3

        weak var controller: PlayerController?
        /// The single click a drag may start from; cleared once a drag starts.
        private var dragOrigin: NSEvent?
        /// A drag started after the last single click, so the next click is not
        /// half of a double-click. Reset only by a fresh single click.
        private var draggedSinceClick = false
        private var scroll = ScrollStepAccumulator()

        override var acceptsFirstResponder: Bool { false }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        // MARK: - Click and drag

        override func mouseDown(with event: NSEvent) {
            switch event.clickCount {
            case 1:
                dragOrigin = event
                draggedSinceClick = false
            case 2:
                dragOrigin = nil
                guard !draggedSinceClick, let window else { return }
                NotificationCenter.default.post(.toggleFillScreen(targetWindow: window))
            default:
                dragOrigin = nil
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragOrigin, let window, !window.styleMask.contains(.fullScreen) else { return }
            let a = start.locationInWindow
            let b = event.locationInWindow
            guard hypot(b.x - a.x, b.y - a.y) > Self.dragThreshold else { return }
            dragOrigin = nil
            draggedSinceClick = true
            window.performDrag(with: start)
        }

        override func mouseUp(with event: NSEvent) {
            dragOrigin = nil
        }

        // MARK: - Wheel

        override func scrollWheel(with event: NSEvent) {
            guard let controller, controller.mediaItem != nil else { return }
            let steps = scroll.steps(
                deltaX: Double(event.deltaX),
                deltaY: Double(event.deltaY),
                isDirectionInverted: event.isDirectionInvertedFromDevice,
                isMouseWheel: event.phase.isEmpty && event.momentumPhase.isEmpty,
                timestamp: event.timestamp)
            for step in steps {
                switch step {
                case .volumeUp: controller.adjustVolume(by: VLCKeyMap.volumeStep)
                case .volumeDown: controller.adjustVolume(by: -VLCKeyMap.volumeStep)
                case .seekForward: controller.seek(by: 3)
                case .seekBackward: controller.seek(by: -3)
                }
            }
        }

        // MARK: - Context menu (VLC voutMenu, IINA titles)

        override func rightMouseDown(with event: NSEvent) {
            // Make the menu bar's focused commands follow the clicked window.
            window?.makeKey()
            super.rightMouseDown(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard let controller, controller.mediaItem != nil, let window else { return nil }
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.addItem(ClosureMenuItem(controller.isPlaying ? "Pause" : "Play") { controller.togglePlayback() })
            menu.addItem(ClosureMenuItem("Stop") { controller.stop() })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Previous") { NotificationCenter.default.post(.openPreviousFile(targetWindow: window)) })
            menu.addItem(ClosureMenuItem("Next") { NotificationCenter.default.post(.openNextFile(targetWindow: window)) })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Volume Up") { controller.adjustVolume(by: VLCKeyMap.volumeStep) })
            menu.addItem(ClosureMenuItem("Volume Down") { controller.adjustVolume(by: -VLCKeyMap.volumeStep) })
            menu.addItem(ClosureMenuItem("Mute", isChecked: controller.isMuted) { controller.toggleMute() })
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem("Fill Screen") { NotificationCenter.default.post(.toggleFillScreen(targetWindow: window)) })
            menu.addItem(ClosureMenuItem("Fullscreen") { controller.toggleFullscreen() })
            menu.addItem(ClosureMenuItem("Snapshot") { NotificationCenter.default.post(.captureScreenshot(targetWindow: window)) })
            menu.addItem(.separator())
            menu.addItem(submenu("Audio Track", items: controller.audioTrackOptions.map { option in
                ClosureMenuItem(option.title, isChecked: option.position == controller.selectedAudioTrackOrderIndex) {
                    controller.selectAudioTrack(at: option.position)
                }
            }))
            menu.addItem(submenu("Aspect Ratio", items: VLCVideoChoices.aspectRatios.indices.map { index in
                ClosureMenuItem(VLCVideoChoices.aspectRatios[index].title, isChecked: index == controller.aspectChoiceIndex) {
                    controller.selectAspectChoice(index)
                }
            }))
            menu.addItem(submenu("Crop", items: VLCVideoChoices.crops.indices.map { index in
                ClosureMenuItem(VLCVideoChoices.crops[index].title, isChecked: index == controller.cropChoiceIndex) {
                    controller.selectCropChoice(index)
                }
            }))
            return menu
        }

        private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            sub.autoenablesItems = false
            items.forEach(sub.addItem)
            item.submenu = sub
            item.isEnabled = !items.isEmpty
            return item
        }
    }
}
```
In `UI/ComparePlayerView.swift`, insert after the `comparisonSurfaces(...)` block (L48-54) and before `if compareSession.isActive { comparisonGuides ... }` (L56). Compare Mode keeps its own pointer handling.
```swift
                if !compareSession.isActive {
                    VideoMouseSurface(controller: primaryController)
                        .frame(width: size.width, height: size.height)
                }
```
**Mac acceptance (C1 is UNSETTLED):**
- A click does nothing, and a drag moves the window.
- A double-click fills the screen, and another restores the window.
- Inside native fullscreen, a double-click leaves fullscreen.
- Right-clicking a background window opens its menu and makes that window key.
- The wheel changes volume and jumps 3 s.
- The OSC card, loupe hover and Compare wipe still work.

If clicks on empty video stop reaching the surface once Part 4.8 makes the OSC overlay full-size, apply `.allowsHitTesting(false)` to the `GeometryReader` and `.allowsHitTesting(true)` to the card. If that is not enough, measure with `onGeometryChange(for:of:action:)` (macOS 13+) instead of a full-size `GeometryReader`.

Commit: `Add VLC's video mouse surface`

### 3.5 WindowConfigurator: fill, size presets, fit to video, float on top, aspect lock

Facts this design rests on:
- Apple documents `contentAspectRatio` and `contentResizeIncrements` as mutually exclusive: setting one cancels the other.
- Programmatic sizes ignore both.
- Assigning `.zero` to `contentAspectRatio` is reported by four apps to leave a degenerate ratio that traps (verified C4).
- New code therefore unlocks with `contentResizeIncrements = 1×1`. `updateNSView` already does this (L367).

In `UI/WindowConfigurator.swift`: `import Combine`. The struct gets `var onFloatOnTopChange: ((Bool) -> Void)? = nil`, which `updateNSView` passes on as `context.coordinator.onFloatOnTopChange = onFloatOnTopChange`.

Coordinator additions:
```swift
        /// The frame before a fill toggle; `nil` when the window is not filled by a toggle.
        var savedFillFrame: NSRect?
        var isFloatingOnTop = false
        /// The level to restore after fullscreen or miniaturize (VLC i_originalLevel).
        var levelBeforeSuspension: NSWindow.Level?
        var onFloatOnTopChange: ((Bool) -> Void)?
        private var commandCancellable: AnyCancellable?
        nonisolated(unsafe) var willStartLiveResize: NSObjectProtocol?
        nonisolated(unsafe) var miniaturizeObservers: [NSObjectProtocol] = []
        private let surfaceReload = DeferredMainActorTask()
```
`deinit` additionally removes `willStartLiveResize` and every token in `miniaturizeObservers`.

`maximize(_:)` (L119-124). Replace `window.contentAspectRatio = .zero` with `unlockAspect(window)` (defined below). Keep the rest.

New methods:
```swift
        func unlockAspect(_ window: NSWindow) {
            window.contentResizeIncrements = NSSize(width: 1, height: 1)
        }

        private func lockAspect(_ window: NSWindow, ratio: CGFloat?) {
            guard let ratio, ratio.isFinite, ratio > 0 else { return }
            applyMinSize(window, ratio: ratio)
            window.contentAspectRatio = NSSize(width: ratio, height: 1)
        }

        private func titlebarHeight(_ window: NSWindow) -> CGFloat {
            window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)
        }

        /// Programmatic resize: unlock, resize, re-lock, then rebuild the surface
        /// (removed by Part 5.1 once the fork reports VO_EVENT_RESIZE).
        private func resize(_ window: NSWindow, to frame: NSRect, lockingTo ratio: CGFloat?) {
            guard frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return }
            unlockAspect(window)
            applyMinSize(window, ratio: nil)
            window.setFrame(frame, display: true, animate: false)
            lockAspect(window, ratio: ratio)
            requestSurfaceReload(window)
        }

        /// VLC's double-click and ⌘3: fill `visibleFrame`, staying windowed;
        /// again restores the saved frame. In native fullscreen it leaves it.
        func toggleFillScreen(_ window: NSWindow) {
            if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
                return
            }
            guard let screen = window.screen ?? NSScreen.main else { return }
            let visible = screen.visibleFrame
            if savedFillFrame != nil || WindowSizing.isFilling(frame: window.frame, visible: visible) {
                let ratio = lastAspectRatio ?? savedAspectRatio
                let target: NSRect
                if let saved = savedFillFrame {
                    target = WindowSizing.fitted(
                        width: saved.width, ratio: ratio ?? saved.width / max(1, saved.height),
                        titlebarHeight: titlebarHeight(window),
                        minimumContent: WindowConfigurator.minContentSize(for: ratio),
                        visible: visible, anchor: saved)
                } else {
                    target = presetFrame(.normal, window: window, ratio: ratio, visible: visible)
                }
                savedFillFrame = nil
                resize(window, to: target, lockingTo: ratio)
            } else {
                savedFillFrame = window.frame
                maximize(window)
                requestSurfaceReload(window)
            }
        }

        func applySizePreset(_ preset: WindowSizePreset, to window: NSWindow, ratio: CGFloat? = nil) {
            guard !window.styleMask.contains(.fullScreen), let screen = window.screen ?? NSScreen.main else { return }
            let ratio = ratio ?? lastAspectRatio ?? savedAspectRatio
            savedFillFrame = nil
            resize(window, to: presetFrame(preset, window: window, ratio: ratio, visible: screen.visibleFrame), lockingTo: ratio)
        }

        /// VLC autoresize after an aspect or crop choice (verified D4): the window
        /// takes the picture's new shape at 1:1, unless filled or in fullscreen.
        func fitWindowToVideo(_ window: NSWindow, ratio: CGFloat) {
            lastAspectRatio = ratio
            savedAspectRatio = ratio
            guard !window.styleMask.contains(.fullScreen), savedFillFrame == nil,
                  let screen = window.screen ?? NSScreen.main,
                  !WindowSizing.isFilling(frame: window.frame, visible: screen.visibleFrame) else { return }
            if UserDefaults.standard.value(for: AppSettings.openAtSourceResolution) {
                applySizePreset(.normal, to: window, ratio: ratio)
            } else {
                let target = WindowSizing.fitted(
                    width: window.frame.width, ratio: ratio, titlebarHeight: titlebarHeight(window),
                    minimumContent: WindowConfigurator.minContentSize(for: ratio),
                    visible: screen.visibleFrame, anchor: window.frame)
                resize(window, to: target, lockingTo: ratio)
            }
        }

        private func presetFrame(_ preset: WindowSizePreset, window: NSWindow, ratio: CGFloat?, visible: NSRect) -> NSRect {
            WindowSizing.presetFrame(
                preset: preset, ratio: ratio ?? 16.0 / 9.0, sourceSize: lastSourceSize,
                backingScale: window.backingScaleFactor, titlebarHeight: titlebarHeight(window),
                minimumContent: WindowConfigurator.minContentSize(for: ratio),
                visible: visible, currentFrame: window.frame)
        }

        /// VLC Float on Top: NSStatusWindowLevel while windowed (verified D1).
        func setFloatingOnTop(_ onTop: Bool, window: NSWindow) {
            isFloatingOnTop = onTop
            onFloatOnTopChange?(onTop)
            let level: NSWindow.Level = onTop ? .statusBar : .normal
            if window.styleMask.contains(.fullScreen) || window.isMiniaturized {
                levelBeforeSuspension = level
            } else {
                window.level = level
            }
        }

        private func suspendLevel(_ window: NSWindow) {
            levelBeforeSuspension = window.level
            window.level = .normal
        }

        private func restoreLevel(_ window: NSWindow) {
            if let level = levelBeforeSuspension { window.level = level }
            levelBeforeSuspension = nil
        }

        private func requestSurfaceReload(_ window: NSWindow) {
            surfaceReload.schedule { [weak window] in
                NotificationCenter.default.post(.reloadPlayer(targetWindow: window))
            }
        }

        private func handle(_ command: AppCommand, window: NSWindow) {
            switch command {
            case let .toggleFillScreen(target):
                guard WindowManager.shared.shouldHandle(window: window, target: target) else { return }
                toggleFillScreen(window)
            case let .setWindowSize(preset):
                guard WindowManager.shared.isActiveWindow(window) else { return }
                applySizePreset(preset, to: window)
            case let .fitWindowToVideo(ratio, target):
                guard WindowManager.shared.shouldHandle(window: window, target: target) else { return }
                fitWindowToVideo(window, ratio: ratio)
            case .toggleFloatOnTop:
                guard WindowManager.shared.isActiveWindow(window) else { return }
                setFloatingOnTop(!isFloatingOnTop, window: window)
            default:
                break
            }
        }
```
In `observeWindow(_:)`, after `observedWindow = window` (L213). AppCommands are posted on the main thread, so the sink runs there:
```swift
            commandCancellable = NotificationCenter.default.appCommandPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self, weak window] notification in
                    MainActor.assumeIsolated {
                        guard let self, let window, let command = notification.appCommand else { return }
                        self.handle(command, window: window)
                    }
                }
            willStartLiveResize = NotificationCenter.default.addObserver(
                forName: NSWindow.willStartLiveResizeNotification, object: window, queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    // VLC macosx-lock-aspect-ratio: a user resize hugs the picture again.
                    guard let self, let window, !window.styleMask.contains(.fullScreen) else { return }
                    self.savedFillFrame = nil
                    self.lockAspect(window, ratio: self.lastAspectRatio ?? self.savedAspectRatio)
                }
            }
            miniaturizeObservers = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willMiniaturizeNotification, object: window, queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window, self.isFloatingOnTop else { return }
                        self.suspendLevel(window)
                    }
                },
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification, object: window, queue: .main
                ) { [weak self, weak window] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window else { return }
                        self.restoreLevel(window)
                    }
                },
            ]
```
Fullscreen observers:
- In the existing `willEnterFullScreen` closure, add `if self.isFloatingOnTop { self.suspendLevel(window) }`.
- In `didExitFullScreen`, add `self.restoreLevel(window)`.
- Use the closure's existing `window` capture.

**`ContentView.swift` plumbing.**
- Add `@State private var isFloatingOnTop = false`.
- Pass `WindowConfigurator(…, onFloatOnTopChange: { isFloatingOnTop = $0 })`.
- Add `.focusedSceneValue(\.isFloatingOnTop, isFloatingOnTop)` and `.focusedSceneObject(controller)` next to the existing `focusedSceneValue` lines (L253-256).

In `Aagedal_Media_PlayerApp.swift`, after `IsCompareModeActiveKey`:
```swift
struct IsFloatingOnTopKey: FocusedValueKey {
    typealias Value = Bool
}
```
and, in the `FocusedValues` extension, following the existing four:
```swift
    var isFloatingOnTop: Bool? {
        get { self[IsFloatingOnTopKey.self] }
        set { self[IsFloatingOnTopKey.self] = newValue }
    }
```
**Tests:**
- Update the `WindowConfiguratorTests` and `PlayerChromeBehaviourTests` L350 expectations that assert `contentAspectRatio == .zero` after a fill. They now assert `contentResizeIncrements == NSSize(width: 1, height: 1)`.
- Mac A/B check from C4: before switching, toggle fill 50 times with the old `.zero` build and with the new one, and record whether only `.zero` raises.

Commit: `Add VLC window sizes, screen fill, fit to video and float on top`

### 3.6 Keymap setting, VLC table wiring, menu shortcuts

**`Logic/AppSettings.swift`, Windows and playback group:**
```swift
    /// "vlc" (default) or "pro": VLC's macOS hotkeys, or AMP's JKL/arrow keys.
    static let keyboardLayout = AppSetting(key: "keyboardLayout", defaultValue: "vlc")
    static let showRemainingTime = AppSetting(key: "showRemainingTime", defaultValue: false)
    static let resumePlayback = AppSetting(key: "resumePlayback", defaultValue: ResumeMode.ask.rawValue)
    static let pauseWhenMinimized = AppSetting(key: "pauseWhenMinimized", defaultValue: false)
```
Add each to `defaultsDictionary`.

**`UI/Settings/KeyboardShortcutsView.swift`.**
- Add `@AppStorage(AppSettings.keyboardLayout.key) private var keyboardLayout = AppSettings.keyboardLayout.defaultValue`.
- At the top of the VStack:
  ```swift
                Picker("Keyboard Shortcuts", selection: $keyboardLayout) {
                    Text("VLC").tag("vlc")
                    Text("AMP Pro").tag("pro")
                }
                .pickerStyle(.segmented)
  ```
- When `keyboardLayout == "vlc"`, replace the Playback and Navigation sections with:
  ```swift
                shortcutSection("VLC", shortcuts: [
                    ("Space", "Play / Pause"),
                    ("\u{2318}.", "Stop"),
                    ("\u{2318}\u{2303}\u{2190} / \u{2192}", "Jump back / forward 3 seconds"),
                    ("\u{2318}\u{2325}\u{2190} / \u{2192}", "Jump back / forward 10 seconds"),
                    ("\u{2318}\u{21E7}\u{2190} / \u{2192}", "Jump back / forward 1 minute"),
                    ("\u{2318}\u{21E7}\u{2325}\u{2190} / \u{2192}", "Jump back / forward 5 minutes"),
                    ("\u{2318}\u{2190} / \u{2318}\u{2192}", "Previous / next file"),
                    ("\u{2318}\u{2191} / \u{2318}\u{2193}", "Volume up / down"),
                    ("\u{2318}\u{2325}\u{2193}", "Mute"),
                    ("\u{2318}= / \u{2318}-", "Faster / slower"),
                    ("E", "Next frame"),
                    ("T", "Show position"),
                    ("A / C", "Cycle aspect ratio / crop"),
                    ("D", "Deinterlace on / off"),
                    ("L", "Next audio track"),
                    ("F / G", "Audio delay \u{2212} / + 50 ms"),
                    ("\u{2318}F", "Fullscreen"),
                    ("Esc", "Leave fullscreen"),
                    ("\u{2318}0 / \u{2318}1 / \u{2318}2", "Half / normal / double size"),
                    ("\u{2318}3 or double-click", "Fill the screen (again to restore)"),
                    ("\u{2318}J", "Jump to time"),
                    ("Scroll", "Volume (vertical), jump 3 s (horizontal)"),
                ])
  ```

**`UI/PlayerView.swift`.**
- Add `@AppStorage(AppSettings.keyboardLayout.key) private var keyboardLayout = AppSettings.keyboardLayout.defaultValue`.
- After the user-override block (L272-283):
  ```swift
        let usesVLCKeys = keyboardLayout == "vlc"
        if usesVLCKeys,
           let chord = KeyChord.from(characters: characters, specialKey: specialKey, flags: modifiers),
           let action = VLCKeyMap.action(for: chord) {
            return perform(action)
        }
  ```
- Guard the AMP Pro key blocks with `!usesVLCKeys`:
  - the `PlayerKeyMap.characterAction` block (L288), except `.nudgeWipe`, which Compare Mode keeps. Insert at the top of the `if let action = …` body:
    ```swift
            let isNudge: Bool = { if case .nudgeWipe = action { return true }; return false }()
            if usesVLCKeys && !isNudge { return false }
    ```
    Return `false`, not `true`, so the key reaches the menu and the rest of the responder chain.
  - the JKL block (L364-383), with `!usesVLCKeys &&`;
  - the arrow table (L387-425), with `!usesVLCKeys,`.
- New method:
  ```swift
    private func perform(_ action: VLCKeyAction) -> Bool {
        let comparing = compareSession?.isActive == true
        switch action {
        case .stop: NotificationCenter.default.post(.stop)
        case .previousFile: NotificationCenter.default.post(.openPreviousFile())
        case .nextFile: NotificationCenter.default.post(.openNextFile())
        case let .seek(seconds): NotificationCenter.default.post(.seekBySeconds(seconds))
        case let .adjustVolume(delta): adjustVolume(by: delta)
        case .toggleMute: NotificationCenter.default.post(.toggleMute)
        case .faster: NotificationCenter.default.post(.stepRate(forward: true))
        case .slower: NotificationCenter.default.post(.stepRate(forward: false))
        case .nextFrame:
            if comparing { NotificationCenter.default.post(.seekByFrames(1)) } else { controller.frameStepForward() }
        case .showPosition: controller.showPositionOSD()
        case .cycleAspectRatio, .cycleCrop, .toggleDeinterlace, .nextAudioTrack, .audioDelay:
            // Compare Mode owns both players' picture and audio; these act on one.
            guard !comparing else { return false }
            switch action {
            case .cycleAspectRatio: controller.cycleAspectRatio()
            case .cycleCrop: controller.cycleCrop()
            case .toggleDeinterlace: controller.toggleDeinterlace()
            case .nextAudioTrack: controller.cycleAudioTrack()
            case let .audioDelay(delta): controller.adjustAudioDelay(by: delta)
            default: break
            }
        case .leaveFullscreen:
            // VLC leaves fullscreen and swallows Esc when windowed (verified D5).
            if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        }
        return true
    }
  ```

**`Aagedal_Media_PlayerApp.swift`.**
- Add `@AppStorage(AppSettings.keyboardLayout.key) private var keyboardLayout = AppSettings.keyboardLayout.defaultValue` and `private var vlcKeys: Bool { keyboardLayout == "vlc" }`.
- **AMP Pro keeps its bare keys unchanged.** `PlayerKeyMap` has no `t` or `m`; those exist only as menu equivalents.
- Shortcut changes:
  - L145: `.keyboardShortcut(vlcKeys ? nil : KeyboardShortcut("t", modifiers: []))`
  - L198: `.keyboardShortcut(vlcKeys ? KeyboardShortcut(.downArrow, modifiers: [.command, .option]) : KeyboardShortcut("m", modifiers: []))`
  - L204 / L210: `.keyboardShortcut(vlcKeys ? KeyboardShortcut(.upArrow, modifiers: .command) : KeyboardShortcut(.upArrow, modifiers: .control))`, and the same with `.downArrow`.
  - L218 / L224: `.keyboardShortcut(vlcKeys ? nil : KeyboardShortcut("j", modifiers: []))`, and the same with `"l"`.
  - L260: `.keyboardShortcut("f", modifiers: vlcKeys ? .command : [.control, .command])`.
- Insert after Play/Pause (L192):
  ```swift
                Button("Stop") { NotificationCenter.default.post(.stop) }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!mediaLoaded)
                Button("Jump to Time\u{2026}") { NotificationCenter.default.post(.jumpToTime) }
                    .keyboardShortcut("j", modifiers: .command)
                    .disabled(!mediaLoaded)
  ```

**`.stop` handler.** In `ContentViewCommandHandlers.swift` `PlaybackHandlers`, after the togglePlayback handler (L358-365):
```swift
            .onReceive(NotificationCenter.default.appCommandPublisher) { notification in
                guard let command = notification.appCommand, case .stop = command,
                      WindowManager.shared.shouldHandlePlaybackCommand(window: nsWindow) else { return }
                if compareSession.isActive {
                    compareSession.pause(primary: controller)
                    compareSession.seek(primary: controller, to: 0)
                } else {
                    controller.stop()
                }
            }
```
Commit: `Add the switchable VLC keyboard layout`

### 3.7 Video and Audio menus

C2 is UNSETTLED. Picker-in-Menu has an Apple-acknowledged bug (FB15061288), and Apple's own workaround for focused values in menus is to read them inside a View used as the menu content (forum 651748). The menus therefore use View-typed content with `@FocusedObject` and Toggle rows, which render as checkmark items.

`UI/PlayerMenus.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's Video and Audio menus. The focused player is read inside a View (Apple's
// workaround, forums 651748); choices are Toggles, which render as checkmarks,
// rather than Pickers (FB15061288).

import SwiftUI

struct VideoMenuContent: View {
    @FocusedObject private var controller: PlayerController?
    let mediaLoaded: Bool
    let isFloatingOnTop: Bool

    var body: some View {
        Button("Half Size") { NotificationCenter.default.post(.setWindowSize(.half)) }
            .keyboardShortcut("0", modifiers: .command).disabled(!mediaLoaded)
        Button("Normal Size") { NotificationCenter.default.post(.setWindowSize(.normal)) }
            .keyboardShortcut("1", modifiers: .command).disabled(!mediaLoaded)
        Button("Double Size") { NotificationCenter.default.post(.setWindowSize(.double)) }
            .keyboardShortcut("2", modifiers: .command).disabled(!mediaLoaded)
        Button("Fit to Screen") { NotificationCenter.default.post(.toggleFillScreen()) }
            .keyboardShortcut("3", modifiers: .command).disabled(!mediaLoaded)
        Toggle("Float on Top", isOn: Binding(
            get: { isFloatingOnTop },
            set: { _ in NotificationCenter.default.post(.toggleFloatOnTop) }))
            .disabled(!mediaLoaded)
        Divider()
        if let controller {
            Menu("Aspect Ratio") {
                ForEach(VLCVideoChoices.aspectRatios.indices, id: \.self) { index in
                    Toggle(VLCVideoChoices.aspectRatios[index].title, isOn: Binding(
                        get: { controller.aspectChoiceIndex == index },
                        set: { _ in controller.selectAspectChoice(index) }))
                }
            }
            Menu("Crop") {
                ForEach(VLCVideoChoices.crops.indices, id: \.self) { index in
                    Toggle(VLCVideoChoices.crops[index].title, isOn: Binding(
                        get: { controller.cropChoiceIndex == index },
                        set: { _ in controller.selectCropChoice(index) }))
                }
            }
            Button("Deinterlace") { controller.toggleDeinterlace() }
        }
    }
}

struct AudioMenuContent: View {
    @FocusedObject private var controller: PlayerController?

    var body: some View {
        if let controller {
            Menu("Audio Track") {
                ForEach(controller.audioTrackOptions) { option in
                    Toggle(option.title, isOn: Binding(
                        get: { controller.selectedAudioTrackOrderIndex == option.position },
                        set: { _ in controller.selectAudioTrack(at: option.position) }))
                }
            }
            Divider()
            Button("Increase Audio Delay") { controller.adjustAudioDelay(by: VLCKeyMap.delayStep) }
            Button("Decrease Audio Delay") { controller.adjustAudioDelay(by: -VLCKeyMap.delayStep) }
            Button("Reset Audio Delay") { controller.resetAudioDelay() }
        }
    }
}
```
In `Aagedal_Media_PlayerApp.swift`, add `@FocusedValue(\.isFloatingOnTop) private var isFloatingOnTop`. After `CommandMenu("Playback") { … }`:
```swift
            CommandMenu("Video") {
                VideoMenuContent(mediaLoaded: mediaLoaded, isFloatingOnTop: isFloatingOnTop ?? false)
            }
            CommandMenu("Audio") {
                AudioMenuContent()
            }
```
**Mac acceptance (C2):**
- Open two player windows with different audio-track counts.
- Change the aspect in window A, then switch to window B.
- Open each menu: the checkmarks and items must reflect B.

If they stay stale, replace the Toggle rows with Buttons whose titles carry a "✓ " prefix computed from the same bindings.

Commit: `Add VLC's Video and Audio menus`

### 3.8 Elapsed and remaining time (IINA and VLC agree)

In `UI/FloatingOSCView.swift`:
- Add `@AppStorage(AppSettings.showRemainingTime.key) private var showRemainingTime = AppSettings.showRemainingTime.defaultValue`.
- Change `timeLabel(_ seconds: Double)` (L116) into `timeLabel(_ text: String)`, with `Text(text)` and the same modifiers.
- In `scrubberRow`:
  - the elapsed label becomes `timeLabel(TimecodeFormatter.formatTraditionalTime(controller.currentPlaybackTime)).accessibilityLabel("Elapsed time").onTapGesture(count: 2) { NotificationCenter.default.post(.jumpToTime) }`;
  - the duration label becomes:
```swift
            timeLabel(showRemainingTime
                      ? "-" + TimecodeFormatter.formatTraditionalTime(max(0, duration - controller.currentPlaybackTime))
                      : TimecodeFormatter.formatTraditionalTime(duration))
                .contentShape(Rectangle())
                .onTapGesture { showRemainingTime.toggle() }
                .help("Click to show remaining time")
                .accessibilityLabel(showRemainingTime ? "Remaining time" : "Duration")
```
Commit: `Toggle elapsed and remaining time like VLC and IINA`

### 3.9 Resume playback (VLC, verified D3)

How VLC behaves:
- Ask, Always or Never, with Ask as the default.
- Playback is **not** paused while asking, and Continue seeks.
- A 10 s countdown ends with Restart, which means no seek. Return activates Continue.
- When the item changes, the offer is cancelled without seeking.

**`UI/Settings/GeneralSettingsView.swift`.** Add the `@AppStorage` properties for `resumePlayback` and `pauseWhenMinimized`, then in `Section("Playback")`:
```swift
                Picker("Continue Playback", selection: $resumePlayback) {
                    Text("Ask").tag(ResumeMode.ask.rawValue)
                    Text("Always").tag(ResumeMode.always.rawValue)
                    Text("Never").tag(ResumeMode.never.rawValue)
                }
                Toggle("Pause When Minimized", isOn: $pauseWhenMinimized)
```
**`Logic/PlayerWindowCoordinator.swift`:**
```swift
    /// VLC's "Continue playback?" offer for the file just opened.
    struct ResumeOffer: Equatable {
        let url: URL
        let position: TimeInterval
    }

    @Published var resumeOffer: ResumeOffer?

    /// Stores where `controller` is, unless this file's offer is still unanswered:
    /// leaving then keeps the position that was offered.
    func saveResumePosition(for controller: PlayerController) {
        guard let item = controller.mediaItem, resumeOffer?.url != item.url else { return }
        ResumePositionStore.standard.save(url: item.url, position: controller.playbackTimeSnapshot(),
                                          duration: item.durationSeconds)
    }
```
In `openFile` (L166), before `var item = Self.makeMediaItem(for: url)` (L179):
```swift
        saveResumePosition(for: controller)
        resumeOffer = nil
        let mode = ResumeMode(rawValue: UserDefaults.standard.value(for: AppSettings.resumePlayback)) ?? .ask
        let saved = mode == .never ? nil : ResumePositionStore.standard.position(for: url)
```
Replace L195:
```swift
            controller.loadMedia(item, startTime: mode == .always ? (saved ?? 0) : 0,
                                 autoplay: UserDefaults.standard.value(for: AppSettings.autoPlayOnOpen))
            if mode == .ask, let saved { self.resumeOffer = ResumeOffer(url: url, position: saved) }
```
**`ContentView.swift`.**
- In the `onClose` closure (L267-274), add `windowCoordinator` to the capture list and call `windowCoordinator.saveResumePosition(for: controller)` before `Self.stopPlaybackForWindowClose`. Do the same before the second call (L389).
- Add the terminate save:
```swift
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            windowCoordinator.saveResumePosition(for: controller)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willMiniaturizeNotification)) { notification in
            guard (notification.object as? NSWindow) === nsWindow,
                  UserDefaults.standard.value(for: AppSettings.pauseWhenMinimized) else { return }
            controller.pause()
        }
```
**`UI/ResumeOfferBanner.swift`:**
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// VLC's "Continue playback?" offer, non-modal like VLC's dialog: playback keeps
// going, Continue seeks, Restart counts down from 10 and wins on timeout.

import SwiftUI

struct ResumeOfferBanner: View {
    let position: TimeInterval
    let onContinue: () -> Void
    let onDismiss: () -> Void
    @State private var remaining = ResumePolicy.offerSeconds

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Text("Continue playback at \(TimecodeFormatter.formatTraditionalTime(position))?")
                    .font(.system(size: 13, weight: .medium))
                Button("Continue", action: onContinue).keyboardShortcut(.defaultAction)
                Button("Restart (\(remaining))", action: onDismiss)
            }
            .padding(.horizontal, IINAStyle.osdPaddingH)
            .padding(.vertical, IINAStyle.osdPaddingV)
            .glassEffect(.regular, in: .rect(cornerRadius: IINAStyle.osdCornerRadius))
            .environment(\.colorScheme, .dark)
            .padding(.top, 36)
            Spacer()
        }
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
            }
            onDismiss()
        }
    }
}
```
Mount it in `renderedContentLayers` (L192-305) after the update banner:
```swift
            if let offer = windowCoordinator.resumeOffer, offer.url == controller.mediaItem?.url {
                ResumeOfferBanner(
                    position: offer.position,
                    onContinue: { controller.seekTo(offer.position); windowCoordinator.resumeOffer = nil },
                    onDismiss: { windowCoordinator.resumeOffer = nil })
            }
```
Commit: `Offer VLC's continue playback`

### 3.10 Now Playing and media keys

Verified C3: handlers are `@Sendable` and hop to the main actor. `MPRemoteCommand`'s handler thread is undocumented, and Apple DTS reports MediaPlayer calling closures off the main thread.

`Logic/NowPlayingCoordinator.swift`:
```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Media keys and Control Center for the active player window. playbackState is
// set on every change (required on macOS). Remote-command handlers are
// @Sendable and hop to the main actor: their thread is undocumented.

import AppKit
import MediaPlayer

final class NowPlayingCoordinator {
    static let shared = NowPlayingCoordinator()
    private weak var owner: PlayerController?
    private weak var ownerWindow: NSWindow?
    private var commandsInstalled = false

    func update(owner: PlayerController, window: NSWindow?) {
        installCommandsIfNeeded()
        self.owner = owner
        ownerWindow = window
        guard let item = owner.mediaItem else { return }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.name,
            MPMediaItemPropertyPlaybackDuration: item.durationSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: owner.playbackTimeSnapshot(),
            MPNowPlayingInfoPropertyPlaybackRate: owner.isPlaying ? Double(owner.currentPlaybackSpeed) : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        center.playbackState = owner.isPlaying ? .playing : .paused
    }

    func clear(owner: PlayerController) {
        guard self.owner === owner else { return }
        self.owner = nil
        ownerWindow = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func installCommandsIfNeeded() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in NowPlayingCoordinator.shared.run { $0.togglePlayback() } }
            return .success
        }
        center.playCommand.addTarget { @Sendable _ in
            Task { @MainActor in NowPlayingCoordinator.shared.run { $0.play() } }
            return .success
        }
        center.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in NowPlayingCoordinator.shared.run { $0.pause() } }
            return .success
        }
        center.nextTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in NowPlayingCoordinator.shared.openAdjacent(next: true) }
            return .success
        }
        center.previousTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in NowPlayingCoordinator.shared.openAdjacent(next: false) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let time = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            Task { @MainActor in NowPlayingCoordinator.shared.run { $0.seekTo(time) } }
            return .success
        }
    }

    private func run(_ action: (PlayerController) -> Void) {
        guard let owner, owner.mediaItem != nil else { return }
        action(owner)
        update(owner: owner, window: ownerWindow)
    }

    private func openAdjacent(next: Bool) {
        guard let ownerWindow else { return }
        NotificationCenter.default.post(next ? .openNextFile(targetWindow: ownerWindow) : .openPreviousFile(targetWindow: ownerWindow))
    }
}
```
**`ContentView.swift` wiring.**
- Call `NowPlayingCoordinator.shared.update(owner: controller, window: nsWindow)` from:
  - `.onChange(of: controller.isPlaying)`
  - `.onChange(of: controller.mediaItem?.url)`
  - `.onChange(of: controller.currentPlaybackSpeed)`
  - `.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification))`, guarded by `(notification.object as? NSWindow) === nsWindow && isMediaLoaded`
- In `stopPlaybackForWindowClose`, call `NowPlayingCoordinator.shared.clear(owner: controller)`.
- `input-media-keys no` stays (`MPVPlayer.swift` L1263).

Commit: `Drive media keys and Now Playing from the active player`

### 3.11 Jump to Time (⌘J)

**`ContentView.swift`.**
- Add `@State private var showJumpToTime = false` and `@State private var jumpText = ""`.
- Add a `.jumpToTime` handler in `FileAndWindowHandlers`, guarded by `WindowManager.shared.isActiveWindow(nsWindow)`. It sets `jumpText = ""; showJumpToTime = true`.
- Add `isTextInputActive: showReviewNotes || showLoupeControls || showJumpToTime` (L144).
- Add the sheet:
```swift
        .sheet(isPresented: $showJumpToTime) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Jump to Time").font(.headline)
                TextField("h:mm:ss", text: $jumpText)
                    .frame(width: 200)
                    .onSubmit(jumpToTime)
                HStack {
                    Spacer()
                    Button("Cancel") { showJumpToTime = false }
                    Button("Go", action: jumpToTime)
                        .keyboardShortcut(.defaultAction)
                        .disabled(JumpToTimeParser.seconds(from: jumpText) == nil)
                }
            }
            .padding(20)
        }
```
and the action:
```swift
    private func jumpToTime() {
        defer { showJumpToTime = false }
        guard let seconds = JumpToTimeParser.seconds(from: jumpText) else { return }
        let target = min(seconds, controller.mediaItem?.durationSeconds ?? seconds)
        if compareSession.isActive {
            compareSession.seek(primary: controller, to: target)
        } else {
            controller.seekTo(target)
        }
    }
```
Commit: `Add VLC's Jump to Time`

**Part 3 checkpoint:** tests, Release install, then the manual VLC checklist:
- mouse: click, drag, double-click fill and restore, right-click on a background window, wheel;
- keys in both layouts, with typing in Review Notes and Jump to Time unaffected;
- menus following the key window across two windows;
- ⌘0–⌘3, aspect and crop resizing the window, Float on Top through fullscreen and minimize;
- resume in Ask, Always and Never;
- media keys and Control Center.

---

# Part 4 — IINA look (Mac)

**4.1 Window chrome.** In `WindowConfigurator.viewDidMoveToWindow`, set:
- `window.tabbingMode = .disallowed`
- `window.collectionBehavior = [.managed, .fullScreenPrimary]`
- `window.appearance = NSAppearance(named: .darkAqua)`

`applyTrafficLightAlpha` changes its duration from `0.2` to `IINAStyle.uiFade`.

**4.2 OSC surface (`FloatingOSCView` L37-54).** Remove `.background(cardBackground)`, the `clipShape`, the stroke overlay and `.shadow`. In their place:
```swift
                .modifier(OSCGlass(reduceTransparency: reduceTransparency))
                .environment(\.colorScheme, .dark)
```
with
```swift
private struct OSCGlass: ViewModifier {
    let reduceTransparency: Bool
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(RoundedRectangle(cornerRadius: IINAStyle.oscCornerRadius).fill(.black))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: IINAStyle.oscCornerRadius))
        }
    }
}
```
plus `@Environment(\.accessibilityReduceTransparency) private var reduceTransparency`. Delete `cardBackground`.

**4.3 Volume group (L126-145).**
- Add `.padding(.leading, IINAStyle.oscVolumeLeading)`.
- The slider gets `.frame(width: IINAStyle.oscVolumeSliderWidth, height: 22)` and `.padding(.trailing, IINAStyle.oscVolumeTrailing)`.
- The symbol is `IINAStyle.volumeSymbol(volume: controller.volume, isMuted: controller.isMuted)`. Delete `volumeSymbolName`.

**4.4 Speed labels.** Surround `transportGroup` with two `Text` slots built from `IINAStyle.speedLabels(Double(controller.currentPlaybackSpeed))`. Each slot gets:
- `.font(.system(size: IINAStyle.oscSpeedLabelFontSize))`
- `.foregroundStyle(.secondary)`
- `.frame(width: IINAStyle.oscSpeedLabelWidth)`

**4.5 Toolbar.**
- Fullscreen symbol: `arrow.up.backward.and.arrow.down.forward.rectangle`.
- Tooltips: "Playlist and chapters", "Toggle full screen".

**4.6 Volume slider cell (`UI/PlaybackVolumeSlider.swift`).**
- In `makeNSView`, before configuring, set `slider.cell = IINAVolumeSliderCell()`.
- Then set `maxValue = PlaybackVolume.maxPercent` and `controlSize = .mini`.
- Add:
```swift
final class IINAVolumeSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard maxValue > 0 else { return super.drawBar(inside: rect, flipped: flipped) }
        let knobX = round(knobRect(flipped: flipped).midX)
        let bar = NSBezierPath(roundedRect: rect, xRadius: IINAStyle.volumeBarRadius, yRadius: IINAStyle.volumeBarRadius)
        let notchX = round(rect.minX + rect.width * CGFloat(100 / maxValue))
        let notch = NSRect(x: notchX - IINAStyle.volumeNotchWidth / 2, y: rect.minY,
                           width: IINAStyle.volumeNotchWidth, height: rect.height)
        let sides: [(NSRect, CGFloat)] = [
            (NSRect(x: rect.minX, y: rect.minY, width: max(0, knobX - rect.minX), height: rect.height), 0.30),
            (NSRect(x: knobX, y: rect.minY, width: max(0, rect.maxX - knobX), height: rect.height), 0.10),
        ]
        for (side, alpha) in sides {
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: side)
            if maxValue > 100, side.intersects(notch) {
                clip.append(NSBezierPath(rect: notch).reversed)
                clip.windingRule = .evenOdd
            }
            clip.addClip()
            NSColor(white: 1, alpha: alpha).setFill()
            bar.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
```
The file comment should say there is no tick row and a 2 pt notch marks 100 %. `PlaybackVolumeTests` L33 still expects 0 tick marks.

**4.7 Play slider (`PlayerScrubber`).**
- Played part: `.white.opacity(IINAStyle.sliderPlayedAlpha)`. Unplayed part: `.white.opacity(IINAStyle.sliderUnplayedAlpha)`.
- Knob: `.white.opacity(isDragging ? IINAStyle.knobActiveAlpha : IINAStyle.knobIdleAlpha)`, with no shadow.
- Hover thumbnail: 120 pt wide, r4, with the time pill 5 pt below it.
- Chapter marks show only when `AppSettings.showTimelineDetails` is on.

**4.8 OSC position (fraction of the whole video, from the bottom, default 0.1).** Today the card's `GeometryReader` is a 120 pt strip, because `ContentView.overlayControls` applies `.frame(height: 120)` (L465). Re-base the position as follows.

`Models/OSCPosition.swift`. Replace `bottomMargin`, `default` and `origin`:
```swift
    /// IINA keeps the card at least this far below the top of the video.
    static let topMargin: CGFloat = 25

    /// `vertical` is the gap under the card as a fraction of the video height
    /// (IINA's default 0.1).
    static let `default` = OSCPosition(horizontal: 0.5, vertical: 0.1)

    func origin(in videoSize: CGSize, cardSize: CGSize) -> CGPoint {
        let freeWidth = max(0, videoSize.width - cardSize.width)
        let lowest = max(0, videoSize.height - cardSize.height)
        let highest = min(Self.topMargin, lowest)
        let y = lowest - CGFloat(vertical) * videoSize.height
        return CGPoint(x: freeWidth * CGFloat(horizontal), y: min(lowest, max(highest, y)))
    }

    /// The stored fraction for a card whose top edge was dragged to `y`.
    static func vertical(forProposedY y: Double, videoHeight: Double, cardHeight: Double) -> Double {
        guard videoHeight > 0 else { return Self.default.vertical }
        return clampFraction((videoHeight - cardHeight - y) / videoHeight)
    }
```
In `FloatingOSCView.dragGesture` (L238-242), replace the `freeHeight` block with:
```swift
                let proposedY = Double(dragOrigin.y + value.translation.height)
                positionVertical = OSCPosition.vertical(forProposedY: proposedY,
                                                        videoHeight: Double(videoSize.height),
                                                        cardHeight: Double(size.height))
```
`FloatingOSCView` gets `var onHoverChange: (Bool) -> Void = { _ in }` and applies `.onHover(perform: onHoverChange)` to `card`, before `.offset`.

`ContentView.overlayControls` (L451-472) becomes:
```swift
    private var overlayControls: some View {
        Group {
            if compareSession.isActive || compareSession.isLoading {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    inspectionControls
                }
                .onHover { overlayController.setControlsHovered($0) }
            } else {
                FloatingOSCView(
                    controller: controller,
                    onShowPlaylist: { showInspector.toggle() },
                    onShowSettings: { openSettings() },
                    onHoverChange: { overlayController.setControlsHovered($0) }
                )
                .transition(.opacity)
            }
        }
        .opacity(isMediaLoaded ? (showOverlay ? 1 : 0) : 1)
        .animation(.easeInOut(duration: 0.25), value: showOverlay)
    }
```
`Logic/SettingsMigration.swift`: set `currentVersion = 3` and add:
```swift
        case 2:
            // The control bar's vertical fraction is now measured up from the
            // bottom of the whole video; the old value used a 120 pt strip.
            defaults.removeObject(forKey: "controlBarPositionVertical")
```
**Tests.**
- `OSCPositionTests`:
  - default vertical is `0.1`;
  - `centred = OSCPosition(horizontal: 0.5, vertical: 0.1).origin(in: 1000×600, card: 460×67)` gives `(270, 473)`;
  - `(0, 0)` gives `(0, 533)`;
  - `(1, 1)` gives `x = 540`, and y is clamped to `25`;
  - a video smaller than the card gives `(0, 0)`;
  - `vertical(forProposedY: 473, videoHeight: 600, cardHeight: 67) == 0.1`.
- `PlayerChromeBehaviourTests` L150-155: expect `y = min(lowest, max(min(25, lowest), lowest - vertical * videoHeight))` with `lowest = videoHeight - cardHeight`.
- `SettingsMigrationTests`: version 2 removes `controlBarPositionVertical`.

**4.9 Auto-hide while paused.** In `Logic/PlayerOverlayController.swift` `scheduleHide` (L133-150), remove `isPlaying()` from both guards. Update `PlayerOverlayControllerTests` so paused playback hides too.

**4.10 Buffering overlay (`PlayerView.stateProgressOverlay`).** Use:
- `VStack(spacing: IINAStyle.bufferSpacing)`
- `.frame(width: IINAStyle.bufferWidth)`
- `.padding(.horizontal, IINAStyle.osdPaddingH).padding(.vertical, IINAStyle.osdPaddingV)`
- `.glassEffect(.regular, in: .rect(cornerRadius: IINAStyle.osdCornerRadius))`

**4.11 Sidebar (inspector).**
- Full height on the trailing edge, `width: IINAStyle.sidebarWidth`.
- `.transition(.move(edge: .trailing))` with `.animation(.easeIn(duration: IINAStyle.sidebarSlide))`. Under Reduce Motion, use opacity instead.

**4.12 Welcome window (`UI/InitialWindowController.swift`).**
- Add IINA's resume row, fed by `ResumePositionStore.standard.mostRecent()`.
- Replace the L11 comment "the Resume row is gone, the app stores no playback position" with "the Resume row reads ResumePositionStore".
- `DropZoneView`: remove the dashed border (L34-41).

**Part 4 checkpoint:** run `IINAParityChromeTests`, `OSCPositionTests`, `PlayerOverlayControllerTests` and `SettingsMigrationTests`, then compare visually side by side with `/Applications/IINA.app`.

---

# Part 5 — Engine (Mac and fork)

**5.1 Fork patch 0005 (display fps and resize; verified A1–A4).** This is the most important engine change: it turns display sync and interpolation on.

1. Copy `docs/research/2026-10-13-vlc-iina-parity/0005-moltenvk-display-fps-resize.patch` to `Sources/BuildScripts/patch/libmpv/` in `profanitys1/MPVKit`, branch `amp-master-vsync`.
2. Rebuild following `docs/superpowers/plans/2026-10-03-mpvkit-fork-rebuild.md`.
3. Push and release only after the user says yes, then bump the pinned revision on purpose (CLAUDE.md).

What the patch adds to `context_moltenvk.m`:
- `VOCTRL_GET_DISPLAY_FPS` from the bound CVDisplayLink (mirroring upstream `currentFps()`);
- `VO_EVENT_WIN_STATE` on a display or refresh change, plus the 0.1 s re-check;
- `VOCTRL_CHECK_EVENTS` comparing the layer's `drawableSize`, then `ra_vk_ctx_resize` + `VO_EVENT_RESIZE | VO_EVENT_EXPOSE`;
- a `vo_wakeup` from the display link thread when the size changes, so a paused player picks it up within one vsync.

Do not set `display-fps-override`. Keep `drawableSize == bounds × contentsScale`, set together with `metalLayer.frame` (`MPVVideoView.swift` L92-98, L204-218).

**Verify on the Mac:**
- `msg-level=vo=v` shows "Assuming … FPS for display sync."
- `display-sync-active` is true with a non-off profile.
- A paused programmatic resize redraws without a reload.
- Moving the window to another screen updates `display-fps`.

Then delete the reload workarounds:
- `MPVVideoView` `handleDrawableGrowth`/`shouldAutoReloadForLayoutJump`;
- the `requestReloadForSurfaceChange` observers for fullscreen enter/exit and end of live resize (L232-394);
- `WindowConfigurator.requestSurfaceReload`;
- the `.reloadPlayer` coalescer.

**Open risk, inherited from 0004:** Apple does not document whether `CVDisplayLinkStop` waits for a running callback.

**5.2 `GPUBudgetMonitor`.** Once 5.1 lands, `interpolating = renderProfile != .off` (`MPVPlayer.swift` L1505) becomes true in practice, and the budget uses the display rate. Re-check the `ProfilePicker` choices on a 120 Hz panel. Today mpv draws once per source frame, so every profile was measured cheaper than it will be.

**5.3 No cadence gate.** Verified A5: within mpv's 1 % factor-1 band, display-resample makes the cadence exact. Interpolation then adds at most one near-zero-weight mix pass per frame, and changes no pixels on clean timestamps. The planned `DisplayCadence` gate is dropped.

**5.4 FSRCNNX filter (A3).** Delete the `displayRefreshRate > 60` strip in `filterShadersForSource` (L1376-1396). `GPUBudgetMonitor` steps down if a profile does not fit.

**5.5 Redundant KrigBilateral (B5).**
- Remove `KrigBilateral.glsl` from `.upscaleLight`, `.compressed`, `.crisp` and `.compressedGrain`.
- Change `.efficient` to `["FSRCNNX_x2_8-0-4-1.glsl", "CfL_Prediction_Lite.glsl"]`.
- Update the shader counts in `RenderProfileTests`.

**5.6 Neural prescalers only when upscaling (B3).** In `ProfilePicker.pick`, when `drawablePixels < sourcePixels * 1.69`, skip `.upscaleLight`, `.crisp`, `.efficient`, `.sharpen` and `.upscaleStrong`. Test case: 3840×2160 at 1728×1117.

**5.7 Power and thermal (B2).**
- Add `ProfilePicker.pick(…, constrained: Bool)`.
- `constrained = ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState >= .serious`.
- When constrained, use budget fraction 0.45 and skip `.upscaleStrong`, `.compressed` and `.crisp`.
- Re-pick on `ProcessInfo.thermalStateDidChangeNotification` and `.NSProcessInfoPowerStateDidChange` with `queue: .main`.

**5.8 Bundled shaders as fallback (B6).** `ShaderLibrary.shaderPaths(named:)` falls back to `Bundle.main.resourceURL/Shaders/<name>`. Ship each shader with its licence file. Test with an empty shader directory.

**5.9 Frame step through mpv (B9).** `seekByFrames(±1)` on MPV maps to `frame-step` / `frame-back-step`. Add `MPVPlayer.frameBackStep()`.

**5.10 Loop respects trim (B10).** `MPVPlayer.setLooping` sets `ab-loop-a/b` to the trim in and out points when both exist, else `loop-file`.

**5.11 Audio device menu (B8).**
- Add `MPVPlayer.audioDevices() -> [(name: String, description: String)]`, read from `audio-device-list`, and `setAudioDevice(_:)`.
- Add an "Audio Device" submenu of Toggles in `AudioMenuContent`.

**5.12 Copy Diagnostics (Help menu).** Copies the macOS version, chip, `hwdec-current`, `display-fps`, `display-sync-active`, the active profile and the last 50 log lines (a ring buffer in the MPVPlayer log handler).

**Part 5 checkpoint:** full suite, Release install, then the playback matrix:
- 24, 25, 30 and 60 fps on 60 and 120 Hz;
- HDR;
- anamorphic DVD and rotated phone clips with aspect and crop;
- fill toggles while paused.

---

## Rejected or deferred (with reason)

**Gemini claims refuted by sources:**
- "setFrame(animate:) blocks per Apple docs": no such text exists.
- "VLC fires one wheel step then zeroes" and "sub-threshold must not re-arm": VLCVoutView.m L269-302 says otherwise.
- "display-fps works via patch 0004": verified A1 shows it does not.
- "@Observable has no focused path": `focusedSceneValue(_:)` for Observable exists on macOS 14+ (verified C2).
- "VLC has a Normal Speed menu item": VLC 3 has only a rate slider. `KEY_RATE_NORMAL` is NULL on macOS.
- "Esc should leave the screen fill": VLC swallows Esc when windowed (verified D5).

**Superseded by verified answers:**
- the cadence gate (A5);
- `video-dec-params/par` as the PAR source (B3);
- `contentAspectRatio = .zero` for unlocking (C4);
- Picker rows in menus (C2);
- `.floating` for Float on Top (D1 says `.statusBar`);
- a separate Fit-to-Screen size (D2 says it is the fill toggle).

**From earlier rounds:**
- The P0.1 mpv handle race and the P0.10 double-fire are false.
- `coreaudio-exclusive=yes`, `gpu-hwdec-interop=moltenvk`, `video-scale-x=-1` and `video-reversal` are invalid options.
- The 203-nit "double tone mapping" fix and the CATransaction "root cause" are wrong.

**Out of scope or user decisions:**
- subtitles;
- the IINA title bar and the 285×120 minimum;
- pinch, zoom Z, autoscale O, audio device ⇧A, loop ⇧L, random ⌘Z, the fullscreen controller I, PiP, music mode, video effects, Open URL;
- the `@Observable` migration and decomposing `PlayerController` (measure first).

**Still UNSETTLED, so each has a manual Mac acceptance check above:**
- C1: hit-testing through the SwiftUI overlay;
- C2: menu staleness;
- C4: the `.zero` versus increments crash, as an A/B check;
- C5: right-click key order;
- the ProMotion CVDisplayLink jitter (A1);
- whether `CVDisplayLinkStop` waits for a running callback (A2).

## Verification

- **Cloud:** the Part 1 files are checked with `swiftc -parse` if a Swift toolchain is present. That does not replace the Mac build.
- **Mac, after each Part:** `xcodebuild test` (full suite), `xcodebuild analyze`, a Release build installed to `/Applications/amp.app`, then that Part's manual checklist.
