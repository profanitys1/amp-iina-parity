# Video Quality Optimization & VLC-Like Playback Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Elevate AMP's video rendering quality with low-overhead libplacebo scalers and deliver VLC-like player behavior (double-click fullscreen, border-to-border window maximization on start, single-click play/pause, and scroll gestures).

**Architecture:** Configure mpv's `gpu-next` rendering backend with high-efficiency mathematical scalers (EWA-Lanczos, anti-ringing, 1-pass deband, BT.2390 tone mapping) to maximize picture fidelity at minimal GPU cost. In the AppKit UI layer, update `WindowConfigurator` to maximize the window frame to the display's visible bounds on every media start, and install non-conflicting AppKit gesture recognizers on the video canvas for instant fullscreen toggle and play/pause.

**Tech Stack:** Swift 6.0, AppKit, SwiftUI, libmpv (`gpu-next` / MoltenVK / Metal), XCTest.

**Spec:** [`docs/superpowers/specs/2026-10-13-video-quality-and-vlc-experience-design.md`](file:///Users/filip/src/amp/docs/superpowers/specs/2026-10-13-video-quality-and-vlc-experience-design.md)

## Global Constraints

- Deployment target is macOS 26.0+ on Apple Silicon.
- All source files must include the SPDX license header: `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Zero-copy hardware decoding must remain `videotoolbox` on `CAMetalLayer`.
- Metal API Validation must remain OFF in the scheme run diagnostics (MoltenVK race condition workaround).
- Build command signing overrides required on Mac without development certificate: `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=`.
- No new external package dependencies may be introduced.

## Review Focus

1. **Double-click does not pause before entering fullscreen:** `singleClickRecognizer.require(toFail: doubleClickRecognizer)` must be verified so rapid double-clicks never stutter playback.
2. **Subsequent media loads in the same window must maximize:** Opening a new video file via playlist or drag-and-drop must resize the window border-to-border, not just the first video.
3. **Overlay controls do not trigger video gestures:** Clicks on the scrubber, volume slider, or playback buttons must not bubble down to trigger fullscreen or pause.
4. **Debanding does not wash out high-contrast textures:** Debanding threshold and iterations must be conservative (`iterations=1, threshold=35`) to eliminate gradient steps without degrading text or fine details.
5. **Multi-window independence:** Fullscreen toggles and window maximizing must only affect the target window, never altering sibling windows in multi-window mode.

---

### Task 1: Video Quality & Scaler Option Optimizations in MPV Backend

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/RenderProfile.swift`
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`
- Test: `Aagedal Media Player Tests/RenderProfileTests.swift`

**Interfaces:**
- Consumes: `RenderProfile`, `MPVPlayer`, `AppSettings`
- Produces: `RenderProfile.scaleOptions` returning `scale=ewa_lanczos` and `scale-antiring=0.7`, `RenderProfile.enablesDeband` returning true for profiles handling compressed/web video, and `MPVPlayer.setupMPV` applying `sigmoid-upscaling=yes`, `correct-downscaling=yes`, `cscale-antiring=0.7`, `tone-mapping=bt.2390`.

- [ ] **Step 1: Write the failing test**

In `Aagedal Media Player Tests/RenderProfileTests.swift`, update and add assertions verifying the improved default scalers and deband flags:

```swift
    func testDefaultScalerUsesEWALanczosWithAntiRinging() {
        for profile in RenderProfile.allCases {
            let options = profile.scaleOptions
            XCTAssertTrue(options.keys.contains("scale"), "every profile must define scale")
            if profile == .sharpen {
                XCTAssertEqual(options["scale"], "ewa_lanczossharp")
                XCTAssertEqual(options["scaler-resizes-only"], "no")
            } else {
                XCTAssertEqual(options["scale"], "ewa_lanczos", "Default scaler should use ewa_lanczos for \(profile.rawValue)")
                XCTAssertEqual(options["scale-antiring"], "0.7", "Default scaler should enable anti-ringing for \(profile.rawValue)")
                XCTAssertEqual(options["scaler-resizes-only"], "yes", "\(profile.rawValue)")
            }
        }
    }

    func testDebandIsEnabledForCompressedAndRestoreProfiles() {
        XCTAssertTrue(RenderProfile.restore.enablesDeband)
        XCTAssertTrue(RenderProfile.compressed.enablesDeband)
        XCTAssertTrue(RenderProfile.compressedGrain.enablesDeband)
        XCTAssertFalse(RenderProfile.off.enablesDeband, "Faithful inspection must remain untouched")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/RenderProfileTests/testDefaultScalerUsesEWALanczosWithAntiRinging" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: FAIL due to `scale` returning `"lanczos"` and missing `"scale-antiring"`.

- [ ] **Step 3: Implement scaler and deband options**

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`:
1. Update `scaleOptions`:
   ```swift
   var scaleOptions: [String: String] {
       self == .sharpen
           ? ["scale": "ewa_lanczossharp", "scaler-resizes-only": "no"]
           : ["scale": "ewa_lanczos", "scale-antiring": "0.7", "scaler-resizes-only": "yes"]
   }
   ```
2. Update `enablesDeband`:
   ```swift
   var enablesDeband: Bool {
       switch self {
       case .restore, .compressed, .compressedGrain:
           return true
       default:
           return false
       }
   }
   ```

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`:
1. In `applyScalerOptions()`:
   ```swift
   private func applyScalerOptions() {
       checkError(mpv_set_option_string(mpv, "dscale", "mitchell"), context: "dscale")
       checkError(mpv_set_option_string(mpv, "correct-downscaling", "yes"), context: "correct-downscaling")
       checkError(mpv_set_option_string(mpv, "cscale", "spline36"), context: "cscale")
       checkError(mpv_set_option_string(mpv, "cscale-antiring", "0.7"), context: "cscale-antiring")
       checkError(mpv_set_option_string(mpv, "sigmoid-upscaling", "yes"), context: "sigmoid-upscaling")
   }
   ```
2. In `setupMPV()`:
   Configure low-overhead deband parameters and tone-mapping curve:
   ```swift
   checkError(mpv_set_option_string(mpv, "deband-iterations", "1"), context: "deband-iterations")
   checkError(mpv_set_option_string(mpv, "deband-threshold", "35"), context: "deband-threshold")
   checkError(mpv_set_option_string(mpv, "deband-range", "16"), context: "deband-range")
   checkError(mpv_set_option_string(mpv, "deband-grain", "5"), context: "deband-grain")
   checkError(mpv_set_option_string(mpv, "tone-mapping", "bt.2390"), context: "tone-mapping")
   ```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/RenderProfileTests" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/RenderProfile.swift" "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" "Aagedal Media Player Tests/RenderProfileTests.swift"
git commit -m "feat(mpv): optimize video scaling, deband, and HDR tone mapping"
```

---

### Task 2: Window Sizing — Always Maximize on Media Start

**Files:**
- Modify: `Aagedal Media Player/UI/WindowConfigurator.swift`
- Modify: `Aagedal Media Player/Logic/PlayerWindowCoordinator.swift`
- Test: `Aagedal Media Player Tests/WindowConfiguratorTests.swift`

**Interfaces:**
- Consumes: `WindowConfigurator`, `PlayerWindowCoordinator`, `AppSettings.openMaximized`
- Produces: `WindowConfigurator.shouldMaximize(hasMaximizedForCurrentMedia:isFullScreen:openMaximized:)` and `WindowConfigurator.resetMediaMaximizationLatch()` ensuring every new media load maximizes the window border-to-border.

- [ ] **Step 1: Write the failing test**

In `Aagedal Media Player Tests/WindowConfiguratorTests.swift`, update `testTheScreenFillHappensOncePerWindowAndNeverInFullScreen` to test per-media fill logic:

```swift
    func testTheScreenFillHappensForEveryNewMediaLoadWhenOpenMaximized() {
        XCTAssertTrue(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForCurrentMedia: false, isFullScreen: false, openMaximized: true),
            "A newly loaded media item fills the screen.")
        XCTAssertFalse(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForCurrentMedia: true, isFullScreen: false, openMaximized: true),
            "After initial sizing of the current media, subsequent layout passes do not re-maximize.")
        XCTAssertFalse(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForCurrentMedia: false, isFullScreen: true, openMaximized: true),
            "Full screen already owns the window frame.")
        XCTAssertFalse(
            WindowConfigurator.shouldMaximize(
                hasMaximizedForCurrentMedia: false, isFullScreen: false, openMaximized: false),
            "When openMaximized is false, screen fill does not trigger.")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/WindowConfiguratorTests/testTheScreenFillHappensForEveryNewMediaLoadWhenOpenMaximized" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: FAIL due to missing `shouldMaximize(hasMaximizedForCurrentMedia:...)` method signature.

- [ ] **Step 3: Implement per-media maximization in WindowConfigurator**

In `Aagedal Media Player/UI/WindowConfigurator.swift`:
1. Rename and refine `shouldMaximize`:
   ```swift
   nonisolated static func shouldMaximize(
       hasMaximizedForCurrentMedia: Bool,
       isFullScreen: Bool,
       openMaximized: Bool
   ) -> Bool {
       openMaximized && !hasMaximizedForCurrentMedia && !isFullScreen
   }
   ```
2. In `WindowConfigurator.Coordinator`:
   Track current media URL / token:
   ```swift
   var currentMediaURL: URL?
   var hasMaximizedForCurrentMedia = false
   ```
   When `applyInitialSize` is called, check if the media has changed or needs maximization:
   ```swift
   func resetMediaMaximization() {
       hasMaximizedForCurrentMedia = false
   }
   ```
   In `applyInitialSize`:
   ```swift
   if WindowConfigurator.shouldMaximize(
       hasMaximizedForCurrentMedia: hasMaximizedForCurrentMedia,
       isFullScreen: isFullScreen,
       openMaximized: openMaximized
   ) {
       hasMaximizedForCurrentMedia = true
       maximize(window)
       return
   }
   ```
3. In `WindowConfigurator.maximize(_ window: NSWindow)`:
   Ensure `window.setFrame(screen.visibleFrame, display: true, animate: false)` cleanly spans top to bottom of the screen.

In `Aagedal Media Player/Logic/PlayerWindowCoordinator.swift`:
Ensure media load notifications / transitions signal `WindowConfigurator` that a new media file has begun loading.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/WindowConfiguratorTests" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/UI/WindowConfigurator.swift" "Aagedal Media Player/Logic/PlayerWindowCoordinator.swift" "Aagedal Media Player Tests/WindowConfiguratorTests.swift"
git commit -m "feat(window): ensure window starts maximized border-to-border on every media load"
```

---

### Task 3: VLC Gesture System — Double-Click Fullscreen & Single-Click Play/Pause

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVVideoView.swift`
- Modify: `Aagedal Media Player/UI/PlayerView.swift`
- Create: `Aagedal Media Player Tests/VideoGestureTests.swift`

**Interfaces:**
- Consumes: `MPVViewController`, `PlayerController.toggleFullscreen()`, `PlayerController.togglePause()`
- Produces: Double-click gesture handler toggling fullscreen, single-click gesture handler toggling play/pause with `require(toFail: doubleClickRecognizer)`.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/VideoGestureTests.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
@testable import Aagedal_Media_Player
import XCTest
import AppKit

@MainActor
final class VideoGestureTests: XCTestCase {
    func testGestureRecognizersConfiguredOnMPVViewController() {
        let player = MPVPlayer()
        let vc = MPVViewController(player: player, managesSurfaceReloads: false, surfaceSize: CGSize(width: 1920, height: 1080))
        _ = vc.view // trigger loadView and viewDidLoad

        let recognizers = vc.view.gestureRecognizers
        XCTAssertFalse(recognizers.isEmpty, "MPVViewController view should have gesture recognizers attached")

        let clickRecognizers = recognizers.compactMap { $0 as? NSClickGestureRecognizer }
        XCTAssertEqual(clickRecognizers.count, 2, "Should have single-click and double-click recognizers")

        let doubleClick = clickRecognizers.first { $0.numberOfClicksRequired == 2 }
        let singleClick = clickRecognizers.first { $0.numberOfClicksRequired == 1 }

        XCTAssertNotNil(doubleClick, "Double-click recognizer must exist")
        XCTAssertNotNil(singleClick, "Single-click recognizer must exist")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/VideoGestureTests" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: FAIL with missing file or zero gesture recognizers found on `vc.view`.

- [ ] **Step 3: Implement gesture recognizers in MPVViewController**

In `Aagedal Media Player/Logic/MPV/MPVVideoView.swift`:
1. Add gesture action methods to `MPVViewController`:
   ```swift
   @objc private func handleVideoDoubleClick(_ sender: NSClickGestureRecognizer) {
       guard sender.state == .ended else { return }
       guard let window = view.window else { return }
       window.toggleFullScreen(nil)
   }

   @objc private func handleVideoSingleClick(_ sender: NSClickGestureRecognizer) {
       guard sender.state == .ended else { return }
       player.togglePause()
   }
   ```
2. In `MPVViewController.viewDidLoad()`:
   Attach recognizers to `self.view`:
   ```swift
   let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleVideoDoubleClick(_:)))
   doubleClick.numberOfClicksRequired = 2
   doubleClick.delaysPrimaryMouseButtonEvents = false

   let singleClick = NSClickGestureRecognizer(target: self, action: #selector(handleVideoSingleClick(_:)))
   singleClick.numberOfClicksRequired = 1
   singleClick.delaysPrimaryMouseButtonEvents = false
   singleClick.require(toFail: doubleClick)

   view.addGestureRecognizer(doubleClick)
   view.addGestureRecognizer(singleClick)
   ```
3. In `Aagedal Media Player/UI/PlayerView.swift`:
   Ensure overlay controls (`FloatingOSCView`, `ControlsView`) receive clicks first and do not trigger underlying video canvas gestures.

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/VideoGestureTests" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVVideoView.swift" "Aagedal Media Player/UI/PlayerView.swift" "Aagedal Media Player Tests/VideoGestureTests.swift"
git commit -m "feat(input): add double-click fullscreen and single-click play/pause gestures"
```

---

### Task 4: VLC Trackpad / Scroll Wheel Volume & Seek Interaction

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVVideoView.swift`
- Test: `Aagedal Media Player Tests/VideoGestureTests.swift`

**Interfaces:**
- Consumes: `NSEvent.scrollWheel`, `player.volume`, `player.seek(by:)`
- Produces: `MPVViewController.scrollWheel(with:)` adjusting volume on vertical delta and scrubbing on horizontal delta.

- [ ] **Step 1: Write the failing test**

In `Aagedal Media Player Tests/VideoGestureTests.swift`, add test for volume calculation from scroll delta:

```swift
    func testVolumeAdjustmentFromScrollDelta() {
        let initialVolume: Double = 50.0
        let deltaY: CGFloat = 5.0
        let newVolume = PlaybackVolume.adjustedVolume(current: initialVolume, deltaY: deltaY)
        XCTAssertGreaterThan(newVolume, initialVolume, "Positive vertical scroll should increase volume")
        XCTAssertLessThanOrEqual(newVolume, 100.0, "Volume must clamp to 100")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/VideoGestureTests/testVolumeAdjustmentFromScrollDelta" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: FAIL with `adjustedVolume` not defined on `PlaybackVolume`.

- [ ] **Step 3: Implement scrollWheel in MPVViewController & PlaybackVolume**

1. In `Aagedal Media Player/Logic/PlaybackVolume.swift`:
   Add static helper:
   ```swift
   static func adjustedVolume(current: Double, deltaY: CGFloat) -> Double {
       let step = Double(deltaY) * 0.5
       return min(100.0, max(0.0, current + step))
   }
   ```
2. In `Aagedal Media Player/Logic/MPV/MPVVideoView.swift`:
   In `MPVViewController`:
   ```swift
   override func scrollWheel(with event: NSEvent) {
       if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
           let newVol = PlaybackVolume.adjustedVolume(current: player.volume, deltaY: event.scrollingDeltaY)
           player.volume = newVol
       } else if abs(event.scrollingDeltaX) > 2.0 {
           let seekSeconds = event.scrollingDeltaX > 0 ? 5.0 : -5.0
           player.seek(by: seekSeconds)
       } else {
           super.scrollWheel(with: event)
       }
   }
   ```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/VideoGestureTests" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/PlaybackVolume.swift" "Aagedal Media Player/Logic/MPV/MPVVideoView.swift" "Aagedal Media Player Tests/VideoGestureTests.swift"
git commit -m "feat(input): add trackpad scroll wheel volume and seek controls"
```

---

### Task 5: End-to-End Build, Test Suite, and Static Analysis Verification

**Files:**
- None (Build & Verification verification task)

- [ ] **Step 1: Run complete test suite**

Run:
```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: All tests pass with zero failures.

- [ ] **Step 2: Run Xcode static analysis**

Run:
```bash
xcodebuild analyze -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```
Expected: Analyze succeeds with zero warnings/issues.

- [ ] **Step 3: Verification commit**

```bash
git status
```
Confirm working tree is clean.
