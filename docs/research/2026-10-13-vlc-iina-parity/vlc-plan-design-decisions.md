# VLC behaviour plan: design decisions (coordinator, 2026-10-13)

These are binding for the plan writer. They resolve choices left open by `verified-vlc.md` and `verified-apple-apis.md`.

## Mouse surface
- New file `UI/VideoMouseSurface.swift`: `NSViewRepresentable` wrapping an `NSView` subclass.
- Insert it in `ComparePlayerView.swift` body ZStack between `comparisonSurfaces(...)…frame(...)` (:48-54) and `if compareSession.isActive { comparisonGuides… }` (:56). Only insert when `!compareSession.isActive`. Compare Mode keeps its own pointer behaviour.
- Single click: no action. Track `mouseDown`. In `mouseDragged`, once the pointer has moved ≥ 3 pt from the mouse-down location, call `window.performDrag(with: storedMouseDownEvent)`. This copies mpv and IINA: Apple says `performDrag` returns immediately and may swallow mouse-up. Once a drag starts, ignore a following clickCount==2 until the next fresh mouseDown (mpv zeroes its double-click timer).
- Double click (`event.clickCount == 2` in `mouseDown`, no drag in progress): post `AppCommand.toggleFillScreen`.
- Right click: `menu(for:)` returns VLC's voutMenu, in this order: Play/Pause, Stop, separator, Previous, Next, separator, Volume Up, Volume Down, Mute, separator, Fill Screen, Fullscreen, separator, Snapshot.
  - Use a small `ClosureMenuItem: NSMenuItem` (`@MainActor`, stores a closure, `target = self`).
  - Each item first calls `window?.makeKeyAndOrderFront(nil)`, then posts the AppCommand: `.togglePlayback`, `.stop` (new), `.openPreviousFile`, `.openNextFile`, `.adjustVolume(by: ±5)`, `.toggleMute`, `.toggleFillScreen` (new), `.toggleFullscreen`, `.captureScreenshot`.
- `acceptsFirstMouse` true; `acceptsFirstResponder` false. Do not override `hitTest` (NSView's default returns self within bounds).
- No pinch gesture (not in VLC ground truth for 3.0; omitted).

## Scroll
- Pure `nonisolated struct ScrollStepAccumulator` that copies VLC master `VLCVoutView.m:239-302` exactly. The source is in `vlc-master-VLCVoutView.m.txt`.
  - Inputs: `deltaX`, `deltaY` (`NSEvent.deltaX/deltaY`, not `scrollingDelta*`), `isInverted` (`isDirectionInvertedFromDevice`), `isMouseWheel` (`event.subtype == .mouseEvent`), `timestamp`.
  - Thresholds: x 0.8, y 1.0, direction 0.05. A mouse wheel bumps a sub-threshold delta up to the threshold.
  - Y wins if |dy| > 0.05, else X. Axis lock comes from the last direction, and is reset with both accumulators when more than 0.4 s pass since the last event. The 0.4 s timer is replaced by the timestamp comparison.
  - Y positive gives volume up and negative gives volume down. X: accumulated < 0 gives `KEY_MOUSEWHEELRIGHT`, which is seek forward; > 0 gives LEFT, which is seek backward.
  - No momentum filtering (VLC does none).
- Output steps: volume ±5 per step, applied per window by calling `controller.adjustVolume(by:)` directly. This matches the arrow-key convention (PlayerView.swift:415-418); do not post `.adjustVolume`. Seek ±3 s per step via `NotificationCenter.default.post(.seekBySeconds(±3))`, same as arrow seeks.

## Fill screen, window sizes, float on top
- New `AppCommand` cases: `.toggleFillScreen`, `.setWindowSize(WindowSizePreset)` (half/normal/double/fit), `.toggleFloatOnTop`, `.stop`.
- The `WindowConfigurator.Coordinator` (private) subscribes to `NotificationCenter.default.appCommandPublisher` (Combine sink stored on the coordinator). It acts only when `WindowManager.shared.isActiveWindow(observedWindow)`. This removes the "no external handle" trap without touching ContentView.
- Pure geometry in `nonisolated enum WindowSizing`, unit-tested:
  - `isFilling(frame:visible:) -> Bool`: within 2 pt on all edges.
  - `presetFrame(preset:ratio:sourceSize:backingScale:titlebarHeight:visible:currentFrame:) -> NSRect`:
    - normal = sourceSize / backingScale; half ×0.5; double ×2.
    - fit = largest content size with `ratio` that fits `visible` (including the titlebar).
    - Clamp every result to `visible` while keeping the ratio.
    - Anchor top-left at the current frame's top-left, shifted to stay inside `visible`.
  - `restoreFrame(saved:fallback:)`: saved frame if present, else fallback (= the normal preset).
- Toggle fill:
  - If in native fullscreen, call `toggleFullScreen(nil)`.
  - Else if filling, restore the saved frame (or the normal preset) and re-lock `contentAspectRatio` to the ratio, plus `applyMinSize`.
  - Else save the frame, clear the aspect lock and min size, and `setFrame(visible, display: true, animate: false)`. Same as `maximize()`, whose comment says AppKit reshapes setFrame under a locked ratio.
  - Ratio source: `lastAspectRatio ?? savedAspectRatio`.
- Stale dst-rect risk (verified: mpv's moltenvk context never sends `VO_EVENT_RESIZE`; a programmatic grow after the one-shot jump does not reload): after every programmatic `setFrame` from fill or size presets, post `.reloadPlayer` on the next main turn. This is the same mechanism fullscreen enter/exit already uses. Remove it when the engine plan's B1 lands.
- Float on top (IINA's approach): toggles `window.level = .floating` / `.normal`. It is ignored while in native fullscreen. In the existing willEnterFullScreen observer, set `.normal`. In didExitFullScreen, restore `.floating` if the flag is on. The flag is a coordinator var (per window, not persisted).
- Menus: new `CommandMenu("Video")` with Fill Screen (no shortcut), Half Size ⌘0, Normal Size ⌘1, Double Size ⌘2, Fit to Screen ⌘3, Float on Top (Toggle bound to a FocusedValue Bool published by ContentView, or a Button titled by state), Fullscreen ⌘F (VLC).

## Volume 125 %
- `PlaybackVolume.maxPercent = 125`; `mpvValue` clamps to `0...maxPercent`.
- Update the `PlaybackVolumeTests` line `mpvValue(for: 200) == 100` to `== 100 * cbrt(1.25)`.
- `PlayerController` clamps at :43, :230 and :845 use `0...PlaybackVolume.maxPercent`.
- AVFoundation adapter (PlayerBackendAdapter.swift:47-50) sets `player.volume = Float(min(newValue, 100) / 100)`.
- Slider `maxValue = PlaybackVolume.maxPercent` with `numberOfTickMarks = 6` (0, 25, 50, 75, 100, 125, which includes 100), `allowsTickMarkValuesOnly = false`. Update the slider comment that says no tick row is drawn.
- mpv `volume-max` default is 130 per the manual; 100·cbrt(1.25) = 107.7 < 130, so no option change.

## OSD
- `@MainActor final class PlayerOSD: ObservableObject` with `@Published private(set) var message: String?` and `func show(_ text: String)`. It holds the text for 1.0 s via `DeferredMainActorTask.schedule(after:)`, then sets nil. It posts `AccessibilityNotification.Announcement`, debounced: announce only the final message (schedule the announcement 0.4 s later, cancelled by newer messages).
- Owned by `PlayerController` as `let osd = PlayerOSD()`. Emitted from:
  - `adjustVolume`: "Volume N%"
  - `toggleMute`: "Mute" / "Volume N%"
  - `seek(by:)`: "m:ss / m:ss" via `TimecodeFormatter.formatTraditionalTime`
  - `stepRate`: "Speed: %.2fx"
  - `selectAudioTrack(at:)`: "Audio track: <title>"
  - `selectSubtitleTrack(at:)`: "Subtitle track: <title>" or "Subtitle track: Off"
  - the new delay/aspect/crop/deinterlace methods (VLC texts)
- View `PlayerOSDView(osd: controller.osd)` (`@ObservedObject`). It sits in `PlayerView.overlayIndicators`' VStack directly below the existing HStack, so top-left, inside the same 16 pt padding and 62 pt leading inset. Style is the `PlaybackSpeedIndicator` look (black 0.75 rounded rect, 14 pt monospaced white), `.allowsHitTesting(false)`, `.transition(.opacity)`. The IINA look plan restyles it later.

## Keymap
- `AppSettings.keyboardLayout = AppSetting(key: "keyboardLayout", defaultValue: "vlc")` (values "vlc", "pro"). Add it to `defaultsDictionary`. Add a Picker "Keyboard Shortcuts" (VLC / AMP Pro) at the top of `KeyboardShortcutsView` so `SettingsCoverageTests` passes. `KeyboardShortcutsView` shows a VLC section when the layout is "vlc".
- Pure `nonisolated enum VLCKeyMap { static func action(characters:specialKey:modifiers:) -> VLCKeyAction? }`, unit-tested. The table copies the VLC macOS defaults in `vlc-macos-behaviour-catalog.md` §2:

  | Key | Action |
  |---|---|
  | ⌘. | stop |
  | ⌘← / ⌘→ | previous / next file |
  | ⌃⌘← / → | ±3 s |
  | ⌥⌘← / → | ±10 s |
  | ⇧⌘← / → | ±60 s |
  | ⇧⌥⌘← / → | ±300 s |
  | ⌘↑ / ⌘↓ | volume ±5 |
  | ⌥⌘↓ | mute |
  | ⌘= / ⌘- | faster / slower |
  | E | next frame (pause first) |
  | A | aspect cycle |
  | C | crop cycle |
  | S / ⌥S / ⇧S | subtitle next / previous / toggle off-last |
  | L | audio track next |
  | T | time OSD |
  | H / J | subtitle delay −/+ 50 ms |
  | F / G | audio delay −/+ 50 ms |
  | D | deinterlace toggle |
  | ⌘F | native fullscreen |
  | Esc | exit native fullscreen only if in fullscreen, else not handled |
  | ⌘0–3 | window size presets |

  Space is unchanged (already play/pause).
- Wiring in `PlayerView.handleKeyEvent`:
  - Insert after the user-override block (step 6, :272-283): when the layout is "vlc", resolve `VLCKeyMap.action` and perform it.
  - Then, still in "vlc" mode, skip `PlayerKeyMap.characterAction` (except `.nudgeWipe` in wipe mode), JKL and the arrow table. Compare `B`, I/O trim, Space and timecode digits stay in both modes.
  - In "pro" mode nothing changes.
- New PlayerController methods (MPV only; no-op when `!useMPV`; each shows its VLC OSD text). They use `mpvPlayer.getDouble`/`getString`/`setString`, which are internal; no MPVPlayer changes are needed.
  - `stop()`: `pause()`, then `seekTo(0)`.
  - `adjustAudioDelay(by:)`, `adjustSubtitleDelay(by:)`: properties `audio-delay`, `sub-delay`, in seconds.
  - `cycleAspectRatio()`: `video-aspect-override` values `["no","1:1","4:3","5:4","16:9","16:10","221:100","235:100","239:100"]`; OSD "Aspect ratio: Default" / value.
  - `cycleCrop()`: `video-crop` values `["", "16:10","16:9","4:3","185:100","221:100","235:100","239:100","5:3","5:4","1:1"]`. The manual says `""` restores the container crop, and the `<x:y>` form crops to a ratio. OSD "Crop: Default" / value.
  - `toggleDeinterlace()`: `deinterlace` "yes"↔"no". OSD "Deinterlace on" / "Deinterlace off".
  - `cycleAudioTrack()`, `cycleSubtitleTrack(forward:)`, `toggleSubtitles()`: use `audioTrackOptions`/`subtitleTrackOptions` with `selectAudioTrack(at:)`/`selectSubtitleTrack(at:)`; -1 means Off.
  - `showTimeOSD()`.
  - Cycling state: pure helper `VLCCycle.next(after:in:)`, tested.
- Menu shortcuts follow the layout. In `Aagedal_Media_PlayerApp`, read `@AppStorage(AppSettings.keyboardLayout.key)` and use `.keyboardShortcut(KeyboardShortcut?)`:
  - VLC layout: Play/Pause Space; Mute ⌥⌘↓; Volume ⌘↑/⌘↓; Reverse and Fast Forward none; Slow Fwd/Rev none; Toggle Fullscreen ⌘F; Cycle Timecode none.
  - Pro layout: today's shortcuts.
  - Remove the bare-key `m`, `t`, `j`, `l` shortcuts in both layouts. The key monitor already handles those keys when the player has focus, and the repo's own comment (App.swift:227-230) explains why bare-key menu shortcuts are unsafe. Put the key in the menu title instead (pattern: "Increase Volume (↑)").

## Elapsed / remaining
- `AppSettings.showRemainingTime = AppSetting(key: "showRemainingTime", defaultValue: false)`. Add it to `defaultsDictionary` and reference it in `FloatingOSCView` (under UI/).
- The right label in `FloatingOSCView.scrubberRow` (:112) toggles it on click (`.onTapGesture`, `.contentShape(Rectangle())`). When on, it shows `"-" + formatTraditionalTime(max(0, duration - current))`. Add `.help("Click to show remaining time")`.

## Resume
- `AppSettings.resumePlayback = AppSetting(key: "resumePlayback", defaultValue: "ask")` ("ask", "always", "never"). Picker in `GeneralSettingsView` Section("Playback").
- Pure `nonisolated enum ResumePolicy { static func shouldStore(position:duration:) -> Bool }` with VLC's rules: duration ≥ 180; not (position/duration < 0.05 and position < 60); not (position/duration > 0.95 and duration − position < 60). Tested.
- `@MainActor final class ResumePositionStore` (UserDefaults key "resumePositions", `[String: Double]` keyed by `url.standardizedFileURL.path`, plus key "resumePositionOrder" `[String]`, capped at 500 most recent). Methods:
  - `save(url:position:duration:)`: removes the entry when `shouldStore` is false.
  - `position(for:)`.
  - `remove(url:)`.
  - Use an injectable UserDefaults for tests.
- Save points:
  - `ContentView.stopPlaybackForWindowClose` before `teardown()` (it runs twice; `save` is idempotent).
  - `PlayerWindowCoordinator.openFile` before loading a different URL into a controller that already has a `mediaItem`.
  - ContentView `.onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification))`.
- Restore in `PlayerWindowCoordinator.openFile`:
  - "always": pass `startTime: saved` to `controller.loadMedia(item, startTime:autoplay:)`.
  - "ask": load from 0 and set `@Published var resumeOffer: ResumeOffer?` (url, position) on the coordinator. ContentView shows `ResumeOfferBanner` with the UpdateAvailableBanner style (`PlayerOverlayViews.swift:275`):
    - Text: "Continue playback at m:ss?" with buttons "Continue" and "Restart (N)".
    - It counts down 10 s (VLC default restart). Timeout or Restart dismisses it; Continue calls `controller.seekTo(position)`.
  - Remove the "stores no playback position" sentence at `InitialWindowController.swift:11`.

## Now Playing / media keys
- `@MainActor final class NowPlayingCoordinator` (singleton).
  - `update(owner:window:title:duration:elapsed:rate:isPlaying:)` sets `MPNowPlayingInfoCenter.default().nowPlayingInfo` (title, duration, elapsed, rate) and `playbackState` every time (required per Apple).
  - `clear(owner:)` runs when the owner window closes.
- Commands: `togglePlayPauseCommand`, `playCommand`, `pauseCommand`, `nextTrackCommand`, `previousTrackCommand`, `changePlaybackPositionCommand`. They act on the owner controller; next/previous make the owner window key, then post `.openNextFile`/`.openPreviousFile`.
- ContentView calls `update` on `isPlaying` change, on seek completion (`.onChange(of: controller.currentPlaybackTime)` is too frequent; update only on `isPlaying`, `mediaItem`, and `currentPlaybackSpeed` changes) and when its window becomes key with media.
- No entitlement changes (app not sandboxed). `input-media-keys no` stays.

## Audio / Video / Subtitles menus
- ContentView adds `.focusedSceneObject(controller)`. The App adds `@FocusedObject private var activeController: PlayerController?`.
- `CommandMenu("Audio")`: Audio Track submenu (ForEach `audioTrackOptions`, checkmark on selected), Volume Up/Down, Mute, Audio Delay +50 ms / −50 ms / Reset.
- `CommandMenu("Subtitles")`: Add Subtitle File… (existing `.openSubtitleFile`), Subtitle Track submenu (Off + `subtitleTrackOptions`), Subtitle Delay +50 / −50 / Reset.
- `CommandMenu("Video")` (from the window task) adds Aspect Ratio and Crop submenus (same lists as the keymap), Deinterlace toggle, Render Profile submenu (`RenderProfile.allCases` → `.setRenderProfile`).
- macOS 26 runtime check step: open two windows with different track counts, switch key window, confirm the menus follow. If they go stale, fall back to `@FocusedValue` with a value-type snapshot.

## Out of scope (state explicitly in the plan)
Jump to Time ⌘J (needs a time-entry UI in ordinary mode; IINA look plan), zoom Z, autoscale O, audio device ⇧A, loop ⇧L, random ⌘Z, fullscreen controller I, pinch, video effects, A→B loop.
