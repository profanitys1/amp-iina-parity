# Fullscreen Surface Reload Fix and Rendering Test Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the already-applied fix that stops the video from rendering at the wrong size after a fullscreen switch made during playback, lock it with a regression test, and close out the remaining 4:2:2 and transition test items.

**Architecture:** `MPVViewController` (in `MPVVideoView.swift`) posts `.reloadPlayer` after fullscreen enter/exit and after a live resize, because mpv keeps a stale destination rectangle when the Metal drawable grows. Commit `d5aa44f` skipped that reload while playing. On-device testing on 2026-10-01 showed that assumption is wrong, so the skip has been removed (uncommitted). `PlayerController.reloadPreservingPlaybackState()` already resumes playback at the same position after the reload.

**Tech Stack:** Swift 6, SwiftUI + AppKit, libmpv via MPVKit (gpu-next / Vulkan / MoltenVK on a `CAMetalLayer`), XCTest, Xcode project with file-system synchronized groups (new test files are picked up automatically).

## Global Constraints

- Repo: `/Users/filip/src/amp`, branch `main` (80+ commits ahead of `upstream/main`). Do not push.
- Build: `xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build` (see `CLAUDE.md`).
- Tests: same flags with `xcodebuild test`, narrowed with `-only-testing:"Aagedal Media Player Tests/<Class>/<method>"`. The full suite is slow; run targeted tests.
- Commit messages: plain `git commit -m "message"`, no attribution or co-author lines.
- Do NOT stage or commit these pre-existing, user-owned working-tree changes: `Aagedal Media Player Tests/CompareLiveBackendTests.swift` (modified) and `LICENSE` (deleted). Stage files by explicit path only.
- Visual testing must use the synthetic clip `/Users/filip/Downloads/Movies/chroma422-test.mov`. Do not open, play or inspect `/Users/filip/Downloads/Movies/gaia.mov` or other personal files in amp's playlist.
- Never change macOS System Settings yourself (for example Reduce Transparency). Ask the user to toggle them.

---

## What was done on 2026-10-01 (context, no action needed)

**Test 4 — 4:2:2 chroma rendering.**
- Generated a test clip in the same format as the user's footage: ProRes HQ, `yuv422p10le`, 1920×1080, 24 fps, 30 s. Top half SMPTE HD bars, bottom half ffmpeg `testsrc2`:
  ```bash
  ffmpeg -f lavfi -i smptehdbars=size=1920x540:rate=24:duration=30 -f lavfi -i testsrc2=size=1920x540:rate=24:duration=30 -filter_complex "[0][1]vstack" -c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le /Users/filip/Downloads/Movies/chroma422-test.mov
  ```
- Compared Settings → Rendering → Profile "Faithful" against "Chroma reconstruction" (CfL_Prediction) with full-resolution `screencapture` and ImageMagick pixel diffs.
- Result: Chroma reconstruction works on 4:2:2, with no fringing, halos, colour shifts, banding or checkerboard artifacts. It is sharper than Faithful: the 2–3 px dark fringe at red/green edges and the purple band at blue/magenta edges shrink to about 1 px. Overall PSNR between the two is 40 dB.
- The user's Profile was already "Chroma reconstruction". It was restored after testing.
- Evidence: `/Users/filip/Downloads/Movies/amp-test-evidence/rg_pair.png`, `bm_pair.png` (left = Faithful, right = Chroma reconstruction).

**Test 5 — transitions.**
- Playlist (Liquid Glass) panel: appears within 0.15 s, no visible animation, dark translucent.
- Tier badge: shows "RAVU zoom" only when Profile = Faithful and Enhance = on. With any manual profile, no badge appears in window, fullscreen, paused or playing.
- **Bug found:** a fullscreen switch made while playing left the picture at the previous size. Entering showed a window-sized picture in the top-left corner with the rest black. Leaving showed a magnified crop of the top-left of the frame. Both persisted 5–7+ s of playback. Paused switches were fine.
  - Evidence: `/Users/filip/Downloads/Movies/amp-test-evidence/bug-enter-fullscreen-stuck-small.jpg`, `bug-exit-fullscreen-cropped.jpg`.
- **Root cause:** the early return `if player.isFileLoaded, player.isPlaying { return }` in `MPVViewController.requestReloadForSurfaceChange(reason:)`, added by commit `d5aa44f` ("Keep playing through a fullscreen transition"). Its premise ("the next presented frame rebuilds the swapchain") does not hold on this machine.
- **Fix applied (uncommitted):** removed that early return; see `git diff -- "Aagedal Media Player/Logic/MPV/MPVVideoView.swift"`.
- **Verified** with a Debug build: enter and exit fullscreen while playing (playlist open, on-screen button) both render the full frame, and playback continues without jumping back.
- **Tests run:** `PlayerReloadTests`, `MPVMetalLayerTests`, `PlayerChromeBehaviourTests`. One failure, `PlayerChromeBehaviourTests.testOpeningAFileWithASubtitleTrackSelectsItAtRuntime`, also fails with the fix reverted, so it is pre-existing (Task 4).

**Not done:**
- Reduce Transparency check (needs the user to toggle the system setting).
- Corner-drag resize (the screen-control tool refused the drag; Window → Zoom resized cleanly).
- `/Applications/amp.app` is still the old build (1.6.1, build 163).

---

### Task 1: Regression test for the fullscreen reload, then commit the fix

**Files:**
- Already modified: `Aagedal Media Player/Logic/MPV/MPVVideoView.swift` (`requestReloadForSurfaceChange(reason:)`, around lines 355-368)
- Create: `Aagedal Media Player Tests/FullscreenSurfaceReloadTests.swift`

**Interfaces:**
- Consumes: `MPVViewController(player:managesSurfaceReloads:surfaceSize:)`, `MPVPlayer()`, `MPVPlayer.isFileLoaded` / `isPlaying` (settable `@Published var`), `MPVPlayer.destroy()`, `NotificationCenter.default.appCommandPublisher`, `notification.appCommand`, `AppCommand.reloadPlayer`.
- Produces: `FullscreenSurfaceReloadTests` (test-only).

- [ ] **Step 1: Write the test**

`Aagedal Media Player Tests/FullscreenSurfaceReloadTests.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import XCTest
@testable import Aagedal_Media_Player

@MainActor
final class FullscreenSurfaceReloadTests: XCTestCase {
    /// A fullscreen transition made while playing must still recreate mpv:
    /// on device, the stale destination rectangle survived seconds of playback
    /// (window-sized picture after entering, cropped zoom after exiting).
    func testFullscreenTransitionsReloadWhilePlaying() async throws {
        let player = MPVPlayer()
        defer { player.destroy() }
        let controller = MPVViewController(
            player: player, managesSurfaceReloads: true,
            surfaceSize: CGSize(width: 320, height: 180)
        )
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        defer {
            window.contentViewController = nil
            window.close()
        }
        // viewDidLayout installs the window observers.
        controller.viewDidLayout()

        var reloadCount = 0
        let observation = NotificationCenter.default.appCommandPublisher.sink { notification in
            if let command = notification.appCommand, case .reloadPlayer = command {
                reloadCount += 1
            }
        }
        defer { observation.cancel() }

        player.isFileLoaded = true
        player.isPlaying = true

        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        XCTAssertEqual(reloadCount, 1, "Entering fullscreen while playing must reload mpv.")

        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        XCTAssertEqual(reloadCount, 2, "Exiting fullscreen while playing must reload mpv.")

        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
        XCTAssertEqual(reloadCount, 3, "Ending a live resize while playing must reload mpv.")
    }
}
```

The observers use `queue: .main` and the test runs on the main actor, so `post` delivers synchronously. If the counts arrive late, wait on them with a short loop (see `waitUntil` in `PlayerChromeBehaviourTests.swift:230`) instead of asserting immediately.

- [ ] **Step 2: Prove the test catches the bug**

Temporarily restore the old code, run the test, then put the fix back:

```bash
cd /Users/filip/src/amp
cp "Aagedal Media Player/Logic/MPV/MPVVideoView.swift" /tmp/MPVVideoView.fixed.swift
git checkout -- "Aagedal Media Player/Logic/MPV/MPVVideoView.swift"
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/FullscreenSurfaceReloadTests" 2>&1 | rg 'TEST (SUCCEEDED|FAILED)|error:'
cp /tmp/MPVVideoView.fixed.swift "Aagedal Media Player/Logic/MPV/MPVVideoView.swift"
```

Expected: `** TEST FAILED **`, with `reloadCount` at 0 because the playing skip swallowed every reload.

- [ ] **Step 3: Run the test with the fix in place**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/FullscreenSurfaceReloadTests" -only-testing:"Aagedal Media Player Tests/PlayerReloadTests" -only-testing:"Aagedal Media Player Tests/MPVMetalLayerTests" 2>&1 | rg 'TEST (SUCCEEDED|FAILED)|error:|failed'
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Confirm the fix diff is exactly this**

`git diff -- "Aagedal Media Player/Logic/MPV/MPVVideoView.swift"` should show only this replacement inside `requestReloadForSurfaceChange(reason:)`:

```swift
        // Reload while playing too: on-device testing showed the stale dst rect
        // surviving many seconds of playback after a fullscreen enter or exit
        // (window-sized picture in the corner, or a cropped zoom). The reload
        // resumes playback at the same position.
        scalingLogger.info("requestReloadForSurfaceChange: \(reason) — posting .reloadPlayer to recreate mpv at current surface size")
        NotificationCenter.default.post(.reloadPlayer)
```

The removed block was the `if player.isFileLoaded, player.isPlaying { … return }` early return and its comment.

- [ ] **Step 5: Commit (explicit paths only)**

```bash
git add "Aagedal Media Player/Logic/MPV/MPVVideoView.swift" "Aagedal Media Player Tests/FullscreenSurfaceReloadTests.swift"
git status --short   # CompareLiveBackendTests.swift and LICENSE must still be unstaged
git commit -m "Reload mpv after fullscreen and resize transitions while playing"
```

---

### Task 2: Manual on-device verification of the remaining transition items

**Files:** none (verification only). Record results in the final report to the user.

- [ ] **Step 1: Build and launch the Debug app with the test clip**

```bash
cd /Users/filip/src/amp
xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -derivedDataPath /tmp/amp-dd CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build 2>&1 | rg 'BUILD (SUCCEEDED|FAILED)|error:'
osascript -e 'quit app id "com.aagedal.MediaPlayer"'
open -a "/tmp/amp-dd/Build/Products/Debug/Aagedal Media Player.app" /Users/filip/Downloads/Movies/chroma422-test.mov
```

Expected: `** BUILD SUCCEEDED **` and a window titled `chroma422-test`.

- [ ] **Step 2: Fullscreen while playing, both entry paths**

Press play. Then toggle fullscreen with each control: the on-screen button (bottom-right of the control bar), View → Enter/Exit Full Screen, and Playback → Toggle Fullscreen. Repeat once with the Playlist panel open.

Expected: the full frame fills the screen with letterboxing, and after exit the window shows the whole frame. The burned-in timecode (top-left of the lower half) keeps advancing and does not jump back.

- [ ] **Step 3: Corner-drag resize while playing**

Drag the window's bottom-right corner to roughly double the size, then release. If the automation tool refuses the drag, ask the user to do it.

Expected: after release (the `didEndLiveResize` reload), the whole frame shows at the new size, not a top-left crop or a small corner picture.

- [ ] **Step 4: Reduce Transparency (user action)**

Ask the user to turn on System Settings → Accessibility → Display → Reduce Transparency. Then open the Playlist panel over the colour bars.

Expected: the panel background is opaque, with no blur and no bars visible through it. Commit `ecd731a` added this support. Ask the user to turn the setting back off afterwards.

- [ ] **Step 5: Report**

Tell the user pass/fail for Steps 2–4, with a screenshot of any failure saved under `/Users/filip/Downloads/Movies/amp-test-evidence/`.

---

### Task 3: Tier badge behaviour with manual profiles (decision first)

**Files (only if the user picks "show it"):** start from the tier badge view and its call site. Find them with:

```bash
rg -n 'RenderTierBadge' "Aagedal Media Player"
```

- [ ] **Step 1: Ask the user**

Use one question with these options:
1. "Keep as is": the badge only reflects automatic Enhance tiers. No code change.
2. "Show the manual profile": with a manual profile selected, the badge shows the profile's display name (for example "Chroma reconstruction").

- [ ] **Step 2: If option 2, plan it separately**

Write a separate short plan once `RenderTierBadge` and its data source have been read. Do not guess the type names here. Stop this task if option 1 is chosen.

---

### Task 4: Investigate the pre-existing subtitle test failure

**Files:** `Aagedal Media Player Tests/PlayerChromeBehaviourTests.swift` (`testOpeningAFileWithASubtitleTrackSelectsItAtRuntime`) and whatever it exercises.

- [ ] **Step 1: Reproduce in isolation**

```bash
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/PlayerChromeBehaviourTests/testOpeningAFileWithASubtitleTrackSelectsItAtRuntime" 2>&1 | rg 'XCTAssert|error|failed|TEST (SUCCEEDED|FAILED)'
```

Expected today: fails after about 30 s, which looks like a `waitUntil` timeout.

- [ ] **Step 2: Find when it broke**

```bash
git log --oneline -15 -- "Aagedal Media Player Tests/PlayerChromeBehaviourTests.swift"
```

Bisect with `git bisect` across recent commits, running only this test. Use the superpowers:systematic-debugging skill. Report the root cause to the user before changing any code. Subtitle features are out of scope per `docs/superpowers/plans/README.md`, so a fix may be test-only.

---

### Task 5: Optional — real-footage check of Chroma reconstruction on 4:2:2

- [ ] **Step 1:** Ask the user for a non-personal 4:2:2 clip with fine coloured detail (for example coloured text or graphics), or generate one with ffmpeg `drawtext` over `smptehdbars`.
- [ ] **Step 2:** Repeat the Faithful vs Chroma reconstruction pixel comparison from "What was done", using `screencapture -x` and `magick compare -metric PSNR`.
- [ ] **Step 3:** If clean, ask the user whether Chroma reconstruction should become the default for 4:2:2 sources. Do not change defaults without a yes.

---

## Suggested skills for the next agent

- `superpowers:executing-plans` or `superpowers:subagent-driven-development`: run this plan.
- `superpowers:test-driven-development`: Task 1.
- `superpowers:systematic-debugging`: Task 4.
- `superpowers:verification-before-completion`: before reporting any task as done.
- `anthropic-skills:computer-use` / `visual-qa`: Task 2 on-device checks.
- `caveman:caveman-commit`: commit messages, if available in your harness.

---

## Status after execution (2026-10-01)

| Task | Result |
|------|--------|
| 1 | Done. `69406f7` — fix plus `FullscreenSurfaceReloadTests`. The test fails on the old code and passes on the new. |
| 2 | Partly done. Fullscreen while playing via the on-screen button passes on device. Menu and ⌘F paths could not be driven by automation; the unit test covers their shared notifications. Corner-drag resize (automation drag refused) and Reduce Transparency are still waiting on the user. |
| 3 | Done (user chose "show the manual profile"). `e3dd3d4` — `RenderTierBadge` shows `renderProfile.displayName` when a manual profile is set. `MPVPlayer.renderProfile` is now `@Published`. Verified on device ("Sharpened upscale"). |
| 4 | Done. `beb034f` — the test inherited the developer's own `autoSelectSubtitles = 0` preference from `UserDefaults.standard`. The test now pins it to `true` and restores the original value afterwards. |
| 5 | Done (user chose "auto for 4:2:2"). `e3dd3d4` — new `RenderTier.chroma` rung between Faithful and Sharpened, and CfL is appended to every enhancing tier. CfL only qualifies the chroma rung; `requiredShaderFileNames` keeps a missing CfL from disabling the luma tiers. CfL skips itself on 4:4:4/RGB sources, but the badge would still say "Chroma reconstruction" there (ponytail comment in `RenderTier.isEligible`). Verified on device: window size with Faithful + Enhance shows the "Chroma reconstruction" badge. Coloured-text evidence: `~/Downloads/Movies/amp-test-evidence/text-*.png` (top = Faithful/RAVU, bottom = Chroma reconstruction). |

**Remaining:**
- User checks: corner-drag resize while playing, and Reduce Transparency on the playlist panel.
- Not yet measured: GPU cost of CfL added to the RAVU/ArtCNN/FSRCNNX tiers (the timings in the `RenderTier` doc comment predate it). Fullscreen playback stayed smooth on the 1080p test clip.
- `/Applications/amp.app` is still the old 1.6.1 (163). Release with `scripts/release.sh` when ready.
- Note for comparisons: "Faithful" with Enhance on is not shader-free. It runs the automatic tier (RAVU zoom in fullscreen).

### Follow-up (same day)

- **Corner-drag resize while playing: pass.** The window grew from 711×400 to about 900×505 pt and the full frame rescaled after release, with playback continuing.
- **CfL cost recorded** in the `RenderTier` doc comment (`46b4751`):
  - about +0.1 ms per frame with RAVU on a 1080p source;
  - +3.4 ms per frame with ArtCNN on a 720p source;
  - about +2 ms per frame with FSRCNNX on a 720p source.
- **Local install.** Release build installed at `/Applications/amp.app`. The previous app is backed up in `~/Library/Application Support/amp-app-backups/Aagedal Media Player-20261001-114350.app`. The new ad-hoc signature triggers macOS's "access files in your Downloads folder" prompt, which the user must answer.
- **Still with the user:** the Reduce Transparency check. Agents must not change System Settings.
- **Reduce Transparency: failed, then fixed** (`0f7012e`).
  - The inspector panel used `Color.black.opacity(0.85)`, so the video showed through.
  - `RenderTierBadge` keyed its opacity on Reduce Motion instead of Reduce Transparency.
  - Both are opaque now. Verified on device with the setting on, and reinstalled to `/Applications/amp.app`.
