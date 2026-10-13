# Task: VLC-style mouse handling on the video surface (AMP Phase 1)

Target: git worktree /Users/filip/src/amp/.claude/worktrees/antigravity-amp-vlc-parity-96dc20 (branch worktree-antigravity-amp-vlc-parity-96dc20). macOS SwiftUI/AppKit app "Aagedal Media Player". Read CLAUDE.md first.

## Change
Add ONE new file `Aagedal Media Player/UI/VideoMouseSurface.swift` with an `NSViewRepresentable` wrapping a transparent `NSView` subclass, and insert it into `PlayerView.body`'s ZStack (Aagedal Media Player/UI/PlayerView.swift) directly AFTER the video branch (the `if let player ... else if controller.useMPV ...` block) and BEFORE `AudioOnlyPresentationView`/`overlayIndicators`, full-size with `.ignoresSafeArea()`. Only insert it when `compareSession == nil` (Compare Mode owns drags). Do NOT add gesture recognizers to MPVViewController or AVPlayerView. The surface view, not SwiftUI gestures, owns all mouse input; SwiftUI controls layered above it in ContentView keep their own clicks.

Behaviour (copied from VLC macOS source, modules/gui/macosx VLCVoutView.m):
1. Single left click: does NOT pause. mouseDown with clickCount == 1 calls `window.performDrag(with: event)` so dragging on video moves the window. Disabled (no drag) when the window is in native fullscreen.
2. Double left click (event.clickCount == 2 in mouseDown): toggle "fill screen, stay windowed" — NOT native fullscreen:
   - If window.styleMask contains .fullScreen: call window.toggleFullScreen(nil) (exit).
   - Else if window frame is ~equal (within 2pt) to window.screen.visibleFrame: restore the saved pre-fill frame (animate: true). If none saved, set a frame centered on visibleFrame at 60% of its width with height from the current video aspect (content aspect = frame aspect is fine).
   - Else: save current frame, then `window.setFrame(screen.visibleFrame, display: true, animate: true)`.
   - Put the save/restore logic in a small `@MainActor enum WindowFillToggle` in the same file; store the saved frame per window (e.g. a `[ObjectIdentifier: NSRect]` static dict, cleaned when restored). Pure function `nonisolated static func isFilling(frame: NSRect, visible: NSRect) -> Bool` for testability.
3. Right click (`menu(for:)` override) returns an NSMenu, items in this order (VLC voutMenu): Play/Pause, separator, Previous, Next, separator, Volume Up, Volume Down, Mute, separator, Fill Screen (same as double-click), Fullscreen, separator, Snapshot. Each item first makes the window key (`window?.makeKeyAndOrderFront(nil)`) then posts the existing typed command via `NotificationCenter.default.post(_ command: AppCommand)` from Logic/AppCommand.swift: .togglePlayback, .openPreviousFile, .openNextFile, .adjustVolume(by: 5), .adjustVolume(by: -5), .toggleMute, .toggleFullscreen, .captureScreenshot. (Stop is omitted: AMP has no stop concept.)
4. Scroll wheel (`scrollWheel(with:)`), VLC accumulator algorithm:
   - Ignore events whose phase/momentumPhase is .ended/.cancelled with zero delta. Ignore momentum events (momentumPhase != []) entirely, so a trackpad flick does not keep changing volume.
   - deltaY = event.scrollingDeltaY, deltaX = event.scrollingDeltaX. If event.hasPreciseScrollingDeltas, scale both by 0.1 (trackpad pixels to line units). If event.isDirectionInvertedFromDevice, negate both (so "natural" scrolling behaves like VLC).
   - Axis lock: whichever axis has larger |delta| on the first event of a gesture wins; ignore the other axis until 0.4 s pass with no scroll events.
   - Accumulate per axis. Vertical: each time |accY| >= 1.0, fire one step and subtract 1.0 (keep sign). Horizontal threshold 0.8. A non-precise mouse wheel notch with |delta| < threshold still fires exactly one step.
   - Vertical step up => post .adjustVolume(by: 5); down => .adjustVolume(by: -5).
   - Horizontal step: right => .seekBySeconds(3), left => .seekBySeconds(-3).
   - Put the accumulator in a pure struct `ScrollStepAccumulator` (nonisolated, no AppKit types in its API: input (dx, dy, precise, inverted, timestamp), output an enum of steps) so it is unit-testable.
5. Pinch (`magnify(with:)`): accumulate event.magnification per gesture; > +0.3 => if not filling, do the fill toggle; < -0.3 => if filling or fullscreen, toggle back. Fire once per gesture (reset on .ended).
6. `acceptsFirstMouse(for:)` returns true. `mouseDownCanMoveWindow` false (we call performDrag ourselves). Do not override hitTest; the view must not steal keyDown (do not become first responder: `acceptsFirstResponder` false).

## Constraints
- Swift 6 strict concurrency, macOS 26 target. SPDX header + copyright header like other files (copy from PlayerView.swift top). Use `// MARK: -` sections. OSLog subsystem com.aagedal.MediaPlayer if logging.
- Do not touch MPVVideoView.swift, MPVPlayer.swift, RenderProfile.swift, WindowConfigurator.swift, or any render/quality code.
- Check the Xcode project uses file-system synchronized groups (new files auto-included). If not, add the file to the target in project.pbxproj.
- Keyboard handling, overlay controls, loupe hover (ContentView onContinuousHover), and window traffic-light hover must keep working.
- No new dependencies. No placeholder/TODO code.

## Ownership
May create: UI/VideoMouseSurface.swift, "Aagedal Media Player Tests/VideoMouseSurfaceTests.swift". May edit: UI/PlayerView.swift (insertion only). Nothing else.

## Acceptance
1. Tests in VideoMouseSurfaceTests.swift for ScrollStepAccumulator (mouse notch fires one step; trackpad small deltas accumulate; axis lock; inverted direction; momentum ignored) and WindowFillToggle.isFilling.
2. Build passes:
   xcodebuild -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build
3. Tests pass:
   xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" -only-testing "Aagedal Media Player Tests/VideoMouseSurfaceTests" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
4. Commit on the current branch with a clean message (no attribution lines): `git commit -m "Add VLC-style mouse handling on the video surface"`.
Report in worker_done: files changed, test output summary, any deviation from this spec and why. If unsure about anything, ask the coordinator with the preamble's ask command instead of guessing.
