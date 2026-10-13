# Verified fact sheet: AMP VLC-parity (Section A of 2026-10-13-gemini4-argon-full-review.md)

Paths relative to `Aagedal Media Player/` (source) unless noted. T = `Aagedal Media Player Tests/`. All line numbers real, re-read from code. Verdicts: CONFIRMED / WRONG / NOT FOUND / UNVERIFIABLE-WITHOUT-RUNTIME (UWR).

Cross-cutting traps for the planner (read first):
1. `SettingsCoverageTests` (T/SettingsCoverageTests.swift:32-58): every new `AppSetting` must be (a) in `AppSettings.defaultsDictionary` (AppSettings.swift:138) and (b) referenced as the text `AppSettings.<name>` somewhere under `UI/`, or listed in `notUserFacing` (:12). Otherwise the test fails.
2. `PlaybackVolumeTests.testMPVCubicGainMatchesLinearAVPlayerAmplitude` asserts `mpvValue(for: 200) == 100` (T/PlaybackVolumeTests.swift:14). Raising the cap to 125 breaks it; it must be edited.
3. Project uses synchronized root groups (4 `PBXFileSystemSynchronizedRootGroup` in pbxproj): new .swift files in source/test dirs auto-join targets. No pbxproj edit.
4. The window `Coordinator` is private to the `WindowConfigurator` representable. `ContentView` only receives an `NSWindow` via `onWindowAvailable`. A double-click or `⌘0-3` handler cannot reach `maximize`/`lastAspectRatio` today; a hook must be added.
5. The ordinary-playback bar is `FloatingOSCView`; `ControlsView` (with the timecode editor and `timecodeActivationTrigger` consumer, ControlsView.swift:144) is mounted only in Compare Mode (ContentView.swift:459-461). Typing digits outside compare mode sets `timecodeActivationTrigger` (PlayerView.swift:432) but nothing consumes it.
6. `MPVViewController` posts `.reloadPlayer` (full mpv recreate via `compareSession.reload` -> `reloadPreservingPlaybackState`, PlayerController.swift:427) on `didEnterFullScreen`/`didExitFullScreen`/`didEndLiveResize` (MPVVideoView.swift:307-353) and once per controller on >=1.5x drawable growth (`hasAutoReloadedForLayoutJump`, :57/:234-238, never reset). Double-click fullscreen and user live-resize will each reload mpv. Programmatic fill/`⌘3` growth after the first jump does NOT reload (risk of the stale-dst-rect bug described at :368-383; UWR).

---
## 1. PlayerView / ComparePlayerView / hit-testing

`UI/PlayerView.swift:11-25` init stored properties (memberwise):
```swift
@ObservedObject var controller: PlayerController
@ObservedObject var audioWaveformGenerator: AudioWaveformGenerator
let item: MediaItem
let showsAudioWaveform: Bool
@Binding var isEditingTimecode: Bool
@Binding var isTimelineFocused: Bool
let isOverlayControlFocused: Bool
var isTextInputActive = false
@Binding var timecodeActivationTrigger: String?
var acceptsKeyboardInput = true
var compareSession: CompareSessionController? = nil
var managesMPVSurfaceReloads = true
```
`PlayerView.body` (:57-142) `ZStack { Color.black; [AVPlayer: PlayerContainerView(...).aspectRatio.id(preparationID).ignoresSafeArea.frame(.infinity)] | [MPV: GeometryReader{ MPVVideoView(...).frame(picture).position.id(preparationID) }.ignoresSafeArea()]; if audioOnly AudioOnlyPresentationView; if player!=nil||mpvPlayer!=nil overlayIndicators (:216, top-left HStack: PlaybackSpeedIndicator, RenderTierBadge; padding 16, leading +62); playbackStateOverlay (:145); EnhancementSuggestionView (.topTrailing, :135) }.frame(.infinity).background(.black)`. PlayerView is instantiated twice in compare (primary + secondary), each subject to scale/offset/mask transforms (ComparePlayerView.swift:179-229), so a surface inside PlayerView would be transformed; put it at ComparePlayerView level.

`UI/ComparePlayerView.swift` embedding:
- `primaryPlayer` :242-255 `PlayerView(controller:audioWaveformGenerator:item:showsAudioWaveform:isEditingTimecode:isTimelineFocused:isOverlayControlFocused:isTextInputActive:timecodeActivationTrigger:compareSession: compareSession)`.
- `secondaryPlayer` :257-279 same plus `acceptsKeyboardInput: false`, `managesMPVSurfaceReloads: !primaryController.useMPV`; else `Color.black`.
- Both are inside `comparisonSurfaces(size:presentation:)` (:172-240: ZStack, `.compositingGroup().brightness().contrast()`).
- Body ZStack (the real insertion point) `ComparePlayerView.swift:47-77`:
```swift
ZStack(alignment: .topLeading) {
    comparisonSurfaces(...).scaleEffect(inverseRenderScale, anchor: .topLeading).frame(...)   // :48-54
    if compareSession.isActive { comparisonGuides(...) }                                       // :56 (allowsHitTesting false)
    if viewMode == .sideBySide { Rectangle()...allowsHitTesting(false) }                       // :60
    if compareSession.isActive { sourceBadges }                                                // :68 (hit-testing off)
    if viewMode.isWipe { wipeInteractionOverlay(referenceRect:) }                              // :72
}.frame(width: size.width, height: size.height).clipped().coordinateSpace(name: "compareCanvas") // :78-80
```
A transparent surface goes between :54 and :56 (size `size`, full canvas). It then sits below the wipe strip and above video. `ComparePlayerView` is only mounted when `controller.mediaItem != nil` (ContentView.swift:134-146); `DropZoneView` otherwise.

Wipe drag gesture: `wipeDragGesture(referenceRect:)` :378-393 = `DragGesture(minimumDistance: 0, coordinateSpace: .named("compareCanvas"))` -> `compareSession.setWipePosition(...)`. It is attached only to a 24 pt `Color.clear.contentShape(Rectangle())` strip: vertical wipe `.frame(width:24, height:referenceRect.height)` :325-335, horizontal `.frame(width:referenceRect.width, height:24)` :350-360. Handle/divider rect: `handleOffset` :400, `dividerOffset` :395.

Other existing mouse handling on the picture: none (no onTapGesture/performDrag/scrollWheel/menu(for:)/isMovableByWindowBackground on player windows; only `ControlsView.swift:846/849` tap gestures on the compare-bar timecode and `InitialWindowController.swift:69`). `ContentView.inspectionCanvas` has `.onContinuousHover` (ContentView.swift:168, drives the loupe); `renderedContentLayers` has `.onHover` (:280, `overlayController.setWindowHovered`); `overlayControls` has `.onHover` (:467 -> `setControlsHovered`). `PlayerOverlayController` additionally installs local monitors for `.mouseMoved`, `.keyDown`(Tab only) and `.leftMouseDown/.rightMouseDown/.otherMouseDown` (PlayerOverlayController.swift:38/54/66); the mouseDown monitor returns the event (does not swallow) and re-arms `NSCursor.setHiddenUntilMouseMoves` when the overlay is hidden.

## 2. WindowConfigurator

`UI/WindowConfigurator.swift` (377 lines). Struct fields :14-18: `aspectRatio: CGFloat?`, `videoSourceSize: NSSize?`, `showTrafficLights: Bool`, `onWindowAvailable: ((NSWindow) -> Void)?`. Statics: `baseMinWidth 690`, `baseMinHeight 540` (:12-13), `trafficLightAlpha(showTrafficLights:isFullScreen:)` :22, `shouldMaximize(hasMaximizedForMedia:isFullScreen:openMaximized:)` :30 (`openMaximized && !hasMaximizedForMedia && !isFullScreen`), `mayResizeToSource(hasMaximizedForMedia:openMaximized:)` :39 (`!(openMaximized && hasMaximizedForMedia)`), `minContentSize(for:)` :47.

`final class Coordinator: NSObject` (:56-): vars `lastAspectRatio: CGFloat?`, `savedAspectRatio: CGFloat?`, `lastSourceSize: NSSize?`, `weak observedWindow`, `willEnterFullScreen/didEnterFullScreen/didExitFullScreen: NSObjectProtocol?` (nonisolated(unsafe)), `isEnteringFullScreen`, `lastTrafficLightAlpha`, `lastShowTrafficLights`, `hasMaximizedForMedia` (sticky, :75). Methods: `applyTrafficLightAlpha(_:animated:)` :80, `applyMinSize(_:ratio:)` :104 (`window.contentMinSize = minContentSize(for:)`), `maximize(_:)` :119, `applyInitialSize(_:ratio:sourceSize:isFullScreen:openMaximized:)` :129, `observeWindow(_:)` :211 (enter-fullscreen: saves `savedAspectRatio`, sets `lastAspectRatio = nil`, `contentResizeIncrements = 1x1`; exit: restores `lastAspectRatio`, re-locks `contentAspectRatio` only if `!hasMaximizedForMedia`, :250-259). No `willStartLiveResize` observer; no saved pre-maximize frame; no size-preset API.

`maximize` (:119-123) verbatim, with the AppKit comment (:109-118):
```swift
/// Fill the screen with the picture. The aspect lock has to go first:
/// AppKit reshapes setFrame to the locked ratio and would letterbox the
/// window rather than the picture. The minimum drops to the base size
/// for the same reason - a portrait source asks for a minimum taller
/// than the screen, which blocks the fill outright.
/// The target is `visibleFrame`, not `frame`. ... Asking for the full screen
/// rect with no aspect lock raises an NSException inside
/// `-[NSWindow _reallySetFrame:]` and takes the app down.
func maximize(_ window: NSWindow) {
    window.contentAspectRatio = .zero
    applyMinSize(window, ratio: nil)
    guard let screen = window.screen ?? NSScreen.main else { return }
    window.setFrame(screen.visibleFrame, display: true, animate: false)
}
```
So AppKit DOES reshape `setFrame` under `contentAspectRatio` per the authors; the review's A2 claim 1 is contradicted. Always clear the lock before programmatic `setFrame`. Note `animate: false` (review says `true`).

Source-size code to reuse (`applyInitialSize` :151-208): `window.contentAspectRatio = NSSize(width: ratio, height: 1)`; `titlebarHeight = frame.height - contentView.bounds.height`; source sizing `sourceSize / window.backingScaleFactor` (:164-165), clamp to 0.9*visibleFrame when `clampWindowToScreen`; center with `centerWindowAfterResize` else anchor top-left (`origin.y = frame.origin.y + frame.height - totalHeight`); `setFrame(..., display: true, animate: false)`.

ContentView wiring (ContentView.swift:259-277):
```swift
WindowConfigurator(aspectRatio: videoAspectRatio,           // controller.videoAspectRatio (:75-79)
                   videoSourceSize: videoSourceSize,        // controller.videoSourceSize
                   showTrafficLights: overlayController.isWindowHovered,
                   onWindowAvailable: { window in windowCoordinator.accept(window, onClose: {...stopPlaybackForWindowClose...}) })
```
`updateNSView` (:326-): reads `UserDefaults ... openMaximized` per update; applies aspect/min size on the next main-queue turn only if `!isFullScreen` and ratio or sourceSize changed.
`ConfiguratorNSView.viewDidMoveToWindow` (:272-310) sets `isRestorable=false`, `backgroundColor=.black`, `.fullSizeContentView`, `titlebarAppearsTransparent`, `titleVisibility = .hidden` (:285), and forces a 711x400 default frame.

## 3. Commands

`Logic/AppCommand.swift` (79 lines) `enum AppCommand` cases: `openFilePicker, openFile(URL, targetWindow: NSWindow? = nil), openPreviousFile, openNextFile, toggleInspector, captureScreenshot, exportTrim, cycleTimecodeMode, togglePlayback, toggleMute, adjustVolume(by: Double), reverse, fastForward, stepRate(forward: Bool), slowForward, slowReverse, seekByFrames(Int), seekBySeconds(Double), seekToEdge(PlaybackEdge), toggleFullscreen, syncTimecode, seekToSyncedTime(SyncedPlaybackTime), copyTimecode, pasteTimecode, reloadPlayer, toggleScopes, toggleScopeParade, toggleAudioWaveform, setRenderProfile(RenderProfile), openComparisonFile, toggleInspectionLoupe, toggleReviewNotes, openSubtitleFile`. Nested `PlaybackEdge {start,end}`, `SyncedPlaybackTime {relativeSeconds, sourceSeconds?}`. No stop, jumpToTime, scaleWindow, toggleFillScreen.
```swift
extension NotificationCenter {
    func post(_ command: AppCommand)                              // AppCommand.swift:73
    var appCommandPublisher: NotificationCenter.Publisher         // :77
}
extension Notification { var appCommand: AppCommand? }            // :66
```
Adding a case means a new `.onReceive` block in `UI/ContentViewCommandHandlers.swift`; every `case` is its own modifier closure (`guard let command = notification.appCommand, case .x = command`).

Handlers (`UI/ContentViewCommandHandlers.swift`):
- `FileAndWindowHandlers` (:73-345), guard `WindowManager.shared.isActiveWindow(nsWindow)`: openFilePicker :98, openFile :104 (targetWindow check), openPreviousFile :114 -> `openPreviousFile()`, openNextFile :120, toggleInspector :126, captureScreenshot :132 (compare -> `captureComparisonStill`, else `controller.captureScreenshot()`), exportTrim :142, openComparisonFile :155, toggleInspectionLoupe :161, toggleReviewNotes :167, openSubtitleFile :173 (also requires mediaItem; calls `addSubtitle`), toggleFullscreen :190 -> `controller.toggleFullscreen()`, toggleScopes :196, toggleAudioWaveform :243. `setRenderProfile` :148 has NO window guard (global).
- `PlaybackHandlers` (:349-476), guard `WindowManager.shared.shouldHandlePlaybackCommand(window:)` (all windows when `syncPlaybackControls`, else active window): togglePlayback :356 (compare -> `compareSession.togglePlayback(primary:)`), toggleMute :366, adjustVolume :376 (compare -> `adjustMonitoringVolume`, else `controller.adjustVolume(by:)`), reverse, fastForward, stepRate :406 (ignored in compare), slowForward, slowReverse, seekByFrames :435, seekBySeconds :445 (compare -> `compareSession.seek(primary:by:)` else `controller.seek(by:)`), seekToEdge :455.
- `TimecodeAndSyncHandlers` (:480-577): cycleTimecodeMode (isActiveWindow && !isEditingTimecode), syncTimecode, seekToSyncedTime, copy/pasteTimecode, reloadPlayer :564 (active window, `compareSession.reload(primary:)`).
Consequence: `.adjustVolume` and `.seekBySeconds` are broadcast to every window when sync is on. PlayerView deliberately keeps arrow-key volume local by calling `controller.adjustVolume` directly (PlayerView.swift:415-418, private helper :488-494, which also handles compare). A scroll handler wanting per-window volume must do the same, not post `.adjustVolume`.
`ContentView.openNextFile/openPreviousFile` (ContentView.swift:~565-575) use `windowCoordinator.nextMediaURL()/previousMediaURL()`.

## 4. PlayerController (Logic/PlayerController.swift, 1700+ lines; the review's 813 is stale)

```swift
@Published var volume: Double = 100 { didSet { clamp 0...100 (:43); backendAdapter?.volume = volume; UserDefaults set playbackVolume } }   // :41-51
@Published var isMuted: Bool = false { didSet { UserDefaults set; backendAdapter?.isMuted = effectiveIsMuted } }                       // :52-57
init: volume = defaults.value(for: playbackVolume).clamped(to: 0...100, ...)                                                           // :229-230
func adjustVolume(by delta: Double) { volume = (volume+delta).clamped(to: 0...100, default: 100); if volume > 0 { isMuted = false } }  // :844
func toggleMute() { isMuted.toggle() }                                                                                                 // :827
func togglePlayback()  :851 (guard isReady)     func pause() :874     func play() :887 (guard isReady)
func seek(by seconds: Double)  :1214  (getCurrentTime()+seconds, clamped 0...mediaItem.durationSeconds -> seekTo)
func seekTo(_ time: Double)    :1251  (guard isReady; sets currentPlaybackTime; backendAdapter?.seek)
func seekByFrames(_ frameCount: Int) :1221 (1/fps from primaryVideoStream.frameRate else 1/30)
func stepRate(forward: Bool) :937  (adds/subtracts 0.5, clamp 0.25...8.0, sets currentPlaybackSpeed)
@Published private(set) var currentPlaybackSpeed: Float = 1.0   :79     // read-only; NO public "set speed to X" API (NOT FOUND)
@Published var currentPlaybackTime: Double :68     func playbackTimeSnapshot() -> TimeInterval :1334     func getCurrentTime() -> TimeInterval? :1323
@Published var mediaItem: MediaItem? :160          // duration = mediaItem?.durationSeconds (MediaItem.durationSeconds: Double, Models/MediaItem.swift:34)
var audioTrackOptions: [AudioTrackOption] :84      var subtitleTrackOptions: [SubtitleTrackOption] :85      var chapterOptions :86
var selectedAudioTrackOrderIndex: Int :87          var selectedSubtitleTrackOrderIndex: Int :88   // -1 == Off
func selectAudioTrack(at position: Int) :1388      // pauses, switches, resumes via togglePlayback
func selectSubtitleTrack(at position: Int) :1528   // guard useMPV; position < 0 -> mpvPlayer.disableSubtitles() (sid=0), selectedSubtitleTrackOrderIndex = -1
func addSubtitle(url: URL) :1533                    // mpvPlayer?.addSubtitle(url:) only; NO option refresh
func jumpToChapter(at:) :1550     func toggleFullscreen() :1365   // (playerView?.window ?? NSApp.keyWindow)?.toggleFullScreen(nil)
var mpvPlayer: MPVPlayer? :172     var useMPV: Bool :173     func loadMedia(_ item: MediaItem, startTime: TimeInterval = 0, autoplay: Bool = false) :254
func preparePlayback(startTime: TimeInterval, resetAudioSelection: Bool = true) :460     func reloadPreservingPlaybackState() :427     func teardown(resetAudioSelection:) :1626 (sets isPlaying=false :1680)
@Published var videoAspectRatio: CGFloat? :122      @Published var videoSourceSize: NSSize? :123
```
`SubtitleTrackOption{id, position, trackId: Int32, title}`; `AudioTrackOption{id, position, streamIndex, mediaOptionIndex?, title, subtitle?}` (TrackSelectionController.swift:20-34). Track options are refreshed on MPV file-loaded only (PlayerController.swift:616-617); `buildMPVSubtitleTrackOptions()` (:1518) has zero callers (dead; only `rebuildMPVTrackOptions` is tested). There is no `stop()` on PlayerController (MPVPlayer has `stop()` :518). `toggleFullscreen` uses `playerView` (AVPlayerView only) so for MPV it falls back to `NSApp.keyWindow`. Compare equivalents: `CompareSessionController.adjustMonitoringVolume(by:primary:)` :740, `toggleMonitoringMute(primary:)` :729, `seek(primary:by:)` :1740, `seek(primary:to:)` :1752, `togglePlayback(primary:)` :1669, `isActive` :465.

## 5. MPVPlayer (Logic/MPV/MPVPlayer.swift)

Visibility (all inside `MPVPlayer`, @MainActor class): `func getDouble(_:) -> Double` :1613 (internal), `func getString(_:) -> String?` :1639 (internal), `func setString(_ name: String, _ value: String)` :1646 (internal, logs on failure), `private func setDouble` :1620, `private nonisolated func getInt` :1626, `private func setInt` :1633, `private func setFlag` :1668, `private func command(_:args:) -> Bool` :1592, `func addSubtitle(url:)` :1578 (`sub-add <path> select`). Plan must widen or add wrappers for double/int/command if used from outside.
`MPVProperty` (Logic/MPV/MPVProperty.swift, `nonisolated static let`): videoParams*, targetPrim/Trc/Peak, iccProfile, hwdecCurrent, video/audioReversalBuffer, duration, timePos, path, pause, pausedForCache, eofReached, seekable, speed, videoParamsDw/Dh/Rotate/PixelFormat/HWPixelFormat, videoBitrate, containerFPS, volume, mute, aid, trackListCount, sid, subVisibility, chapter, chapterListCount. NOT present: audio-delay, sub-delay, sub-scale, video-aspect-override, video-crop, panscan, video-zoom, ab-loop-a/b. A repo-wide grep finds none of these used (only a comment at MPVVideoView.swift:380). `deinterlace` is set once as an option `"auto"` at MPVPlayer.swift:370 (no runtime control). `volume-max` is not set anywhere (mpv default 130 applies). `osd-level 0` :369; `input-media-keys no` :387 (review said :320, WRONG); `input-default-bindings no` :373; `input-vo-keyboard no` :374.
`@Published var volume` didSet -> `setDouble(MPVProperty.volume, PlaybackVolume.mpvValue(for: volume))` :83-87 and again at attach :412. `isMuted` -> `setFlag(mute)` :88-92. `var rate: Float` get/set speed :627.
`Logic/PlaybackVolume.swift` (whole):
```swift
nonisolated enum PlaybackVolume {
    static func mpvValue(for percent: Double) -> Double {
        let amplitude = percent.isFinite ? min(100, max(0, percent)) / 100 : 1
        return 100 * cbrt(amplitude)   // inverts mpv 0.41 cubed gain
    }
}
```
Adapters (Logic/PlayerBackendAdapter.swift): `AVFoundationPlayerBackend.volume` get `Double(player.volume)*100`, set `player.volume = Float(newValue/100)` :47-50; `MPVPlayerBackend.volume` get/set `player.volume` :106-109 (class at :93; protocol :15-31). Slider: `PlaybackVolumeSlider.swift:17 slider.maxValue = 100`; `Control: NSSlider` has only focus overrides (no `draw`, no snap); used at FloatingOSCView.swift:132 and ControlsView.swift:281. `AVAudioChannelRouter` tap: `audioChannelTapProcess` AVAudioChannelRouter.swift:48, installed via `playerItem.audioMix` only when routing is non-default (`audioMix = nil` at :136/:144), so tap gain would need an always-on tap.

## 6. Keyboard

Monitors: `MPVVideoView.Coordinator` (MPVVideoView.swift:441-472, `.keyDown`, requires key window, calls `keyHandler(characters, flags, specialKey)`; handled -> returns nil) and `PlayerContainerView.Coordinator` for AVPlayer (PlayerView.swift:535-577, same plus `if isTextInputActive { return event }`). Both are per PlayerView; in compare the secondary's handler returns false at the first guard. Review cites wrong lines (:380, :479).

`PlayerView.handleKeyEvent(_ characters: String, _ modifiers: NSEvent.ModifierFlags, _ specialKey: NSEvent.SpecialKey?) -> Bool` :243 order:
1. `guard acceptsKeyboardInput` :244
2. `isEditingTimecode || isTextInputActive` -> false :247 (NO NSTextView/firstResponder check anywhere in the file)
3. `isTimelineFocused` + left/right arrow -> false :254
4. `isOverlayControlFocused` + any arrow -> false :261
5. `isWipeMode` computed :267
6. user override: `PlayerKeyMap.userOverride(characters:specialKey:modifiers:isWipeMode:table: KeyBindingStore.shared.table)`; skipped for space when overlay control focused; `.unbound` -> false, `.bound(a)` -> `perform(a)` :272-283
7. `PlayerKeyMap.characterAction(_:modifiers:isWipeMode:)` -> stepRate/stepFrames/togglePlayback/toggleFullscreen/nudgeWipe :288-306 (rejects any cmd/ctrl/opt)
8. `b` compare toggle :310; `i`/`o` trim :319-343; opt+x :346
9. space -> `.togglePlayback` (false if overlay control focused) :353
10. `j`/`k`/`l` (+opt slow) :364-383
11. arrows via `PlayerKeyMap.arrowAction/arrowRoute` :387-425
12. digits/`+-:;` with no cmd/ctrl/opt -> `timecodeActivationTrigger` :428-434; else false.

`UI/PlayerKeyMap.swift`: `enum PlayerCharacterAction {stepRate(forward:), stepFrames(Int), togglePlayback, toggleFullscreen, nudgeWipe(by:)}`; `PlayerKeyMap.characterAction` :32 (keys `[ ] { } . , p f`); `userOverride` :70; `arrowAction`/`arrowRoute`/`arrowDecision` :89-117; `PlayerArrowAction {seekBy, stepFrames, seekToStart, seekToEnd, adjustVolume(Int), previousFile, nextFile}`; `PlayerArrowRoute {local, broadcast}`. No `PlayerKeyMap.resolve(event:)` and no `KeyBindingPresets` exist (NOT FOUND).
Arrow matrix today (arrowDecision :117-169): plain Left/Right = +-5 s broadcast; Shift +-10; Opt 1 frame local; Cmd prev/next file (broadcast); Cmd+Opt +-10 s local; Cmd+Ctrl and Cmd+Shift fall to plain seek/nextFile (shift ignored in cmd branch); Up/Down plain = volume +-5 local, Ctrl +-5, Opt +-1, Shift +-10 frames, Cmd = start/end, Cmd+Opt = start/end local. VLC says plain arrows do nothing and Cmd+Up/Down = volume: direct conflicts.
`KeyBindingAction` (Logic/Input/KeyBindingAction.swift:17) `String, CaseIterable, Codable` cases: togglePlayback, toggleFullscreen, stepRateForward, stepRateBackward, stepFrameForward, stepFrameBackward, reverse, fastForward, slowReverse, slowForward, setTrimIn, clearTrimIn, jumpToTrimIn, setTrimOut, clearTrimOut, jumpToTrimOut, clearAllTrim, toggleCompareSource. Header (:9-13) says arrows are deliberately absent. `KeyBindingDefaults.table: [KeyChord: KeyBindingAction]` :40 (bind("p"/"k"/"space"/"f"/"]"/"["/"."/","/"j"/"l"/"alt+j"/"alt+l"/"i".."alt+x"/"b")). `KeyBindingTable` (Logic/Input/KeyBindingTable.swift): `enum Override {bound(KeyBindingAction), unbound}`, `init(overrides: [String:String])`, `init(fileData:) throws`, `override(for:)`, `static let empty`. `KeyChord{key, modifiers (shift,control,option,command)}`: `init(key:modifiers:)`, `init?(string:)` ("shift+i"), `stringValue`, `static from(characters:specialKey:flags:)`; only arrows have special names (left/right/up/down); space -> "space". `KeyBindingStore.shared` (@MainActor): `table`, `fileURL` (~/Library/Application Support/Aagedal Media Player/keybindings.json), `reload()`, `writeDefaultFileIfMissing()`. Existing tests: T/KeyBindingDefaultsTests, KeyBindingTableTests, KeyChordTests, PlayerKeyMapTests, PlayerArrowKeyMapTests, PlayerKeyWiringTests.

`Aagedal_Media_PlayerApp.swift` `.keyboardShortcut` list (default modifiers = Command when omitted):
- New Window `n` :85; Open `o` :91; Open Subtitle `o` cmd+shift :96; Close `w` :102; Prev File `[` cmd :113; Next File `]` cmd :119; Save Screenshot `s` :126; Export Trim `e` :132; Toggle Inspector `i` :139
- **Cycle Timecode `t` modifiers [] :145**; Video Scopes `w` cmd+shift :153; Toggle Parade `p` cmd+shift :159; Audio Waveform `a` cmd+shift :165; Open Comparison `d` cmd+shift :173; Inspection Loupe `l` cmd+shift :179; Review Notes `n` cmd+shift :185
- **Play/Pause `.space` [] :192; Mute `m` [] :198**; Volume up `.upArrow` ctrl :204; Volume down `.downArrow` ctrl :210; **Reverse `j` [] :218; Fast Forward `l` [] :224**; Slow Forward `l` opt :246; Slow Reverse `j` opt :252; Toggle Fullscreen `f` ctrl+cmd :260; Align Windows `s` cmd+shift :270; Copy Timecode `c` cmd+shift :278; Paste Timecode `v` cmd+shift :284; Reload Player `r` cmd+shift :292
- Speed Down/Up have no key equivalent on purpose (comment :227-230).
Free for VLC chords: Cmd+F, Cmd+., Cmd+J, Cmd+0/1/2/3, Cmd+=/-, Cmd+Alt+Down (key monitor still claims it as seekToEnd, local).

Bare-key menu shortcuts firing while typing in a TextField: the code paths are consistent with it: the repo's own comment (:227-230) states a plain-key menu shortcut "would fire exactly in the cases the monitor deliberately yields"; handleKeyEvent returns false when `isTextInputActive` (so the event reaches AppKit); `isTextInputActive` is `showReviewNotes || showLoupeControls` (ContentView.swift:~141). Whether AppKit/SwiftUI actually dispatches a no-modifier `CommandMenu` key equivalent to the main menu before a focused field editor consumes it is UNVERIFIABLE-WITHOUT-RUNTIME. Local monitor ordering (monitor before menu) is standard AppKit.

## 7. Settings

`Logic/AppSettings.swift`: `nonisolated struct AppSetting<Value: Sendable>: Sendable { let key: String; let defaultValue: Value }` :12; `nonisolated enum AppSettings { static let x = AppSetting(key: "x", defaultValue: ...) }` :17; `registerDefaults(in:)` :133; `defaultsDictionary` :138 (every non-nil setting must be added); `unregisteredKeys` :128 for nil defaults; `allKeys` :131.
```swift
nonisolated extension UserDefaults {
    func value<Value: Sendable>(for setting: AppSetting<Value>) -> Value      // :207  object(forKey:) as? Value ?? default
    func set<Value: Sendable>(_ value: Value, for setting: AppSetting<Value>) // :211
}
```
Views bind with `@AppStorage(AppSettings.x.key) private var x = AppSettings.x.defaultValue`. Window settings: `openAtSourceResolution` default true :27, **`openMaximized` default true :32** (review said :26; no UI; in `notUserFacing`), `clampWindowToScreen` :33, `centerWindowAfterResize` :34, `playbackVolume` :35. Usage: WindowConfigurator.swift :157/:169/:190/:338; GeneralSettingsView :16-21 and toggle at **:39** (review said :37), with `Toggle("Limit Window Size to Screen")` :41 and `Toggle("Center Window on Screen")` :42 shown only if `openAtSourceResolution`. Effective behaviour: with `openMaximized == true` (default, unchangeable in UI) first load maximizes and every later load returns early at `mayResizeToSource` (WindowConfigurator.swift:146-149), so "Open Windows at Source Resolution" is dead for ALL loads, not just the first.
Settings UI: `UI/Settings/SettingsView.swift` `TabView` :118 with tabs General(120)/Playback/Screenshots/Export/Rendering/Scopes/Audio/Shortcuts(141, `KeyboardShortcutsView`)/Updates. `GeneralSettingsView` = `Form { Section("Windows"){Toggle...} Section("Playback"){...} }.formStyle(.grouped)`. Picker style used elsewhere: `Picker("Gapless Playback", selection: $gaplessAudio) { Text("Weak").tag("weak") ... }` (PlaybackSettingsView.swift:56) with caption `Text(...).font(.caption).foregroundStyle(.secondary)`. `KeyboardShortcutsView` (UI/Settings/KeyboardShortcutsView.swift) is a static `ScrollView{VStack}` of `shortcutSection(_, shortcuts:[(String,String)])` tables plus a keybindings.json blurb (:73-80); it hard-codes today's keys and would need preset-dependent content. A keymap Picker fits GeneralSettingsView (Form) or the top of KeyboardShortcutsView.

## 8. Overlay and chrome

`Logic/PlayerOverlayController.swift` (@MainActor ObservableObject): `@Published private(set) var isVisible = true, isWindowHovered, isControlsHovered`; `init(hideDelay: Duration = .seconds(2.5))` :26; API `install(isMediaLoaded:isKeyWindow:isPlaying:isControlInteractionActive:)` :30, `setWindowHovered(_:isControlInteractionActive:)` :89, `setControlsHovered(_:)` :96, `reveal()` :103, `revealForKeyboardNavigation()` :111, `hide()` :116 (also hides cursor), `static hideCursorUntilMouseMoves()` :129, `scheduleHide(isPlaying:isControlInteractionActive:)` :133 (no hide unless playing, not hovered), `appDidResign(...)` :151, `cancelScheduledHide()` :156, `tearDown()` :161.
`UI/PlayerOverlayViews.swift`: `MediaOperationFeedbackOverlay` :10 (capsules `.background(.black.opacity(0.7), in: .capsule)`, `.font(.system(size: 13, weight: .medium))`, padding 16x10, `.padding(.bottom, 80)`, `.transition(.opacity)`); **`UpdateAvailableBanner` :275** (review said :235): `VStack{ HStack{icon, Text 12pt medium white, capsule Download button, xmark} .padding(.horizontal,14).padding(.vertical,8).background(.blue.opacity(0.85), in: .capsule).padding(.top,36); Spacer() }.transition(.move(edge: .top).combined(with: .opacity))`; `TransportSyncStatusView` :333.
`UI/FloatingOSCView.swift`: `scrubberRow` :100-114 = `HStack{ timeLabel(controller.currentPlaybackTime) :102; PlayerScrubber(...) ; timeLabel(duration) :112 }`; `timeLabel(_ seconds: Double)` :116-122 = `Text(TimecodeFormatter.formatTraditionalTime(seconds)).font(.system(size: 11, weight: .regular, design: .monospaced)).foregroundStyle(.secondary).frame(minWidth: 46).padding(.horizontal, 2)`; no tap/click handler on either label. Volume slider `PlaybackVolumeSlider(value: $controller.volume, ...)` :132-135 (not compare-aware). `subtitleMenu` :180 (`Off` -> `selectSubtitleTrack(at: -1)`). `PlaybackSpeedIndicator` is `UI/PlaybackSpeedIndicator.swift:7` (struct, `speed: Float`, `isReversing: Bool`, black 0.75 rounded rect, 14 pt mono) rendered in `PlayerView.overlayIndicators` :216-236 top-left (leading inset 62 for traffic lights). `RenderTierBadge` same HStack :224. Top-right is already used by `EnhancementSuggestionView` (PlayerView.swift:135, `.topTrailing`) and the inspector panel (`.padding(.top, 36).padding(.trailing, 12)`, ContentView.swift:211-216): an OSD in the top-right collides.
ContentView `renderedContentLayers` ZStack order (ContentView.swift:192-250, bottom to top): `inspectionCanvas` (:123; ComparePlayerView or DropZoneView, + `InspectionLoupeOverlay` :156) -> `MediaOperationFeedbackOverlay` (:197) -> `UpdateAvailableBanner` (:201, if update available and not dismissed) -> inspector panel (:209, `showInspector`) -> `overlayControls` (:219/:451: `VStack{Spacer; compare ? inspectionControls : FloatingOSCView.frame(height: 120)}` with opacity tied to `showOverlay`) -> audio waveform overlay (:222) -> scope overlay (:238, `allowsHitTesting(false)`).

## 9. Existing helpers

- `DeferredMainActorTask` (Logic/DeferredMainActorTask.swift, @MainActor final class): `@discardableResult func schedule(_ op: @escaping @MainActor @Sendable () -> Void) -> Task<Void,Never>` (next turn), `schedule(after delay: Duration, _ op:)`, `scheduleAsync(after:_ op: async)`, `func cancel()`. Re-scheduling cancels the prior task. Tests: T/DeferredMainActorTaskTests.
- `TimecodeFormatter.formatTraditionalTime(_ seconds: Double) -> String` (UI/TimecodeFormatter.swift:334, `struct TimecodeFormatter`): rounds to Int; `mm:ss` or `h:mm:ss`; non-finite -> `--:--`; no sign handling (a remaining-time label needs its own "-" prefix, and negative input would mis-format).
- `SleepPreventer.shared` (@MainActor): `update(for owner: AnyObject, isPlaying:isAudioOnly:)`, `forget(_ owner:)`, `isHoldingAssertion`. 
- `WindowManager.shared` (Logic/WindowManager.swift): `isActiveWindow(_ window: NSWindow?) -> Bool` :158 (true if <=1 live window, else `window.isKeyWindow`), `shouldHandlePlaybackCommand(window:) -> Bool` :172 (`syncPlaybackControls || isActiveWindow`), `var syncPlaybackControls: Bool` :56 (live UserDefaults), `allowMultipleWindows`, `windows`, `mediaWindowCount`, `register/unregister/markHasMedia`, `open(_ urls:)`, `openInNewPlayerWindow`.
- `PlayerWindowCoordinator` (@MainActor ObservableObject): `accept(_ candidate: NSWindow, onClose: (() -> Void)?) -> Bool` :42; close hook = `NSWindow.willCloseNotification` observer :282-300 -> `windowCloseHandler` then `tearDown()`; open hook = `openFile(_ url:controller:onTimecodeModeChange:onMetadataLoaded:)` :166, which sets `window.title = item.name` :181, calls `controller.loadMedia(item, autoplay: autoPlayOnOpen)` :195 (a `startTime:` slot exists), `NSDocumentController.shared.noteNewRecentDocumentURL` :219. `ContentView` wires `onClose` at ContentView.swift:267-277 and runs the same `stopPlaybackForWindowClose` (:592) again in `.onDisappear` (:389), so any save-on-close must be idempotent. `AppDelegate.applicationShouldTerminate` is at Aagedal_Media_PlayerApp.swift:410 (no willTerminate observer today).
- Now Playing: `MediaPlayer` framework is imported nowhere; no `MPRemoteCommandCenter`/`MPNowPlayingInfoCenter`. mpv media keys are disabled (`input-media-keys no`, MPVPlayer.swift:387).
- Resume storage: none. `UI/InitialWindowController.swift:11` states "the app stores no playback position" (deliberate IINA divergence). Closest identity helper: `CompareReviewSourceIdentity` (Models/CompareReviewNote.swift:198: `canonicalPath`, `fileSystemNumber`, `fileNumber`, `fileSize`, `modificationDate`; `init(url:fileManager:)`, `matches(url:fileManager:)` :218, Codable/Equatable/Sendable).
- `ComparisonStillFrameExtractor.image(from:at:maximumSize:tolerance:) async throws -> CGImage` (Logic/ComparisonStillExporter.swift:434, `@concurrent`, AVAssetImageGenerator then ffmpeg fallback) - usable for Now Playing artwork.
- App is NOT sandboxed: `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES` (pbxproj :373-374, :407-408); entitlements file `Aagedal Media Player/Aagedal_Media_Player.entitlements`.
- AccessibilityNotification announcements already used (`ContentView.announce`, :~580).

## 10. Tests

Target "Aagedal Media Player Tests" (scheme "Aagedal Media Player", shared). Import: `@testable import Aagedal_Media_Player`. Pure-logic, no-window model to copy: `T/WindowConfiguratorTests.swift` (decision functions as `nonisolated static`) or the small `T/KeyBindingDefaultsTests.swift`:
```swift
// Aagedal Media Player
// Copyright (c) 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Aagedal_Media_Player

final class KeyBindingDefaultsTests: XCTestCase {
```
(@MainActor classes use `@MainActor final class XTests: XCTestCase`, e.g. PlayerKeyMapTests.) Pure decision code should be `nonisolated enum`/static funcs, matching `PlaybackVolume`, `PlayerKeyMap`, `WindowConfigurator.shouldMaximize`. Run one class:
```
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/PlaybackVolumeTests"
```
(`-only-testing:` takes `<TestTarget>/<Class>[/<method>]`; CLAUDE.md only documents the unfiltered form, the `-only-testing` form is standard xcodebuild). Project memory: batch builds, verify once per checkpoint.

---
## Claim verdict table (Part 0 items relevant to the plan + all Section A)

| # | Claim | Verdict / truth |
|---|---|---|
| P0.2 | addSubtitle never refreshes track options; buildMPVSubtitleTrackOptions dead | CONFIRMED (PlayerController.swift:1533, :1518 zero callers; refresh only at :616). Lines in review wrong |
| P0.3 | Secondary leaks SleepPreventer entry | PARTLY: only primary is forgotten (ContentView.swift:597), but `teardown()` sets isPlaying=false (:1680), so no assertion leak, at most a stale dict entry. "Replace" scenario N/A: `secondaryController` is a `let` (CompareSessionController.swift:402) |
| P0.4 | fullscreen/live-resize/layout-jump post `.reloadPlayer` | CONFIRMED (MPVVideoView.swift:307-353, :394, :404); playback state is preserved via reloadPreservingPlaybackState |
| P0.5 | Dual key monitors | CONFIRMED in shape (MPVVideoView.swift:450, PlayerView.swift:552, PlayerOverlayController.swift:54 Tab-only); lines in review wrong |
| P0.7 | setRenderProfile writes UserDefaults, Enhance Now overwrites global | CONFIRMED (MPVPlayer.swift:1337; PlayerView.swift:127; handler unguarded ContentViewCommandHandlers.swift:148) |
| P0.10 | display-resample + interpolation forced | NOT CHECKED (not needed by Section A) |
| A1.1 | performDrag after 3 pt threshold, store mouseDownEvent | Design, no code claim; the NSEvent reuse pattern is plausible; swallow-mouseUp/clickCount effects UWR |
| A1.2 | clickCount==2 on mouseDown, no delay needed | Design; consistent with VLC ground truth; UWR |
| A1.3 | Surface below inspector/overlayControls/waveform so SwiftUI controls get clicks | Layering CONFIRMED (ContentView.swift:192-250); hit-test interplay of NSViewRepresentable vs SwiftUI in one NSHostingView UWR |
| A1.4 | Insert at ComparePlayerView.swift:62 between comparisonSurfaces and wipe overlay | WRONG line: ZStack is :47-77, comparisonSurfaces :48-54, wipe overlay :72. Position choice valid |
| A1.5 | Wipe strip is at ComparePlayerView.swift:267 | WRONG: :322-360 (gesture :378) |
| A1.6 | `.onContinuousHover` / `.onHover` continue to work | Exists (ContentView.swift:168, :280, :467); non-interference UWR |
| A1.7 | `acceptsFirstMouse` true | Design; UWR |
| A1.8 | Magnify toggles same action | Not VLC ground truth; unrequested; omit |
| A2.1 | contentAspectRatio does not constrain programmatic setFrame | WRONG per repo (WindowConfigurator.swift:109-118: "AppKit reshapes setFrame to the locked ratio"); clear lock first |
| A2.2 | maximize() at :127 clears lock, applyMinSize(nil), then setFrame(visibleFrame, animate: true) | PARTLY: it is :119 and uses `animate: false` |
| A2.3 | openMaximized default true at AppSettings.swift:26 | CONFIRMED value; line is :32 |
| A2.4 | savedPreMaximizeFrame, toggleFillScreen, centeredSourceFrame | NOT FOUND (all new). `lastAspectRatio`, `lastSourceSize` CONFIRMED (:57,:59) but `lastAspectRatio` is set nil while in fullscreen / when controller ratio is nil, so prefer `savedAspectRatio` |
| A2.5 | window.zoom conflicts with SwiftUI delegate | UWR; nothing in repo uses zoom/delegate |
| A2.6 | Coordinator reachable from command handler | WRONG implicit: no external handle (trap 4) |
| A3 | VLC thresholds/axis lock/inversion/momentum | VLC facts match ground truth. `VideoScrollWheelHandler` NOT FOUND (new). Per-window volume convention CONFIRMED (PlayerView.swift:415-418); seek via `.seekBySeconds` is broadcast when sync on (handlers :445). Review's "PlayerView.swift:412" is :415 |
| A3b | Natural-direction sign math (dX = -deltaX*sign) | UWR; unit-testable if extracted as pure func |
| A4 | ClosureMenuItem pattern | Design; not present in repo; context-menu items needing APIs that don't exist: Stop (no PlayerController.stop), Speed set (no setter), Audio/Sub delay, aspect, crop, deinterlace runtime, Float on Top, Window Size, Jump to Time (all NOT FOUND). Existing: chapters `jumpToChapter`, `selectAudioTrack`, `selectSubtitleTrack`, `addSubtitle`, `RenderProfile` + `.setRenderProfile` |
| A5.1 | Local monitor runs before menu performKeyEquivalent | Standard AppKit; consistent with code |
| A5.2 | Bare t/m/j/l/space menu shortcuts at App.swift:127,173,193,199 | Shortcuts CONFIRMED but lines are :145, :198, :218, :224, :192 |
| A5.3 | They fire while typing in a TextField | UWR (see item 6) |
| A5.4 | `NSApp.keyWindow?.firstResponder is NSTextView` guard | Not present today (only isEditingTimecode/isTextInputActive); proposal valid |
| A5.5 | Unify KeyBindingAction (KeyBindingAction.swift:17) with VLC actions incl. seek/volume | Enum line :17 CONFIRMED; BUT file header (:9-13) deliberately excludes arrows/seek matrix; `PlayerKeyMap.resolve(event:)`, `KeyBindingPresets`, `AppSettings.keymapPreset` NOT FOUND |
| A5.6 | AMP Pro ⇧→ = 10 s etc. | CONFIRMED as current arrow matrix (PlayerKeyMap.swift:117-169) |
| A6.1 | `.focusedSceneObject(controller)` at ContentView.swift:221 | NOT FOUND today (proposal); existing: four `.focusedSceneValue` Bools :253-256, `@FocusedValue` in App :49-52 |
| A6.2 | PlayerController publishes track arrays via trackSelectionCancellable | CONFIRMED (:82-88, :235-237) |
| A6.3 | SwiftUI wipes manual NSApp.mainMenu edits | UWR |
| A7.1 | PlayerOSDController | NOT FOUND (new). `DeferredMainActorTask.schedule(after:)` signature matches use. `AccessibilityNotification.Announcement` already used (ContentView.swift announce) |
| A7.2 | top-right free | WRONG: EnhancementSuggestionView `.topTrailing` (PlayerView.swift:135) and inspector panel occupy top-right |
| A7.3 | osd-level=0, screenshotRaw unaffected | CONFIRMED osd-level 0 (MPVPlayer.swift:369) |
| A8.1 | App not sandboxed | CONFIRMED (pbxproj) |
| A8.2 | CompareReviewSourceIdentity at CompareReviewNote.swift:162 | WRONG line: :198 (fields confirmed; `matches(url:)` :218) |
| A8.3 | UpdateAvailableBanner at PlayerOverlayViews.swift:235 | WRONG: :275 |
| A8.4 | `loadMedia(item, startTime:, autoplay:)`, `controller.seekTo` | CONFIRMED (:254, :1251) |
| A8.5 | ResumePositionStore / policy enum | NOT FOUND (new). Existing comment says app stores no position (InitialWindowController.swift:11). Store rules in review match VLC ground truth; ask/always/never and 10 s countdown are new |
| A8.6 | Save on stopPlaybackForWindowClose / app terminate | Close hook CONFIRMED (called twice); willTerminate observer NOT FOUND |
| A9.1 | input-media-keys=no at MPVPlayer.swift:320 | Fact CONFIRMED; line is :387 |
| A9.2 | MediaPlayer framework imported / now playing | NOT FOUND (new). Entitlement-free claim UWR |
| A9.3 | openNextFile/openPreviousFile routes | CONFIRMED: `.openNextFile/.openPreviousFile` -> ContentView funcs |
| A9.4 | `currentPlaybackSpeed` | CONFIRMED (:79, Float, read-only) |
| A9.5 | ComparisonStillFrameExtractor.image(from:at:maximumSize:) | CONFIRMED (Logic/ComparisonStillExporter.swift:434; has extra `tolerance` default) |
| A10.1 | openAtSourceResolution dead on first file because openMaximized wins | CONFIRMED and WIDER: dead for every load (see item 7); GeneralSettingsView toggle at :39 not :37 |
| A10.2 | WindowConfigurator.shouldMaximize :28 | Real :30 |
| A10.3 | `.scaleWindow(WindowSizePreset)` | NOT FOUND (new); `backingScaleFactor` division pattern CONFIRMED (WindowConfigurator.swift:164) |
| A10.4 | Re-lock aspect on willStartLiveResize | NOT FOUND; contradicts existing intent (didExitFullScreen deliberately leaves a maximized window unlocked, :250-259) |
| A10.5 | Float on Top | NOT FOUND (no window.level for player windows; AudioWaveformWindowController.swift:71 uses .floating for its panel) |
| A10.6 | titleVisibility hidden at WindowConfigurator.swift:225 | CONFIRMED value; line :285. Window title is already set to file name (PlayerWindowCoordinator.swift:181) |
| A11.1 | mpv gain cubic; mpvValue formula with 125 cap | Cubing CONFIRMED (PlaybackVolume.swift comment); new formula arithmetic correct (100*cbrt(1.25)=107.72). Current cap is `min(100, ...)` |
| A11.2 | mpv default volume-max 130 | Not set in repo; mpv default per upstream, UWR; setting it explicitly is harmless |
| A11.3 | AVPlayer.volume > 1 | UWR (Apple documents 0...1); safest clamp to 1.0 in `AVFoundationPlayerBackend` (PlayerBackendAdapter.swift:47-50) |
| A11.4 | Volume clamps at PlayerController.swift:56, :488 | WRONG: clamps at :43, :230, :845 |
| A11.5 | AVAudioChannelRouter tap exists | CONFIRMED (:48) but only installed for non-default routing |
| A11.6 | slider.maxValue=100 at PlaybackVolumeSlider.swift:17; `Control.draw(_:)` | maxValue CONFIRMED :17; `draw` override NOT FOUND (add), no snapping code |
| A11.7 | Existing test impact | `PlaybackVolumeTests` :14 asserts 200 -> 100; update |
| A12.1 | Jump to Time: editor exists in ControlsView | PARTLY: editor exists only in compare ControlsView (trap 5); ordinary mode uses FloatingOSCView with none |
| A12.2 | A->B loop via trimIn/trimOut + ab-loop-a/b | trimIn/trimOut CONFIRMED (PlayerController.swift:129-130); ab-loop NOT FOUND; trim has no loop behaviour today |
| A12.3 | Remaining-time toggle at FloatingOSCView.swift:115 | `timeLabel(duration)` is :112, helper :116; no click/AppStorage exists |
| A12.4 | window.titleVisibility/representedURL proxy icon | titleVisibility hidden confirmed; representedURL NOT FOUND |
| A12.5 | Pause on minimize | NOT FOUND (no miniaturize observer, no setting) |
| A12.6 | audio-delay/sub-delay via setDouble | Properties unused; `setDouble` is private (use `setString` which is internal) |
| A12.7 | video-aspect-override / video-crop / panscan | Unused; same visibility note |
| A12.8 | Video effects properties | Unused; not requested by VLC ground truth |
