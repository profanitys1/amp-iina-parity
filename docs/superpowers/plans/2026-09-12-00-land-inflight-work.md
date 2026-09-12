# Plan 0: Land the in-flight work

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Commit the uncommitted working tree as five reviewable commits so every later plan starts clean.

**Architecture:** No new code. The tree already builds and the app runs. This plan only separates the existing diff into commits that can be reviewed and reverted independently, and adds the two tests that the changes should have carried.

**Tech Stack:** Swift 6, SwiftUI + AppKit, XCTest, Xcode 26 command-line builds.

## Global Constraints

- Deployment target macOS 15.0. Swift 6 strict concurrency is on: types touched from `awakeFromNib` or from an mpv event thread need explicit `nonisolated`.
- Build and test with signing disabled, or the build fails on this machine with "No signing certificate":
  `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""`
- Metal API Validation must stay OFF in the scheme's Run diagnostics (MoltenVK race, KhronosGroup/MoltenVK#2226).
- Every source file carries `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Logging uses `OSLog` with subsystem `com.aagedal.MediaPlayer`.
- Commit messages: the message only. No `Generated with`, no `Co-Authored-By`.
- Work on branch `iina-parity`.

---

## File Structure

Already-written files this plan commits:

| File | Responsibility |
|------|----------------|
| `Aagedal Media Player/Logic/SleepPreventer.swift` | Holds a `ProcessInfo` activity while any window plays |
| `Aagedal Media Player/UI/InitialWindowController.swift` | Welcome window, ported from IINA |
| `Aagedal Media Player/UI/WelcomeWindowPresenter.swift` | Lets non-AppDelegate code show/hide the welcome window |
| `Aagedal Media Player/Base.lproj/InitialWindowController.xib` | IINA's nib, retargeted |
| `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` | Clock coalescing, `setString`, display-fps, audio/decoder options |
| `Aagedal Media Player/Logic/MPV/MPVVideoView.swift` | Skips reload while playing; screen-change observers |
| `Aagedal Media Player/Logic/PlayerController.swift` | `reloadPreservingPlaybackState()`, sleep-prevention hook |
| `Aagedal Media Player/Logic/PlayerOverlayController.swift` | Cursor hiding on the idle timer |

Deleted: `Aagedal Media Player/UI/CursorHideZone.swift`.

---

### Task 1: Commit the fullscreen-pause fix

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVVideoView.swift` (the `!player.isPlaying` guard in `requestReloadForSurfaceChange`)
- Modify: `Aagedal Media Player/Logic/PlayerController.swift` (`reloadPreservingPlaybackState`, `surfaceReloadResumeTask`)
- Modify: `Aagedal Media Player/Logic/CompareSessionController.swift` (line ~1790, the non-compare branch)
- Test: `Aagedal Media Player Tests/PlayerReloadTests.swift`

**Interfaces:**
- Produces: `PlayerController.reloadPreservingPlaybackState()` — no arguments, no return. Later plans do not call it.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/PlayerReloadTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class PlayerReloadTests: XCTestCase {
    /// A reload with no media must not leave a resume task behind that could
    /// start playback on the next file.
    func testReloadWithoutMediaIsInert() {
        let controller = PlayerController()
        XCTAssertNil(controller.mediaItem)
        controller.reloadPreservingPlaybackState()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.playbackPhase, .idle)
    }
}
```

- [ ] **Step 2: Run it and watch it pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/PlayerReloadTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 1 test, with 0 failures`. The implementation is already present, so this is a characterization test, not a red-then-green cycle.

- [ ] **Step 3: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVVideoView.swift" \
        "Aagedal Media Player/Logic/PlayerController.swift" \
        "Aagedal Media Player/Logic/CompareSessionController.swift" \
        "Aagedal Media Player Tests/PlayerReloadTests.swift"
git commit -m "Keep playing through a fullscreen transition

The stale dst rect is a paused-stream bug: the surface grows while nothing
is presented, so MoltenVK never reports the swapchain out of date. While
playing, the next presented frame rebuilds it, so skip the mpv context
recreate entirely. Any reload the app triggers itself now restores the
play state and position it interrupted."
```

---

### Task 2: Commit the playback-clock coalescing

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (`publishTimePos`, `flushWithheldTimePos`, `resetTimePosCoalescing`, the `timePos` and `pause` event cases)
- Test: `Aagedal Media Player Tests/MPVTimePosCoalescingTests.swift`

**Interfaces:**
- Produces: `MPVPlayer.resetTimePosCoalescing()` — `nonisolated`, no arguments. Plan 5 reads `MPVPlayer.timePos`; it does not call this.

- [ ] **Step 1: Write the test**

The coalescing state is private and lives on the mpv queue, so test the policy
constant and the published default rather than reaching inside.

Create `Aagedal Media Player Tests/MPVTimePosCoalescingTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class MPVTimePosCoalescingTests: XCTestCase {
    /// Matches the interval IINA uses for its sync timer (AppData.swift:14).
    func testCoalescingIntervalMatchesReference() {
        XCTAssertEqual(MPVPlayer.timePosPublishInterval, 0.1, accuracy: 0.0001)
    }

    /// Resetting must be safe before any mpv context exists.
    func testResetBeforeContextDoesNotCrash() {
        let player = MPVPlayer()
        player.resetTimePosCoalescing()
    }
}
```

- [ ] **Step 2: Make the interval visible to tests**

In `Aagedal Media Player/Logic/MPV/MPVPlayer.swift`, change the constant from
`private static let` to `static let`:

```swift
    static let timePosPublishInterval: TimeInterval = 0.1
```

- [ ] **Step 3: Run the tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/MPVTimePosCoalescingTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" \
        "Aagedal Media Player Tests/MPVTimePosCoalescingTests.swift"
git commit -m "Coalesce the playback clock while playing

mpv reports time-pos once per decoded frame, and every one of them drove a
SwiftUI invalidation for a readout that only shows tenths. While playing,
publish at most every 0.1s; while paused, publish every sample so frame
stepping and scrubbing stay exact. Pausing flushes whatever the window
withheld, and seeking lets the next sample through immediately."
```

---

### Task 3: Commit the cursor change

**Files:**
- Delete: `Aagedal Media Player/UI/CursorHideZone.swift`
- Modify: `Aagedal Media Player/Logic/PlayerOverlayController.swift`
- Modify: `Aagedal Media Player/ContentView.swift` (zone removed from the layer stack)
- Modify: `Aagedal Media Player/UI/SettingsView.swift` (toggle removed)
- Modify: `Aagedal Media Player/Logic/AppSettings.swift` (`showCursorHideHint` removed)
- Modify: `Aagedal Media Player Tests/PlayerOverlayControllerTests.swift`

**Interfaces:**
- Produces: `PlayerOverlayController.hideCursorUntilMouseMoves()` — `static`, no arguments. Nothing outside the class calls it.
- Removed: `PlayerOverlayController.isRightEdgeHovered` and `setRightEdgeHovered(_:isPlaying:isControlInteractionActive:)`. Any code still referencing them will not compile.

- [ ] **Step 1: Run the existing overlay tests**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/PlayerOverlayControllerTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 6 tests, with 0 failures`. If a test still references
`setRightEdgeHovered`, delete that test — the behaviour is gone on purpose.

- [ ] **Step 2: Confirm nothing still references the removed zone**

```bash
rg -n 'CursorHideZone|CursorHideNSView|isRightEdgeHovered|showCursorHideHint|rightEdgeWidth' --glob '*.swift' .
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add -A "Aagedal Media Player/UI/CursorHideZone.swift" \
           "Aagedal Media Player/Logic/PlayerOverlayController.swift" \
           "Aagedal Media Player/ContentView.swift" \
           "Aagedal Media Player/UI/SettingsView.swift" \
           "Aagedal Media Player/Logic/AppSettings.swift" \
           "Aagedal Media Player Tests/PlayerOverlayControllerTests.swift"
git commit -m "Hide the cursor over the whole picture, not in a corner

The right-edge strip was a bespoke affordance that swallowed the pointer in
one hidden region. Hide the cursor over the entire video once the controls
auto-hide, and bring it back on the next mouse move, which is what a player
is expected to do. Re-arm on mouse-down as well: since Big Sur a click
without movement makes the cursor reappear (Apple FB11963121)."
```

---

### Task 4: Commit sleep prevention, display refresh rate and the mpv option groups

**Files:**
- Create: `Aagedal Media Player/Logic/SleepPreventer.swift`
- Modify: `Aagedal Media Player/Logic/PlayerController.swift` (the `isPlaying` `didSet`)
- Modify: `Aagedal Media Player/ContentView.swift` (`SleepPreventer.shared.forget` on window close)
- Modify: `Aagedal Media Player/Logic/AppSettings.swift` (the new settings)
- Modify: `Aagedal Media Player/Logic/MPV/MPVPlayer.swift` (`applyAudioAndDecoderOptions`, `setString`, `applyDisplayRefreshRate`)
- Modify: `Aagedal Media Player/Logic/MPV/MPVVideoView.swift` (screen observers)
- Test: `Aagedal Media Player Tests/SleepPreventerTests.swift`

**Interfaces:**
- Produces, used by Plan 1 (which gives these settings their UI):
  `AppSettings.preventDisplaySleep` (Bool, true), `quitWhenNoOpenedWindow` (Bool, true),
  `audioPassthroughCodecs` (String, ""), `replayGainMode` (String, "no"),
  `replayGainPreamp` (Double, 0), `replayGainClip` (Bool, true),
  `replayGainFallback` (Double, 0), `gaplessAudio` (String, "weak"),
  `forceAVFoundationOutput` (Bool, false), `videoDecodeThreads` (Int, 0),
  `audioDecodeThreads` (Int, 0), `preferredAudioLanguages` (String, ""),
  `demuxerMaxBytes` (String, ""), `demuxerReadaheadSeconds` (Double, 0).
- Produces, used by Plan 2: `MPVPlayer.setString(_ name: String, _ value: String)` (internal),
  and `MPVPlayer.applyDisplayRefreshRate(_ fps: Double)`.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/SleepPreventerTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class SleepPreventerTests: XCTestCase {
    private final class Owner {}

    /// Forgetting an owner that never registered must be harmless, so a window
    /// that closes before playing cannot unbalance the assertion.
    func testForgetUnknownOwnerIsHarmless() {
        let owner = Owner()
        SleepPreventer.shared.forget(owner)
    }

    /// Registering then forgetting must leave no assertion behind.
    func testRegisterThenForgetReleases() {
        let owner = Owner()
        SleepPreventer.shared.update(for: owner, isPlaying: true, isAudioOnly: false)
        SleepPreventer.shared.forget(owner)
        XCTAssertFalse(SleepPreventer.shared.isHoldingAssertion)
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/SleepPreventerTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: compile error, `value of type 'SleepPreventer' has no member 'isHoldingAssertion'`.

- [ ] **Step 3: Expose the state the test needs**

In `Aagedal Media Player/Logic/SleepPreventer.swift`, add below `private var allowsScreenSaver`:

```swift
    /// Whether an activity is currently outstanding. `beginActivity` reports no
    /// status, so this is the only way to observe it short of `pmset`.
    var isHoldingAssertion: Bool { activityToken != nil }
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/SleepPreventerTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 2 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add "Aagedal Media Player/Logic/SleepPreventer.swift" \
        "Aagedal Media Player/Logic/PlayerController.swift" \
        "Aagedal Media Player/ContentView.swift" \
        "Aagedal Media Player/Logic/AppSettings.swift" \
        "Aagedal Media Player/Logic/MPV/MPVPlayer.swift" \
        "Aagedal Media Player/Logic/MPV/MPVVideoView.swift" \
        "Aagedal Media Player Tests/SleepPreventerTests.swift"
git commit -m "Keep the display awake, and tell mpv about the display

Video playback holds an idleDisplaySleepDisabled activity; audio-only
playback takes the weaker system-sleep assertion and lets the screen saver
run. mpv cannot query display refresh on macOS and otherwise assumes 60Hz,
so push the real rate from NSScreen on attach and whenever the window
changes screen. Adds the audio, decoder-threading and demuxer options that
were previously fixed at mpv's defaults, each inert until set."
```

---

### Task 5: Commit the welcome window

**Files:**
- Create: `Aagedal Media Player/Base.lproj/InitialWindowController.xib`
- Create: `Aagedal Media Player/UI/InitialWindowController.swift`
- Create: `Aagedal Media Player/UI/WelcomeWindowPresenter.swift`
- Modify: `Aagedal Media Player/Aagedal_Media_PlayerApp.swift`
- Modify: `Aagedal Media Player/Logic/WindowManager.swift`
- Modify: `Aagedal Media Player/Logic/PlayerWindowCoordinator.swift`
- Modify: `Aagedal Media Player/Logic/AppVersion.swift` (`AppIdentity`)
- Modify: `Aagedal Media Player/UI/DropZoneView.swift`
- Test: `Aagedal Media Player Tests/AppIdentityTests.swift`

**Interfaces:**
- Produces: `AppIdentity.name`, `.shortVersion`, `.build`, `.prereleaseChannel -> String?`,
  `.versionDescription` — all `static`, on a `nonisolated enum`.
- Produces: `WindowManager.openInNewPlayerWindow(_ url: URL)` and
  `WindowManager.welcomeWindowOwnsLaunch: Bool`.
- Produces: `WelcomeWindowPresenter.shared.present` / `.dismiss`, both `(() -> Void)?`.

- [ ] **Step 1: Write the failing test**

Create `Aagedal Media Player Tests/AppIdentityTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class AppIdentityTests: XCTestCase {
    func testReleaseVersionHasNoChannel() {
        XCTAssertNil(AppIdentity.prereleaseChannel(for: "1.6.1"))
    }

    func testBetaSuffixIsRecognised() {
        XCTAssertEqual(AppIdentity.prereleaseChannel(for: "1.5.0-beta1"), "beta")
    }

    func testBuildMetadataSuffixIsRecognised() {
        XCTAssertEqual(AppIdentity.prereleaseChannel(for: "1.5.0+g1a2b3c"), "g")
    }

    func testLeadingVeeIsIgnored() {
        XCTAssertNil(AppIdentity.prereleaseChannel(for: "v2.0.0"))
    }
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/AppIdentityTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "error:|Executed"
```

Expected: compile error, no member `prereleaseChannel(for:)`.

- [ ] **Step 3: Make the channel parser testable**

In `Aagedal Media Player/Logic/AppVersion.swift`, replace the computed
`prereleaseChannel` with a pure function plus a thin property:

```swift
    /// "beta", "alpha", "rc"… when the version carries a prerelease suffix.
    static func prereleaseChannel(for version: String) -> String? {
        let normalized = AppVersion.normalized(version).lowercased()
        guard let separator = normalized.firstIndex(where: { $0 == "-" || $0 == "+" }) else {
            return nil
        }
        let suffix = normalized[normalized.index(after: separator)...]
        let channel = suffix.prefix { $0.isLetter }
        return channel.isEmpty ? "beta" : String(channel)
    }

    static var prereleaseChannel: String? { prereleaseChannel(for: shortVersion) }
```

- [ ] **Step 4: Run the tests and watch them pass**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing:"Aagedal Media Player Tests/AppIdentityTests" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed|error:"
```

Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Verify the window by launching it**

```bash
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build 2>&1 | grep -E "error:|BUILD"
open -a "$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 5 -name 'Aagedal Media Player.app' -path '*Debug*' | head -1)"
sleep 4
osascript -e 'tell application "System Events" to tell process "Aagedal Media Player" to get {name, size} of every window'
```

Expected: exactly one window, size `640, 400`. Two windows means the empty
player window is no longer being rejected — check `welcomeWindowOwnsLaunch`
in `PlayerWindowCoordinator.accept`.

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Base.lproj" \
        "Aagedal Media Player/UI/InitialWindowController.swift" \
        "Aagedal Media Player/UI/WelcomeWindowPresenter.swift" \
        "Aagedal Media Player/Aagedal_Media_PlayerApp.swift" \
        "Aagedal Media Player/Logic/WindowManager.swift" \
        "Aagedal Media Player/Logic/PlayerWindowCoordinator.swift" \
        "Aagedal Media Player/Logic/AppVersion.swift" \
        "Aagedal Media Player/UI/DropZoneView.swift" \
        "Aagedal Media Player Tests/AppIdentityTests.swift"
git commit -m "Show a welcome window at launch, ported from IINA

Uses IINA's own nib and controller so the metrics, colours and interaction
behaviour match exactly rather than being approximated: 640x400, a 180pt
branding column under a gradient, the material covering only the right side,
28pt rows, and the recents table with its hover and selection highlights.
The file is routed through WindowManager instead of a PlayerCore; the Open
URL and Resume rows are dropped, having no equivalent here.

SwiftUI's WindowGroup creates a window at launch whether or not there is
anything to play, so that empty window is rejected while the welcome window
stands in as the launch UI."
```

---

### Task 6: Verify the whole suite and push

- [ ] **Step 1: Run every test**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E "Executed [0-9]+ tests|error:|TEST"
```

Expected: `TEST SUCCEEDED`, zero failures.

- [ ] **Step 2: Confirm the tree is clean apart from CLAUDE.md**

```bash
git status --short
```

Expected: only ` M CLAUDE.md` remains, if you have not decided what to do with
that edit. Commit or revert it deliberately; do not leave it dangling.

- [ ] **Step 3: Push**

```bash
git push origin iina-parity
```
