As a second-opinion reviewer, I have analyzed AMP's current GUI implementation against the established behaviors of VLC for macOS (3.0.x stable branch). While AMP establishes a modern SwiftUI/Metal baseline, it lacks several core Mac-specific window paradigms and mouse/keyboard interactions that VLC users consider non-negotiable. 

Here is the comprehensive breakdown of behavioral differences, ranked by user impact, including implementation hints and critical pitfalls.

### 1. Video Surface Interactions (Mouse & Trackpad)
*   **VLC Behavior:** A double-click on the video toggles native macOS fullscreen. Vertical trackpad/scroll wheel dynamically adjusts volume in 5% increments. Clicking and dragging anywhere on the video surface moves the window. Right-clicking summons a dense contextual menu.
*   **AMP Gap:** The video surface is dead to mouse input. No double-click fullscreen, no scroll volume, no right-click. Window dragging is restricted to an invisible top titlebar strip.
*   **AppKit Hint:** Attach an `NSClickGestureRecognizer` (`numberOfClicksRequired = 2`) to the metal view for fullscreen. Override `scrollWheel(with:)` for volume. Override `mouseDownCanMoveWindow` returning `true` for window dragging. 
*   **Implementation Pitfalls:**
    *   **NSClickGestureRecognizer vs SwiftUI overlays:** Placing a SwiftUI layer (like `.onTapGesture`, even on `Color.clear`) over your `CAMetalLayer` completely swallows `NSEvent` routing. It will silently kill all underlying AppKit gesture recognizers on the video view.
    *   **Trackpad scroll floods:** Overriding `scrollWheel` blindly will break volume control. Mac trackpads fire hundreds of micro-events per second where `hasPreciseScrollingDeltas == true`. You must accumulate `event.scrollingDeltaY` and throttle it using `NSEvent.Phase` (or `momentumPhase`); otherwise, the volume will wildly snap from 0 to 100% in a single twitch.
    *   **Window dragging with `isMovableByWindowBackground`:** Setting this flag to `true` often fails if libmpv’s Metal view or AVPlayerView aggressively accepts the responder chain. You must explicitly subclass the AppKit video view and force it to return `true` for `mouseDownCanMoveWindow`.

### 2. Keyboard Navigation & Muscle-Memory Collisions
*   **VLC Behavior:** `Esc` escapes fullscreen. `S` stops playback entirely. `A` cycles aspect ratio, `C` cycles crop. `B` cycles audio tracks, `V` cycles subtitles. `Cmd+Up/Down` changes volume. `=` resets speed. `J/K` adjusts audio delay (±50ms), and `G/H` adjusts subtitle delay.
*   **AMP Gap:** Custom fullscreen traps users without an `Esc` exit. Critical toggles (A/C/B/V/S) are missing. Layout suffers from extreme hotkey collisions.
*   **AppKit Hint:** Use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` to catch `Esc` (keyCode 53) and unhandled shortcuts before they hit the responder chain.
*   **Implementation Pitfalls:**
    *   **Conflicts with JKL professional shortcuts:** AMP maps J/K/L to shuttle control (Rewind/Pause/Fast-Forward), mimicking Premiere/Final Cut. However, VLC permanently maps `J` and `K` to **Audio Delay**. This creates a severe muscle-memory collision. You must provide a "VLC Classic" vs "Professional" keyboard mapping preference.
    *   **System Error Beeps:** Overriding standard letter keys in AppKit without formally returning `true` via `performKeyEquivalent:` (or returning `nil` in the local monitor) will trigger macOS system error "boop" beeps on every single keystroke.

### 3. Window Sizing & Aspect Ratio Enforcement
*   **VLC Behavior:** On the first file load, the window resizes to exactly 1x the source media resolution (bounded by the display). During manual resize, the window *strictly* locks to the video's aspect ratio. `Cmd+1/2/3` scales the window to exactly 50/100/200%. `Cmd+Ctrl+T` floats the window on top. *(Note: VLC 4.0 alters the initial UI with a media library view, but 3.0 playback behavior remains the gold standard).*
*   **AMP Gap:** The first load randomly maximizes to `screen.visibleFrame`. Aspect ratio lock breaks during manual window resizing. No 1x/2x scale hotkeys or float-on-top.
*   **AppKit Hint:** Read the media dimensions and set `window.contentAspectRatio`. Use `window.setContentSize(_:)` for hotkey scaling. Set `window.level = .floating` for always-on-top.
*   **Implementation Pitfalls:**
    *   **Hidden Titlebar Aspect Math:** If AMP uses `hiddenTitleBar` combined with `fullSizeContentView`, `NSWindow`’s aspect ratio calculation will erroneously include the invisible 28pt title bar. This yields microscopic black borders on the sides during manual drag-resizing. You must manually offset your target aspect ratio math by the title bar height.
    *   **Retina Scaling:** A 1080p video on a Retina display will massively overflow the screen if you map 1:1 pixels. You must divide the raw media dimensions by the `NSScreen`'s `backingScaleFactor` before setting the frame size.

### 4. Floating HUD Controller & Cursor Detection
*   **VLC Behavior:** The floating HUD auto-hides after ~3s of inactivity, but the timer continuously *resets* as long as the mouse is moving. Clicking the elapsed time text toggles to remaining time. Volume overdrive reaches 125% (200% in older branches).
*   **AMP Gap:** A strict 2.5s auto-hide that ignores continuous movement. No time remaining toggle on click. Volume strictly capped at 100%.
*   **AppKit Hint:** Instantiate an `NSTrackingArea` with `[.mouseMoved, .activeInActiveApp]`. In `mouseMoved(with:)`, continuously invalidate and restart your 2.5s hide-timer.
*   **Implementation Pitfalls:**
    *   **SwiftUI vs Continuous Hover:** SwiftUI’s `.onHover` only detects boundary crossings (enter/exit); it cannot track continuous motion inside the view. You must bridge AppKit’s `mouseMoved` logic via `NSViewRepresentable`.
    *   **Cursor Hiding Desync:** If using `NSCursor.setHiddenUntilMouseMoves(true)`, ensure your programmatic HUD fading strictly syncs with the system cursor state. Otherwise, rapid gestures will result in a visible cursor but a hidden HUD.

### 5. Dynamic Top Menus (Main Menu)
*   **VLC Behavior:** A deeply integrated macOS native menu bar containing dedicated "Audio", "Video", and "Subtitles" top-level menus, allowing on-the-fly track selection, delay adjustments, and deinterlacing toggles.
*   **AMP Gap:** Media-specific top menus are completely missing (only File/View/Playback exist).
*   **AppKit Hint:** Generate `NSMenuItem` lists dynamically upon file load events using `NSMenuDelegate`.
*   **Implementation Pitfalls:**
    *   **SwiftUI Menu Rigidity:** Using SwiftUI’s `.commands` or `CommandMenu` to build dynamically changing lists (like unpredictable subtitle track lists) is notoriously rigid and rarely updates correctly mid-playback. You must drop down to `NSApplication.shared.mainMenu` and use `NSMenuDelegate`'s `menuNeedsUpdate(_:)` to reliably swap media track lists.

***

### 5 Non-GUI Improvements VLC Users Expect
1. **Resume Playback Position:** Storing last-played timestamps per file (via path or hash) and automatically seeking to that position on launch.
2. **System Media Keys & Now Playing:** Implementing `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter` to capture physical keyboard media keys (Play/Pause/Skip) and display media metadata in the macOS Control Center and Lock Screen.
3. **On-Screen Display (OSD) Text:** Rendering crisp white, black-outlined text directly over the video layer when hotkeys are pressed (e.g., popping up "Volume: 110%", "Audio Track: English", or "Subtitle Delay 50ms" without looking at the HUD).
4. **Hardware Acceleration Fallbacks:** A user preference to explicitly disable VideoToolbox/Metal and drop back to software decoding, which power users rely on heavily to bypass corrupted or exotic video encodes.
5. **A/V and Subtitle Sync Adjustments:** The underlying capability to dynamically shift audio and subtitle tracks forwards or backwards by precise milliseconds to fix out-of-sync files on the fly.
