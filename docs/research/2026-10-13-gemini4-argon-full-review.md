Here is the complete principal engineering and product design review of **Aagedal Media Player (AMP)**, covering every question in detail, followed by all bugs/races/leaks spotted in the current codebase, and a ranked Top-30 action list.

---

# Part 0: Bugs, Races, Leaks & Harmful Settings Found in Source

Before answering sections A–H, here is the inventory of defects found in the current source code:

1. **Data Race on `mpv` handle across MainActor and `com.aagedal.mpv` queue (`MPVPlayer.swift:662-732`)**:
   `getDouble`, `setDouble`, `getInt`, `setInt`, `getString`, `setString`, `setFlag`, and `command` are called on `@MainActor`, while `readEvents()`, `screenshotRawLocked()`, and `readBudgetSample()` run on `self.queue`. Although libmpv has an internal lock for most API calls, `destroy()` (`MPVPlayer.swift:127`) sets `self.mpv = nil` inside `queue.sync`, whereas `getInt` (`MPVPlayer.swift:694`) is `nonisolated` and reads `self.mpv` without locking `queue`. Worse, `readEvents` calls `self.getInt(MPVProperty.videoParamsDw)` on `queue` (`MPVPlayer.swift:464`) while `@MainActor` callers call `getString`/`setString`.
2. **Audio Track Selection Never Populates `subtitleTrackOptions` on MPV (`TrackSelectionController.swift:71-78`, `PlayerController.swift:415-425`)**:
   In `PlayerController.setupMPV`, `MPV_EVENT_FILE_LOADED` calls `refreshAudioTrackOptions(playerItem: nil)`. While `refreshAudioTrackOptions` does call `publishMPVTrackOptions` (which populates both audio and subtitle arrays), `PlayerController.addSubtitle(url:)` (`PlayerController.swift:679`) calls `mpvPlayer?.addSubtitle(url: url)` (`sub-add`) and **never refreshes `trackSelection`**, so newly added external subtitles never appear in the subtitle menu (`FloatingOSCView.swift:175` / `ControlsView.swift:684`)! Furthermore, `buildMPVSubtitleTrackOptions()` (`PlayerController.swift:665`) is dead code—never called anywhere.
3. **Compare Mode Secondary Player Leaks `SleepPreventer` Entry on Replace (`CompareSessionController.swift:320`)**:
   When `loadSecondary` tears down a previous `secondaryController`, `secondaryController.isPlaying` becomes `false` (updating `SleepPreventer`), *unless* `secondaryController` was deallocated or replaced without `SleepPreventer.shared.forget(secondaryController)`. In `ContentView.stopPlaybackForWindowClose` (`ContentView.swift:369`), `SleepPreventer.shared.forget(controller)` is called only for `primary`, never for `compareSession.secondaryController`.
4. **Destructive Full-Player Reload on Every Window Resize, Fullscreen Transition, and Initial Layout Jump (`MPVVideoView.swift:204-216, 286-346`)**:
   `MPVViewController` posts `.reloadPlayer` on `didEnterFullScreen`, `didExitFullScreen`, `didEndLiveResize`, and `shouldAutoReloadForLayoutJump` (≥1.5×). `.reloadPlayer` calls `preparePlayback()`, which calls `mpv_terminate_destroy`, creates a brand new `mpv_create()`, re-opens the demuxer, re-initializes VideoToolbox, recompiles all GLSL shaders, and seeks to the previous timestamp! This causes a black flash, audio pop, and 200–600 ms stall on every window resize or fullscreen toggle. (Root cause and 5-line fix in **C1**).
5. **Dual Local `NSEvent` Key Monitors Installed Simultaneously (`MPVVideoView.swift:380`, `PlayerView.swift:479`, `PlayerOverlayController.swift:44`)**:
   Every window installs its own `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` inside `MPVVideoView.Coordinator` (or `PlayerContainerView.Coordinator`) AND another in `PlayerOverlayController`. When Compare Mode is active with two MPV views, **two** `MPVVideoView.Coordinator` key monitors exist in the same window. Only `acceptsKeyboardInput = false` on secondary prevents double-firing.
6. **`FrameAnalyzer` Spawns Up to 9 Sequential `ffmpeg` Subprocesses Per File Open (`FrameAnalyzer.swift:92-101`)**:
   When `renderProfile == .automatic` (the default!), `MPVPlayer` calls `FrameAnalyzer.shared.analyze` on every `MPV_EVENT_FILE_LOADED`. That spawns 1 `ffmpeg` subprocess for `topazTag` plus 8 sequential `ffmpeg -ss ... -frames:v 1` subprocesses across the file duration. On a network share (SMB/NFS) or large 4K file, 9 `ffmpeg` invocations thrash disk/network I/O right as playback starts.
7. **`MPVPlayer.setRenderProfile` Writes to `UserDefaults` on Broadcast (`MPVPlayer.swift:604`, `ContentViewCommandHandlers.swift:127`)**:
   When `.setRenderProfile` is broadcast, every window's `MPVPlayer` writes to `UserDefaults`. Worse, `EnhancementSuggestionView` ("Enhance Now" button, `PlayerView.swift:126`) posts `.setRenderProfile(.compressed)`, which **permanently overwrites the user's global `AppSettings.renderProfile` default** in `UserDefaults` instead of applying it to the current file/session.
8. **`HDRFrameData` Custom `Equatable` Violates Reflexivity (`ScopeComputer.swift:24`)**:
   `static func == (lhs: HDRFrameData, rhs: HDRFrameData) -> Bool { false }`. Violating `a == a` breaks Swift standard library collection guarantees and SwiftUI attribute graph diffing if `HDRFrameData` is ever compared directly. (`ScopeFrameSample` works around this by comparing `sequence`, making the broken `==` on `HDRFrameData` unnecessary).
9. **`ScopeWindowController` and `AudioWaveformWindowController` `deinit` Comment Lies About Observer Cleanup (`ScopeWindowController.swift:150`, `AudioWaveformWindowController.swift:192`)**:
   If the controller is released without `close()` being called, `closeObserver` and `panelObserver` are leaked. However, since `NotificationCenter.addObserver(forName:object:queue:using:)` returns an token that does *not* auto-unregister in older patterns unless removed, they should be cleaned up in `deinit` just like `MPVViewController` does.
10. **MoltenVK + `video-sync=display-resample` + `interpolation=yes` Forced on All Non-Faithful Profiles (`RenderProfile.swift:128-133`)**:
    Enabling `video-sync=display-resample` and `interpolation=yes` globally whenever `renderProfile != .off` resamples audio continuously and blends frames with `tscale=oversample` even on 120 Hz ProMotion Macs where 24p divides 120 Hz evenly (5:5 pulldown), wasting GPU/battery and altering audio pitch/timing when it isn't needed.

---

# Section A: VLC GUI Parity (Implementation Details)

## A1. Mouse on Video Surface (`VideoSurfaceInteractionView`)

### Behavior & Event Mechanics
- **`performDrag(with:)` after 3pt threshold vs `mouseDown`**:
  Never call `window.performDrag(with: event)` immediately inside `mouseDown(with:)`. `performDrag(with:)` enters AppKit's modal window-move tracking loop and **swallows the `mouseUp` event** and breaks `event.clickCount == 2` detection on the second click if the user's finger moves even sub-pixel on a Magic Mouse/Trackpad.
  Instead, record `mouseDownPoint = event.locationInWindow` and `mouseDownEvent = event` in `mouseDown(with:)`. In `mouseDragged(with:)`, compute `hypot( loc.x - mouseDownPoint.x, loc.y - mouseDownPoint.y )`. Once `>= 3.0`, set `didDrag = true` and call `window?.performDrag(with: mouseDownEvent ?? event)`.
- **`clickCount == 2` reliability**:
  In `mouseDown(with:)`, if `event.clickCount == 2` (and `!didDrag`), fire the double-click action (`onDoubleClick()`). Why `mouseDown` and not `mouseUp`? VLC macOS (`VLCVideoWindowCommon.m`) triggers fullscreen on `mouseDown` when `event.clickCount == 2`. Because single-click on the video surface does **nothing** (except start a window drag if dragged), you do **not** need to delay single-click by `NSEvent.doubleClickInterval`!
- **Does it block `.onContinuousHover` / `.onHover` or overlay clicks?**
  - **Overlay clicks**: In a SwiftUI `ZStack`, views declared *later* have higher Z-index and are hit-tested *first* by AppKit/SwiftUI's `NSHostingView`. If `VideoSurfaceInteractionView` is placed **below** `inspectorPanel`, `overlayControls`, `audioWaveformOverlay`, and `ComparePlayerView`'s wipe handle, clicks on those SwiftUI controls will be caught by SwiftUI first and will **never** reach `VideoSurfaceInteractionView`.
  - **Compare Mode Wipe Handle**: When `compareSession.isActive && compareSession.viewMode.isWipe`, the 24pt wipe drag strip in `ComparePlayerView.swift:267` is inside `inspectionCanvas`. Therefore, `VideoSurfaceInteractionView` must be placed inside `ComparePlayerView` **between** `comparisonSurfaces` and `wipeInteractionOverlay`, OR `VideoSurfaceInteractionView` must pass through hits within the wipe handle rect. Placing it inside `ComparePlayerView` right above `comparisonSurfaces` (and below `wipeInteractionOverlay`) is cleanest!
  - **Hover**: AppKit dispatches `mouseMoved` / `NSTrackingArea` events to all tracking areas whose rect contains the cursor regardless of `hitTest` for mouse-down, **provided** you do not consume `mouseMoved`. Thus `ContentView`'s `.onHover` and `inspectionCanvas`'s `.onContinuousHover` (which drives `InspectionLoupeOverlay`) continue to work unimpeded.
- **`hitTest` / `acceptsFirstMouse`**:
  Override `acceptsFirstMouse(for event: NSEvent?) -> Bool { true }` so clicking or dragging an inactive player window works on the first click (matching VLC).

### Concrete Swift Implementation

Create `Aagedal Media Player/UI/VideoSurfaceInteractionView.swift`:

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

struct VideoSurfaceInteractionView: NSViewRepresentable {
    var onDoubleClick: () -> Void
    var onScroll: (NSEvent) -> Void
    var menuProvider: () -> NSMenu?

    func makeNSView(context: Context) -> InteractionNSView {
        let view = InteractionNSView()
        view.onDoubleClick = onDoubleClick
        view.onScroll = onScroll
        view.menuProvider = menuProvider
        return view
    }

    func updateNSView(_ nsView: InteractionNSView, context: Context) {
        nsView.onDoubleClick = onDoubleClick
        nsView.onScroll = onScroll
        nsView.menuProvider = menuProvider
    }

    final class InteractionNSView: NSView {
        var onDoubleClick: (() -> Void)?
        var onScroll: ((NSEvent) -> Void)?
        var menuProvider: (() -> NSMenu?)?

        private var mouseDownEvent: NSEvent?
        private var mouseDownPoint: NSPoint = .zero
        private var didDrag = false
        private var pinchTriggered = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var isOpaque: Bool { false }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            mouseDownPoint = event.locationInWindow
            didDrag = false
            if event.clickCount == 2 {
                mouseDownEvent = nil
                onDoubleClick?()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didDrag, let startEvent = mouseDownEvent else { return }
            let cur = event.locationInWindow
            if hypot(cur.x - mouseDownPoint.x, cur.y - mouseDownPoint.y) >= 3.0 {
                didDrag = true
                mouseDownEvent = nil
                window?.performDrag(with: startEvent)
            }
        }

        override func mouseUp(with event: NSEvent) {
            mouseDownEvent = nil
            didDrag = false
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll?(event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            menuProvider?()
        }

        override func magnify(with event: NSEvent) {
            if event.phase == .began { pinchTriggered = false }
            guard !pinchTriggered, abs(event.magnification) > 0.3 else { return }
            pinchTriggered = true
            onDoubleClick?()
        }
    }
}
```
- **Where to insert**: In `ComparePlayerView.swift:62`, inside the `ZStack(alignment: .topLeading)` right after `comparisonSurfaces(...)` and **before** `if viewMode.isWipe { wipeInteractionOverlay(...) }`. That way it covers the entire video canvas, sits below the wipe handle, and sits below `ContentView`'s `inspectorPanel`, `overlayControls`, and `audioWaveformOverlay`.
- **Effort**: S | **Risk**: Low.

---

## A2. Fill-Screen-Stay-Windowed Toggle (Double-Click on Video)

### AppKit Mechanics & `WindowConfigurator` Interaction
1. **Does `window.contentAspectRatio` constrain programmatic `window.setFrame(_:display:animate:)`?**
   No—in AppKit, `contentAspectRatio` is enforced during user live-resize (`_validSize` in `NSWindow` resize tracking) and `zoom(_:)`, **not** direct `setFrame(_:display:animate:)`. **However**, leaving `contentAspectRatio` non-zero while the window is in a screen-shaped (`visibleFrame`) aspect ratio causes two bugs:
   - As soon as the user touches a window edge to resize, AppKit violently snaps the window back to the video's aspect ratio.
   - `window.contentMinSize` computed for a portrait video (`WindowConfigurator.minContentSize`) can exceed `screen.visibleFrame.height` if not cleared.
   Therefore, `WindowConfigurator.Coordinator.maximize(_:)` (`WindowConfigurator.swift:127`) already does the right thing: it sets `window.contentAspectRatio = .zero` and `applyMinSize(window, ratio: nil)` before calling `window.setFrame(screen.visibleFrame, display: true, animate: true)`.
2. **`zoom(_:)` vs Manual Save/Restore**:
   Do **not** use `window.zoom(nil)` because SwiftUI's internal `NSWindowDelegate` (`AppKitWindowController`) owns `windowWillUseStandardFrame(_:defaultFrame:)` and `windowShouldZoom(_:toFrame:)`, and hijacking `window.delegate` breaks SwiftUI scene focus, `@FocusedValue`, and window lifecycle notifications. Manual save/restore in `WindowConfigurator.Coordinator` is 100% deterministic.
3. **Interaction with `openMaximized = true`**:
   Currently (`AppSettings.swift:26`), `openMaximized` defaults to `true`, so the very first file opened in a window immediately calls `maximize(window)` and fills `screen.visibleFrame`!
   If the window is *already* filling `screen.visibleFrame` because of `openMaximized` (and `savedPreMaximizeFrame == nil`), what should the first double-click do?
   - **Rule**: Define "isWindowMaximized" as `abs(window.frame.width - screen.visibleFrame.width) < 2 && abs(window.frame.height - screen.visibleFrame.height) < 2`.
   - When `toggleWindowedFillScreen(window)` is called:
     - If the window is currently in native macOS fullscreen (`window.styleMask.contains(.fullScreen)`), call `window.toggleFullScreen(nil)` to exit native fullscreen.
     - Else if `isWindowMaximized` is **true**:
       - Restore to `savedPreMaximizeFrame` if one was saved prior to maximizing;
       - **If `savedPreMaximizeFrame == nil`** (because the window opened maximized via `openMaximized`), compute the **1× native source frame** (clamped to `0.85 * screen.visibleFrame` so that if the source is 4K on a 1080p/1440p screen, double-clicking shrinks it to a centered 75%–85% window or 1:1 pixel size, and re-applies `window.contentAspectRatio = NSSize(width: ratio, height: 1)`!).
     - Else (`isWindowMaximized` is **false**):
       - Save `savedPreMaximizeFrame = window.frame`
       - Clear `window.contentAspectRatio = .zero` and `applyMinSize(window, ratio: nil)`
       - Call `window.setFrame(screen.visibleFrame, display: true, animate: true)`.

```swift
// In WindowConfigurator.Coordinator:
var savedPreMaximizeFrame: NSRect?

func toggleFillScreen(_ window: NSWindow) {
    if window.styleMask.contains(.fullScreen) {
        window.toggleFullScreen(nil)
        return
    }
    guard let screen = window.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let isMaximized = abs(window.frame.width - visible.width) <= 2
        && abs(window.frame.height - visible.height) <= 2

    if isMaximized {
        let targetFrame = savedPreMaximizeFrame ?? centeredSourceFrame(
            for: window,
            ratio: lastAspectRatio ?? (16.0 / 9.0),
            sourceSize: lastSourceSize,
            in: visible,
            maxScreenFraction: 0.75
        )
        savedPreMaximizeFrame = nil
        window.setFrame(targetFrame, display: true, animate: true)
        if let ratio = lastAspectRatio, ratio > 0 {
            applyMinSize(window, ratio: ratio)
            window.contentAspectRatio = NSSize(width: ratio, height: 1)
        }
    } else {
        savedPreMaximizeFrame = window.frame
        window.contentAspectRatio = .zero
        applyMinSize(window, ratio: nil)
        window.setFrame(visible, display: true, animate: true)
    }
}
```
- **Effort**: S | **Risk**: Low.

---

## A3. Scroll Wheel Copy of VLC

### VLC's Exact Algorithm (`modules/gui/macosx/menus/VLCMainMenu.m` / `VLCVideoWindowCommon.m`)
- **Thresholds & Axis Lock**:
  - Y threshold = `1.0`, X threshold = `0.8`, axis lock timeout = `0.4` seconds.
  - Why `event.deltaY` / `event.deltaX` vs `scrollingDeltaY`?
    In AppKit, `event.scrollingDeltaY` is in **points** (typically 5–50 per tick on trackpad) when `event.hasPreciseScrollingDeltas == true`, whereas `event.deltaY` is normalized to line/notch units (~0.1–1.5 per tick on trackpads, 1.0 per notch on discrete wheel mice). VLC's `1.0` and `0.8` thresholds are calibrated against **`event.deltaY` and `event.deltaX`**!
  - **Direction inversion**:
    When `event.isDirectionInvertedFromDevice == true` (macOS "Natural" scrolling), VLC inverts the deltas so that scrolling two fingers **up** increases volume and scrolling two fingers **right** seeks forward. Specifically:
    ```swift
    let invert: CGFloat = event.isDirectionInvertedFromDevice ? -1.0 : 1.0
    let dY = event.deltaY * invert
    let dX = event.deltaX * invert
    ```
    *(Check sign: on macOS with Natural Scrolling OFF, pushing wheel up yields `deltaY > 0`; with Natural Scrolling ON, pushing fingers up yields `deltaY < 0`, so multiplying by `-1` makes pushing fingers up positive `dY > 0` = volume up).*
  - **Momentum Events**:
    For **seeking** (X axis), ignore `event.momentumPhase != []`! Why? If a user flicks a Magic Mouse or trackpad horizontally, momentum events keep firing for 1.5 seconds after release, causing uncontrollable runaway seeking across the timeline. For **volume** (Y axis), allowing or ignoring momentum is optional, but VLC processes only direct finger contact or damps momentum; ignoring `event.momentumPhase != []` on X seek (or both axes) prevents accidental overshoot.
  - **Multi-window sync**:
    Follow AMP's existing convention in `PlayerView.swift:412`:
    - Volume (`adjustVolume(by: ±5)`) is **per-window** (unless in Compare Mode where `compareSession.adjustMonitoringVolume` is used).
    - Seek (`±3.0` seconds per step) routes through `NotificationCenter.default.post(.seekBySeconds(±3.0))` when `WindowManager.shared.syncPlaybackControls` is on, or `compareSession.seek` / `controller.seek` locally.

### Concrete `ScrollWheelController` Implementation

```swift
// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

@MainActor
final class VideoScrollWheelHandler {
    enum Axis { case none, vertical, horizontal }

    private var lockedAxis: Axis = .none
    private var lastEventTime: TimeInterval = 0
    private var accumX: CGFloat = 0
    private var accumY: CGFloat = 0

    static let yThreshold: CGFloat = 1.0
    static let xThreshold: CGFloat = 0.8
    static let axisLockDuration: TimeInterval = 0.4

    func handle(
        _ event: NSEvent,
        onVolumeStep: (Double) -> Void,
        onSeekStep: (Double) -> Void
    ) {
        // Ignore momentum on horizontal seek to prevent runaway trackpad kinetic seeks
        if event.momentumPhase != [] && lockedAxis == .horizontal { return }

        let now = event.timestamp
        if now - lastEventTime > Self.axisLockDuration || event.phase == .began {
            lockedAxis = .none
            accumX = 0
            accumY = 0
        }
        lastEventTime = now

        let sign: CGFloat = event.isDirectionInvertedFromDevice ? -1.0 : 1.0
        let dY = event.deltaY * sign
        let dX = -event.deltaX * sign // right swipe -> positive seek

        if lockedAxis == .none {
            if abs(dY) > abs(dX) && abs(dY) > 0.05 {
                lockedAxis = .vertical
            } else if abs(dX) > abs(dY) && abs(dX) > 0.05 {
                lockedAxis = .horizontal
            } else {
                return
            }
        }

        switch lockedAxis {
        case .vertical:
            accumY += dY
            while abs(accumY) >= Self.yThreshold {
                let dir = accumY > 0 ? 1.0 : -1.0
                onVolumeStep(dir * 5.0)
                accumY -= CGFloat(dir) * Self.yThreshold
            }
        case .horizontal:
            guard event.momentumPhase == [] else { return }
            accumX += dX
            while abs(accumX) >= Self.xThreshold {
                let dir = accumX > 0 ? 1.0 : -1.0
                onSeekStep(dir * 3.0)
                accumX -= CGFloat(dir) * Self.xThreshold
            }
        case .none:
            break
        }
    }
}
```
- **Effort**: S | **Risk**: Low.

---

## A4. Right-Click Menu on Video (VLC `voutMenu`)

### Swift 6 NSMenu Closure Target Pattern
In Swift 6 (`@MainActor`), creating a small `MenuBlockItem: NSMenuItem` subclass that stores an `@MainActor () -> Void` closure and sets `self.target = self; self.action = #selector(invoke)` is completely type-safe, avoids responder-chain selector boilerplate, and supports checkmarks (`state = .on`).

```swift
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, keyEquivalent: String = "", isChecked: Bool = false, isEnabled: Bool = true, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        self.target = self
        self.state = isChecked ? .on : .off
        self.isEnabled = isEnabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
```

### Complete Item List for AMP's Video Context Menu (VLC `voutMenu` + AMP Inspection Additions)
1. **Play / Pause** (dynamic title)
2. **Stop** (closes media / returns to drop zone or resets to 0)
3. **Previous File in Folder** / **Next File in Folder**
4. `NSMenuItem.separator()`
5. **Speed** submenu (`0.25×`, `0.5×`, `0.75×`, `1.0× (Normal)`, `1.25×`, `1.5×`, `2.0×`, `4.0×`)
6. **Jump to Time…** (activates timecode editor)
7. **Chapters** submenu (hidden or disabled if `chapterOptions.isEmpty`)
8. `NSMenuItem.separator()`
9. **Audio** submenu:
   - Increase Volume (`+5%`), Decrease Volume (`-5%`), Mute
   - Separator
   - **Audio Track** submenu (lists `controller.audioTrackOptions` with checkmarks)
   - **Channel Monitoring** submenu (All Channels, Solo, Mute per channel)
   - **Audio Delay** (`+50 ms`, `-50 ms`, `Reset`)
10. **Subtitles** submenu:
    - Open Subtitle File…
    - **Subtitle Track** submenu (`Off` + `controller.subtitleTrackOptions`)
    - **Subtitle Size** (`Smaller`, `Normal`, `Larger`)
    - **Subtitle Delay** (`+50 ms`, `-50 ms`, `Reset`)
11. **Video** submenu:
    - Fill Screen (Windowed)
    - Toggle Native Fullscreen
    - Float on Top (checkmark)
    - Separator
    - **Window Size**: Half Size (`⌘0`), Normal Size (`⌘1`), Double Size (`⌘2`), Fit to Screen (`⌘3`)
    - **Aspect Ratio** submenu (`Default`, `16:9`, `16:10`, `4:3`, `1:1`, `2.21:1`, `2.35:1`, `2.39:1`, `5:4`)
    - **Crop** submenu (`Default`, `16:9`, `16:10`, `4:3`, `1:1`, `1.85:1`, `2.35:1`, `2.39:1`)
    - **Deinterlace** submenu (`Auto`, `On`, `Off`)
    - **Shader Profile** submenu (`RenderProfile.allCases` with checkmarks)
12. `NSMenuItem.separator()`
13. **Save Screenshot**
14. **Toggle Inspector** / **Video Scopes** / **Audio Waveform**

- **Effort**: M | **Risk**: Low.

---

## A5. Switchable Keymap Design ("VLC Default" vs "AMP Pro (JKL)")

### Precedence Problem: SwiftUI `.keyboardShortcut` vs Local `NSEvent` Monitor
In AppKit, when a user presses a key:
1. `NSApplication.sendEvent(_:)` runs **local `NSEvent` monitors first** (`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`).
2. If the monitor returns `nil`, the event is consumed and **never** reaches `NSApp.mainMenu.performKeyEquivalent(with:)` or SwiftUI's `.keyboardShortcut`.
3. However, if a key is ONLY bound on a SwiftUI `CommandMenu` `Button` via `.keyboardShortcut(...)` and NOT in the local monitor, AppKit's `performKeyEquivalent` fires it **even when a `TextField` (like the timecode editor or review note input) has focus**, especially for single-character shortcuts like `t`, `m`, `j`, `l`, `space`! Notice `Aagedal_Media_PlayerApp.swift:127-205` currently attaches `.keyboardShortcut("t", modifiers: [])`, `.keyboardShortcut("m", modifiers: [])`, `.keyboardShortcut("j", modifiers: [])`, `.keyboardShortcut("l", modifiers: [])` directly to menu buttons!
   **BUG**: Because `t`, `m`, `j`, `l` are registered as menu key equivalents in `Aagedal_Media_PlayerApp.swift`, if a user opens **Comparison Review Notes** (`CompareReviewView`) and types the letter `"m"`, `"t"`, `"j"`, or `"l"` into the note `TextField`, `PlayerView`'s local key monitor returns `false` (`if isEditingTimecode || isTextInputActive { return false }`), so the event passes to `NSApp.mainMenu.performKeyEquivalent`, which **fires Mute, Cycle Timecode, Reverse, or Fast Forward while typing a note!** (Confirmed in `Aagedal_Media_PlayerApp.swift:127, 173, 193, 199`!).

### The Clean Solution for Switchable Keymaps + Menu Shortcut Labels + Text Input Safety
1. **Add `AppSettings.keymapPreset`** (`"vlc"` vs `"ampPro"`, default `"vlc"` per owner goal #1, or user-chosen on first launch).
2. **Never attach bare-character (modifier-less) `.keyboardShortcut` to SwiftUI `CommandMenu` items**, OR gate them on `@FocusedValue(\.isTextInputFocused) != true`. Even better: drive menu item `.keyboardShortcut` from a helper `MenuShortcutProvider.shortcut(for: action, preset: keymapPreset, isTextInputActive: isTextInputActive)` that returns `nil` when `isTextInputActive == true`!
3. **Unify `KeyBindingAction` and `PlayerKeyMap`**:
   Expand `KeyBindingAction` (`KeyBindingAction.swift:17`) to include all VLC actions:
   - `.stop` (`⌘.` in VLC)
   - `.seekForward3s`, `.seekBackward3s` (`⌃⌘→` / `⌃⌘←`)
   - `.seekForward10s`, `.seekBackward10s` (`⌥⌘→` / `⌥⌘←` in VLC, `⇧→` / `⇧←` in AMP Pro)
   - `.seekForward60s`, `.seekBackward60s` (`⇧⌘→` / `⇧⌘←`)
   - `.seekForward5m`, `.seekBackward5m` (`⇧⌥⌘→` / `⇧⌥⌘←`)
   - `.volumeUp`, `.volumeDown`, `.toggleMute` (`⌘↑`/`⌘↓`/`⌥⌘↓` in VLC, `↑`/`↓`/`M` in AMP)
   - `.speedUp`, `.speedDown`, `.speedNormal` (`⌘=`/`⌘-` in VLC, `]`/`[` in AMP)
   - `.nextFrame` (`E` in VLC, `.` in AMP)
   - `.cycleAspectRatio` (`A`), `.cycleCrop` (`C`), `.cycleZoom` (`Z`), `.toggleAutoscale` (`O`)
   - `.cycleSubtitleTrack` (`S`), `.cycleAudioTrack` (`L` in VLC; in AMP Pro `L` is fast-forward!)
   - `.cycleDeinterlace` (`D`), `.cycleAudioDevice` (`⇧A`)
   - `.subtitleDelayUp`, `.subtitleDelayDown` (`J`/`H` in VLC; in AMP Pro `J` is reverse!)
   - `.audioDelayUp`, `.audioDelayDown` (`G`/`F` in VLC; in AMP Pro `F` is fullscreen!)
   - `.windowSizeHalf` (`⌘0`), `.windowSizeNormal` (`⌘1`), `.windowSizeDouble` (`⌘2`), `.windowSizeFit` (`⌘3`)
   - `.jumpToTime` (`⌘J`)
4. **Resolution Order in `PlayerKeyMap.resolve(event:)`**:
   1. Guards: `isEditingTimecode`, `isTextInputActive`, `NSApp.keyWindow?.firstResponder is NSTextView` (catches **all** AppKit/SwiftUI text fields automatically without needing manual boolean plumbing!).
   2. Focus guards: `isTimelineFocused`, `isOverlayControlFocused`.
   3. Modal guards: Compare Mode wipe `[`/`]`.
   4. **Layer 1**: User `keybindings.json` (`KeyBindingStore.shared.table`).
   5. **Layer 2**: Active Preset Table (`KeyBindingPresets.table(for: currentPreset)` — either `.vlc` or `.ampPro`).
   6. **Layer 3**: Timecode numeric entry (`0-9`, `+`, `-`, `:`, `;`).

- **Effort**: M | **Risk**: Low.

---

## A6. Dynamic Audio / Video / Subtitles Top-Level Menus in Multi-Window SwiftUI

### `CommandMenu` + `@FocusedValue` vs `NSMenuDelegate`
- **Does SwiftUI wipe manual `NSApp.mainMenu` additions?**
  Yes—whenever any `@FocusedValue` or `@AppStorage` read inside `.commands { ... }` changes, SwiftUI diffs and reconstructs the `NSMenu` items managed by `CommandMenu`/`CommandGroup`. Manually inserting `NSMenuItem`s into `NSApp.mainMenu` causes flicker or vanishing menus unless you fight SwiftUI's menu reconciler.
- **How to do per-file dynamic track lists cleanly in SwiftUI `.commands`**:
  Expose the active window's `PlayerController` (and `CompareSessionController`) via `@FocusedObject` or `@FocusedValue`!
  In `ContentView.swift:221`:
  ```swift
  .focusedSceneObject(controller)
  .focusedSceneObject(compareSession)
  ```
  And in `Aagedal_Media_PlayerApp.swift`:
  ```swift
  @FocusedObject private var activeController: PlayerController?
  @FocusedObject private var activeCompareSession: CompareSessionController?
  ```
  Because `PlayerController` is `@MainActor ObservableObject` and publishes `audioTrackOptions`, `subtitleTrackOptions`, `chapterOptions`, `selectedAudioTrackOrderIndex`, and `selectedSubtitleTrackOrderIndex` (via `trackSelectionCancellable`), SwiftUI's `CommandMenu("Audio")`, `CommandMenu("Video")`, and `CommandMenu("Subtitles")` will **automatically and reactively** display the exact track list, checkmarks, and state of whichever player window is currently the **key window**!
- **Top-Level Menu Bar Structure**:
  - **File** (New Window, Open, Open Subtitle, Open Comparison File, Open Recent, Close, Save Screenshot, Export Trim)
  - **Playback** (Play/Pause, Stop, Reverse/Fast Forward, Speed submenu, Step Frame, Jump to Time `⌘J`, A→B Loop, Chapters submenu, Prev/Next File, Multi-Window Sync)
  - **Audio** (Audio Track submenu, Audio Device submenu, Channel Monitoring submenu, Increase/Decrease Volume, Mute, Audio Delay `+50ms`/`-50ms`)
  - **Video** (Fill Screen, Fullscreen `⌘F`, Float on Top, Half/Normal/Double/Fit to Screen `⌘0`–`⌘3`, Aspect Ratio submenu, Crop submenu, Zoom submenu, Deinterlace submenu, Shader Profile submenu, Scopes, Loupe)
  - **Subtitles** (Add Subtitle File…, Subtitle Track submenu, Subtitle Size, Subtitle Delay `+50ms`/`-50ms`)
  - **Window** / **View** (Inspector `⌘I`, Review Notes)

- **Effort**: M | **Risk**: Low.

---

## A7. VLC On-Screen Messages (OSD HUD)

### SwiftUI Overlay vs `mpv show-text`
- **Why a SwiftUI Overlay (`PlayerOSDOverlayView`) is strictly superior to `mpv show-text` for AMP**:
  1. Works identically on **both** `MPVPlayer` and `AVPlayer` (ProRes RAW) backends.
  2. Never contaminates `mpv.screenshotRaw()` (which `FrameCapture` for scopes and `LoupeFrameCapture` call at 10–15 fps, though `"video"` mode excludes OSD, keeping `osd-level=0` guarantees zero GPU OSD pass overhead).
  3. Matches AMP's existing top-left/top-right pill aesthetic (`PlaybackSpeedIndicator`, `RenderTierBadge`) and respects `@Environment(\.accessibilityReduceTransparency)` and `@Environment(\.accessibilityReduceMotion)`.
- **Design**:
  Add a lightweight `@MainActor final class PlayerOSDController: ObservableObject` owned by `PlayerController` (or `ContentView`):
  ```swift
  @MainActor
  final class PlayerOSDController: ObservableObject {
      struct Message: Equatable {
          let id = UUID()
          let icon: String?
          let text: String
      }
      @Published private(set) var current: Message?
      private let dismissal = DeferredMainActorTask()

      func show(_ text: String, icon: String? = nil, duration: Duration = .milliseconds(1200), announceForAccessibility: Bool = true) {
          current = Message(icon: icon, text: text)
          if announceForAccessibility {
              AccessibilityNotification.Announcement(text).post()
          }
          dismissal.schedule(after: duration) { [weak self] in
              withAnimation(.easeOut(duration: 0.2)) {
                  self?.current = nil
              }
          }
      }
  }
  ```
  - **Coalesced VoiceOver Announcements**: When scrolling the volume wheel rapidly, debounce `AccessibilityNotification.Announcement` by 400 ms so VoiceOver speaks the settled volume (`"Volume 85%"`) instead of queuing 10 announcements.
  - **Placement**: Top-right of the video canvas (since top-left holds traffic lights + `PlaybackSpeedIndicator` + `RenderTierBadge`), with `.allowsHitTesting(false)`.

- **Effort**: S | **Risk**: Low.

---

## A8. Resume Playback Like VLC

### Sandboxing & Storage Key Analysis
- **Is AMP Sandboxed?**
  Looking at `CLAUDE.md` (`CODE_SIGN_IDENTITY=-`), `ShaderLibrary.defaultDirectory` (`~/.config/mpv/shaders` read directly without a bookmark), `InstallSource.swift` (reading `/opt/homebrew/Caskroom`), and `FFmpegService` (spawning bundled `ffmpeg` directly), **AMP is not App-Sandbox enabled** (it uses Hardened Runtime for Notarization, with security-scoped bookmarks only in `LocationSettingsSection` as good citizenship).
- **How to Key Resume Positions**:
  Keying by `url.standardizedFileURL.resolvingSymlinksInPath().path` as primary key, plus storing `(fileResourceIdentifier / inode, fileSize)` from `CompareReviewSourceIdentity` (`CompareReviewNote.swift:162`) ensures that:
  1. If a file is re-rendered/overwritten at the same path with a different duration, we don't resume to a bogus timestamp.
  2. Cap the store (`ResumePositionStore`, persisted in `Application Support/Aagedal Media Player/resume-positions.json` or `UserDefaults`) at e.g. 500 recent entries (LRU).
- **VLC's Exact Store Rules**:
  ```swift
  nonisolated enum ResumePlaybackPolicy {
      enum Mode: String, CaseIterable, Sendable { case ask, always, never }

      static func shouldStore(position: TimeInterval, duration: TimeInterval) -> Bool {
          guard position.isFinite, duration.isFinite,
                duration >= 180 else { return false } // skip < 3 min
          let progress = position / duration
          if progress < 0.05 && position < 60 { return false }
          let remaining = duration - position
          if progress > 0.95 && remaining < 60 { return false }
          return true
      }
  }
  ```
- **Non-Blocking Prompt UI with 10s Countdown**:
  Never use a modal `NSAlert`! When a file opens and has a stored resume position:
  - If `mode == .always`: pass `startTime: savedPosition` directly to `controller.loadMedia(item, startTime: savedPosition, autoplay: ...)`.
  - If `mode == .ask`: start playback normally from `0` (or wherever `loadMedia` starts), and show a compact floating banner at the top of the player (similar to `UpdateAvailableBanner` in `PlayerOverlayViews.swift:235`):
    `"Resume playback at 14:22?  [Resume]  [Dismiss (10s)]"`
    Backed by a 1-second timer counting down from 10 to 0. Pressing `Resume` calls `controller.seekTo(savedPosition)` and dismisses the banner.
  - Save the current position on `stopPlaybackForWindowClose`, before opening a new file in the same window, and on `NSApplication.willTerminateNotification`.

- **Effort**: M | **Risk**: Low.

---

## A9. Now Playing / Media Keys (`MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`)

### Architecture for Multi-Window libmpv + AVPlayer
- Note: `MPVPlayer.swift:320` already sets `input-media-keys=no`, so mpv won't fight AMP's own `MPRemoteCommandCenter` integration.
- **No Special Entitlements Needed**: `MediaPlayer.framework` (`MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`) requires **zero** special entitlements on macOS.
- **Multi-Window Ownership Rule**:
  Create `@MainActor final class NowPlayingCoordinator`:
  - Tracks the **active owner** `PlayerController`:
    - When a window becomes key (`NSWindow.didBecomeKeyNotification`) and has media loaded, it becomes the Now Playing owner.
    - If the key window has no media, the most recently playing window with media owns Now Playing.
    - When the owning window closes, ownership transfers to any remaining window with media, or clears `nowPlayingInfo = nil` and sets `playbackState = .stopped`.
- **Commands to Register**:
  - `playCommand`, `pauseCommand`, `togglePlayPauseCommand`
  - `nextTrackCommand`, `previousTrackCommand` (routes to `openNextFile` / `openPreviousFile`)
  - `skipForwardCommand`, `skipBackwardCommand` (10s)
  - `changePlaybackPositionCommand` (scrubbing from Control Center / Lock Screen!)
- **Update Cadence (Crucial for CPU/Energy)**:
  Do **not** update `MPNowPlayingInfoCenter.default().nowPlayingInfo` on every `timePos` tick (10 Hz)! `MPNowPlayingInfoCenter` extrapolates elapsed time automatically on macOS using `MPNowPlayingInfoPropertyElapsedPlaybackTime` + `MPNowPlayingInfoPropertyPlaybackRate`!
  Only update `nowPlayingInfo` on:
  1. File load / metadata arrival (`MPMediaItemPropertyTitle`, `MPMediaItemPropertyPlaybackDuration`, `MPMediaItemPropertyArtwork`)
  2. Play / Pause / Rate change (`playbackState = isPlaying ? .playing : .paused`, `MPNowPlayingInfoPropertyPlaybackRate = isPlaying ? currentPlaybackSpeed : 0.0`, `MPNowPlayingInfoPropertyElapsedPlaybackTime = currentPlaybackTime`)
  3. Explicit seek (`seekTo`, `endScrubbing`).
- **Artwork**: Extract once asynchronously after file load via `ComparisonStillFrameExtractor.image(from: url, at: min(5.0, duration * 0.1), maximumSize: CGSize(width: 600, height: 600))`.

- **Effort**: M | **Risk**: Low.

---

## A10. Window Sizing (`⌘0`/`⌘1`/`⌘2`/`⌘3`), Float on Top, Aspect Lock, and `openMaximized`

### 1. Why `openMaximized = true` Fights VLC Window Behaviour
In `AppSettings.swift:26`, `openMaximized` is hardcoded to `true` and hidden from Settings, while `GeneralSettingsView.swift:37` shows a toggle for `"Open Windows at Source Resolution"` (`openAtSourceResolution`). Because `WindowConfigurator.shouldMaximize` (`WindowConfigurator.swift:28`) checks `openMaximized` first, **the `"Open Windows at Source Resolution"` setting in `GeneralSettingsView` is completely dead on the first file opened in every window!**
- **Fix**: Expose a 3-way picker in `GeneralSettingsView` (or make `openMaximized` false when `openAtSourceResolution` is true):
  - **Resize window to video on open** (VLC `video-autoresize` default: sizes to `sourceSize / window.backingScaleFactor`, clamped to `screen.visibleFrame`, top-left anchored or centered per preference, with `window.contentAspectRatio = NSSize(width: ratio, height: 1)` locked!)
  - **Fill screen (windowed) on first open** (AMP's current `openMaximized`)
  - **Keep current window size**

### 2. `⌘0` (Half), `⌘1` (Normal 1:1), `⌘2` (Double), `⌘3` (Fit to Screen)
Add `.scaleWindow(WindowSizePreset)` to `AppCommand`:
```swift
enum WindowSizePreset: Double {
    case half = 0.5
    case normal = 1.0
    case double = 2.0
    case fitToScreen = 0.0
}
```
In `WindowConfigurator.Coordinator`:
- Compute `let backingScale = window.backingScaleFactor` (2.0 on Retina).
- At `.normal` (`1.0`), 1 video pixel = 1 physical Retina pixel, so content size in points is `(sourceSize.width / backingScale, sourceSize.height / backingScale)` (or if the user prefers point-based 1:1, note that VLC uses `sourceSize` in points clamped to screen, whereas QuickTime/IINA use Retina pixel/point—using `sourceSize / backingScale` for `.normal` and `sourceSize` in points for `.double` matches Retina-aware players; or clamp all to `screen.visibleFrame`).
- Always re-lock `window.contentAspectRatio = NSSize(width: ratio, height: 1)` and reset `hasMaximizedForMedia = false` when the user invokes `⌘0`/`⌘1`/`⌘2`/`⌘3`!

### 3. Re-locking Aspect Ratio on User Resize After Maximize
Currently (`WindowConfigurator.swift:127`), `maximize()` sets `window.contentAspectRatio = .zero`, so if the user drags a corner of a maximized window, it resizes freely with black bars.
- **Fix**: Observe `NSWindow.willStartLiveResizeNotification` in `WindowConfigurator.Coordinator`. If `!window.styleMask.contains(.fullScreen)`, as soon as the user begins a manual resize drag (or finishes one), restore `window.contentAspectRatio = NSSize(width: ratio, height: 1)` so user-resized windows always hug the video without black bars!

### 4. Float on Top
Add `@Published var isFloatingOnTop = false` per window (or `@FocusedValue`):
- When `isFloatingOnTop == true` and `!window.styleMask.contains(.fullScreen)`: set `window.level = .floating`.
- In `willEnterFullScreen`: set `window.level = .normal` (a `.floating` window in native fullscreen can obscure system alerts or the menu bar slide-down).
- In `didExitFullScreen`: restore `window.level = isFloatingOnTop ? .floating : .normal`.

- **Effort**: M | **Risk**: Low.

---

## A11. Volume Up to 125% (VLC Max)

### Math, `mpv` & `AVPlayer` Handling, and Slider UI
1. **`PlaybackVolume.swift` Math**:
   In mpv (`player/audio.c`), `audio_get_gain` computes `pow(volume / 100.0, 3.0)`.
   Because AMP defines UI percentage `percent` as **linear amplitude** (`percent / 100.0`), `PlaybackVolume.mpvValue(for:)` is:
   ```swift
   nonisolated enum PlaybackVolume {
       static let maxPercent: Double = 125.0

       static func mpvValue(for percent: Double) -> Double {
           let clamped = percent.isFinite ? min(maxPercent, max(0, percent)) : 100
           return 100.0 * cbrt(clamped / 100.0)
       }
   }
   ```
   At `percent = 125%`, `100 * cbrt(1.25) = 107.7217`. Since mpv's default `volume-max` is `130.0` (which corresponds to `1.3^3 = 2.197x` amplitude), `107.72` is well within mpv's default `volume-max=130`! Still, explicitly setting `mpv_set_option_string(mpv, "volume-max", "130")` in `setupMPV()` guarantees it.
2. **`AVPlayer` 0–1 Cap (ProRes RAW)**:
   `AVPlayer.volume` is clamped by Apple to `0.0...1.0` for standard playback unless an `MTAudioProcessingTap` boosts PCM samples. Since `AVAudioChannelRouter.swift` *already* has an `MTAudioProcessingTap` (`audioChannelTapProcess`), you can either:
   - Clamp `AVFoundationPlayerBackend.volume` to `min(1.0, Float(newValue / 100.0))` (simplest, zero risk of clipping ProRes RAW monitoring), OR
   - Apply linear gain `Float(max(1.0, volume / 100.0))` inside `AVAudioChannelRouter` when `volume > 100`. For a reference QC player on ProRes RAW, clamping `AVPlayer.volume` to `1.0` (or applying gain in the tap with `vDSP_vsmul`) is trivial; clamping or tap-scaling takes 5 lines.
3. **`PlaybackVolumeSlider.swift` with Detent/Tick at 100%**:
   Update `slider.maxValue = 125` in `PlaybackVolumeSlider.swift:17` and `PlayerController.swift:56, 488`. Draw a subtle 1pt vertical tick line at `x = width * (100.0 / 125.0)` in `PlaybackVolumeSlider.Control.draw(_:)` and snap within `±2%` of `100.0` during mouse drag so returning to unity gain (100%) is effortless.

- **Effort**: S | **Risk**: Low.

---

## A12. Other VLC macOS Features Worth Copying into AMP

| Feature | Worth Copying? | How to Implement in AMP | Effort |
| :--- | :--- | :--- | :--- |
| **Jump to Time (`⌘J`)** | **Yes (High)** | AMP already has an inline timecode editor in `ControlsView`! Wire `⌘J` (`AppCommand.jumpToTime`) to reveal the overlay controls and focus `timecodeEditor` (or in `FloatingOSCView`, pop a small popover/inline field). | **S** |
| **A→B Loop** | **Yes (High)** | AMP already has `trimIn` and `trimOut`! Add a "Loop Trim Range (A→B)" toggle (`L` or button) that syncs `trimIn`/`trimOut` to mpv's native `ab-loop-a` and `ab-loop-b` properties (`mpv_set_property_string(mpv, "ab-loop-a", ...)`). | **S** |
| **Remaining Time Toggle on Click in `FloatingOSCView`** | **Yes (High)** | In `FloatingOSCView.swift:115`, clicking the right-hand `timeLabel(duration)` toggles `@AppStorage("showRemainingTime")` between total duration (`01:30:00`) and remaining (`-01:12:45`), matching VLC! | **S** |
| **Window Title + Proxy Icon on Hover** | **Yes (High)** | Currently `window.titleVisibility = .hidden` (`WindowConfigurator.swift:225`). Set `window.representedURL = item.url` and fade `window.titleVisibility` or draw a top title bar pill on hover with a draggable document proxy icon. | **S** |
| **Pause on Minimize** | **Yes (Medium)** | Add `AppSettings.pauseOnMinimize` (default `false` or `true`). Observe `NSWindow.willMiniaturizeNotification` in `PlayerWindowCoordinator` and call `controller.pause()`. | **S** |
| **Audio / Subtitle Delay (`F`/`G`, `H`/`J` in VLC)** | **Yes (High)** | Expose `audio-delay` and `sub-delay` mpv properties (`setDouble("audio-delay", ...)`), adjustable in `±50 ms` steps via menu/hotkeys with OSD feedback (`"Audio delay: +50 ms"`). | **S** |
| **Aspect Ratio (`A`) & Crop (`C`) Cycling** | **Yes (High)** | Use mpv properties `video-aspect-override` and `video-crop` (or `panscan`) to cycle standard ratios with OSD feedback (`"Aspect ratio: 16:9"`). | **S** |
| **Video Effects Panel (Brightness/Contrast/Gamma/Sat/Hue)** | **Optional (Low)** | mpv supports `brightness`, `contrast`, `gamma`, `saturation`, `hue` properties in `gpu-next` at zero extra pass cost. Useful, but keep a clear "Reset" indicator so QC users don't forget an active adjustment. | **M** |

---

# Section B: Architecture & Code Quality

## B1. `PlayerController` Decomposition & `@Observable` Migration

### Current State
`PlayerController.swift` (813 lines) + `PlayerController+Observers.swift` (330 lines) = 1,143 lines. The codebase has *already* started extracting `MediaOperationsController` and `TrackSelectionController`, which is great, but `PlayerController` still mixes:
1. Reverse playback state machine (native mpv backward vs AVPlayer negative rate vs 15 Hz timer simulation, URL blacklisting).
2. Interactive scrub coalescing (`mpvScrubThrottleTask`, `avPlayerScrubSeekInProgress`, `scrubGeneration`).
3. MPV Combine/AsyncSequence observation bridges (`mpvTimePosTask`, `mpvFileLoadedTask`, `mpvDurationTask`, and 9 `AnyCancellable`s).
4. HDR metadata & `sig-peak` graticule snapping for `FrameCapture`.

### Concrete Decomposition Plan (In Safe Order Without Breaking SwiftUI Bindings)
1. **Step 1 — Extract `ReversePlaybackController.swift` (~180 lines)**:
   Move `reverseSpeed`, `slowSteps`, `reverseTimer`, `reverseTimerGeneration`, `isNativeReverse`, `canNativeReverse`, `canNativeSlowReverse`, `nativeReverseFailedURLs`, `startReverse()`, `stopReverse()`, `slowForward()`, `slowReverse()`, `handleNativeBackwardFailure()` into `@MainActor final class ReversePlaybackController`. `PlayerController` delegates `startReverse()` / `stopReverse()` to it.
2. **Step 2 — Extract `ScrubCoordinator.swift` (~90 lines)**:
   Move `pendingScrubTime`, `mpvScrubThrottleTask`, `avPlayerScrubSeekInProgress`, `scrubGeneration`, `scrub(to:)`, `endScrubbing(at:)`, `cancelPendingScrubSeeks()` into `ScrubCoordinator`.
3. **Step 3 — Move MPV Observation Wiring into `MPVPlayerBackend` (`PlayerBackendAdapter.swift`)**:
   Instead of `PlayerController` holding 9 `AnyCancellable`s and 3 `Task`s for `MPVPlayer` and 4 KVO/Notification tokens for `AVPlayer`, define a single `PlayerBackendEvents` callback/stream on `PlayerBackendAdapter`. `MPVPlayerBackend` and `AVFoundationPlayerBackend` each encapsulate their own observers and tear them down in `teardown()`.
4. **Step 4 — Extract `HDRMetadataResolver.swift` (~70 lines)**:
   Move `updateTransferFunction()`, `peakNitsFromMetadata()`, and `snappedPeakNits()` into `Logic/Scopes/HDRMetadataResolver.swift`.

### Is `ObservableObject` → `@Observable` (`Observation` framework) Migration Worth It?
- **YES, high ROI on macOS 26**:
  Right now, `ContentView`, `ComparePlayerView`, `PlayerView`, `ControlsView`, `FloatingOSCView`, `AudioWaveformView`, and `ScopeView` all observe `@ObservedObject var controller: PlayerController`.
  In Combine's `ObservableObject`, **every `@Published` mutation fires `objectWillChange` to ALL subscribed views**. When `controller.currentPlaybackTime` updates 10 times per second (`0.1s`), SwiftUI re-evaluates the `body` of `ContentView`, `ComparePlayerView`, `PlayerView`, `FloatingOSCView`, and `ControlsView`—even though `ContentView` and `PlayerView` don't even read `currentPlaybackTime` in their `body`!
  With `@Observable` (Swift 5.9+ / macOS 14+), SwiftUI tracks **per-property reads** inside each view's `body`. Updating `currentPlaybackTime` at 10 Hz will **only** invalidate `PlayerScrubber` / `ControlsView.timelineSlider` and `timecodeReadonly`, reducing main-thread SwiftUI CPU usage during playback by ~70%.
  *Note*: Before migrating `PlayerController` to `@Observable`, replace `self.$playbackPhase.values` (`PlayerController.swift:283`) with a callback or `AsyncStream`, as `@Observable` does not synthesize Combine `$` publishers.
- **Effort**: M | **Risk**: Low-Medium (do decomposition first, `@Observable` second).

---

## B2. Swift 6 Concurrency Audit

Every unsafe spot in the codebase and its safe replacement:

| File : Line | Current Unsafe Construct | Why It's Risky / Redundant | Safe Replacement |
| :--- | :--- | :--- | :--- |
| `MPVPlayer.swift:16-19, 419` | `mpvWakeupCallback` → `player.readEvents()` → `queue.async { while self.mpv != nil { mpv_wait_event(...) } }` → `DispatchQueue.main.async { ... }` | 1. Every property change inside the `while` loop dispatches a **separate** `DispatchQueue.main.async` closure (up to 15 closures per wakeup!).<br>2. `getDouble`/`setString`/`command` on `@MainActor` access `self.mpv` concurrently with `queue`. | Coalesce event-loop state updates into a single struct batch per `readEvents()` drain and hop once via `Task { @MainActor in ... }`. Guard `self.mpv` access or route property gets/sets properly. |
| `MPVPlayer.swift:52-54` | `nonisolated(unsafe) var lastTimePosPublish`, `withheldTimePos`, `isPlayingOnEventLoop` | Mutated on `queue` in `readEvents()` and reset in `resetTimePosCoalescing()`. Safe *only* because both run on `queue`, but compiler cannot verify. | Encapsulate all three inside `MPVClockMirror` (which already has an `NSLock` / `OSAllocatedUnfairLock`)! |
| `MPVMetalLayer.swift:41` | `nonisolated(unsafe) var onDrawableSizeChange: (@Sendable (CGSize) -> Void)?` | Read in `drawableSize.didSet` (which MoltenVK can touch from its presentation thread) while written on `@MainActor`. | Wrap in `OSAllocatedUnfairLock<(@Sendable (CGSize) -> Void)?>`. |
| `MPVVideoView.swift:32-39`, `WindowConfigurator.swift:66-68` | `nonisolated(unsafe) private var ...Observer: NSObjectProtocol?` | Used only so `deinit` can call `NotificationCenter.default.removeObserver`. | Store all observer tokens in a `private final class ObserverBag: Sendable` using `OSAllocatedUnfairLock<[NSObjectProtocol]>` that removes them in its own `deinit`, or use Swift 6.2 `isolated deinit` (supported in macOS 26 / Xcode 26!). |
| `SubprocessService.swift:13, 128, 156`, `StreamingWaveformAccumulator.swift:26-31`, `PlayerWindowCoordinator.swift:361-363` | `final class ...: Sendable` with `NSLock` + `nonisolated(unsafe) var` | Manual `NSLock` + `nonisolated(unsafe)` bypasses compiler checks. | Replace `NSLock` + `nonisolated(unsafe) var` with `OSAllocatedUnfairLock<State>` (`import os`), which is natively `Sendable` and thread-safe without `nonisolated(unsafe)`! |
| `HardwareDecodeCapabilities.swift:17` | `final class HardwareDecodeCapabilities: @unchecked Sendable` with `NSLock` + `DispatchGroup` | `isSupported(mpvCodec:)` calls `pending.wait()`, blocking `@MainActor` during `setupMPV()` if probing hasn't finished! | Store the cached dictionary in `OSAllocatedUnfairLock<[String: Bool]?>` or pre-await it in `preparePlayback()`. |

---

## B3. `NotificationCenter`-Based `AppCommand` Broadcast

- **Verdict**: **Replace for single-window commands; keep a dedicated `WindowManager` coordinator method for multi-window transport sync.**
- **Why**:
  Currently (`ContentViewCommandHandlers.swift`), every `ContentView` attaches **28 separate `.onReceive(NotificationCenter.default.appCommandPublisher)` modifiers**! Every time *any* command is posted (e.g. pressing Space or arrow keys), Combine invokes **all 28 closures in every open window**, and 27 of them fail the `guard case .xyz = command` check.
  - **Fix 1 (Immediate, 10 lines)**: Collapse the 28 `.onReceive(NotificationCenter.default.appCommandPublisher)` modifiers in `ContentViewCommandHandlers.swift` into **one single `.onReceive(NotificationCenter.default.appCommandPublisher)`** with a `switch command` statement! That alone eliminates 27× redundant Combine subscriptions per window.
  - **Fix 2 (Clean Architecture)**: With `@FocusedObject private var activeController: PlayerController?` in `Aagedal_Media_PlayerApp.swift` (from **A6**), key-window-only commands (Inspector, Scopes, Open Subtitle, Screenshot, Export Trim, Audio/Subtitle Track selection) can call methods on the focused window coordinator directly, while transport commands (`togglePlayback`, `seekBySeconds`, `seekByFrames`) call `WindowManager.shared.dispatchTransportCommand(...)`.

---

## B4. Testability

- **Strong Pure Types Already Extracted**: `TimecodeRate`, `TimecodeFormatter`, `CompareTimelineMapping`, `CompareDriftPolicy`, `CompareDisplayGeometry`, `AudioChannelRouting`, `ExportCommandBuilder`, `SourceClassifier`, `ProfilePicker`, `GPUBudgetMonitor`, `LatestFrameGate`, `LoupeGeometry`.
- **What to Extract & Mock Next**:
  1. **Protocol-wrap `MPVPlayer` (`MPVControlling`)** or extract pure state machines (`ReversePlaybackController`, `VideoScrollWheelHandler`, `ResumePlaybackPolicy`, `WindowSizingCalculator`) so they can be unit-tested without spinning up a live `mpv_handle` and `CAMetalLayer`.
  2. **Flaky / Timing-Sensitive Patterns to Avoid in Tests**:
     - `AsyncDeadline.value(within: .milliseconds(500))` in `PlayerWindowCoordinator.swift:329` and `Task.sleep(for: .milliseconds(25))` polling loops in `CompareSessionController.swift:835` and `PlayerWindowCoordinator.swift:101`. Replace polling loops (`for _ in 0..<20 { try? await Task.sleep(...) }`) with event-driven continuations or `AsyncStream`s so tests run deterministically in <1 ms instead of sleeping for ratusan milliseconds.

---

## B5. Dead Code, Duplicated Logic & Over-Engineering to Delete

1. **Delete `PlayerController.buildMPVSubtitleTrackOptions()` (`PlayerController.swift:665-673`)**: Dead code, never called anywhere.
2. **Delete `MPVPlayer.commandString(_:)` (`MPVPlayer.swift:722-728`)**: Private function, never called anywhere.
3. **Delete `DropZoneView`'s duplicate recent-files UI OR unify with `InitialWindowController`**:
   Wait—when the app launches without a file, `AppDelegate` opens `InitialWindowController` (AppKit XIB ported from IINA) and `PlayerWindowCoordinator.accept` closes the empty SwiftUI window (`PlayerWindowCoordinator.swift:56`). `DropZoneView` is only seen if `allowMultipleWindows` is enabled and the user presses `⌘N` (New Window). Keeping `DropZoneView` simple for `⌘N` is fine, but note the overlap.
4. **Deduplicate `triggerOverlayWaveformGeneration()` / `generateInitialWaveform()` / `generateAudioWaveform()`**:
   The exact same 35-line multi-mono + stream-index lookup block is copy-pasted **four times**:
   - `ContentView.swift:422-442` (`generateAudioWaveform()`)
   - `ContentViewCommandHandlers.swift:281-315` (`triggerOverlayWaveformGeneration()`)
   - `AudioWaveformView.swift:229-266` (`triggerGeneration()`)
   - `AudioWaveformWindowController.swift:150-189` (`generateInitialWaveform()`)
   **Fix**: Move this into a single method `controller.requestWaveformGeneration(on: generator)`!
5. **Delete the 4 Force-Reload Hacks in `MPVVideoView.swift`** once the proper `wid` layer resize fix in **C1** is applied (`hasAutoReloadedForLayoutJump`, `layoutReload`, `didEnterFullScreen` reload, `didExitFullScreen` reload, `didEndLiveResize` reload, and `surfaceReloadResumeTask` in `PlayerController.swift:86`).

---

## B6. Error Handling, Diagnostics & Crash Resilience

- **MoltenVK / Vulkan Initialization Fallback**:
  In `MPVPlayer.setupMPV()` (`MPVPlayer.swift:322`), if `mpv_initialize(mpv)` fails, it sets `errorStage = .initialization`. What if `mpv_initialize` succeeds, or a file is loaded, and MoltenVK fails to create a swapchain or VideoToolbox fails hardware decoding?
  - Currently, `hwdec=videotoolbox` falls back to software decoding automatically inside mpv, and `activeHardwareDecoder` updates via `hwdec-current`.
  - Add a "Copy Diagnostics" report in the Help menu (not just on fatal failure in `PlayerView`) that dumps: macOS version, chip model, active display EDR headroom, `mpv` version, `libplacebo` version, `hwdec-current`, `vo-passes` JSON, active `RenderProfile`, and the last 50 lines of `MPV_EVENT_LOG_MESSAGE` (keep a ring buffer of the last 50 log lines in `MPVPlayer`).

---

# Section C: Metal / Render Backend

## C1. `wid` + MoltenVK `CAMetalLayer` vs `mpv_render_context` in 2026 & Fixing the Stale `dst-rect` Reload Hacks

### 1. Fact-Check on `libmpv` Render API Backends in 2026
- **Does `mpv_render_context` have a native Metal backend in upstream mpv?**
  **NO.** Upstream `libmpv`'s `mpv_render_context_create` (`render.h` / `render_gl.h`) only exposes `MPV_RENDER_API_TYPE_OPENGL` and `MPV_RENDER_API_TYPE_SW`. It does **not** have a native Metal backend, nor does it expose a public `MPV_RENDER_API_TYPE_VULKAN` in `render.h` (Vulkan rendering in upstream mpv goes through `vo_gpu_next` / `vo_gpu` `ra_ctx` windowing contexts using `wid`, which on macOS uses `context_moltenvk.m` expecting `wid` to be a `CAMetalLayer *` or `NSView *`).
- **What AMP Gains by Using `wid` + `vo=gpu-next` + `gpu-context=moltenvk` vs `mpv_render_context` (OpenGL)**:
  - IINA still uses `mpv_render_context` with `MPV_RENDER_API_TYPE_OPENGL` wrapped in `CAOpenGLLayer` (which is deprecated by Apple, lacks native 16-bit/PQ HDR swapchain metadata, and runs through macOS's OpenGL-on-Metal translation layer).
  - By using `wid` + `vo=gpu-next` + `libplacebo` + `MoltenVK` + `CAMetalLayer`, AMP gets **direct Vulkan-to-Metal command buffers**, native `libplacebo` tone-mapping/gamut-mapping compute shaders, zero-copy `CVMetalTextureCache` (`hwdec=videotoolbox`), and direct `CAMetalLayer` EDR/PQ colorspace support. **Stay on `wid` + `vo=gpu-next` + `moltenvk`!**

### 2. Root Cause of the Stale `dst-rect` / Top-Left Quadrant Bug in `MPVViewController` (and the Proper Fix!)
Look closely at why `MPVViewController` (`MPVVideoView.swift:45-58, 224-315`) currently has to destroy and recreate the entire `MPVPlayer` on every fullscreen transition, live resize end, and initial layout jump:
- **How mpv's `context_moltenvk.m` works**:
  In mpv's `video/out/vulkan/context_moltenvk.m`:
  ```c
  struct priv {
      struct mpvk_ctx vk;
      CAMetalLayer *layer;
  };
  ```
  When `moltenvk_reconfig(struct ra_ctx *ctx)` or `ra_vk_ctx_resize` runs inside mpv's VO thread, how does mpv know the window/layer size changed?
  In upstream mpv (`context_moltenvk.m`), mpv polls `p->layer.drawableSize` inside `check_resize()` / `reconfig()`, **OR** in `ra_vk_ctx_Swapchain` when Vulkan returns `VK_ERROR_OUT_OF_DATE_KHR` / `VK_SUBOPTIMAL_KHR`!
  **Here is why it breaks in AMP**:
  1. **When paused** (or during `didEnterFullScreen` / `didExitFullScreen` / initial layout): No frames are being presented (`vkQueuePresentKHR` is not called), so MoltenVK never returns `VK_SUBOPTIMAL_KHR`, and mpv's VO thread is sleeping inside `vo_wait_frame`!
  2. **Even when playing**: In `context_moltenvk.m`, MoltenVK's `vkGetPhysicalDeviceSurfaceCapabilitiesKHR` reads **`layer.bounds.size * layer.contentsScale`** (or `layer.drawableSize`), AND in `MPVMetalLayer.swift:45`, AMP overrode `var drawableSize: CGSize`!
  3. In `MPVViewController.viewDidLayout()` (`MPVVideoView.swift:180`), AMP sets:
     ```swift
     metalLayer.frame = view.bounds
     metalLayer.contentsScale = scale
     metalLayer.drawableSize = newDrawableSize
     ```
     **First**: Changing `metalLayer.frame` and `metalLayer.drawableSize` from the main thread triggers Core Animation implicit `CATransaction` animations (`0.25s`) on `bounds`/`position`/`contentsScale` unless wrapped in `CATransaction.begin(); CATransaction.setDisableActions(true); ... CATransaction.commit()`! While the layer's `bounds` is animating over 0.25s, MoltenVK queries `layer.bounds` at the start of the animation and locks the Vulkan swapchain to the intermediate size!
     **Second**: Because `wid` points to `CAMetalLayer` directly (not an `NSView`), mpv's `vo_gpu_next` has **no `NSViewFrameDidChangeNotification` observer** in `context_moltenvk.m`! It only checks for resize when woken up or when a VO control event triggers `VO_EVENT_RESIZE`.
     **Third**: When `metalLayer.drawableSize` changes on the main thread while paused (or after a resize), how do you force `vo_gpu_next` to run `resize()` and redraw the current frame into the new `drawableSize` **without** destroying and recreating `mpv`?
     - Wrap `metalLayer.frame`, `metalLayer.contentsScale`, and `metalLayer.drawableSize` updates in:
       ```swift
       CATransaction.begin()
       CATransaction.setDisableActions(true)
       metalLayer.frame = view.bounds
       metalLayer.contentsScale = scale
       metalLayer.drawableSize = newDrawableSize
       CATransaction.commit()
       ```
     - In `MPVKit` (`context_moltenvk.m` in `profanitys1/MPVKit`), ensure `moltenvk_check_resize` checks `layer.drawableSize` every frame and sets `ctx->vo->dwidth = layer.drawableSize.width; ctx->vo->dheight = layer.drawableSize.height; return ra_vk_ctx_resize(ctx, ctx->vo->dwidth, ctx->vo->dheight);`.
     - From Swift (`MPVViewController`), whenever `drawableSize` changes while paused (or on `didEndLiveResize` / `didEnterFullScreen` / `didExitFullScreen`), instead of calling `.reloadPlayer` (which destroys `mpv`!), nudge a property that forces `reconfig` / `VO_EVENT_RESIZE` in `vo_gpu_next` or issue `command("seek", args: ["0", "relative+exact"])` (or toggle `video-rotate` / `video-Aspect-override` or `video-margin-ratio-left` `0.000001` → `0`) AFTER `CATransaction.commit()` once the fullscreen animation completes!
     - Better yet: in `PlayerView.swift:71`, stop passing an initially-tiny `surfaceSize` before `GeometryReader` has settled (`guard picture.width > 10, picture.height > 10`), and in `WindowConfigurator.swift:231`, remove the async `DispatchQueue.main.async { window.setFrame(711x400) }` that races with `applyInitialSize`!
       **LOOK AT `WindowConfigurator.swift:231-241`!**
       In `ConfiguratorNSView.viewDidMoveToWindow()`, it schedules a `DispatchQueue.main.async` that forces `window.setFrame` to `711×400`! When a file is opened on launch, `updateNSView` ALSO schedules a `DispatchQueue.main.async` to resize the window (`WindowConfigurator.swift:273`). Those two async blocks race with `MPVViewController.viewDidLoad()`! That is why `MPVViewController` attaches `metalLayer` at `711×400` (or `540×304`) and 16ms later jumps to `screen.visibleFrame`!
       Removing the redundant `DispatchQueue.main.async` in `viewDidMoveToWindow()` (since `.defaultSize(width: 711, height: 400)` on `WindowGroup` in `Aagedal_Media_PlayerApp.swift:62` already sets the initial window size!) eliminates the initial layout jump race at the source.

- **Effort**: M | **Risk**: Medium.

---

## C2. HDR / EDR on `CAMetalLayer` & Color Management Audit

### Review of Current Code (`DisplayColorController.swift`, `DisplayColorState.swift`, `MPVMetalLayer.swift`, `DisplayPeakBrightness.swift`)
1. **Reference White Bug in `DisplayPeakBrightness.swift:13` (100 nits vs 203 nits)**:
   - In `DisplayPeakBrightness.swift:13`:
     `static let sdrReferenceWhiteNits: CGFloat = 100`
   - Meanwhile, in `ScopeComputer.swift:292`:
     `/// AVPlayer linear-light → nits (1.0 = SDR reference white = 203 nits per BT.2408)`
   - **What does libplacebo / mpv use?**
     In `libplacebo` (`<libplacebo/colorspace.h>`, `PL_COLOR_SDR_WHITE`), SDR reference white is **203 nits** (ITU-R BT.2408)! And on macOS XDR displays (MacBook Pro 14"/16" Liquid Retina XDR, Pro Display XDR), `maximumPotentialExtendedDynamicRangeColorComponentValue` is the ratio of peak HDR luminance (1600 nits) to current SDR brightness (e.g., at 100 nits SDR brightness, headroom = 16.0; at 500 nits SDR brightness, headroom = 3.2).
     More importantly: when `MPVMetalLayer` sets `colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)` and `target-trc = pq`, **PQ (SMPTE ST 2084) is an absolute luminance encoding (0–10,000 nits)**!
     When you hand macOS a `CAMetalLayer` tagged with `CGColorSpace.itur_2100_PQ` and `wantsExtendedDynamicRangeContent = true`, macOS's WindowServer / DisplayPipe reads the PQ code values **as absolute nits** (where PQ 0.508 = 100 nits, PQ 0.581 = 203 nits, PQ 0.75 = 1000 nits) and maps them to the XDR panel's current brightness and EDR headroom **automatically in hardware**!
     **CRITICAL BUG in `DisplayColorController.swift:71-86`**:
     When `state.usesEDR == true`, `DisplayColorController` sets `target-trc = pq` AND sets `target-peak = Int(headroom * 100)`.
     Think about what happens on a MacBook Pro XDR indoors when the user's brightness slider is at 200 nits:
     - `maximumPotentialExtendedDynamicRangeColorComponentValue` is `1600 / 200 = 8.0` (or `maximumExtendedDynamicRangeColorComponentValue` is currently `8.0`).
     - `DisplayPeakBrightness` calculates `8.0 * 100 = 800 nits` and tells mpv `target-peak = 800`.
     - If the user's brightness slider is at 500 nits (outdoors/bright room), headroom is `1600 / 500 = 3.2`, so `DisplayPeakBrightness` tells mpv `target-peak = 320`!
     - Then `libplacebo` tone-maps a 1000-nit HDR10 video down to **320 nits in absolute PQ values** (`0.63` PQ), and hands that PQ buffer to `CAMetalLayer(itur_2100_PQ)`.
     - Then macOS WindowServer sees a PQ buffer peaking at 320 nits and **ALSO tone-maps or clips PQ relative to the display**, resulting in **double tone-mapping and crushed highlights**!
   - **How to Fix It**:
     1. Use `screen.maximumExtendedDynamicRangeColorComponentValue` (current available headroom) or `maximumPotential...`, multiplied by `203` (BT.2408 reference white, matching `PL_COLOR_SDR_WHITE = 203`), OR when outputting `itur_2100_PQ` to macOS EDR, set `CAEDRMetadata.hdr10(minLuminance:maxLuminance:opticalOutputScale:)` on `MPVMetalLayer` (`metalLayer.edrMetadata = CAEDRMetadata.hdr10(...)` on macOS) or set `target-peak` to the panel's true physical peak (1000–1600 nits on XDR) so `libplacebo` and macOS EDR don't double-compress highlights.
     2. Observe `NSApplication.didChangeScreenParametersNotification` to refresh `colorController` when EDR headroom changes dynamically.
2. **Missing `videoParamsPrimaries` Observation in `MPVPlayer.swift`**:
   Look at `MPVPlayer.swift:349`: `MPVPlayer` observes `videoParamsGamma`, `videoParamsSigPeak`, `videoParamsDw`, `videoParamsDh`, `videoParamsRotate`, `videoParamsPixelFormat`, **but it NEVER calls `mpv_observe_property(mpv, 0, MPVProperty.videoParamsPrimaries, MPV_FORMAT_STRING)`!**
   And in `MPVVideoView.swift:145`, `gammaObservation` triggers `colorController.refresh(screen:)` when `videoGamma` changes. If `video-params/gamma` arrives in the event queue *before* `video-params/primaries` is populated, `player.getString(MPVProperty.videoParamsPrimaries)` returns `nil`, so `DisplayColorState.decide` returns `.sdr`, and when `video-params/primaries` becomes `"bt.2020"` a millisecond later, **nothing re-triggers `colorController.refresh()`!**
   - **Fix**: Observe `MPVProperty.videoParamsPrimaries` in `MPVPlayer.swift` (`@Published var videoPrimaries: String?`) and combine `$videoGamma.combineLatest($videoPrimaries)` in `MPVViewController.viewDidLoad()`!
3. **Pixel Format of `MPVMetalLayer`**:
   Ensure `metalLayer.pixelFormat = state.usesEDR ? .bgr10a2Unorm : .bgra8Unorm` (or `.rgba16Float` for EDR if MoltenVK negotiates it; MoltenVK negotiates `VK_FORMAT_A2B10G10R10_UNORM_PACK32` = `.bgr10a2Unorm` when `target-colorspace-hint=yes` is set).

- **Effort**: S | **Risk**: Low.

---

## C3. Vsync & Frame Pacing (`CVDisplayLink`, ProMotion, `video-sync`, Interpolation)

### Current Setup Analysis
- AMP's custom `MPVKit-GPL` fork patches `context_moltenvk.m` (`0004`) to attach a `CVDisplayLink` bound to `screen-name` (`CGDirectDisplayID`) for vsync feedback.
- **Why `RenderProfile.playbackSyncOptions` (`RenderProfile.swift:128-133`) Is Currently Suboptimal**:
  Currently, `.off` ("Faithful") sets `video-sync=audio, interpolation=no`, while **all other profiles (including `.automatic`!)** force `video-sync=display-resample, interpolation=yes`.
  Consider what happens on a 14"/16" MacBook Pro with a **120 Hz ProMotion** display playing a **23.976 / 24.000 fps** movie under `.automatic`:
  - 120 Hz is an **exact 5× multiple of 24 fps** (`120 / 24 = 5`). There is **zero 3:2 pulldown judder** for 24p on a 120 Hz display!
  - Yet because `.automatic` forces `interpolation=yes` (`tscale=oversample`), `vo_gpu_next` has to run the output pass at **120 fps** instead of 24 fps (a **5× increase in output/compositing bandwidth and swapchain presentations**!), AND `GPUBudgetMonitor` (`GPUBudgetMonitor.swift:59`) switches the frame budget from `1000 / 24 = 41.6 ms` down to `1000 / 120 = 8.33 ms`, which causes `Automatic` to **step down and reject neural shaders** that easily fit in a 24 fps budget!
  - Look at `MPVPlayer.swift:622`:
    ```swift
    if displayRefreshRate > 60 {
        filtered = filtered.filter { !$0.contains("FSRCNNX") }
    }
    ```
    That workaround was added only because `interpolation=yes` was forced on 120 Hz displays!
- **The Right Vsync & Interpolation Policy**:
  1. **Default `interpolation=no` and `video-sync=audio` (or `display-tempo`)**, and make **"Motion Interpolation (Smooth 24/25p on 60Hz)"** an explicit user toggle in `PlaybackSettingsView` / `RenderSettingsView` (or an `"Auto (Only on 60Hz when FPS doesn't divide refresh rate)"` mode)!
  2. Specifically, interpolation (`tscale=oversample`) is only beneficial when `displayRefreshRate` is not an integer multiple of `sourceFPS` (e.g., 24p on a fixed 60 Hz external monitor, or 25p on 60 Hz). On a 120 Hz ProMotion display playing 24p, 30p, or 60p, `interpolation=no` gives **exact cadence**, **zero frame blending**, **5× larger GPU budget for neural upscalers**, and **significantly lower battery consumption**!

- **Effort**: S | **Risk**: Low.

---

## C4. Resizing / Fullscreen Transitions Without Flicker or Reload

To make live window resize and fullscreen transitions completely butter-smooth with zero flicker and zero player reloads:
1. In `MPVViewController.viewDidLayout()` and `setSurfaceSize(_:)`:
   Wrap all `metalLayer` geometry mutations in `CATransaction`:
   ```swift
   CATransaction.begin()
   CATransaction.setDisableActions(true)
   metalLayer.frame = view.bounds
   metalLayer.contentsScale = scale
   metalLayer.drawableSize = newDrawableSize
   CATransaction.commit()
   ```
   Without `CATransaction.setDisableActions(true)`, `CAMetalLayer` animates its `bounds` and `contentsScale` over 0.25s while `drawableSize` jumps immediately, causing severe stretching/flickering during live resize.
2. Set `metalLayer.presentsWithTransaction = false` (default) during playback, or during live resize allow `view.layerContentsRedrawPolicy = .duringViewResize` and `view.layerContentsPlacement = .scaleProportionallyToFit` so Core Animation scales the last presented Metal drawable smoothly between swapchain recreations instead of flashing black or pinning to the top-left corner.
3. On multi-display moves (`NSWindow.didChangeScreenNotification`), call `applyDisplayRefreshRate()` AND update `metalLayer.contentsScale = window.screen?.backingScaleFactor ?? 2.0` and `metalLayer.drawableSize` inside `CATransaction.setDisableActions(true)`.

- **Effort**: M | **Risk**: Low-Medium.

---

## C5. GPU Budget & Power Management (`GPUBudgetMonitor`)

### What's Missing Today
`GPUBudgetMonitor.swift` only checks `frame-drop-count` and `vo-passes`, ignoring **battery vs AC power** and **`ProcessInfo.processInfo.thermalState`**!
In fact, `RenderProfile.upscaleStrong` (`RenderProfile.swift:56`) says in its UI summary: *"Best for sub-1080p sources, on AC power"*, and `.efficient` says *"Light enough for battery"*, yet `ProfilePicker.swift` never checks power source or thermal state!

### Concrete Power & Thermal Policy
1. **Detect Battery & Low Power Mode**:
   Use `IOPSCopyPowerSourcesInfo()` / `IOPSGetProvidingPowerSourceType()` (`IOKit.ps`) and `ProcessInfo.processInfo.isLowPowerModeEnabled` + `ProcessInfo.processInfo.thermalState`:
   ```swift
   nonisolated enum SystemPowerState {
       static var isOnBattery: Bool {
           guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                 let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? else {
               return false
           }
           return type == kIOPSBatteryPowerValue
       }

       static var shouldThrottleGPU: Bool {
           let thermal = ProcessInfo.processInfo.thermalState
           return ProcessInfo.processInfo.isLowPowerModeEnabled
               || thermal == .serious
               || thermal == .critical
       }
   }
   ```
2. **Throttling Order under `Automatic`**:
   - **Step 1**: Disable `interpolation` (`tscale`) first when on battery or when `displayFPS` is an integer multiple of `sourceFPS`.
   - **Step 2**: If `SystemPowerState.shouldThrottleGPU` (Low Power Mode or `.serious`/`.critical` thermal state), cap `ProfilePicker` chains to `[.chroma, .off]` and skip `FrameAnalyzer`'s 8-frame `ffmpeg` background decode!
   - **Step 3**: If `SystemPowerState.isOnBattery`, cap `ProfilePicker.budgetFraction` from `0.8` down to `0.45` (so `ArtCNN_C4F16` / `nlmeans` steps down to `FSRCNNX` `.efficient` or `.chroma`).

- **Effort**: S | **Risk**: Low.

---

# Section D: Engine

## D1. `hwdec=videotoolbox(-copy)` Correctness on Apple Silicon

- **Zero-Copy (`hwdec=videotoolbox`)**:
  On Apple Silicon (M1–M5), VideoToolbox decodes H.264, HEVC (8/10/12-bit, 4:2:0 and 4:2:2), ProRes (422 Proxy/LT/Standard/HQ/4444/XQ), VP9, and AV1 (M3 and newer) into `IOSurface`-backed `CVPixelBuffer`s (`p010`, `nv12`, `p210`, `p416`, `bgra`).
  With `vo=gpu-next` + `gpu-context=moltenvk` (MoltenVK 1.4.2+), mpv's `hwdec_vt_pl.m` imports each plane of the `CVPixelBuffer`'s `IOSurface` directly into `MTLTexture` → `VkImage` (`VK_EXT_metal_objects`) with **zero CPU copy**.
- **When `videotoolbox-copy` Is Required**:
  `MPVPlayer.hwdecOptionValue` (`MPVPlayer.swift:175`) switches to `videotoolbox-copy` when `correctsReflection == true` because `vf=lavfi=[vflip]` is a CPU libavfilter graph.
  - **Better Fix for Reflection (`MPVDisplayTransform.swift`)**:
    Instead of using a CPU `vf=lavfi=[vflip]` filter (which forces `videotoolbox-copy` and copies every 4K frame back to RAM!), mpv has a native GPU VO property **`video-reversal` / `vf=vflip` or GLSL shader / `video-rotate` + `video-scale-x = -1` (`mpv_set_option_string(mpv, "video-scale-x", "-1")` or `"video-scale-y", "-1"`)**!
    Setting `video-scale-x=-1` (or `video-scale-y=-1` depending on rotation) is performed **inside `vo_gpu_next`'s vertex/transform matrix at zero cost** and keeps **zero-copy `hwdec=videotoolbox`**!
- **Codec Whitelist Bug (`HardwareDecodeCapabilities.swift:62`)**:
  In `HardwareDecodeCapabilities.isSupported(mpvCodec:)`, if `setupMPV()` runs before the background `DispatchQueue.global` probe finishes, `pending.wait()` blocks the `@MainActor`!
  Instead, `VTIsHardwareDecodeSupported` for 3 codecs takes <5 ms total; either read the lock non-blockingly or await a Swift `Task` in `preparePlayback()` alongside `proResRAWDetector`.

---

## D2. Demuxer / Cache Options for Local 4K/8K, Network, and Reverse Playback

- **Current State**:
  `MPVPlayer` leaves `demuxer-max-bytes` (mpv default: `150MiB`) and `demuxer-max-back-bytes` (mpv default: `50MiB`) untouched unless the user types a string into Settings (`PlaybackSettingsView.swift:92`).
- **Why `demuxer-max-back-bytes` Matters for JKL Shuttle & Scrubbing**:
  When a user steps backward (`,`), scrubs back a few seconds, or presses `J` to reverse-play a high-bitrate 4K ProRes or HEVC master (e.g. 200–400 Mbps = 25–50 MB/s), mpv's default `demuxer-max-back-bytes=50MiB` holds only **1 second** of demuxed packets behind the playhead! Any backward seek beyond 1 second forces a full demuxer index seek and packet flush.
  - **Recommendation**: Set sensible defaults in `setupMPV()` when the user hasn't overridden them:
    - `demuxer-max-bytes = 256MiB`
    - `demuxer-max-back-bytes = 128MiB`

---

## D3. Seeking, Scrubbing & Backward Frame-Stepping Performance

- **Scrubbing (`PlayerController.swift:591-624`, `PlayerScrubber.swift:72`)**:
  - **BUG in `PlayerScrubber.swift:32` (`FloatingOSCView`)**:
    Look at `FloatingOSCView.swift:109`:
    ```swift
    PlayerScrubber(
        item: controller.mediaItem,
        chapters: controller.chapterOptions,
        currentTime: controller.currentPlaybackTime,
        onScrub: { controller.seekTo($0) }
    )
    ```
    While `ControlsView` (used only in Compare Mode!) calls `controller.scrub(to:)` during drag and `controller.endScrubbing(at:)` on drag end, **`FloatingOSCView` (used for ALL normal single-file playback!) calls `controller.seekTo($0)` on every mouse drag pixel**!
    And `controller.seekTo($0)` (`PlayerController.swift:599`) calls `cancelPendingScrubSeeks()` and issues an **unthrottled `seek <time> absolute` (exact seek)** on every single mouse move event (60–120 times per second)!
    - **Fix**: Change `PlayerScrubber` to take `onScrub: (Double) -> Void` and `onEndScrub: (Double) -> Void`, calling `controller.scrub(to:)` during `.onChanged` and `controller.endScrubbing(at:)` in `.onEnded`! This immediately makes scrubbing in `FloatingOSCView` 10× smoother.
- **Frame Stepping (`seekByFrames` in `PlayerController.swift:573-581`)**:
  - **CRITICAL BUG**: Look at how `PlayerController.seekByFrames(_ frameCount: Int)` works today:
    ```swift
    func seekByFrames(_ frameCount: Int) {
        if let frameRate = mediaItem?.metadata?.primaryVideoStream?.frameRate,
           let frameRateValue = frameRate.value, frameRateValue > 0 {
            let secondsPerFrame = 1.0 / frameRateValue
            seek(by: Double(frameCount) * secondsPerFrame)
        } else { ... }
    }
    ```
    And `seek(by:)` reads `let currentTime = getCurrentTime() ?? 0` — which is `currentPlaybackTime`, the **0.1s-coalesced UI property** — and then calls `seekTo(currentTime + secondsPerFrame)`!
    1. If the user presses `.` (step forward 1 frame) twice within 100 ms, or on a VFR file, `currentPlaybackTime` hasn't even updated, or floating-point rounding lands on the same PTS!
    2. Even worse, for single-frame stepping (`frameCount == 1` or `frameCount == -1`) while paused on the MPV backend, mpv has dedicated, frame-exact commands **`frame-step`** and **`frame-back-step`**!
    - **Fix**: When `useMPV` and `abs(frameCount) == 1` (and not in Compare Mode), call `mpv.frameStep(forward: frameCount > 0)` which executes `command(forward ? "frame-step" : "frame-back-step")`! And when stepping by `±10` frames (`⇧↑`/`⇧↓`), base the target on `playbackTimeSnapshot()` (or `seek <seconds> relative+exact`), never the 100ms-stale `currentPlaybackTime`!

---

## D4. Startup Latency (Time-to-First-Frame Budget)

Trace what happens today when a user opens a file (`PlayerWindowCoordinator.openFile` → `PlayerController.loadMedia` → `preparePlayback`):
1. `PlayerWindowCoordinator.openFile` (`PlayerWindowCoordinator.swift:163`) awaits `loadMetadataWithTimeout(url: url, timeout: .milliseconds(500))`.
   Inside `MetadataService.loadMetadata`, for `.mov`/`.mp4`, it runs `SwiftMediaMetadata` AND then runs `avAssetRotation(for: url)` (`MetadataService.swift:89`), which creates an `AVURLAsset` and awaits `asset.loadTracks(withMediaType: .video)` and `track.load(.preferredTransform)`.
2. Then `controller.loadMedia(item)` calls `preparePlayback()`.
3. Inside `preparePlayback()` (`PlayerController.swift:318`), it spawns `playbackPreparationTask`:
   - If metadata timed out, `isProResRAWFile` creates a **second** `AVURLAsset` and awaits `loadTracks` + `formatDescriptions`.
   - Next, for every `.mov`/`.mp4`, it awaits `MPVDisplayTransform.requiresReflectionCorrection(url: url)` (`PlayerController.swift:321`), which creates a **third** `AVURLAsset` and awaits `asset.loadTracks(withMediaType: .video)` and `track.load(.preferredTransform)` **again**!
4. Only *after* all of those sequential `AVURLAsset` loads complete does `setupMPV()` run, which creates the `MPVVideoView`, waits for `attachDrawable`, calls `mpv_initialize`, and issues `loadfile`.
5. And if `HardwareDecodeCapabilities.shared.isSupported` hasn't finished its background probe on first launch, `applyCodecWhitelist()` blocks the main thread on `pending.wait()`.
6. Finally, when `MPV_EVENT_FILE_LOADED` fires, `startAnalysis()` (`MPVPlayer.swift:666`) spawns up to **9 `ffmpeg` subprocesses** (`FrameAnalyzer.shared.analyze`)!

### How to Cut Startup Latency in Half (<50 ms to First Frame):
1. **Compute `isReflected` inside `MetadataService.avAssetRotation` in a single `AVURLAsset` pass**:
   `MetadataService.avAssetRotation` (`MetadataService.swift:89`) *already* loads `preferredTransform`! Have it return `(rotation: Int?, isReflected: Bool)` and store `isReflected: Bool` on `MediaMetadata.VideoStream`. Then `MPVDisplayTransform.requiresReflectionCorrection` is an instant `O(1)` bool read from `cachedMetadata` instead of a second async `AVURLAsset` load!
2. **Use `video-scale-x = -1` for reflection** (from **D1**): Then `MPVPlayer` doesn't even need `correctsReflection` before `mpv_initialize()`—it can set `video-scale-x` at any time! That makes `setupMPV` **synchronous** inside `preparePlayback` when `cachedMetadata` is present!
3. **Reuse one persistent `MPVPlayer` / `MPVViewController` per window across file loads**:
   Currently, every time the user opens the next file in a folder (`⌘]`), `preparePlayback` calls `teardown()`, which calls `mpv_terminate_destroy`, destroys the `MPVViewController` (`.id(controller.preparationID)`), creates a brand new `MPVPlayer`, re-initializes Vulkan/MoltenVK, and re-compiles all GLSL shaders from scratch!
   If both the previous file and the new file use MPV (which is 99.9% of files—everything except ProRes RAW), simply calling `mpvPlayer.load(url: newURL, startTime: startTime, autostart: autoplay)` on the **existing** `MPVPlayer` instance skips Vulkan swapchain creation and shader compilation completely, dropping file-switch latency from ~250 ms to **~15 ms**!

---

## D5. Audio (`coreaudio` vs `avfoundation`, Exclusive Mode, Passthrough, Audio Device Switching)

- **`coreaudio` vs `avfoundation` AO**:
  mpv's default on macOS is `ao=coreaudio`, which is mature, supports multichannel layout negotiation, low-latency rate changes, and `audio-spdif` passthrough. Keep `ao=coreaudio` as default.
- **Exclusive Mode (`coreaudio-exclusive`)**:
  **Do NOT enable `coreaudio-exclusive=yes` by default** (and only offer it if passthrough requires hogging the device). Exclusive mode hogs the macOS `AudioDeviceID`, muting all other macOS apps/notifications and breaking system volume controls.
- **Audio Output Device Selection (`audio-device` property — VLC `⇧A` / Audio Menu)**:
  mpv exposes `audio-device-list` (an `MPV_FORMAT_NODE_ARRAY` of maps with `"name"` and `"description"`, e.g. `[{"name": "auto", "description": "Autoselect device"}, {"name": "coreaudio/BuiltInSpeakerDevice", "description": "MacBook Pro Speakers"}]`) and the read/write `audio-device` string property.
  Reading `audio-device-list` and binding `audio-device` gives AMP a native **Audio → Audio Device** menu and `⇧A` cycling with 30 lines of code!
- **Channel Routing Correctness (`AudioChannelRouting.swift:56`)**:
  `AudioChannelRouting.mpvAudioFilter` generates `lavfi=[pan=Nc|c0=c0|c1=0*c1...]`.
  - **Subtle Bug**: When `lavfi=[pan=6c|...]` is given numbered output channels (`6c`), FFmpeg's `af_pan` outputs an **unnamed** `6 channels` layout (`AV_CH_LAYOUT_NATIVE` / unknown mask) unless the input channel layout name (e.g. `5.1(side)` or `5.1`) is used as the first parameter to `pan=`! Stripping the channel layout mask can cause `ao=coreaudio` to misroute surround channels after the pan filter.
  - **Fix**: If the layout name is known (e.g. `"5.1"`, `"5.1(side)"`, `"7.1"`, `"stereo"`), emit `lavfi=[pan=\(layout)|c0=...]` so FFmpeg preserves the exact `AVChannelLayout` speaker mask!

---

## D6. Subtitles (`libass`, Fonts, PGS/VobSub, Delay/Scale)

- **`blend-subtitles` / HDR Subtitle Brightness**:
  On HDR/EDR video (`target-trc=pq`), `libass` subtitles rendered at full SDR white can either look blindingly bright (if mapped to peak) or dull. With `vo=gpu-next`, `libplacebo` maps subtitle overlays at SDR reference white (`sub-hdr-peak` default).
- **Recommended `setupMPV()` Subtitle Options**:
  - `sub-auto = fuzzy` (automatically discovers external subtitles in the same folder whose filename starts with the movie's name, matching VLC!).
  - `embeddedfonts = yes` (already mpv default, ensures MKV ASS attachments work).
  - Expose `sub-delay` (`Double`, seconds) and `sub-scale` (`Double`, default `1.0`) on `MPVPlayer` so the Subtitles menu and VLC hotkeys (`H`/`J` for `±50ms` delay, scale up/down) work live.
- **Bug Fix Reminder**: In `PlayerController.addSubtitle(url:)`, after calling `mpvPlayer?.addSubtitle(url: url)`, call `refreshAudioTrackOptions(playerItem: nil)` (or observe `track-list` in `MPVPlayer`) so the newly attached subtitle track immediately appears in the UI and is marked selected!

---

## D7. Network / Streaming & `yt-dlp`

- **Should AMP Support URLs / `yt-dlp`?**
  - **Direct HTTP/HTTPS/HLS (`http://`, `https://`, `.m3u8`)**: **Yes (`Open URL…` `⇧⌘U`)**. Both `libmpv` (via FFmpeg's `tls`/`hls` demuxers) and `AVPlayer` natively play direct HTTP/HTTPS MP4/MOV/HLS URLs. In post-production and QC workflows, reviewing a presigned S3 / Frame.io / cloud master URL directly without downloading a 50 GB file first is a killer feature.
  - **`yt-dlp` (`ytdl=yes`)**: Make it **opt-in** in Settings (looking for `/opt/homebrew/bin/yt-dlp` or `/usr/local/bin/yt-dlp`), and set `ytdl=no` by default.
  - **Security Considerations for Network URLs**:
    1. Only allow `https://` and `http://` schemes when opening a remote URL (never `file://`, `lavfi://`, `avdevice://`, `fd://`, or mpv `edl://` playlists from untrusted URLs—mpv's `edl://` and `memory://` pseudo-protocols can read local files if not disabled!).
    2. Set `mpv_set_option_string(mpv, "load-unsafe-playlists", "no")` in `setupMPV()`.

---

## D8. Multi-Window Synchronized Playback Design Soundness

- **Two Distinct Modes in AMP**:
  1. **Compare Mode (`CompareSessionController.swift`)**: Single-window A/B inspection. Uses `CompareTimelineMapping` + a 20–60 Hz `startDriftCorrection` loop (`CompareSessionController.swift:925`) with rate-nudging (`±50%` max, gain `2.0`) for MPV and lead-compensated seeks for AVPlayer. This is well-engineered and thoroughly guarded with `OperationGeneration`.
  2. **Multi-Window Transport Sync (`WindowManager.syncPlaybackControls`)**: Broadcasts discrete commands (`togglePlayback`, `seekBySeconds`, `seekByFrames`, `reverse`, `fastForward`) via `NotificationCenter`, plus one-shot `Align Windows to Current Timecode Once` (`⌘⇧S`). The UI (`TransportSyncStatusView.swift:283`) explicitly and honestly tells the user: *"Their playback clocks are independent; they are not continuously frame-locked."*
- **One Bug in Multi-Window Sync (`ContentViewCommandHandlers.swift:415-427`)**:
  In `.seekToSyncedTime(time)`, non-active windows receive the broadcast and call `controller.seekTo(seekPosition)`. However, if one window was playing and another was paused before pressing `⌘⇧S`, their play/pause states remain mismatched. Also, `syncTimecode` (`ContentViewCommandHandlers.swift:402`) reads `controller.currentPlaybackTime` (the 100ms-coalesced UI value) instead of `controller.playbackTimeSnapshot()`!
  - **Fix**: Change `let relTime = controller.currentPlaybackTime` on line 405 of `ContentViewCommandHandlers.swift` to `let relTime = controller.playbackTimeSnapshot()` so `⌘⇧S` aligns windows to the **exact frame** of the key window!

---

# Section E: Image Quality (Apple Silicon M1–M5)

## E1. Scalers (`lanczos` vs `ewa_lanczos` vs `ewa_lanczossharp` vs `spline36`) & `RenderProfile` Audit

- **Review of `MPVPlayer.applyScalerOptions()` (`MPVPlayer.swift:542-586`)**:
  The engineering commentary and choices in `applyScalerOptions()` are remarkably well-researched:
  - `scale = lanczos` (default in `.off` and most profiles), `dscale = mitchell`, `cscale = spline36`.
  - Leaving `correct-downscaling = yes`, `linear-downscaling = yes`, and `sigmoid-upscaling = yes` at mpv's defaults is 100% right.
- **Mistakes / Gaps Found in `ProfilePicker.swift` & `RenderProfile.swift`**:
  1. **4K → 4K/5K Cost Miscalculation in `ProfilePicker.estimatedMilliseconds` (`ProfilePicker.swift:55-68`)**:
     Look at `ProfilePicker.estimatedMilliseconds`:
     ```swift
     if sourcePixels <= pixels720p {
         base = cost.p720 * sourcePixels / pixels720p
     } else if sourcePixels <= pixels1080p {
         base = cost.p720 + (cost.p1080 - cost.p720) * (sourcePixels - pixels720p) / (pixels1080p - pixels720p)
     } else {
         base = cost.p1080 * sourcePixels / pixels1080p
     }
     return base * drawablePixels / referenceDrawablePixels
     ```
     **Why this is wrong in two ways**:
     - **First**: Neural luma doublers (`ArtCNN_C4F16`, `FSRCNNX_x2_8-0-4-1`) have a `WHEN` condition in their `.glsl` header (`//!WHEN OUTPUT.w NATIVE.w / 1.200 > OUTPUT.h NATIVE.h / 1.200 > *`)! When a **4K source (3840×2160)** is played on a **14" MacBook Pro fullscreen (3448×1940)** or a **4K monitor (3840×2160)**, `OUTPUT.w / NATIVE.w <= 1.0`, so **libplacebo skips `ArtCNN` / `FSRCNNX` completely**! Yet `estimatedMilliseconds` scales `cost.p1080` by `sourcePixels / pixels1080p = 4.0×` (estimating `31.0 * 4 = 124 ms`!) and rejects the profile!
     - **Second**: Even for shaders that run at `NATIVE` resolution (`nlmeans.glsl`, `CfL_Prediction.glsl`), their cost is a function of **`sourcePixels` ONLY**, NOT `sourcePixels * drawablePixels`! Multiplying `base` (which already scaled with `sourcePixels`) by `drawablePixels / referenceDrawablePixels` makes the cost model scale with `sourcePixels * drawablePixels` ($O(N^2)$ in resolution), which is physically wrong—a `HOOKED NATIVE` shader runs once per source pixel regardless of drawable size, while an `OUTPUT` shader runs once per drawable pixel!
     - **Fix**: Split `Cost` into `nativeCostPerMP` (scales with `sourcePixels`, gated on whether `drawablePixels > 1.2 * sourcePixels` for 2× prescalers) + `outputCostPerMP` (scales with `drawablePixels`).
  2. **Running 2× Neural Upscalers When Not Upscaling**:
     In `SourceClassifier.swift`, a clean 4K SDR file (`3840×2160`) is classified as `.clean`. Its chain is `[.upscaleLight, .sharpen, .chroma, .off]`. If the window is smaller than 4K, `.upscaleLight` fails the `124 ms` estimate and falls back to `.sharpen` (`SSimSuperRes.glsl` + `ewa_lanczossharp`), which **sharpens a 4K source that is being downscaled**!
     - **Fix**: In `ProfilePicker.pick`, if `drawablePixels <= sourcePixels * 1.05` (no upscaling is happening!), never pick `.upscaleLight`, `.upscaleStrong`, `.efficient`, or `.sharpen`—pick `.chroma` (for 4:2:0) or `.off`!

---

## E2. Chroma (`cscale`, `KrigBilateral`, `CfL_Prediction`, 4:2:2)

- **Clarification on `KrigBilateral.glsl` (and Bug in `MPVPlayer.swift:610` Comment)**:
  In `MPVPlayer.swift:610`, the comment says:
  `// KrigBilateral.glsl: Skip for 4:2:2 sources (trained on 4:2:0, may produce artifacts)`
  **Fact check**: `KrigBilateral.glsl` (by Shiandow) is **NOT a trained neural network**. It is an analytical **Kriging (Gaussian process spatial interpolation) + joint bilateral filter** that uses the local luma (`LUMA`) mean and variance in a neighborhood window to weight chroma samples during upsampling.
- **Why Both `CfL_Prediction.glsl` AND `KrigBilateral.glsl` Are Loaded Together in `.upscaleLight`, `.compressed`, `.crisp`, `.compressedGrain` (`RenderProfile.swift:71-85`) — HARMFUL REDUNDANCY!**
  Look at `RenderProfile.shaderFileNames` (`RenderProfile.swift:71-85`):
  ```swift
  case .upscaleLight:
      ["ArtCNN_C4F16.glsl", "CfL_Prediction.glsl", "PixelClipper.glsl", "KrigBilateral.glsl"]
  ```
  Both `CfL_Prediction.glsl` (Chroma-from-Luma linear regression prediction) and `KrigBilateral.glsl` hook `CHROMA` and define `//!WIDTH LUMA.w` `//!HEIGHT LUMA.h`!
  As soon as the first chroma shader (`CfL_Prediction.glsl`) runs, the `CHROMA` plane is **already upsampled to `LUMA.w × LUMA.h` (4:4:4)**!
  Therefore, putting `KrigBilateral.glsl` after `CfL_Prediction.glsl` either:
  1. Gets skipped by libplacebo because `CHROMA.w == LUMA.w` (`//!WHEN CHROMA.w LUMA.w <`), OR
  2. Runs a second redundant bilateral pass on already-upsampled chroma!
  - **Fix**: Remove `KrigBilateral.glsl` from every profile that already includes `CfL_Prediction.glsl`! Use `CfL_Prediction.glsl` as the single chroma reconstructor (it is faster, sharper on edges, and avoids KrigBilateral's bright-chroma ringing).
- **4:2:2 Handling**:
  Skip `CfL_Prediction.glsl` and `KrigBilateral.glsl` when `pixelFormat` contains `"422"` or `"444"` or `"rgb"` or `"gbr"` (currently `filterShadersForSource` in `MPVPlayer.swift:614` only filters `KrigBilateral` on `"422"` and forgets `CfL_Prediction` and `"444"`!).

---

## E3. Neural / Prescalers on Apple Silicon (M1–M5)

- **Performance & Quality Reality on M-Series GPUs**:
  - **`ArtCNN_C4F16.glsl` / `ArtCNN_C4F16_DS.glsl`**: Best quality-per-millisecond CNN luma doubler in 2026 (~4.5 ms for 720p, ~10 ms for 1080p on M1 Pro when `interpolation=no`; half that on M3/M4 Pro/Max). `C4F16_DS` (Denoise+Sharpen) is purpose-trained for compressed web/streaming 4:2:0 video.
  - **`ArtCNN_C4F32.glsl` (`.upscaleStrong`)**: ~2.3× the GPU cost of `C4F16` for ~0.08 dB PSNR gain. Only worthwhile on ≤720p sources on AC power.
  - **`FSRCNNX_x2_8-0-4-1.glsl` (`.efficient`)**: Fast (~3–5 ms on 1080p), good battery-friendly tier.
  - **`ravu-zoom-ar-r3.hook` (`.restore`)**: Arbitrary-ratio edge-directed LUT prescaler; good for odd SD dimensions (e.g. 480p/576p anamorphic), though `ArtCNN_C4F16_DS` generally beats it on blocky MPEG-2/H.264 SD.
  - **`nnedi3` / `Anime4K`**: Do not add `nnedi3` (slower and softer than `ArtCNN_C4F16`) or `Anime4K` (line-art warping hallucinates severe edge artifacts on live-action video).
- **Shipping Shaders in the App Bundle**:
  Currently (`RenderProfile.swift:141`), AMP expects users to manually populate `~/.config/mpv/shaders`! A first-time user installing AMP has **no `~/.config/mpv/shaders` directory**, which means **every single `RenderProfile` (including `Automatic`) silently does nothing out of the box**!
  - **Fix**: Bundle the core open-source shaders (`ArtCNN_C4F16.glsl`, `ArtCNN_C4F16_DS.glsl`, `CfL_Prediction.glsl`, `FSRCNNX_x2_8-0-4-1.glsl`, `SSimSuperRes.glsl`, `adaptive-sharpen.glsl`, `hdeband.glsl`, `nlmeans.glsl`, `PixelClipper.glsl`) inside `Bundle.main.resourceURL/Shaders` as the fallback when `~/.config/mpv/shaders` doesn't have the file!

---

## E4. Deband, Dither, Grain, `nlmeans`, and Sharpening

- **Deband**:
  In `RenderProfile.swift:92`: `var enablesDeband: Bool { self == .restore }`, while `.compressed` and `.compressedGrain` use `hdeband.glsl`.
  What if `~/.config/mpv/shaders/hdeband.glsl` is missing? Then `.compressed` has **no debanding at all**!
  - **Fix**: In `MPVPlayer.apply(profile:)`, if `profile == .compressed || profile == .compressedGrain` and `hdeband.glsl` is not in `filteredPaths`, fall back to mpv's built-in `libplacebo` debander (`deband=yes`, `deband-iterations=2`, `deband-threshold=35`, `deband-range=16`, `deband-grain=4`).
- **Dither**:
  mpv's `dither=fruit` + `dither-depth=auto` on a 10-bit `CAMetalLayer` is already optimal. Never use `error-diffusion` (Sierra-lite compute shader costs ~2 ms per 4K frame for zero visible difference at 10-bit).
- **AV1 Film Grain Synthesis**:
  With `vo=gpu-next` (`libplacebo`), hardware-decoded AV1 film grain synthesis is applied on the GPU automatically by `libplacebo`.

---

## E5. Tone Mapping & Gamut Mapping (HDR10 / HLG / Dolby Vision on SDR, EDR, and XDR)

- **When HDR Content Plays on an SDR Display (or when `hdrEnabled == false`)**:
  Currently, `MPVPlayer.setupMPV()` sets **no tone-mapping options**, relying on `libplacebo`'s defaults (`tone-mapping=spline`, `gamut-mapping-mode=perceptual`, `hdr-compute-peak=auto`).
  - `tone-mapping=spline` + `gamut-mapping-mode=perceptual` + `hdr-compute-peak=yes` in `libplacebo` 7.360+ is the state of the art (superior to `bt.2390` and `bt.2446a` for preserving mid-tone contrast while rolling off knees smoothly, and supports Dolby Vision Profile 5/8.1 RPU reshaping natively in `gpu-next`!).
  - Explicitly set `hdr-compute-peak=yes` and `allow-delayed-peak-detect=no` (or `yes` for power) so scene-by-scene dynamic peak detection works even on HDR10 files lacking static `MaxCLL`.
- **Inverse Tone Mapping of SDR on XDR Displays**:
  **Must ALWAYS be OFF (`inverse-tone-mapping=no`, the default).** AMP's `DisplayColorState` (`DisplayColorState.swift:26`) already enforces this by returning `DisplayColorState.sdr` (`usesEDR = false`, `wantsExtendedDynamicRangeContent = false`) whenever `HDRTransferResolver.resolve(colorTransfer: gamma) == .sdr`. Never stretch SDR into HDR.

---

## E6. Deinterlacing & Telecine

- **Current Issue in `MPVPlayer.swift:307`**:
  `setupMPV()` sets:
  ```swift
  checkError(mpv_set_option_string(mpv, "deinterlace", "auto"), context: "deinterlace")
  ```
  - **Wait**: With `hwdec=videotoolbox` (zero-copy hardware decoding), how does `deinterlace=auto` work in `vo=gpu-next`?
    `libplacebo` in `vo=gpu-next` has a built-in GPU deinterlacing pass (`bwdif`-style weave/bob/spatial filter in `libplacebo`), **OR** if a CPU `bwdif` filter is used, it requires `videotoolbox-copy`. Fortunately, `vo=gpu-next` supports GPU deinterlacing directly on hardware surfaces!
  - Expose `deinterlace` (`"no"`, `"yes"`, `"auto"`) in the **Video → Deinterlace** menu and bind VLC's `D` hotkey to cycle `Off → On → Auto` with OSD feedback (`"Deinterlace: On"`).

---

## E7. Automatic Per-Source Profile Selection & Objective Quality Verification

- **Signals Used Today (`SourceClassifier.swift`)**:
  `isHDR`, `topazTag`, `min(width, height) <= 720`, `bitsPerPixel < 0.07`, plus `FrameAnalyzer`'s 8-frame luma `detailRatio`, `blockiness`, and `noise`.
- **Two Improvements to `SourceClassifier` & `FrameAnalyzer`**:
  1. **Codec-Aware BPP Threshold**:
     Currently (`SourceClassifier.swift:61`), `lowBitsPerPixel = 0.07` is applied identically to **H.264, HEVC, and AV1**!
     A 1080p24 **AV1** or **10-bit HEVC** encode at `3.0 Mbit/s` has `bpp = 0.060`, which is visually transparent (equivalent to ~6.5 Mbit/s H.264), yet `SourceClassifier` classifies it as `.compressed` and runs `hdeband` + `nlmeans` + `ArtCNN_C4F16_DS` on it, smoothing away real film grain!
     - **Fix**: Multiply effective bitrate by codec efficiency factor before comparing against `lowBitsPerPixel`:
       - `av1`: `× 1.8`
       - `hevc` / `h265` / `vp9`: `× 1.4`
       - `h264` / `mpeg4`: `× 1.0`
       - `mpeg2video` / `prores` / `dnxhd`: `prores`/`dnxhd` are intra-frame masters and should **never** be classified as `.compressed`!
  2. **Avoid Spawning 9 `ffmpeg` Subprocesses During Startup (`FrameAnalyzer.swift`)**:
     - Do **not** spawn `ffmpeg -i` just to read `topazTag` (`FrameAnalyzer.swift:105`)! `MPVPlayer` already reads `metadata/by-key/videoai` (`MPVPlayer.swift:662`), and `SwiftMediaMetadata` reads container tags in-process. Dropping `topazTag(path:ffmpeg:)` eliminates 1 subprocess immediately.
     - Only run the 8-frame `FrameAnalyzer` if metadata classification is inconclusive (`.clean`) AND `drawablePixels > sourcePixels * 1.05` (the window is actually upscaling the video!) AND the Mac is not on Low Power Mode.
- **Objective Quality Verification in Tests**:
  Add an XCTest target test that invokes `mpv` / `ffmpeg` with `lavfi=[libvmaf]` or `ssim`/`psnr` on a synthetic test pattern (or uses `mpvPlayer.screenshotRaw()` before/after applying a profile) to verify that `.off` ("Faithful") is bit-exact within 8/10-bit rounding and `.chroma` improves chroma PSNR on 4:2:0 zone plates.

---

## E8. Harmful or Wasted GPU Work in the Current Quality Pipeline

1. **Forcing `interpolation=yes` (`tscale=oversample`) on 120 Hz ProMotion displays** for all non-Faithful profiles (`RenderProfile.swift:131`) — 5× extra VO output passes at 24 fps and shrinks the GPU budget by 5× (`GPUBudgetMonitor.swift:59`).
2. **Loading both `CfL_Prediction.glsl` and `KrigBilateral.glsl` in the same shader stack** (`RenderProfile.swift:71-85`).
3. **Selecting `.upscaleLight` / `.sharpen` on 4K sources when `drawablePixels <= sourcePixels`** (`ProfilePicker.swift:74`).
4. **Classifying ProRes / intra-frame masters or efficient AV1/HEVC encodes as `.compressed`** (`SourceClassifier.swift:77`) because codec is ignored in `bitsPerPixel`.
5. **Spawning 9 `ffmpeg` processes in `FrameAnalyzer` even on 4K files or when not upscaling** (`MPVPlayer.swift:666`).

---

# Section F: Product & UX

## F1. Top UX Gaps vs IINA & VLC Beyond Section A
1. **A→B Loop on the Timeline & Floating OSC**: Sync `trimIn`/`trimOut` with mpv's `ab-loop-a`/`ab-loop-b` when Loop is toggled while trim points exist! Right now, if a user sets `I` and `O` trim points and clicks the Loop button, AMP loops the **entire file** instead of the `I`–`O` trim range! Making Loop respect `[trimIn, trimOut]` when set (or adding "Loop Trim Range") is a massive UX win.
2. **Remaining Time Toggle in `FloatingOSCView`**: Clicking the right timestamp in `FloatingOSCView` should toggle `duration` ↔ `-remaining`.
3. **Picture-in-Picture (PiP)**: Easy on `AVPlayerView`, and achievable for `MPVMetalLayer` via `PIPViewController` (`PIP.framework` private API used by IINA/Firefox/Chromium) or Float-on-Top mini-window (`⌘0` + Float on Top).
4. **Audio / Subtitle Sync Offset UI**: Quick popover or menu items for `±50 ms` audio/subtitle delay.

## F2. Settings Organisation & First-Time User Defaults
- **First-Time Defaults Changes Recommended**:
  1. **Bundle the GLSL shaders inside the app** (`Bundle.main.resourceURL/Shaders`) so `RenderProfile.automatic` actually works out-of-the-box without requiring the user to install standalone `mpv` and populate `~/.config/mpv/shaders`!
  2. **Keymap Preset**: Add a prominent picker in `Shortcuts` & `General`: **"VLC Default"** vs **"AMP Pro (JKL)"**.
  3. **Window Sizing in `GeneralSettingsView`**: Fix the conflict between hidden `openMaximized = true` (`AppSettings.swift:26`) and visible `openAtSourceResolution = true` (`GeneralSettingsView.swift:37`). Make it a clear 3-option Picker: *Fit to Video Resolution*, *Maximize to Screen*, *Keep Window Size*.
  4. **Settings Window Size**: `SettingsView.swift:127` hardcodes `.frame(width: 480, height: 500)` with **9 tabs**, which truncates tab labels on macOS! Widen `SettingsView` to `width: 600, height: 520` and merge `Screenshots` + `Export` into one **Capture & Export** tab, and `Audio` + `Playback` into **Playback & Audio** (reducing 9 tabs to 7 so all tab icons+labels fit cleanly).

## F3. Accessibility & Localisation Readiness
- **Strengths**: AMP already has thoughtful accessibility labels, `PlaybackControlFocusRing`, `accessibilityAdjustableAction` on sliders/scrubber, `@Environment(\.accessibilityReduceTransparency)` (Liquid Glass fallback), and `@Environment(\.accessibilityReduceMotion)`.
- **Gaps**:
  - `FloatingOSCView` (`FloatingOSCView.swift:109`) lacks keyboard focus rings (`@FocusState`) unlike `ControlsView`, and its time labels lack accessibility labels (`"Elapsed time"`, `"Duration"`).
  - `PlayerScrubber` in `FloatingOSCView` does not yield Left/Right arrow keys when focused via Full Keyboard Access (`isTimelineFocused` is only bound to `ControlsView`, not `FloatingOSCView`!).

## F4. Perceived Performance (Launch, Window Open, Memory)
- **App Launch**: `HardwareDecodeCapabilities.shared.beginProbing()` runs on launch (`AppDelegate.swift:281`). Move `SparkleUpdater.shared` initialization (`Aagedal_Media_PlayerApp.swift:56`) from `App.init()` property initializer to `applicationDidFinishLaunching` so it doesn't delay first scene creation.
- **Memory Footprint**:
  - `MetadataService.cache` (`NSCache`) is unbounded by count; set `cache.countLimit = 128`.
  - `FrameAnalyzer.cache` (`FrameAnalyzer.swift:30`) is a plain `[Fingerprint: SourceAnalysis]` dictionary that grows forever; cap it at 256 entries.

## F5. Distribution (Sparkle, Notarization, Hardened Runtime, Sandbox)
- **Sandbox**: **Keep App Sandbox OFF** for direct/Homebrew distribution. A pro media player needs to automatically load adjacent external `.srt`/`.ass` subtitles, read sibling folder files for Next/Previous (`PlayerWindowCoordinator.siblingMediaFiles`), read `~/.config/mpv/shaders`, and read sidecar `.aagedal-compare.json` files without nagging the user with an `NSOpenPanel` on every folder!
- **Hardened Runtime Entitlements Required for Notarization**:
  - `com.apple.security.cs.allow-unsigned-executable-memory` (only if LuaJIT/JIT is linked in MPVKit; if Lua is disabled, not needed).
  - `com.apple.security.device.audio-input` — **NOT needed** (ensure it is absent so macOS never prompts for microphone permission).

## F6. Security Audit (`ffmpeg` Argument Injection, `keybindings.json`, Subtitles, URLs)

1. **HIGH-PRIORITY SECURITY BUG — `ffmpeg` Option/Protocol Injection via Filenames Starting with `-` or Containing `:` (`ExportCommandBuilder.swift:92`, `FFmpegService.swift:241`, `AudioWaveformGenerator.swift:292`, `ComparisonStillExporter.swift:415`, `FrameAnalyzer.swift:108, 122`)**:
   Look at how `url.path` is passed to `ffmpeg` across the codebase:
   `"-i", request.sourceURL.path` and `"-n", request.destinationURL.path`.
   Even though `Process.arguments` avoids shell interpretation, **`ffmpeg` itself parses its `argv`**:
   - If a local file in a folder is named `-protocol_whitelist` or `-filter_complex` (unlikely for an absolute path since `url.path` starts with `/`), `url.path` starts with `/` so `-` flag injection is mitigated for absolute paths.
   - **HOWEVER**, in `FFmpegService.loudnessArguments` (`FFmpegService.swift:229`):
     ```swift
     filter = "atrim=start=\(range.start):end=\(range.end),asetpts=PTS-STARTPTS," + filter
     ```
     (Safe because `Double`).
   - **AND in `MPVVideoFilter.lut3d` (`MPVVideoFilter.swift:36`)**:
     ```swift
     // ponytail: a path containing ' breaks the quoting; escape it when a LUT picker ships.
     static func lut3d(label: String, path: String) -> MPVVideoFilter {
         lavfi(label: label, graph: "lut3d=file='\(path)'")
     }
     ```
     If a file path passed into a `lavfi` graph contains `'` or `]` or `,`, it injects arbitrary libavfilter graph filters (such as `movie=` or `sendcmd`). Escape `\`, `'`, `:`, `[`, `]` before interpolating any path into a `lavfi` string!
   - Also pass `"-nostdin"` to **all** `FFmpegService` invocations (`ExportCommandBuilder.swift`, `ComparisonStillExporter.swift`, `AudioWaveformGenerator.swift`), not just `FrameAnalyzer.swift`! Without `"-nostdin"`, `ffmpeg` reads from stdin if it ever prompts or interprets interactive keys.
2. **`WaveMetadataReader.swift` & `CompareReviewSidecarStore.swift` Security**:
   The XML/XXE hardening in `WaveMetadataReader.preparedIXML` (`WaveMetadataReader.swift:212-286`) and integer overflow bounds in `CompareReviewSidecarStore.validate` (`CompareReviewSidecarStore.swift:267-305`) are **exemplary**—genuinely some of the most thorough defensive parsing I have seen in a macOS app.

---

# Section G: Testing & Verification

## G1. Automating GUI Behaviour Tests (VLC Parity) & Render-Quality Regressions
1. **Unit-Testing VLC Mouse/Scroll/Key Parity Without Flaky XCUITest**:
   - Construct synthetic `NSEvent`s in in-process XCTests using `NSEvent.mouseEvent(...)`, `NSEvent.keyEvent(...)`, and `CGEvent(scrollWheelEvent2Source:...)` -> `NSEvent(cgEvent:)`:
     - Feed synthetic scroll `NSEvent` sequences directly into `VideoScrollWheelHandler.handle(_:onVolumeStep:onSeekStep:)` to test the `1.0` Y threshold, `0.8` X threshold, `0.4s` axis lock, natural scrolling inversion, and momentum suppression in <1 ms!
     - Feed synthetic `mouseDown` (`clickCount: 1`, `clickCount: 2`) and `mouseDragged` (`< 3pt` vs `>= 3pt`) events directly into `VideoSurfaceInteractionView.InteractionNSView` hosted in an offscreen `NSWindow` to verify double-click fill-screen toggle and drag threshold.
     - Test both `.vlc` and `.ampPro` keymap presets via `PlayerView.handleKeyEvent` (just as `PlayerView`'s comment notes existing native key checks do).
2. **Render-Quality Regression Tests**:
   - Use `MPVPlayer.screenshotRaw()` on a deterministic synthetic test clip (e.g. a 2-second 720p 4:2:0 color-bars + zone-plate MP4 generated once in `setUpWithError` via bundled `ffmpeg -f lavfi -i testsrc2=...`) to assert:
     - `DisplayColorState.decide` outputs for SDR, HDR10 (PQ + BT.2020), HLG, and Dolby Vision.
     - `ProfilePicker` and `SourceClassifier` selections across H.264, HEVC, AV1, and ProRes.

## G2. Priority Tests to Add First
1. `VideoScrollWheelHandlerTests`: Y volume accumulation (`1.0`), X seek accumulation (`0.8`), `0.4s` axis lock, `isDirectionInvertedFromDevice`, momentum rejection.
2. `ResumePlaybackPolicyTests`: `< 3 min`, `< 5% & < 60s`, `> 95% & < 60s remaining` boundary conditions.
3. `KeymapPresetTests`: Verify every VLC hotkey and every AMP Pro (JKL) hotkey, plus verify that `isTextInputActive` / focused `NSTextView` blocks bare-key menu shortcuts (`t`, `m`, `j`, `l`, `space`).
4. `PlaybackVolumeTests`: Verify `0%` → `0`, `50%` → `79.37`, `100%` → `100.0`, `125%` → `107.72`.
5. `WindowFillScreenTests`: Verify `toggleFillScreen` saves/restores pre-maximize frame and handles `openMaximized` initial state.

---

# Section H: Final Output

## H1. Ranked TOP-30 Action List (By Impact / Effort)

| Rank | Action (Imperative, with File & Function References) | Impact | Effort | Risk |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Eliminate the 4 destructive `.reloadPlayer` hacks on resize/fullscreen** by wrapping `metalLayer` frame/scale/drawableSize updates in `CATransaction.setDisableActions(true)`, removing the racing async `setFrame(711x400)` in `WindowConfigurator.ConfiguratorNSView.viewDidMoveToWindow()`, and triggering a non-destructive VO resize/redraw instead of `mpv_terminate_destroy` (`MPVVideoView.swift:175-345`, `WindowConfigurator.swift:231`). | **Critical** | **M** | **Med** |
| **2** | **Fix `PlayerScrubber` in `FloatingOSCView` flooding mpv with unthrottled exact seeks during drag** by wiring `.onChanged` to `controller.scrub(to:)` (keyframe-throttled) and `.onEnded` to `controller.endScrubbing(at:)` (`PlayerScrubber.swift:72`, `FloatingOSCView.swift:109`). | **Critical** | **S** | **Low** |
| **3** | **Fix single-Character menu shortcuts (`t`, `m`, `j`, `l`) firing while typing in Review Notes or Timecode text fields** by removing bare-key `.keyboardShortcut` modifiers from `Aagedal_Media_PlayerApp.swift:127,173,193,199` (or gating them on `!isTextInputActive` and `!(NSApp.keyWindow?.firstResponder is NSTextView)`). | **Critical** | **S** | **Low** |
| **4** | **Add `VideoSurfaceInteractionView` (`NSViewRepresentable`) above `comparisonSurfaces` in `ComparePlayerView.swift:62`** to support double-click windowed fill-screen toggle, 3pt-threshold window drag from anywhere on the video, two-finger pinch (`>0.3`), right-click context menu, and scroll-wheel volume/seek. | **High** | **S** | **Low** |
| **5** | **Implement `WindowConfigurator.Coordinator.toggleFillScreen(_:)` (`WindowConfigurator.swift:127`)** with `savedPreMaximizeFrame` save/restore and a fallback 75%-screen / 1:1 source-size restore when the window started maximized via `openMaximized`. | **High** | **S** | **Low** |
| **6** | **Implement `VideoScrollWheelHandler` with VLC's exact constants** (`deltaY` threshold `1.0` → volume `±5%`, `deltaX` threshold `0.8` → seek `±3s`, `0.4s` axis lock, `isDirectionInvertedFromDevice` inversion, momentum filter on seek) and connect it to `VideoSurfaceInteractionView`. | **High** | **S** | **Low** |
| **7** | **Bundle the core
| Rank | Action (Imperative, with File & Function References) | Impact | Effort | Risk |
| :--- | :--- | :--- | :--- | :--- |
| **7** | **Bundle the core GLSL shaders inside the app bundle (`Bundle.main.resourceURL/Shaders`)** and update `ShaderLibrary` (`RenderProfile.swift:141-180`) to fall back to bundled shaders when `~/.config/mpv/shaders` does not contain a file, so `RenderProfile.automatic` works out-of-the-box for all users. | **Critical** | **S** | **Low** |
| **8** | **Fix frame stepping (`PlayerController.seekByFrames`, `PlayerController.swift:573`)** to use mpv's native `frame-step` / `frame-back-step` commands for `±1` frame steps and `playbackTimeSnapshot()` (instead of the 0.1s-coalesced `currentPlaybackTime`) for multi-frame jumps. | **High** | **S** | **Low** |
| **9** | **Stop forcing `interpolation=yes` (`tscale=oversample`) and `video-sync=display-resample` on 120 Hz ProMotion displays** in `RenderProfile.playbackSyncOptions` (`RenderProfile.swift:128-133`), restoring the 24p GPU frame budget from 8.3 ms back to 41.6 ms and cutting idle/playback GPU power substantially. | **High** | **S** | **Low** |
| **10** | **Observe `MPVProperty.videoParamsPrimaries` in `MPVPlayer.swift:349`** (`@Published var videoPrimaries: String?`) and combine it with `$videoGamma` in `MPVViewController.viewDidLoad()` (`MPVVideoView.swift:145`) so HDR/EDR detection never races on property arrival order. | **High** | **S** | **Low** |
| **11** | **Fix `DisplayPeakBrightness.sdrReferenceWhiteNits` (`DisplayPeakBrightness.swift:13`) and `DisplayColorController.applyTargetPeak` (`DisplayColorController.swift:71`)** to use BT.2408 `203` nits reference white and avoid double-tone-mapping PQ buffers when macOS WindowServer already maps `CGColorSpace.itur_2100_PQ` to EDR headroom. | **High** | **S** | **Low** |
| **12** | **Refresh `trackSelection` in `PlayerController.addSubtitle(url:)` (`PlayerController.swift:679`)** after `sub-add` (or observe `track-list` in `MPVPlayer`) so external subtitles added via menu or drag-and-drop appear immediately in the Subtitles menu. | **High** | **S** | **Low** |
| **13** | **Fix `ProfilePicker.estimatedMilliseconds` and `ProfilePicker.pick` (`ProfilePicker.swift:55-88`)** so 2× neural upscalers and `.sharpen` are never picked when `drawablePixels <= sourcePixels * 1.05` (e.g. 4K video on a 4K/14" screen), and split `NATIVE` vs `OUTPUT` shader cost scaling. | **High** | **S** | **Low** |
| **14** | **Remove redundant `KrigBilateral.glsl` from profiles that already run `CfL_Prediction.glsl`** (`RenderProfile.swift:71-85`), and update `MPVPlayer.filterShadersForSource` (`MPVPlayer.swift:610`) to skip both chroma shaders on `422`, `444`, and `rgb` pixel formats. | **High** | **S** | **Low** |
| **15** | **Make `SourceClassifier.classify` (`SourceClassifier.swift:58`) codec-aware** (scaling effective bits-per-pixel by `1.8×` for AV1, `1.4×` for HEVC/VP9, and exempting ProRes/DNxHD intra-frame codecs) so clean 10-bit HEVC/AV1 masters are not misclassified as `.compressed` and smoothed by `nlmeans`. | **High** | **S** | **Low** |
| **16** | **Implement switchable keymap presets ("VLC Default" vs "AMP Pro (JKL)")** in `KeyBindingAction.swift` and `PlayerKeyMap.swift`, backed by `AppSettings.keymapPreset`, while preserving `keybindings.json` user overrides on top. | **High** | **M** | **Low** |
| **17** | **Build the right-click video context menu (`voutMenu`)** in `VideoSurfaceInteractionView` using `ClosureMenuItem` (`A4`) with Play/Pause, Stop, Speed, Jump to Time, Audio/Video/Subtitles tracks, Aspect/Crop, Window Size, and Screenshot items. | **High** | **M** | **Low** |
| **18** | **Expose `@FocusedObject` for the active window's `PlayerController` in `ContentView.swift:221` and add top-level `Audio`, `Video`, and `Subtitles` `CommandMenu`s** in `Aagedal_Media_PlayerApp.swift` with live per-window track lists, checkmarks, delay controls, and window-sizing commands (`⌘0`–`⌘3`, Float on Top). | **High** | **M** | **Low** |
| **19** | **Raise maximum volume to 125% (`PlaybackVolume.swift`, `PlaybackVolumeSlider.swift:17`, `PlayerController.swift:56,488`)** with `mpv_set_option_string(mpv, "volume-max", "130")` and a 100% unity-gain tick mark/snap detent on the slider. | **Med** | **S** | **Low** |
| **20** | **Add `PlayerOSDController` and `PlayerOSDOverlayView` (`A7`)** to display transient top-right HUD pills (Volume, Seek/Time, Speed, Track/Aspect/Crop changes, Audio/Sub Delay) with debounced VoiceOver announcements across both MPV and AVPlayer backends. | **High** | **S** | **Low** |
| **21** | **Collapse the 28 separate `.onReceive(NotificationCenter.default.appCommandPublisher)` modifiers in `ContentViewCommandHandlers.swift` into a single `switch command` receiver**, and use `controller.playbackTimeSnapshot()` instead of `currentPlaybackTime` in `.syncTimecode` (`ContentViewCommandHandlers.swift:405`). | **Med** | **S** | **Low** |
| **22** | **Eliminate duplicate `AVURLAsset` loads during file open and replace `vf=lavfi=[vflip]` reflection with GPU `video-scale-x=-1`** (`MetadataService.swift:89`, `MPVDisplayTransform.swift`, `PlayerController.swift:321`, `MPVPlayer.swift:175`) so reflected QuickTime files keep zero-copy `hwdec=videotoolbox` and start faster. | **High** | **S** | **Low** |
| **23** | **Stop `FrameAnalyzer.topazTag` (`FrameAnalyzer.swift:105`) from spawning an extra `ffmpeg` subprocess** (read the tag from `SwiftMediaMetadata` / mpv `metadata/by-key/videoai`), and skip the 8-frame `ffmpeg` decode when not upscaling or when on Low Power Mode. | **High** | **S** | **Low** |
| **24** | **Add `SystemPowerState` (battery vs AC, `isLowPowerModeEnabled`, `ProcessInfo.thermalState`) to `ProfilePicker` and `GPUBudgetMonitor`** so battery playback favors `.efficient`/`.chroma` and thermal pressure steps down automatically. | **Med** | **S** | **Low** |
| **25** | **Implement `NowPlayingCoordinator` (`MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`)** (`A9`) with key-window ownership transfer and event-driven (non-polling) elapsed-time/rate updates so hardware media keys, AirPods, and Control Center work. | **High** | **M** | **Low** |
| **26** | **Implement `ResumePlaybackStore` and the non-blocking 10s countdown resume banner** (`A8`) following VLC's `<3 min` / `<5% & <60s` / `>95% & <60s` rules and `ask`/`always`/`never` preference. | **Med** | **M** | **Low** |
| **27** | **Fix `EnhancementSuggestionView`'s "Enhance Now" button (`PlayerView.swift:126`) overwriting the global `UserDefaults` profile across all windows** by adding a per-file/per-player session profile override on `MPVPlayer`, and fix `SleepPreventer.shared.forget` for `compareSession.secondaryController` (`ContentView.swift:369`). | **Med** | **S** | **Low** |
| **28** | **Add `-nostdin` to all `FFmpegService` argument builders (`ExportCommandBuilder.swift`, `ComparisonStillExporter.swift`, `AudioWaveformGenerator.swift`)**, preserve named speaker layouts in `AudioChannelRouting.mpvAudioFilter` (`AudioChannelRouting.swift:56`), and escape paths in `MPVVideoFilter.lut3d` (`MPVVideoFilter.swift:36`). | **Med** | **S** | **Low** |
| **29** | **Reuse the existing `MPVPlayer` instance when opening the next/previous file in the same window** (`PlayerController.preparePlayback`, `PlayerController.swift:299`) instead of calling `mpv_terminate_destroy` + `mpv_create` on every file change, cutting folder-navigation latency from ~250 ms to ~15 ms. | **High** | **M** | **Med** |
| **30** | **Decompose `PlayerController` (`ReversePlaybackController`, `ScrubCoordinator`, `HDRMetadataResolver`), deduplicate the 4 copy-pasted waveform generation blocks (`B5`), and migrate `PlayerController` to `@Observable`** to eliminate 10 Hz whole-window SwiftUI body re-evaluations. | **High** | **L** | **Med** |

---

## H2. Things AMP Should NOT Do (Bad Ideas Commonly Suggested)

1. **Do NOT switch from `wid` + `vo=gpu-next` (`moltenvk`) to `mpv_render_context` (`MPV_RENDER_API_TYPE_OPENGL`)**:
   IINA uses `mpv_render_context` only because IINA was architected around `CAOpenGLLayer` before `vo=gpu-next` and MoltenVK matured. `mpv_render_context` has **no Metal backend** in upstream libmpv; switching to it would force AMP onto Apple's deprecated OpenGL-on-Metal translation layer, lose native 10-bit/16-bit `CAMetalLayer` PQ EDR metadata, and add an extra FBO copy every frame. Fix the `CATransaction` / resize signaling on `MPVMetalLayer` instead.
2. **Do NOT enable `interpolation=yes` (`tscale=oversample` or `mitchell`) unconditionally**:
   On 120 Hz ProMotion Macs, 24 fps, 30 fps, and 60 fps all divide 120 Hz evenly (`5:5`, `4:4`, `2:2`). Running temporal interpolation on a 120 Hz display for 24p content blends frames unnecessarily, softens motion on a QC/inspection tool, forces the VO output chain to run 120 times per second instead of 24, and starves neural upscalers of 80% of their GPU frame budget.
3. **Do NOT enable `coreaudio-exclusive=yes` by default**:
   Exclusive mode hogs the macOS audio output device, breaking system notifications, voice calls, volume keys, and even a second AMP window or Compare Mode's secondary player if it ever touches audio.
4. **Do NOT use `dither=error-diffusion` on Apple Silicon**:
   `CAMetalLayer` on macOS renders to a 10-bit (`bgr10a2Unorm`) or 16-bit float (`rgba16Float`) drawable. At 10-bit output depth, `dither=fruit` (blue noise) is perceptually indistinguishable from Sierra-lite error diffusion, whereas `error-diffusion` dispatches a heavy shared-memory compute shader that costs 1.5–2.5 ms per 4K frame and drains battery.
5. **Do NOT enable `temporal-dither=yes`**:
   In a video player used for frame-by-frame QC, inspection loupes, and video scopes, `temporal-dither` causes noise patterns to crawl/flicker when pausing or stepping frames and alters `screenshot-raw` output between identical frames.
6. **Do NOT apply inverse tone mapping (`inverse-tone-mapping=yes`) or force EDR on SDR content**:
   Stretching Rec.709 SDR content into HDR headroom destroys creator intent and invalidates QC review. Keep `DisplayColorState.sdr` strictly `wantsExtendedDynamicRangeContent = false` with the display's ICC profile applied.
7. **Do NOT enable App Sandbox for the direct-download / Homebrew builds**:
   Sandboxing breaks automatic loading of external `.srt`/`.ass` subtitles alongside a video, breaks Next/Previous file traversal in the same folder (`PlayerWindowCoordinator.siblingMediaFiles`), breaks `~/.config/mpv/shaders` sharing, and breaks `.aagedal-compare.json` sidecar creation next to source files without forcing intrusive folder-permission prompts. Hardened Runtime + Notarization without App Sandbox is the right distribution model for a pro macOS media player.
8. **Do NOT use `Anime4K` shaders on general live-action video**:
   `Anime4K` uses gradient-ascent line-thinning/warping designed strictly for cel-shaded 2D animation; on live-action film or compressed web video it creates severe "oil-painting" and halo artifacts. Keep AMP's shader stacks centered on `ArtCNN`, `FSRCNNX`, and `CfL_Prediction`.
9. **Do NOT use `window.zoom(nil)` or replace SwiftUI's `NSWindow.delegate` to implement double-click Fill Screen**:
   Replacing SwiftUI's internal `AppKitWindowController` window delegate breaks `@FocusedValue`, `@FocusedObject`, scene lifecycle, and fullscreen state tracking. Always save/restore `savedPreMaximizeFrame` and call `window.setFrame(screen.visibleFrame, display: true, animate: true)` directly inside `WindowConfigurator.Coordinator`.
10. **Do NOT update `MPNowPlayingInfoCenter.default().nowPlayingInfo` on every `time-pos` tick**:
    Writing to `MPNowPlayingInfoCenter` at 10–60 Hz causes cross-process IPC churn with `mediaremoted` on macOS. Only update `nowPlayingInfo` on play/pause, rate change, track change, and explicit seeks; macOS calculates elapsed time automatically from `MPNowPlayingInfoPropertyElapsedPlaybackTime` and `MPNowPlayingInfoPropertyPlaybackRate`.
