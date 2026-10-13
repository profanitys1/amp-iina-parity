### Q1. `performDrag(with:)` vs. Double-Click Detection

**Behavior of `performDrag(with:)`:**
`NSWindow.performDrag(with:)` enters a synchronous, modal event-tracking loop on the main thread that consumes subsequent mouse-dragged and mouse-up events until the button is released. 
* **Stationary click:** It does **not** return immediately on `mouseDown`; it blocks until the corresponding `mouseUp` occurs.
* **Double-click impact:** If the user clicks and releases quickly without moving the mouse, `performDrag` returns upon the first `mouseUp`. When the second `mouseDown` arrives within `NSEvent.doubleClickInterval`, AppKit’s window server still increments `event.clickCount` to `2`. However, calling `performDrag` unconditionally on `mouseDown` is a known anti-pattern: any micro-movement during the first click initiates a window server move, which cancels the double-click sequence and consumes the `mouseUp` event that `NSView` subclasses normally rely on.

**Better Pattern:**
Do **not** call `performDrag` in `mouseDown`. Instead, defer `performDrag` to `mouseDragged` (using a ~3pt hysteresis threshold) and handle the double-click in `mouseDown` (or `mouseUp`) when `clickCount == 2`. This matches how `mpv` and `IINA` avoid eating double-clicks.

```swift
final class VideoInteractionView: NSView {
    private var initialMouseDownEvent: NSEvent?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false } // Prevent automatic AppKit drag

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            initialMouseDownEvent = nil
            toggleFillScreen()
        } else if event.clickCount == 1 {
            initialMouseDownEvent = event
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startEvent = initialMouseDownEvent else { return }
        let dx = event.locationInWindow.x - startEvent.locationInWindow.x
        let dy = event.locationInWindow.y - startEvent.locationInWindow.y
        if hypot(dx, dy) > 3.0 {
            initialMouseDownEvent = nil
            window?.performDrag(with: startEvent)
        }
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseDownEvent = nil
    }
}
```

---

### Q2. ZStack Hit-Testing, Hover, and `NSViewRepresentable`

* **Controls above `NSViewRepresentable` in `ZStack`:** SwiftUI views rendered inside the same `NSHostingView` above an `NSViewRepresentable` intercept mouse events first where they have hittable content (e.g., `Button`, `Slider`, or shapes with `.contentShape(Rectangle())`).
* **Transparent regions:** Transparent layout containers (`Spacer`, `VStack`, `Color.clear` without `.contentShape`) do **not** catch clicks in SwiftUI. Hit-testing falls through the SwiftUI layer into the underlying `NSViewRepresentable`'s `NSView`.
* **Ancestor `.onHover` / `.onContinuousHover`:** `NSHostingView` manages cursor tracking via an overarching `NSTrackingArea`. An `NSView` subview does **not** block ancestor `.onContinuousHover` unless the `NSView` installs a tracking area that overrides cursor/mouse-moved behavior without forwarding, or enters a modal loop (like `performDrag`, during which hover updates pause until mouse release).
* **Required `NSView` tweaks:**
  1. Override `acceptsFirstMouse(for:) -> Bool { true }` so clicking an inactive player window immediately drags or double-clicks without requiring an activation click first.
  2. Do **not** override `hitTest(_:)` to return `nil`—doing so would block `mouseDown`, `menu(for:)`, and `scrollWheel(with:)`.

---

### Q3. Right-Click Context Menu via `menu(for:)`

Overriding `menu(for event: NSEvent) -> NSMenu?` on your `NSView` is the cleanest way to replicate VLC’s context menu.

* **SwiftUI Hosting Pitfalls:** Avoid SwiftUI’s `.contextMenu` modifier on the `ZStack`. SwiftUI `.contextMenu` evaluates eagerly or applies blur/highlight effects to the target view, and cannot easily interleave dynamic `NSMenuItem` features (such as submenu delegates or mixed state checkmarks `.mixed`). `NSView.menu(for:)` bypasses SwiftUI’s gesture system cleanly.
* **Target/Action vs. Closures (Swift 6):** Because `NSView` and `NSMenu` are strictly `@MainActor` in the macOS SDK, target/action works, but closure-backed `NSMenuItem`s (avoiding `@objc` selector boilerplate and retaining strongly typed model values like track IDs) are much cleaner under Swift 6 strict concurrency:

```swift
@MainActor
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, state: NSControl.StateValue = .off, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
        self.state = state
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func invoke() { handler() }
}
```

---

### Q4. `scrollWheel` Accumulator and VLC Delta Math

* **How VLC works:** VLC’s macOS module (`VLCMainVideoView.m` / `VLCCoreInteraction.m`) reads `event.deltaY` and `event.deltaX` directly (not `scrollingDeltaY`).
* **Is `deltaY` already "line-ish" for trackpads?** Yes. Per Apple’s `NSEvent` documentation:
  * When `hasPreciseScrollingDeltas == false` (discrete mouse wheel), `deltaY` and `scrollingDeltaY` both represent lines (typically `±0.1` to `±3.0` per notch depending on acceleration).
  * When `hasPreciseScrollingDeltas == true` (trackpad / Magic Mouse), `scrollingDeltaY` is in **points/pixels**, whereas `deltaY` is synthesized by AppKit into coarse line-equivalent units (`scrollingDeltaY * 0.1` approximately, with curve adjustments).
* **Scaling `scrollingDeltaY` to match `deltaY`:** You don't need to manually scale `scrollingDeltaY` if you want exact VLC behavior—just use `event.deltaY` and `event.deltaX` directly (they are not deprecated). If you prefer using `scrollingDeltaY`, divide by `10.0` when `hasPreciseScrollingDeltas` is `true`.
* **Momentum events:** VLC **includes** momentum events (`event.momentumPhase != []`) for volume and seeking, which allows a flick on a Magic Trackpad to smoothly scrub or sweep volume. However, if you map scroll to discrete actions (e.g., frame-step or playlist item skip), filter out `event.momentumPhase != []`.

```swift
override func scrollWheel(with event: NSEvent) {
    let isDirectionInverted = event.isDirectionInvertedFromDevice
    let dy = isDirectionInverted ? -event.deltaY : event.deltaY
    let dx = isDirectionInverted ? -event.deltaX : event.deltaX

    // VLC thresholds: Y = 1.0, X = 0.8
    accumY += dy
    accumX += dx
    if abs(accumY) >= 1.0 {
        let steps = (accumY > 0) ? 1 : -1
        adjustVolume(steps: steps)
        accumY = 0
    }
    if abs(accumX) >= 0.8 {
        seekByScroll(delta: dx)
        accumX = 0
    }
}
```

---

### Q5. Dynamic Top-Level Menus (Audio / Video / Subtitles)

* **Does `CommandMenu` + `ForEach` over `@Observable` work in macOS 26?**
  Mostly yes for simple lists, **but** SwiftUI’s `.commands` builder still has well-known limitations:
  1. Updating an `@Observable` property watched inside `.commands` causes SwiftUI to diff and rebuild the entire `NSMenu` hierarchy on the main thread, which can stutter if properties change frequently (like timecodes).
  2. In multi-window or state-restoration scenarios, `.commands` often fails to re-evaluate immediately when focus changes or when nested submenus are already open.
* **Does SwiftUI wipe manually inserted `NSApp.mainMenu` items?**
  **Yes.** Whenever SwiftUI re-evaluates the `App.body` or `.commands` block, `NSApplication.shared.mainMenu` is reconciled by SwiftUI’s internal menu coordinator, which strips or reorders unknown top-level `NSMenuItem`s that it didn't create.
* **Best Practice Hybrid Pattern:**
  Declare the top-level menus (`Audio`, `Video`, `Subtitles`) using SwiftUI `CommandMenu("Audio") { ... }` so SwiftUI owns the top-level menu bar slot and never wipes it. Then, inside `applicationDidFinishLaunching` (or an `@Observable` menu manager), locate those `NSMenu` instances by title (or identifier) in `NSApp.mainMenu`, and attach an `NSMenuDelegate` implementing `menuNeedsUpdate(_:)`. Because `menuNeedsUpdate(_:)` fires lazily right as the user opens the menu, you can clear and populate the track items via AppKit `NSMenuItem`s on demand with zero background overhead.

---

### Q6. `MPNowPlayingInfoCenter` & `MPRemoteCommandCenter` (Non-AVPlayer)

* **`AVAudioSession`:** Does not exist on macOS. `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` work out of the box with CoreAudio / `libmpv`.
* **Must `playbackState` be set explicitly?** **Yes, this is critical on macOS.** Unlike iOS (which infers playback state from the audio session), macOS `mediaremoted` will **ignore** your app and will not route hardware media keys (`F7`/`F8`/`F9`) or Control Center controls to it unless you explicitly transition `MPNowPlayingInfoCenter.default().playbackState` between `.playing`, `.paused`, and `.stopped`, **and** register at least one handler on `MPRemoteCommandCenter`.
* **Supported Commands:**
  * `togglePlayPauseCommand` (Hardware Play/Pause key)
  * `playCommand` / `pauseCommand` (Control Center / AirPods / TouchBar)
  * `nextTrackCommand` / `previousTrackCommand` (Hardware F9 / F7 short press)
  * `seekForwardCommand` / `seekBackwardCommand` (Hardware F9 / F7 click-and-hold)
  * `skipForwardCommand` / `skipBackwardCommand` (If enabled, replaces Next/Prev track buttons in Control Center with `+15s`/`-15s` buttons)
  * `changePlaybackPositionCommand` (Scrubbing bar in Control Center / Notification widget)
* **NowPlaying Info Keys for Scrubbing:** Do not update `MPNowPlayingInfoPropertyElapsedPlaybackTime` every frame. Set it only on play, pause, seek, or rate change, alongside `MPMediaItemPropertyPlaybackDuration` and `MPNowPlayingInfoPropertyPlaybackRate` (`1.0` or `0.0`). macOS interpolates the progress bar automatically.
* **Entitlements / Sandbox:** No special entitlements or `Info.plist` keys are required under the App Sandbox for `MediaPlayer.framework`.

---

### Q7. "Fill Screen, Stay Windowed" Toggle

* **Does `contentAspectRatio` constrain programmatic `setFrame(_:display:animate:)`?**
  **No.** Per Apple’s `NSWindow.contentAspectRatio` documentation, aspect ratio constraints are enforced during **interactive user resizing** (dragging window edges). Programmatic calls to `setFrame(_:display:animate:)` bypass `contentAspectRatio` and will set the window to `screen.visibleFrame` verbatim.
  * *Caveat:* As soon as the user touches a window edge while in "fill screen" mode, the window will violently snap back to the `contentAspectRatio`. Furthermore, if `contentAspectRatio` is active alongside SwiftUI’s `NSHostingView` sizing constraints, AppKit can log layout constraint warnings.
* **`setFrame` vs. `NSWindow.zoom(_:)` + `windowWillUseStandardFrame(_:defaultFrame:)`:**
  * **Using `zoom(_:)`:** Implementing `windowWillUseStandardFrame` to return `window.screen?.visibleFrame ?? defaultFrame` integrates natively with macOS: double-clicking the title bar (if enabled), clicking `Window -> Zoom` in the menu bar, and Option-clicking the green traffic light button will all use your fill-screen logic, and AppKit automatically stores the pre-zoomed restore frame.
  * **Using manual `setFrame`:** Gives you explicit control over saving `savedFrame: NSRect?` and temporarily setting `window.aspectRatio = .zero` (or clearing `resizeIncrements`) while filled, then restoring both the old `frame` and `contentAspectRatio` when toggling back. For a VLC clone where `contentAspectRatio` is used heavily, **manual `setFrame` with saved state (or temporarily clearing `contentAspectRatio` inside `windowWillUseStandardFrame`)** is safer.

---

### Q8. Per-File Resume Keys in a Sandboxed App

* **Keying by `url.path(percentEncoded: false)`:**
  * *Pros:* Simple `String` key in `UserDefaults`, human-readable, works across external drives mounted at `/Volumes/...` as long as the file isn’t moved/renamed. This is what VLC actually does.
  * *Cons:* Breaks if the user renames or moves the file.
* **Keying by Security-Scoped Bookmark `Data`:**
  * *Bad as a dictionary key:* Bookmark `Data` blobs are large (several KB each) and **non-deterministic**—creating two bookmarks for the same file produces different byte sequences, so you cannot use them as dictionary lookup keys.
* **Keying by `NSURLFileResourceIdentifierKey` (`url.resourceIdentifier`):**
  * Returns an opaque `NSObject` (inode/volume ID tuple) that survives renames/moves on the same volume, **but** Apple explicitly documents: *"This value is not persistent across system restarts."* Do **not** persist it in `UserDefaults`.
* **Recommended Pattern:**
  1. For simple VLC parity: Key `UserDefaults` by `url.standardizedFileURL.path(percentEncoded: false)` (or a SHA-256 hash of it + file byte size) in an LRU dictionary capped at ~1,000 entries.
  2. If you want rename-resilience: Obtain the persistent file reference ID via `CGWindow` / Carbon `FSRef` equivalents or extract the inode (`FileAttributeKey.systemFileNumber`) + volume UUID (`URLResourceKey.volumeUUIDStringKey`). The tuple `"<volumeUUID>:<inode>"` is small, deterministic, survives file moves/renames on APFS, and persists across reboots.

---

### Q9. Transient OSD Text Overlay (`SwiftUI` vs `mpv show-text`)

Use a **SwiftUI overlay with `.allowsHitTesting(false)`** placed at the top of your `ZStack`.

* **Why it beats `mpv show-text`:**
  1. **Dual-backend consistency:** You support both `libmpv` and `AVPlayerView`. Using SwiftUI means you write the OSD once, with identical typography, SF Symbols (e.g., speaker icons), animations, and localization across both backends.
  2. **Rendering resolution:** When playing low-resolution video (e.g., 480p), `mpv` OSD scales with the VO surface or requires `osd-scale-by-window` tuning and libass font configuration, whereas SwiftUI renders crisp Retina vector text at native display resolution regardless of video dimensions.
* **Will it be hidden behind `CAMetalLayer` (`wid`)?**
  **No, provided the host `NSView` is layer-backed (`wantsLayer = true`).** In modern macOS (and mandatory in macOS 26), `NSHostingView` uses a flattened CoreAnimation layer tree. When `libmpv` attaches a `CAMetalLayer` to your `NSViewRepresentable`’s `NSView` (or as a sublayer), SwiftUI sibling views declared *after* the video view in the `ZStack` have higher `zPosition` / sublayer ordering in the `NSHostingView` layer tree and composite cleanly over the Metal surface in both windowed and native fullscreen spaces.

---

### Q10. Switchable Keymap: Local `NSEvent` Monitor vs. SwiftUI `.keyboardShortcut`

* **Event Dispatch Order (Which Wins?):**
  When a key event enters `NSApplication.sendEvent(_:)`:
  1. Registered **local `NSEvent` monitors** (`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`) run **first**, before `sendEvent` dispatches the event to the menu bar (`NSApp.mainMenu.performKeyEquivalent(with:)`) or the key window (`performKeyEquivalent` -> `keyDown`).
  2. **Therefore, your local `NSEvent` monitor wins.** If your monitor handles `⌘↑` and returns `nil`, the menu item never sees the event (though the top-level menu bar title won't briefly flash).
  3. *Exception:* System-reserved shortcuts and certain single-key equivalents when a text field (`NSTextView`) is first responder—always guard your local monitor by checking reading focus:
     ```swift
     if let responder = window.firstResponder, responder is NSText { return event }
     ```

* **Reflecting Active Keymap Dynamically in Menu Shortcuts:**
  * **For modified shortcuts (`⌘↑`, `⌘F`):** Bind the `.keyboardShortcut()` modifier on your menu commands to your `@Observable` keymap model:
    ```swift
    Button("Volume Up") { player.volumeUp() }
        .keyboardShortcut(keymap.volumeUpKey.keyEquivalent, modifiers: keymap.volumeUpKey.modifiers)
    ```
  * **For single unmodified keys (`Space`, `E`, `A`, `C`, `S`, `L`, `J`, `K`):**
    If you attach `.keyboardShortcut("e", modifiers: [])` to a SwiftUI menu item, macOS will intercept `"e"` **globally inside the app**, breaking typing in search fields, Go-to-Time dialogs, or subtitle delay text boxes!
    * **How VLC handles this:** Do **not** use SwiftUI `.keyboardShortcut(..., modifiers: [])` for bare letter keys if your app has any text inputs, or if you use the `NSMenuDelegate` approach (from Q5), set `menuItem.keyEquivalent = "e"` and `menuItem.keyEquivalentModifierMask = []` **only** when a text field is *not* first responder (via `menuNeedsUpdate`), and handle the actual trigger in your `VideoInteractionView.keyDown(with:)` or local `NSEvent` monitor (where you can filter out `firstResponder is NSText`).
    * To prevents the macOS error beep (`NSBeep`) when handling bare keys in a local monitor, return `nil` from the monitor for any recognized key.
