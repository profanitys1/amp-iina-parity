# Video Quality Optimization & VLC-Like Playback Experience

- **Date:** 2026-10-13
- **Status:** Proposed / Draft
- **Target App:** Aagedal Media Player (AMP)
- **Deployment Target:** macOS 26.0+ (Apple Silicon)

---

## 1. Overview & Problem Statement

Users expect two core pillars from a modern desktop media player:
1. **Pristine Visual Fidelity with Low Resource Overhead:** Video rendering should deliver sharp edge reconstruction, smooth color gradients, and accurate HDR tone mapping without driving fans or draining laptop batteries.
2. **VLC Ergonomics & Intuitive Windowing:** Interacting with playback should feel familiar and effortless:
   - Double-clicking the video canvas must immediately toggle Fullscreen.
   - Starting a video must automatically maximize the window to fill the display border-to-border (top and bottom), letterboxing or pillarboxing the picture cleanly.
   - Single-clicking the video canvas toggles Play/Pause (without conflicting with double-click).
   - Trackpad and scroll wheel inputs provide volume and scrub navigation.

Currently in AMP:
- Mouse clicks on the video surface fall through unhandled; double-clicking does not toggle fullscreen.
- Window maximization (`openMaximized`) is latched after the very first media file, leaving subsequent videos at whatever arbitrary window frame remained.
- The default built-in mathematical scaler is standard `lanczos` without anti-ringing, debanding is disabled for clean/streaming profiles, and HDR tone mapping lacks an explicit curve standard.

---

## 2. Architecture & Detailed Component Design

### 2.1 Video Quality & Rendering Engine

AMP leverages `libplacebo` and mpv's `gpu-next` rendering backend over Vulkan (MoltenVK) rendering into an AppKit `CAMetalLayer`.

#### Core Tuning Parameters:
* **Luma / Main Upscaling:**
  * Upgrade default fallback scaling to `scale=ewa_lanczos` (Jinc) paired with `scale-antiring=0.7`.
  * For power-saving or high-fps playback (50/60+ fps), allow graceful fallback to `spline36` to guarantee zero dropped frames on any Apple Silicon display (including 120Hz ProMotion).
* **Chroma Reconstruction:**
  * Configure `cscale=spline36` with `cscale-antiring=0.7` (when standalone chroma shaders like CfL are not active).
* **Downscaling:**
  * Enforce `dscale=mitchell` and `correct-downscaling=yes` to maintain accurate luminance and avoid moiré when viewing 4K files on sub-4K viewports.
* **Sigmoid Upscaling:**
  * Enforce `sigmoid-upscaling=yes` to suppress dark halo artifacts around high-contrast edges.
* **Lightweight Gradient Debanding:**
  * Enable mpv's built-in debanding with minimal iterations: `deband=yes`, `deband-iterations=1`, `deband-threshold=35`, `deband-range=16`, `deband-grain=5`.
  * Eliminates color gradient banding in 8-bit web and streaming video without softening textures or sacrificing GPU milliseconds.
* **HDR Tone Mapping:**
  * Explicitly enforce `tone-mapping=bt.2390` in `MPVPlayer.swift` to ensure highlights roll off cleanly and shadow detail is preserved on Apple XDR/Retina displays.
* **Hardware Decoding:**
  * Maintain zero-copy `hwdec=videotoolbox` (`CAMetalLayer` texture import), keeping CPU usage near zero and eliminating memory copy penalties.

---

### 2.2 Window Management: Border-to-Border on Start

#### Window Geometry Policy:
* Whenever a media file is opened (`PlayerController.loadMedia` or playlist item transition):
  * Reset the single-shot maximization latch `hasMaximizedForMedia = false`.
  * `WindowConfigurator.Coordinator.applyInitialSize` evaluates `openMaximized`.
  * Call `maximize(window)`:
    * Sets window frame to `screen.visibleFrame` (from top menu bar to bottom dock/screen edge, across full screen width).
    * Clears `contentAspectRatio` constraint before setting frame to avoid AppKit clamping anomalies.
  * In `PlayerView.swift`, the video rendering surface is positioned using `CompareDisplayGeometry.aspectFitRect`, centering the picture and presenting black borders (letterboxing/pillarboxing) if the aspect ratio differs from the screen.

---

### 2.3 VLC Interaction & Gesture System

#### 1. Mouse Click Recognizers on Video Canvas
In `MPVViewController` (and `PlayerContainerView`):
* **Double-Click Recognizer (`doubleClickRecognizer`):**
  * Type: `NSClickGestureRecognizer`
  * `numberOfClicksRequired = 2`
  * Action: calls `player.toggleFullscreen()` -> `window?.toggleFullScreen(nil)`
* **Single-Click Recognizer (`singleClickRecognizer`):**
  * Type: `NSClickGestureRecognizer`
  * `numberOfClicksRequired = 1`
  * Action: calls `player.togglePause()`
  * Dependency:
    ```swift
    singleClickRecognizer.require(toFail: doubleClickRecognizer)
    ```
    Prevents single-click from triggering when a double-click is initiated.

#### 2. Trackpad & Scroll Gestures
* Implement `scrollWheel(with event: NSEvent)` in `MPVViewController`:
  * **Vertical Scroll:** Smoothly adjusts volume (`±2%` per scroll step, clamped to `0...100`), updating the HUD overlay.
  * **Horizontal Scroll:** Smooth relative seek by short jump (5 seconds forward/backward).

#### 3. Control Exclusion:
* Click recognizers are attached to the video surface underneath SwiftUI overlay controls.
* Clicks originating within `FloatingOSCView`, `ControlsView`, and overlay HUD buttons do not bubble down to trigger video play/pause or fullscreen.

---

## 3. Data Flow & Event Routing

```
[ User Interaction ]
   │
   ├─► Double Click on Video ──► MPVViewController ──► PlayerController.toggleFullscreen() ──► NSWindow.toggleFullScreen()
   │
   ├─► Single Click on Video ──► MPVViewController (after debounce) ──► PlayerController.togglePause()
   │
   ├─► Scroll Wheel (Vertical) ──► MPVViewController ──► PlayerController.volume += delta
   │
   └─► Open Video File ──► PlayerController.loadMedia() 
                               │
                               ▼
                       WindowConfigurator.applyInitialSize() ──► NSWindow.setFrame(screen.visibleFrame)
```

---

## 4. Error Handling & Edge Cases

1. **Multi-Window Isolation:**
   * Fullscreen toggles and sizing events reference `self.view.window` specifically, never globally broadcasting window bounds to sibling windows.
2. **Fullscreen Exit Restoration:**
   * When exiting fullscreen, the window returns to its maximized state rather than collapsing to the default 711×400 canvas.
3. **Rapid Double-Clicks:**
   * `require(toFail:)` prevents audio/video stutter from play/pause toggles during rapid double-clicking.
4. **Display Reconnection / Dynamic Resolution:**
   * `screenParametersObserver` updates display bounds if an external monitor is disconnected or changed.

---

## 5. Testing & Verification Plan

### Automated Unit Tests:
* `WindowConfiguratorTests`: Verify `shouldMaximize` returns true on new media file loads.
* `RenderProfileTests`: Verify default profile options include `scale=ewa_lanczos`, anti-ringing, and deband flags.

### Manual Verification Matrix:
1. **Fullscreen Toggle:** Double-click on video canvas enters fullscreen; double-click in fullscreen exits to maximized window.
2. **Single-Click Play/Pause:** Single-click pauses playing video; single-click resumes paused video. Double-click does not trigger pause.
3. **Window Launch:** Open a 16:9, 4:3, and 2.39:1 video file. Confirm the window starts filled from top to bottom of screen (border-to-border) with clean black bars.
4. **Scroll Volume:** Scroll vertically on trackpad/mouse; verify volume increments smoothly and HUD reflects change.
5. **GPU / Thermal Overhead:** Inspect Instruments / Activity Monitor GPU usage during 1080p and 4K playback. Verify GPU load stays well below 5-10% without heavy shaders, and thermals remain cool.
