Here are the precise answers for building your macOS video player app with Swift 6 and strict concurrency.

### Q1. `performDrag` and Double-Click Detection
**Does `performDrag` break detection of the second click?**
No, `performDrag(with:)` is a modal tracking loop that behaves well. If the mouse doesn't move, it returns immediately on `mouseUp`. The WindowServer maintains the `clickCount` threshold independently, so the subsequent `mouseDown` will correctly register `clickCount == 2`.

**Stationary click behavior:** 
A stationary click inside `performDrag` returns immediately. However, optical mice and trackpads often register 1-2 points of jitter, which can unintentionally trigger a visual window drag and consume the `mouseUp`.

**Better Pattern (Distance Threshold):** 
To avoid accidental tiny drags, capture the initial `mouseDown` and initiate `performDrag(with:)` only in `mouseDragged` after a 3pt threshold.

```swift
@MainActor
final class DragView: NSView {
    private var initialMouseDown: NSEvent?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Toggle fill-screen
            initialMouseDown = nil
        } else {
            initialMouseDown = event
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = initialMouseDown else { return }
        let dx = event.locationInWindow.x - start.locationInWindow.x
        let dy = event.locationInWindow.y - start.locationInWindow.y
        if hypot(dx, dy) > 3.0 {
            // Must pass the ORIGINAL mouseDown event
            window?.performDrag(with: start)
            initialMouseDown = nil // Prevent re-triggering
        }
    }
}
```

### Q2. Hit Testing and Hover Blocking
**Will the NSView block SwiftUI hover/ancestors?**
If the `NSView` is transparent and does not explicitly track hover, it will not block an ancestor's `.onHover`. Hover events in SwiftUI are driven by underlying `NSTrackingArea`s, which evaluate the hit-tested view hierarchy. 

**Do transparent overlay regions pass clicks down?**
Yes, in a `ZStack`, a SwiftUI overlay will pass clicks down to the `NSViewRepresentable` *if* the overlay is transparent and does not have a `.contentShape(Rectangle())` assigned. Use `.allowsHitTesting(false)` on purely visual overlay components to guarantee they don't intercept events.

**HitTest Tweaks:**
To ensure your transparent `NSView` catches clicks (since empty AppKit views return `nil` by default), override `hitTest(_:)` and `acceptsFirstMouse(for:)` so the user can drag/click even if the app is inactive.

```swift
override func hitTest(_ point: NSPoint) -> NSView? {
    // Return self so we catch clicks over the video layer
    return self.bounds.contains(point) ? self : super.hitTest(point)
}

override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
}
```

### Q3. Right-Click and `menu(for:)` Pitfalls
Overriding `menu(for:)` in your `NSView` works perfectly. The main SwiftUI-hosting pitfall is that `NSViewRepresentable` lifecycles can rebuild or recycle the view. 

**Target/Action vs Closures:** 
While macOS 14+ supports closures via `UIAction` in `NSMenuItem`, standard target/action remains the most robust pattern to avoid strict concurrency closure capture issues in Swift 6. 
*Rule of thumb:* Make your `NSViewRepresentable.Coordinator` the target, and route actions through `@objc` methods on the `@MainActor` coordinator. Retain a weak reference to the Coordinator inside the `NSView`.

```swift
let item = NSMenuItem(title: "Play", action: #selector(Coordinator.play), keyEquivalent: "")
item.target = coordinator
```

### Q4. scrollWheel Accumulator (VLC style)
**Delta scaling:**
To match VLC precisely, rely on `event.deltaY` and `event.deltaX`, *not* `scrollingDeltaY`. `deltaY` is already normalized by AppKit into "lines" (roughly 1.0 per detent on a traditional mouse). Trackpads emit fractional `deltaY` values.

VLC accumulates these values until the absolute sum crosses `1.0` for Y (volume) or `0.8` for X (seeking).

**Momentum Events:**
VLC historically includes momentum events, causing "drift" (seeking/volume keeps changing after lifting fingers). Modern Apple HIG recommends **ignoring momentum events** for discrete media controls.

```swift
private var scrollAccumulatorY: CGFloat = 0

override func scrollWheel(with event: NSEvent) {
    // Ignore momentum for precise media control
    guard event.momentumPhase.isEmpty else { return }
    
    scrollAccumulatorY += event.deltaY
    if abs(scrollAccumulatorY) >= 1.0 {
        let steps = Int(scrollAccumulatorY)
        // Adjust volume by `steps`
        scrollAccumulatorY -= CGFloat(steps)
    }
}
```

### Q5. Dynamic Top-Level Menus in SwiftUI
Yes, you can reliably use `CommandMenu` with `ForEach` observing an `@Observable` model. SwiftUI fully handles dynamic menu rebuilding at runtime on modern macOS.

**Do not manipulate `NSApp.mainMenu` manually.** 
If you manually append `NSMenuItem`s, SwiftUI's lifecycle (e.g., scene phase changes or window state changes) will eventually evaluate the `.commands` modifier, rebuild the menu tree from scratch, and wipe out your manual insertions. Use pure SwiftUI state:

```swift
@Observable final class TrackModel { var audioTracks: [Track] = [] }

// In App
.commands {
    CommandMenu("Audio") {
        ForEach(trackModel.audioTracks) { track in
            Button(track.name) { /* switch track */ }
        }
    }
}
```

### Q6. Now Playing / Media Keys for non-AVPlayer Apps
**Does it work without AVAudioSession?**
Yes. `AVAudioSession` does not exist on macOS. `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter` work flawlessly out of the box for apps rendering custom audio (CoreAudio/libmpv).

**PlaybackState:**
You **must** explicitly set `MPNowPlayingInfoCenter.default().playbackState = .playing` (or `.paused`). If you omit this, Control Center won't know the state and the Play/Pause icon will desync.

**Mapped Commands:**
Map `togglePlayPauseCommand`, `playCommand`, `pauseCommand`, `nextTrackCommand`, `previousTrackCommand`, and `changePlaybackPositionCommand`.

**Entitlements/Sandbox:**
No special sandboxing entitlements or `Info.plist` keys (like UIBackgroundModes) are required on macOS to receive media keys or populate the Now Playing center.

### Q7. "Fill Screen, Stay Windowed" Toggle
**Does `contentAspectRatio` constrain `setFrame`?**
Yes. If you call `window.setFrame(screen.visibleFrame)`, the window will strictly obey its `contentAspectRatio`. If the screen's aspect ratio differs from the video's, the window will stop expanding when it hits the aspect ratio limit, failing to fill the width or height of the screen bounds.

**Better approach: `NSWindow.zoom(_:)`**
Use `zoom(_:)` and configure the window's delegate. 
*   **Pros:** It properly fills the screen (ignoring aspect ratio for the window frame, while AVPlayer/libmpv letterboxes the video internally), animates beautifully via system APIs, and natively remembers its pre-zoomed frame to toggle back.
*   **Cons:** Requires overriding the delegate method.

```swift
// In NSWindowDelegate
func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
    return window.screen?.visibleFrame ?? newFrame
}
```
Trigger via `window.zoom(nil)` on your double-click.

### Q8. Per-File Resume Keying
**Any issue keying by path?**
Yes. In a sandboxed app, keying by absolute path is fragile. If the user moves or renames the file, the path breaks. If the bookmark resolves differently across app launches, the sandbox path might technically differ.

**Recommended Key:**
Use the `URLResourceKey.fileResourceIdentifierKey` (the APFS Object ID). This is a unique, persistent identifier that survives renames and moves on the same volume. Convert its data to a Base64 string to use as the `UserDefaults` dictionary key.

```swift
let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey])
if let fileID = values.fileResourceIdentifier as? Data {
    let defaultsKey = fileID.base64EncodedString()
    // Use as dictionary key for resume time
}
```

### Q9. Transient OSD Text (Volume, Position)
**SwiftUI Overlay vs mpv `show-text`:**
Use a **SwiftUI overlay with `.allowsHitTesting(false)`**. 

*   **Avoids Backend Coupling:** `show-text` is highly specific to `libmpv` and impossible to mirror to `AVPlayerView`. By placing the OSD in SwiftUI, you write it once for both backends.
*   **Layer Compositing:** Because your window uses `.hiddenTitleBar`, `fullSizeContentView`, and is layer-backed (due to `CAMetalLayer` in a SwiftUI `ZStack`), the SwiftUI OSD natively composites flawlessly *above* the Metal layer. It will not be hidden or clipped by the video renderer as long as it sits conceptually higher in the `ZStack`.

### Q10. Switchable Keymap Conflicts
**Which wins: `addLocalMonitorForEvents` or `.keyboardShortcut`?**
If you use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` and return `nil`, the monitor **wins**. The event is consumed, `performKeyEquivalent:` is bypassed, and the SwiftUI `.keyboardShortcut` will never trigger.

**Dynamically reflecting the active keymap in menus:**
If you want the top menu items to show the correct shortcut (e.g., swapping ⌘F vs F for fullscreen) based on the user's keymap preference, do not rely exclusively on a local monitor. Let SwiftUI's menu system handle it by passing dynamic `KeyEquivalent` values. 

In Swift 6 / modern SwiftUI, `.keyboardShortcut` accepts dynamic values. Expose your current keymap from an `@Observable` model:

```swift
@Observable final class KeymapManager {
    var isProMode = false
    
    var fullscreenKey: KeyEquivalent { isProMode ? "f" : "f" }
    var fullscreenModifiers: EventModifiers { isProMode ? [] : [.command] }
}

// In your SwiftUI menu:
Button("Fullscreen") { toggleFullscreen() }
    .keyboardShortcut(keymap.fullscreenKey, modifiers: keymap.fullscreenModifiers)
```
*Note:* For bare-letter keys (like `A`, `E`, `Space`) in the menu, ensure your video player's window is the first responder, otherwise they can interfere with text fields. You can optionally use the local event monitor *only* for unmapped or bare letter keys while returning the event normally so SwiftUI's menu `.keyboardShortcut`s continue to function and display accurately.
