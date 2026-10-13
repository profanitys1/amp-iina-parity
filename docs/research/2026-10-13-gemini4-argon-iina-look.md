Below is the complete, code-audited specification to make **Aagedal Media Player (AMP)** visually indistinguishable from **IINA v1.5.0** (`tag v1.5.0`, commit `fbcff4d`) while preserving all decided **VLC macOS standard interaction behaviours** and retaining every **AMP-exclusive inspection/pro feature** restyled in IINA’s visual language.

---

## 1. Player window chrome

| Element | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **1.1 Window class & styleMask** | `MainWindow` (`MainWindow.swift:11`), XIB `F0z-JX-Cv5` (`MainWindowController.xib:21`): `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`; `window.styleMask.insert(.fullSizeContentView)` (`MainWindowController.swift:283`); `tabbingMode="disallowed"`, `restorable="NO"`, `releasedWhenClosed="NO"` | SwiftUI `WindowGroup(id: "player")` with `.windowStyle(.hiddenTitleBar)` (`Aagedal_Media_PlayerApp.swift:61`), `WindowConfigurator.swift:267` inserts `.fullSizeContentView`, `isRestorable = false` | Keep `.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView`; explicitly set `window.tabbingMode = .disallowed` in `WindowConfigurator.ConfiguratorNSView.viewDidMoveToWindow()` | S |
| **titlebarAppearsTransparent & titleVisibility** | `window.titlebarAppearsTransparent = true` (`PlayerWindowController.swift:178`), `window.titleVisibility = .hidden` (`Titlebar.swift:112`); in native fullscreen `titleVisibility = .visible` (`Titlebar.swift:219`) and `titlebarAppearsTransparent = false` (`MainWindowController.swift:835`) | `window.titlebarAppearsTransparent = true`, `window.titleVisibility = .hidden` always (`WindowConfigurator.swift:268-269`) | Toggle `titleVisibility = .visible` and `titlebarAppearsTransparent = false` inside `willEnterFullScreen` / `didEnterFullScreen`, and restore on exit | S |
| **Toolbar & Corner Radius (macOS 26)** | `MainWindowController.swift:499-515`: when `!compactUI` (default `false`) and windowed: `window.toolbar = NSToolbar()`, `window.toolbarStyle = .unifiedCompact` (or `.unified` when leading sidebar open), `displayMode = .iconOnly`. On macOS 26, an attached `NSToolbar` changes the window’s concentric corner radius to the Tahoe unified radius (~16 pt vs standard 10 pt) | No `NSToolbar` attached (`window.toolbar == nil`) | In `WindowConfigurator`, attach an empty `NSToolbar()` with `window.toolbarStyle = .unifiedCompact` and `toolbar.displayMode = .iconOnly` when windowed (nil in fullscreen/fill-screen) | S |
| **isMovableByWindowBackground** | `false` (`MainWindowController.swift:286` comments out `isMovableByWindowBackground = true`), manual drag in `mouseDragged` after `minimumInitialDragDistance: CGFloat = 3.0` (`MainWindowController.swift:27, 608-625`) | Handled by SwiftUI/AppKit default | Keep `window.isMovableByWindowBackground = false` and drag via `window.performDrag(with: event)` after `hypot(dx, dy) > 3.0` on video surface | S |
| **collectionBehavior** | `MainWindowController.swift:1454-1461`: `[.managed, .fullScreenPrimary]` (or `[.managed, .fullScreenAuxiliary]` when `useLegacyFullScreen`) | Default SwiftUI window collectionBehavior | Set `window.collectionBehavior = [.managed, .fullScreenPrimary]` | S |
| **Appearance & backgroundColor** | `PlayerWindowController.swift:238-243`: `Preference.Theme.dark` (default `0` in `Preference.swift:591`) sets `window.appearance = NSAppearance(named: .darkAqua)` and `window.backgroundColor = window.effectiveAppearance.isDark ? .black : .white` | `window.backgroundColor = .black` (`WindowConfigurator.swift:265`), no forced appearance | Force `window.appearance = NSAppearance(named: .darkAqua)` by default (or bind to theme setting) so all materials/controls match IINA Dark | S |
| **hasShadow & isOpaque** | `window.hasShadow = true` in windowed, `false` in legacy fullscreen (`MainWindowController.swift:1012, 1072`). `VideoView.isOpaque = true` (`VideoView.swift:41`) | `hasShadow = true` always | Set `window.hasShadow = false` when entering VLC "fill screen, stay windowed" mode; restore `true` on exit | S |
| **1.2 Title bar container & height** | Custom `Titlebar: NSView` (`Titlebar.swift:19-297`). Height = `LayoutValue.titlebarHeight`: `TitleBarHeightNormal = 32` on macOS 26, `28` on macOS ≤15; non-compact adds `+ 8` → **40 pt** on macOS 26 (compact 32 pt), **36 pt** on macOS ≤15 (compact 28 pt) (`Titlebar.swift:8-17`) | No custom title bar view; traffic lights float over raw video (`WindowConfigurator.swift:88-103`) | Add `IINATitleBarView` at top of `ContentView` with height `40 pt` (macOS 26) / `36 pt` (macOS ≤15) | M |
| **Title bar material & bottom border** | `background = NSVisualEffectView()`, `blendingMode = .withinWindow`, `material = .titlebar`, `state = .active` (`Titlebar.swift:75-83`) + bottom 1 pt `NSBox` (`boxType = .separator`, `fillColor = .titleBarBorder`: Dark `sRGB(0,0,0,1.0)`, Light `sRGB(0.659,0.659,0.659,1.0)`) (`Titlebar.swift:89-92`, `TitleBarBorder.colorset`) | None | Render `NSVisualEffectView(material: .titlebar, blendingMode: .withinWindow, state: .active)` + 1 pt bottom border (`Color.black` in Dark, `Color(srgbRed: 0.659, green: 0.659, blue: 0.659)` in Light) | M |
| **Title text, docIcon & accessory buttons** | `docIcon`: `16×16 pt`, `leading = 86 pt` (`Titlebar.docIconLeadingPadding`, clears traffic lights +unifiedCompact toolbar). `titleTextField`: `.titleBarFont(ofSize: 13)` (`13 pt` regular/semibold per OS), `lineBreakMode = .byTruncatingMiddle`, `spacing(.leading(2), to: docIcon)`. On macOS 26: left-aligned after `86 pt`; on macOS ≤15: centered (`titleCenterConstraint`, `Titlebar.swift:136-163`). Right accessories (`trailing = 8 pt`, `spacing = 8 pt`): `removeBlackBarButton` (`remove.blackbars` custom symbol, `12 pt regular`, height `16 pt`) and `onTopButton` (`pin` / `pin.fill`, `12 pt regular`, height `16 pt`) (`Titlebar.swift:24, 59-105, 165-172`). Right-clicking title/icon pops path menu (`Titlebar.swift:256-297`) | No title text or document icon over video; transport-sync badge is in `FloatingOSCView` | Build `IINATitleBarView` with `86 pt` leading inset, `16×16` `NSWorkspace.shared.icon(forFile:)`, `2 pt` gap, `13 pt` title label, right-click path menu, and trailing pin (`pin`/`pin.fill`) + AMP badges | M |
| **Traffic lights & Title bar fade** | Standard buttons `[.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton]` registered in `fadeableViews` (`MainWindowController.swift:235-254`). Fade duration `UIAnimationDuration = 0.25 s` (`MainWindowController.swift:16, 1185-1231`). When hidden, traffic light buttons set `alphaValue = 1e-100` (not `isHidden = true`, so hover/click rects still work!). Auto-hide timer = `Preference.controlBarAutoHideTimeout` = **2.5 s** (`Preference.swift:583`) | `WindowConfigurator.swift:88-103` fades `button.superview` with `duration = 0.2 s` to `0.0` | Change traffic light fade duration in `WindowConfigurator.swift:95` from `0.2` to `0.25`, fade individual buttons to `1e-100` when hidden, and sync with `titleBarView` alpha | S |
| **1.3 Sizes & Aspect Ratio** | `AppData.sizeWhenNoVideo = NSSize(width: 640, height: 360)` (`AppData.swift:56-58`), `AppData.mainWindowMinSize = NSMakeSize(285, 120)` (`AppData.swift:59`). Frame autosave key `"MainWindowLastPosition"` (`MainWindowController.swift:775`). Open resize animation: `window.setFrame(rect, display: true, animate: true)` (system duration) unless `disableAnimations` (`MainWindowController.swift:1388-1393`) | `defaultSize(width: 711, height: 400)` (`Aagedal_Media_PlayerApp.swift:62`), `minWidth: 270, minHeight: 200` (`ContentView.swift:198`), `baseMinWidth = 690, baseMinHeight = 540` (`WindowConfigurator.swift:12-13`), `animate: false` | Set `mainWindowMinSize = NSSize(width: 285, height: 120)` in `WindowConfigurator` and `ContentView`; keep VLC sizing semantics as required, but use IINA’s `285×120` floor | S |
| **1.4 Video view & Buffering overlay** | `ViewLayer.backgroundColor = NSColor.black.cgColor` (`ViewLayer.swift:107`). Window background `.black` in Dark, `.white` in Light (`MainWindowController.swift:289`). `videoView` has `0 pt` padding on all 4 sides when `edgeToEdgeVideo == true` (default `true`, `MainWindowController.swift:549-569`). Buffering overlay (`BufferIndicatorView.swift:9-84`): centered `TranslucentView(padding: (16, 8))` (`NSGlassEffectView` radius `16` on macOS 26 / `NSVisualEffectView(.popover)` radius `8` on macOS ≤15), containing vertical `NSStackView(spacing: 4, width: 150)` with `.all(4)` inner padding: spinning `NSProgressIndicator`, `progressLabel` (`13 pt` system: `"Opening stream…"` / `"Buffering… %d%%"` / `"Seeking…"`), `detailLabel` | `PlayerView.swift:164-170`: `stateProgressOverlay` uses `padding(18)` and `.background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))` | Restyle `stateProgressOverlay` and `playbackStateOverlay` in `PlayerView.swift` to use `IINATranslucentView(cornerRadius: 16, padding: (20, 12))` with `width: 150` and `spacing: 4` | S |
| **1.5 HDR Black-Screen Workaround** | `MainWindowController.swift:296-305`: `0.1×0.1 pt` subview with `backgroundColor = .black`, `opacity = 0.01` (optional via `enableHdrWorkaround`) | Not present | No change needed unless Ventura HDR dimming is observed | S |

```swift
// WindowConfigurator.swift — exact IINA min size, appearance, and traffic-light fade
static let baseMinWidth: CGFloat = 285
static let baseMinHeight: CGFloat = 120

func applyTrafficLightAlpha(_ window: NSWindow, animated: Bool = true) {
    let targetAlpha: CGFloat = lastTrafficLightAlpha == 0 ? 1e-100 : 1.0
    let buttons = ([.closeButton, .miniaturizeButton, .zoomButton, .documentIconButton] as [NSWindow.ButtonType])
        .compactMap { window.standardWindowButton($0) }
    let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.0 : 0.25
    NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = animated ? duration : 0.0
        for btn in buttons {
            btn.animator().alphaValue = targetAlpha
        }
    }
}
```

---

## 2. On-screen controller (OSC)

### 2.1 – 2.5 IINA OSC Specifications (Floating, Top/Titlebar, Bottom, Music Mode)

| Element | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **2.1 Floating Container (`OSCFloatingView`)** | `OSCFloatingView.swift:14-68`, `TranslucentView.swift:9-119`:<br>• Width: `460 pt` (priority `300`), min width `>= 200 pt`, horizontal margin from `videoViewContainer` `>= 1 pt` (drag clamp `10 pt` left/right, `0 pt` bottom, `25 pt` top; `OSCFloatingView.swift:71, 148-150`)<br>• Height: `~67 pt` (`14` top pad + `24` top row + `8` row gap + `27` slider row + `8` bottom pad − `6` alignmentRectInsets)<br>• Corner radius: **`12 pt`** on macOS 26 (`NSGlassEffectView`), **`6 pt`** on macOS ≤15 (`NSVisualEffectView`, `material = .popover`, `blendingMode = .withinWindow`, `state = .active`)<br>• Border & Shadow: **None** (native `NSGlassEffectView` / `NSVisualEffectView` only)<br>• Default position: `controlBarPositionHorizontal = 0.5` (centerX), `controlBarPositionVertical = 0.1` (`10%` from bottom; `Preference.swift:580-581`)<br>• Center snap: `controlBarStickToCenter = true`, threshold `abs(newOrigin.x - xPosWhenCenter) <= 5 pt`, haptic `.alignment` (`OSCFloatingView.swift:136-146`) | `FloatingOSCView.swift:14-56`:<br>• Width `460`, minWidth `200`, cornerRadius `12`<br>• Uses SwiftUI `.ultraThinMaterial` + `.black.opacity(0.34)` + `.strokeBorder(.white.opacity(0.12), lineWidth: 0.5)` + `.shadow(color: .black.opacity(0.35), radius: 12, y: 4)` | Replace `.ultraThinMaterial` + custom border/shadow with `IINATranslucentEffectView` wrapping `NSGlassEffectView(cornerRadius: 12)` on macOS 26 and `NSVisualEffectView(material: .popover, blendingMode: .withinWindow)` (`cornerRadius: 6`) on macOS ≤15 | M |
| **Top Bar OSC (`Titlebar.oscContainer`)** | `Titlebar.swift:176-185`, `MainWindowController.swift:666-678`:<br>• Single horizontal `TimeLabelOverflowedStackView` inside `Titlebar`, height `24 pt`, leading `6 pt`, trailing `6 pt`, top `0 pt` (`8 pt` in fullscreen), bottom `LayoutValue(10, 6)`<br>• Order L→R: `oscPlayControlView` (`.leading`) → `oscSliderView` (`.leading`, `.mustHold`) → `oscVolumeView` (`.trailing`, `.detachEarly` = `850`) → `oscToolbarView` (`.trailing`, `.detachEarlier` = `800`)<br>• Middle transport button spacing = `16 pt` (`MainWindowController.swift:693`) | Not implemented | Optional layout variant (if AMP exposes IINA OSC position setting); Floating is default | M |
| **Bottom Bar OSC (`OSCBottomView`)** | `OSCBottomView.swift:9-56`, `MainWindowController.swift:679-691`:<br>• Full window width at bottom edge; `TranslucentView` with `cornerRadius = 0`<br>• Padding: vertical `LayoutValue(12, 8)`, leading `LayoutValue(16, 12)`, trailing `LayoutValue(12, 8)`<br>• Same single-row element order & visibility priorities as Top Bar; transport spacing `16 pt` | Compare Mode uses `ControlsView` as a bottom bar with `12 pt` outer padding and `10 pt` corner radius (`ContentView.swift:324-345`) | Restyle Compare Mode’s `ControlsView` to use `IINATranslucentEffectView` (`NSGlassEffectView` / `NSVisualEffectView(.popover)`) and IINA paddings (`16` leading, `12` trailing, `10` vertical) | M |
| **2.2 Floating Layout Grid** | `OSCFloatingView.swift:32-41`, `MainWindowController.swift:344-409, 646-665`:<br>• **Row 1 (`oscTopView`)**: `.top(LayoutValue(14, 10))`, `.horizontal(12)`, height `24 pt`<br>  - **Leading**: `oscVolumeView` (`muteButton` `24×24` at `.leading(4)` + `4 pt` gap + `volumeSlider` `width: 70` + `.trailing(6)` = `108 pt` total; detachment `.detachOnlyIfNecessary`)<br>  - **Center**: `oscPlayControlView` (`oscSpeedLabelLeftContainer` `width: 30` + `[leftArrow 24×24, 24 pt gap, playButton 24×24, 24 pt gap, rightArrow 24×24]` + `oscSpeedLabelRightContainer` `width: 30`)<br>  - **Trailing**: `oscToolbarView` (horizontal stack, `spacing = 0`, `height = 24`, up to 5 buttons × `24×24` (`20×24` when 5 buttons), detachment `.detachOnlyIfNecessary`)<br>• **Row 2 (`oscBottomView`)**: `spacing(.top(8), to: oscTopView)` (visually `2 pt` due to `TimeLabelOverflowedView.alignmentRectInsets.top = 6`), `.bottom(LayoutValue(8, 5))`, `.horizontal(8)`<br>  - `leftLabel` (`.leading(2)`, `minWidth >= 46`) → `2 pt` gap → `playSlider` (`.vertical(6)`) → `2 pt` gap → `rightLabel` (`.trailing(2)`, `minWidth >= 46`) | `FloatingOSCView.swift:59-165`:<br>• `volumeSlider` width is `60` (missing `.leading(4)` and `.trailing(6)` padding)<br>• Transport buttons use SF Symbols `gobackward.10`/`goforward.10` instead of `speedl`/`speed` PDFs, and lacks `30 pt` speed label containers<br>• `scrubberRow` lacks `TimeLabelOverflowedView` `top: 6` inset | Update `FloatingOSCView`:<br>1. `volumeSlider` width `70 pt`, leading pad `4 pt`, gap `4 pt`, trailing pad `6 pt`<br>2. Add `30 pt` left/right speed label slots around transport buttons<br>3. Set `scrubberRow` top spacing to `2 pt` (matching `8 pt - 6 pt` alignment inset) | S |
| **2.3 Transport & Volume Buttons** | • **Play/Pause**: Asset `play.pdf` / `pause.pdf` (template), button frame `24×24 pt`, `.smallSquare`, borderless (`PlayerWindowController.swift:185-186`, `MainWindowController.swift:361-366`)<br>• **Left/Right Arrow**: Asset `speedl.pdf` / `speed.pdf` (or `nextl.pdf` / `nextr.pdf` when `arrowButtonAction == .playlist`), frame `24×24 pt`, spacing `24 pt` (floating) / `16 pt` (top/bottom)<br>• **Mute/Volume (`VolumeButton.swift:9-71`)**: `24×24 pt` view, `imageScaling = .scaleProportionallyDown`, SF Symbol `13 pt, weight: .regular`:<br>  - Muted: `"speaker.slash.fill"` (with `.replace.offUp` symbol transition on macOS 15+)<br>  - `0`: `"speaker.fill"`<br>  - `1...33`: `"speaker.wave.1.fill"`<br>  - `34...66`: `"speaker.wave.2.fill"`<br>  - `>= 67`: `"speaker.wave.3.fill"` | • Uses SF Symbols `play.fill`/`pause.fill` at `16 pt`, `gobackward.10`/`goforward.10` at `14 pt medium`<br>• Volume icon uses `14 pt medium` and shows `speaker.slash.fill` when `volume == 0` (IINA uses `speaker.fill` for `0` and `speaker.slash.fill` only when muted) | • Copy `play.pdf`, `pause.pdf`, `speed.pdf`, `speedl.pdf`, `next.pdf`, `nextr.pdf` from IINA `Assets.xcassets/Icons` (or render exact vector paths) at `24×24 pt`<br>• Fix volume icon at `volume == 0 && !isMuted` to `"speaker.fill"` at `13 pt regular` with `.contentTransition(.symbolEffect(.replace.offUp))` | S |
| **OSC Toolbar Buttons (`Preference.ToolBarButton`)** | `Preference.swift:448-524`, `OSCToolbarButton.swift:13-24`:<br>• Frame: `24×24 pt` (`20×24 pt` when 5 buttons), spacing `0 pt`, `bezelStyle = .regularSquare`, `isBordered = false`<br>• Default set (`Preference.swift:585`): `[.plugins, .pip, .playlist, .settings]`<br>• Symbols (`pointSize: 14, weight: .medium`, except `.pip` & `.plugins` at `13.5 pt medium`):<br>  - `.settings`: `"gearshape"` (active: `"gearshape.fill"`), tooltip `"Quick Settings"`<br>  - `.playlist`: `"list.bullet.rectangle"` (active: `"list.bullet.rectangle.fill"`), tooltip `"Playlist and chapters"`<br>  - `.pip`: `"pip.enter"` `13.5 pt` (active: `"pip.exit"`), tooltip `"Toggle Picture-in-Picture"`<br>  - `.fullScreen`: `"arrow.up.backward.and.arrow.down.forward.rectangle"` (active: `"arrow.down.forward.and.arrow.up.backward.rectangle"`), tooltip `"Toggle full screen"`<br>  - `.musicMode`: `"microphone.dynamic.on.stand"` (fallback `"music.microphone"`), tooltip `"Enter music mode"`<br>  - `.subTrack`: `"captions.bubble.fill"`, tooltip `"Choose subtitle track"`<br>  - `.screenshot`: `"camera.shutter.button"`, tooltip `"Take a screenshot"`<br>  - `.plugins`: `"puzzlepiece.extension"` `13.5 pt` (active: `"puzzlepiece.extension.fill"`), tooltip `"Show plugins panel"`<br>  - `.liveText`: `"document.viewfinder"` (active: `"viewfinder.circle.fill"`), tooltip `"Toggle Live Text"` | `FloatingOSCView.swift:145-172` has `TransportSyncStatusView`, `gearshape` (opens App Settings instead of Quick Settings sidebar), `list.bullet.rectangle` (never switches to `.fill` when active), `captions.bubble.fill`, `arrow.up.left.and.arrow.down.right` | Use exact IINA symbol names, sizes (`14 pt` / `13.5 pt`, `.medium`), active `.fill` states when sidebar/fullscreen is active, and IINA tooltips (`"Quick Settings"`, `"Playlist and chapters"`, `"Choose subtitle track"`, `"Toggle full screen"`) | S |
| **2.4 Show/Hide & Cursor** | `MainWindowController.swift:16, 709-733, 1171-1255`:<br>• Trigger: mouse enter/move in window shows UI; mouse exit hides UI immediately (`0.25 s` fade)<br>• Auto-hide delay: `Preference.controlBarAutoHideTimeout` = **`2.5 s`** (`Timer.scheduledTimer`), destroyed while mouse is inside `[currentControlBar, titleBarView]` or while dragging `oscFloatingView`<br>• Does IINA keep OSC visible while paused? **No** — IINA auto-hides OSC after `2.5 s` even when paused if mouse is not over OSC/titlebar (`createTimer()` does not gate on `isPlaying`)<br>• Fade duration: `UIAnimationDuration = 0.25 s` (default `NSAnimationContext` easeInEaseOut curve)<br>• Cursor: `NSCursor.setHiddenUntilMouseMoves(true)` called when `hideUIAndCursor()` fires, and re-armed on mouseDown/Up/rightMouseDown when `animationState == .hidden` (`workaroundCursorDefect()`) | `PlayerOverlayController.swift:24, 96-112` uses `hideDelay = 2.5 s` and `0.25 s` fade (`ContentView.swift:146`), **but** `scheduleHide` gates on `isPlaying()` (`PlayerOverlayController.swift:100`), keeping OSC permanently visible when paused | Remove `isPlaying()` gate in `PlayerOverlayController.scheduleHide` so the OSC auto-hides after `2.5 s` even when paused (unless hovered or editing timecode/popover open), matching IINA | S |
| **2.5 Speed Indicators in OSC** | `MainWindowController.swift:368-383, 1347-1363`:<br>• `oscSpeedLabelLeft` / `oscSpeedLabelRight` inside `30 pt`-wide containers flanking `[leftArrow, play, rightArrow]` (`8 pt` inner gap)<br>• Font: `.systemFont(ofSize: 10)` (`10 pt regular`), colour `.secondaryLabelColor`<br>• Hidden when `speed == 1.0`; left shown when `speed < 1.0` (`String(format: "%.2fx", speed)`), right shown when `speed > 1.0` (`NumberFormatter` decimal, `maxSignificantDigits = 3`, `"\(str)x"`) | `FloatingOSCView` has no speed label; `PlaybackSpeedIndicator` is top-left over video | Add `oscSpeedLabelLeft` and `oscSpeedLabelRight` (`10 pt` regular, `.secondaryLabelColor`, `30 pt` container width) flanking transport buttons in `FloatingOSCView` | S |
| **2.6 AMP Mapping** | — | `gearshape` in `FloatingOSCView` opens macOS Settings window instead of in-window Quick Settings sidebar | Make `gearshape` in `FloatingOSCView` toggle the in-window Quick Settings / Inspector sidebar (with Video / Audio / Subtitles / Metadata tabs), and keep `TransportSyncStatusView` styled as a `24 pt`-tall `.secondaryLabelColor` icon/pill in the toolbar slot | M |

---

## 3. Sliders

| Element | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **3.1 Play/Seek Slider (`PlaySlider` / `PlaySliderCell`)** | `PlaySlider.swift:44-52`, `PlaySliderCell.swift:22-168`:<br>• `controlSize = .small`<br>• Bar height: AppKit `.small` slider bar height = **`3 pt`**, `barRadius = 1.5 pt` (`PlaySliderCell.swift:27`)<br>• Knob shape: rounded rectangle, `knobWidth = 3 pt`, `knobHeight = 15 pt`, `knobRadius = 1 pt` (`PlaySliderCell.swift:24-26`), X position `round(pos)`<br>• Knob colour (`MainSliderKnob.colorset` / `MainSliderKnobActive.colorset`):<br>  - Dark idle: `sRGB(1, 1, 1, 0.80)`, active/drag: `sRGB(1, 1, 1, 0.98)`<br>  - Light idle: `sRGB(1, 1, 1, 0.96)`, active/drag: `sRGB(1, 1, 1, 0.75)` + shadow (`blurRadius = 1`, `offset = (0, -0.5)`, `0.4 pt` stroke of `black.withAlphaComponent(1/3)`)<br>• Dark-mode knob gap: clips **`1 pt` clear gap** on both sides of knob (`NSRect(x: knobPos - 1, y: barRect.origin.y, width: knobWidth + 2, height: barRect.height)`, `PlaySliderCell.swift:134-137`)<br>• Bar colours (`MainSliderBarLeft.colorset` / `MainSliderBarRight.colorset`):<br>  - Played/Cached left: Dark `sRGB(1, 1, 1, 0.30)`, Light `sRGB(0, 0, 0, 0.40)`<br>  - Unplayed right: Dark `sRGB(1, 1, 1, 0.10)`, Light `sRGB(0, 0, 0, 0.20)`<br>• Chapter marks (`PlaySliderCell.swift:115-127`): **`1 pt` wide vertical cut-outs (transparent gaps)** clipped out of the bar at each `chapt.time.second / totalSec * barRect.width - 0.5`<br>• A-B Loop knobs (`PlaySliderLoopKnob.swift:31, 79-111`): `3 pt × 11 pt` (`round(15 * 0.75)`), radius `1 pt`, colour `MainSliderLoopKnob`: Dark `sRGB(0.65, 0.65, 0.65, 1.0)`, Light `sRGB(0.41, 0.41, 0.41, 1.0)` | `PlayerScrubber.swift:12-65`:<br>• Bar height `3 pt`, knob `3×15 pt`, radius `1 pt`<br>• Played fill is `.white.opacity(0.85)` (too bright vs IINA’s `0.30`)<br>• Unplayed fill is `.white.opacity(0.28)` (too bright vs IINA’s `0.10`)<br>• Knob fill is `.white` (`1.0`) with shadow always, no `1 pt` clear gap around knob in Dark mode<br>• Chapters use `ChapterTimelineMarkers` (`6 pt` diamonds below bar) instead of `1 pt` vertical gaps cut out of the bar | Update `PlayerScrubber.swift` (and `ControlsView.timelineSlider`):<br>1. Left bar fill: `Color.white.opacity(0.30)` (Dark) / `Color.black.opacity(0.40)` (Light)<br>2. Right bar fill: `Color.white.opacity(0.10)` (Dark) / `Color.black.opacity(0.20)` (Light)<br>3. Cut `1 pt` clear gaps around the knob (`knobPos - 1` to `knobPos + 4`) in Dark mode and `1 pt` clear gaps at each chapter position<br>4. Knob fill: `Color.white.opacity(isDragging ? 0.98 : 0.80)` in Dark mode (no shadow in Dark mode) | M |
| **Hover Time Preview (`TimePreviewView`) & Thumbnail (`ThumbnailPeekView`)** | • `TimePreviewView.swift:9-33`, `MainWindowController.swift:340, 1419-1450`:<br>  - Separate floating `TranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 8, padding: (4, 4))`<br>  - Text: `[chapter.title + "\n"] + time.stringRepresentation`, font `.monospacedDigitFont(for: .small)` (`11 pt regular`), centered<br>  - Position: centered on cursor X, `5 pt` above `playSlider.maxY` (or `5 pt` below `playSlider.minY` when OSC is at top)<br>• `ThumbnailPeekView.swift:11-44`, `MainWindowController.swift:1395-1417`:<br>  - Separate view `5 pt` above `timePreviewView.maxY` (or below if near top of window)<br>  - Width: `Preference.thumbnailWidth` = **`120 pt`** (`Preference.swift:620`), height = `round(120 / displayAspectRatio)`<br>  - Corner radius: **`4 pt`**, border: **`1 pt`** `CGColor(gray: 0.6, alpha: 0.5)`, shadow: `blurRadius = 2`, `offset = .zero`, `color = .black` | `PlayerScrubber.swift:128-142` & `ControlsView.swift:562-575`:<br>• Combines image (`160×90`) + time label (`10 pt`) inside one `.black.opacity(0.75)` or `.regularMaterial` box | Split or restyle hover preview to match IINA:<br>• Thumbnail: `120 pt` wide × `round(120 / aspect)`, `cornerRadius: 4`, `1 pt` border `Color(white: 0.6, opacity: 0.5)`, shadow `radius: 2, color: .black`<br>• Time pill below thumbnail (`5 pt` gap): `IINATranslucentView(cornerRadius: 16/8, padding: (4, 4))` with `11 pt` monospaced-digit text (plus chapter title line if present) | M |
| **3.2 Volume Slider (`VolumeSlider` / `VolumeSliderCell`)** | `PlayerWindowController.swift:191-199`, `MainWindowController.swift:351`, `VolumeSlider.swift:11-94`:<br>• `controlSize = .mini`, width = **`70 pt`** (in OSC) / `100 pt` (in MiniPlayer popover)<br>• Bar radius: `1.5 pt`<br>• Left fill (`VolumeSliderBarLeft.colorset`): Dark `sRGB(1, 1, 1, 0.30)`, Light `sRGB(0, 0, 0, 0.40)`<br>• Right fill (`VolumeSliderBarRight.colorset`): Dark `sRGB(1, 1, 1, 0.10)`, Light `sRGB(0, 0, 0, 0.10)`<br>• **>100% Volume Marker**: When `maxValue > 100` (e.g. VLC’s `125%` max), draws a **`2 pt` wide clear gap** at `x100 = round(rect.minX + rect.width * CGFloat(100 / maxValue))` (`VolumeSlider.swift:63-68`), plus haptic `.generic` when crossing `100..101` (`PlayerWindowController.swift:505`) | `PlaybackVolumeSlider.swift:13-24`:<br>• Uses default AppKit `NSSliderCell` with `controlSize = .small`, `maxValue = 100`, width `60 pt` (`FloatingOSCView`) / `72 pt` (`ControlsView`), system accent colour fill | Subclass `NSSliderCell` in `PlaybackVolumeSlider` using IINA’s exact `VolumeSliderCell.drawBar(inside:flipped:)`, set `controlSize = .mini`, width = `70 pt`, `maxValue = 125` (per VLC requirement), with the `2 pt` clear notch at `100%` | S |
| **3.3 AMP Mapping (`ControlsView` timeline)** | — | `ControlsView.swift:415-505`: Compare Mode timeline uses `4 pt` track, `#FF125C` `2×14 pt` playhead, cyan overlap bar (`6 pt`), blue trim region + `2×14 pt` markers, orange review markers (`3×14 pt`) | In `ControlsView.timelineSlider`:<br>• Use IINA’s `3 pt` track (`barRadius: 1.5`), `sRGB(1,1,1,0.30)` / `sRGB(1,1,1,0.10)` fills, and `3×15 pt` white rounded-rect playhead knob (`radius: 1 pt`)<br>• Keep AMP’s cyan overlap bar, blue trim region, and orange review markers, sized to `3 pt` bar height and `3×11 pt` (`PlaySliderLoopKnob` size) for trim In/Out knobs | M |

```swift
// PlaybackVolumeSlider.swift — IINA VolumeSliderCell with 100% notch for 125% VLC max volume
final class IINAVolumeSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let knobPos = round(knobRect(flipped: flipped).origin.x)
        let path = NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5)
        let x100 = round(rect.minX + rect.width * CGFloat(100.0 / maxValue))
        let isDark = controlView?.effectiveAppearance.isDarkAppearance ?? true

        let gapClip: NSBezierPath? = maxValue > 100
            ? NSBezierPath(rect: NSRect(x: x100 - 1, y: rect.minY, width: 2, height: rect.height)).reversed
            : nil

        NSGraphicsContext.saveGraphicsState()
        let clipLeft = NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: knobPos, height: rect.height))
        if let gapClip, x100 < knobPos { clipLeft.append(gapClip) }
        clipLeft.addClip()
        NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0, blue: isDark ? 1 : 0, alpha: isDark ? 0.3 : 0.4).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        let clipRight = NSBezierPath(rect: NSRect(x: rect.minX + knobPos, y: rect.minY, width: rect.width - knobPos, height: rect.height))
        if let gapClip, knobPos < x100 { clipRight.append(gapClip) }
        clipRight.addClip()
        NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0, blue: isDark ? 1 : 0, alpha: 0.1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}
```

---

## 4. Time labels

| Element | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **4.1 OSC Time Labels (`DurationDisplayTextField`)** | `DurationDisplayTextField.swift:11-94`, `MainWindowController.swift:387-399`, `VideoTime.swift:31-73`:<br>• Font: `NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)` (in MainWindow) / `9 pt` (`.mini` in MiniPlayer)<br>• Colour: `.secondaryLabelColor`<br>• Alignment: `.center`, `minWidth >= 46 pt`, hugging priority `251`<br>• Placement: `2 pt` leading/trailing outer pad, `2 pt` gap to `playSlider`, vertically centered with `playSlider`<br>• Format (`VideoTime.swift:41-72`): `h:mm:ss` when `h > 0`, `mm:ss` when `h == 0` (minutes always 2-digit `00`..`59`), rounding half down (`0.5 -> 0`, `0.51 -> 1`). Optional fractional precision via right-click context menu (`1s`, `100ms`, `10ms`, `1ms`)<br>• Click right label: toggles `.duration` ↔ `.remaining` (`"-\(remaining)"`), persisted in `Preference.showRemainingTime` | `FloatingOSCView.swift:100-105`:<br>• `11 pt` `.regular` `.monospaced` (uses full monospaced design instead of system proportional font with `.monospacedDigit()`), `.secondary`, `minWidth: 46`<br>• Right label is static duration (no click-to-toggle remaining time) | 1. Change font from `.system(size: 11, design: .monospaced)` to `.system(size: 11, weight: .regular).monospacedDigit()`<br>2. Add click handler on right time label to toggle elapsed/remaining (`"-mm:ss"`) persisted in `AppSettings.showRemainingTime` + right-click precision menu | S |
| **4.2 AMP Timecode Readout (`ControlsView`)** | — | `ControlsView.swift:669-725`: `12 pt medium monospaced` (`REL TC 00:00:00:00 / 00:00:00:00`), editor `140 pt` wide on `white.opacity(0.1)` `cornerRadius: 4` | Restyle `ControlsView.timecodeDisplay` to use `.system(size: 11, weight: .regular).monospacedDigit()`, prefix badge (`REL TC` / `SRC TC` / `FRM`) in `10 pt bold` `.secondaryLabelColor`, primary timecode in `.labelColor`, and `" / "` + duration/remaining in `.secondaryLabelColor` | S |

---

## 5. On-screen messages (OSD)

### 5.1 IINA OSD Container & Timing (`OSDView.swift`, `MainWindowController.swift`)

| Property | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **Position & Constraints** | `MainWindowController.swift:402-404`:<br>• Top-left of video area:<br>  - `spacing(.top(8), to: titleBarView)` (`8 pt` below titleBarView bottom)<br>  - `spacing(.leading(8), to: sidebars.leadingSidebar.view)` (`8 pt` from leading sidebar / window left edge)<br>  - `padding(.trailing(greaterThan: 8), .bottom(greaterThan: 8))` | No general OSD view; `PlaybackSpeedIndicator` & `RenderTierBadge` sit at top-left (`padding(16) + leading(62)`), `MediaOperationFeedbackOverlay` sits at bottom-center (`bottom: 80`) | Add `IINAOSDView` anchored at top-left: `8 pt` below `IINATitleBarView` and `8 pt` from leading sidebar/window edge | M |
| **Material, Corner Radius & Padding** | `OSDView.swift:11-57`, `TranslucentView.swift:22`:<br>• `TranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 8))`<br>• macOS 26 (`useLiquidGlassOSD == true`): `NSGlassEffectView` with `cornerRadius = 16`<br>• macOS ≤15 (or Liquid Glass off): `NSVisualEffectView(material: .popover, blendingMode: .withinWindow, state: .active)` with `cornerRadius = 10`<br>• Inner content padding: `horizontal = 16 pt`, `vertical = 8 pt` | Various ad-hoc capsules (`.black.opacity(0.75)` with `cornerRadius: 8` or `.capsule`) | Use `IINATranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 8))` for OSD and top-left/top-right overlays | M |
| **Typography & Split-Hierarchy Attribution** | `OSDView.swift:63-91`, `OSDMessage.swift:25-56, 421-438`:<br>• Base `textSize = Preference.float(for: .osdTextSize)` = **`20 pt`** (`Preference.swift:598`)<br>• `smallTextSize = (textSize * 0.9).clamped(to: 11...25)` = **`18 pt`**<br>• `secondaryTextSize = (textSize * 0.5).clamped(to: 11...25)` = **`11 pt`**<br>• Primary `label`: `NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .regular)`, `.labelColor`, `lineBreakMode = .byTruncatingMiddle`<br>• **Colon-split messages** (`Volume: 80`, `Speed: 1.5x`, etc.): prefix before `":"` is `18 pt regular` in `.secondaryLabelColor`; suffix `": ..."` is `20 pt regular` in `.labelColor`<br>• **Seek message** (`01:23 / 04:56`): current time is `20 pt` `.labelColor`; `" / 04:56"` is `18 pt` `.secondaryLabelColor`<br>• `secondaryLabel` (line 2): `11 pt` monospacedDigit regular, `.secondaryLabelColor` | Ad-hoc `13 pt` / `14 pt` fonts | Implement exact `OSDMessage.attributedTitle` colon-splitting (`18 pt` `.secondaryLabelColor` prefix + `20 pt` `.labelColor` value) and `11 pt` `.secondaryLabelColor` secondary line | S |
| **Progress Bar (`FixedProgressBar`)** | `FixedProgressBar.swift:10-31`, `OSDView.swift:46-49`:<br>• Height constraint: `12 pt`, `paddingY = 4 pt` → drawn bar height = **`4 pt`**, `cornerRadius = 3 pt`, fill = `NSColor.controlAccentColor` | None in OSD | Add `FixedProgressBar` (`12 pt` frame height, `4 pt` bar height, `3 pt` radius, `.controlAccentColor` fill) inside `IINAOSDView` | S |
| **Timing & Stacking** | `MainWindowController.swift:17, 1296-1365`, `Preference.swift:597`:<br>• Replaces current message immediately (`osdView.alphaValue = 1`, resets timer)<br>• Display duration: `Preference.osdAutoHideTimeout` = **`1.0 s`** (`5.0 s` for screenshot preview)<br>• Fade-in: instant (`alphaValue = 1`); Fade-out: `OSDAnimationDuration = 0.5 s` | None | Use `1.0 s` hold timer + `0.5 s` fade-out (`AccessibilityPreferences.adjustedDuration(0.5)`) | S |
| **Additional Info View (Fullscreen top-right)** | `AdditionalInfoView.swift:9-84`: top-right (`8 pt` below titleBar, `8 pt` from trailing sidebar), `TranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 8))`, shows media title (`18 pt regular`) + clock icon (`18 pt bold`) + current time (`18 pt bold monospaced`, `.secondaryLabelColor`) + `2×16` separator + battery icon & percentage (`13 pt bold`) | Not present | Optional fullscreen clock/battery pill if enabled | S |

### 5.2 Complete List of IINA OSD Message Types & Exact Strings (`OSDMessage.swift` + `Localizable.strings`)

| Case | Primary Text (`label`) | Secondary Text / Progress (`OSDType`) |
|---|---|---|
| `.fileStart(filename)` | `"\(filename)"` | `.normal` |
| `.pause` | `"Pause"` | `.withLeftToRightText("{{position}} / {{duration}}")` |
| `.resume` | `"Resume"` | `.withLeftToRightText("{{position}} / {{duration}}")` |
| `.seek(cur, tot, pct)` | `"\(cur)"` (`20pt` primary) + `" / \(tot)"` (`18pt` secondary) | `.withPosition(pct)` |
| `.showTime(pct)` | `"{{precisePosition}} / {{preciseDuration}}"` | `.withPosition(pct)` |
| `.volume(val)` | `"Volume"` (`18pt` sec) + `": \(Int(val))"` (`20pt` pri) | `.withProgress(val / maxVolume)` |
| `.speed(val)` | `"Speed"` (`18pt` sec) + `": \(val)x"` (`20pt` pri) | `.normal` |
| `.aspect(val)` | `"Aspect Ratio: \(val)"` (colon-split) | `.normal` |
| `.crop(val)` | `"Crop: \(val)"` (colon-split) | `.normal` |
| `.rotate(deg)` | `"Rotate: \(deg)°"` (colon-split) | `.normal` |
| `.deinterlace(on)` | `"Deinterlace: \(on ? "On" : "Off")"` (colon-split) | `.normal` |
| `.hwdec(on)` | `"Hardware Decoding: \(on ? "On" : "Off")"` (colon-split) | `.normal` |
| `.audioDelay(val)` | `0`: `"Audio Delay: No Delay"`, `>0`: `"Audio Delay: \(v)s Later"`, `<0`: `"Audio Delay: \(v)s Earlier"` | `.withProgress((val + 10) / 20)` |
| `.subDelay(val)` | `0`: `"Subtitle Delay: No Delay"`, `>0`: `"Subtitle Delay: \(v)s Later"`, `<0`: `"Subtitle Delay: \(v)s Earlier"` | `.withProgress((val + 10) / 20)` |
| `.subPos(val)` | `"Subtitle Position: \(val)"` | `.withProgress(val / 100)` |
| `.subScale(val)` | `"Subtitle Scale: \(val)x"` | `.normal` |
| `.subHidden` / `.subVisible` | `"Subtitles Hidden"` / `"Subtitles Visible"` | `.normal` |
| `.mute` / `.unMute` | `"Mute"` / `"Unmute"` | `.normal` |
| `.screenshot` | `"Screenshot Captured"` | `.normal` (or `ScreenshootOSDView` accessory for `5 s`) |
| `.abLoop(.aSet / .bSet / .cleared)` | `"AB-Loop: A"` / `"AB-Loop: B"` / `"AB-Loop: Cleared"` | `.withLeftToRightText("{{position}} / {{duration}}")` for A/B |
| `.stop` | `"Stop"` | `.normal` |
| `.chapter(name)` | `"Chapter: \(name)"` | `.withLeftToRightText("({{currChapter}}/{{chapterCount}}) {{position}} / {{duration}}")` |
| `.track(track)` | `"Video/Audio/Subtitle: #\(id) \(readableString)"` | `.normal` |
| `.addToPlaylist(count)` | `"Added \(count) Files to Playlist"` | `.normal` |
| `.clearPlaylist` | `"Cleared Playlist"` | `.normal` |
| `.contrast/.gamma/.hue/.saturation/.brightness(v)` | `"Contrast: \(v)"` etc. | `.withProgress((v + 100) / 200)` |
| `.addFilter(name)` / `.removeFilter` | `"Added Filter: \(name)"` / `"Removed Filter"` | `.normal` |
| `.fileLoop` / `.playlistLoop` / `.noLoop` | `"Loop Single File"` / `"Loop Playlist"` / `"Disable Looping"` | `.normal` |

### 5.3 AMP OSD & Overlay Restyling

| AMP Element | Current AMP Look | Exact IINA Restyle | Effort |
|---|---|---|---|
| **VLC Hotkey OSD** | Missing for most hotkeys | Trigger `IINAOSDView` for every VLC/AMP hotkey using IINA’s exact `OSDMessage` formatting (`Pause`, `Resume`, `Volume: %d`, `Mute`, `Unmute`, `Speed: %@x`, `cur / tot` + progress bar, `Subtitle: ...`, `Audio: ...`, `Aspect Ratio: ...`, `Crop: ...`, `Screenshot Captured`, `Loop Single File`, + AMP’s `Trim In: <tc>`, `Trim Out: <tc>`, `Trim: Cleared`, `Timecode: REL TC / SRC TC / FRM`) | M |
| **`PlaybackSpeedIndicator` & `RenderTierBadge`** (`PlaybackSpeedIndicator.swift`, `RenderTierBadge.swift`) | Top-left (`padding(16) + leading(62)`), `14 pt semibold`, `.black.opacity(0.75)` rounded rect (`radius: 8`) | Keep speed in the OSC `oscSpeedLabelLeft/Right` (`10 pt` `.secondaryLabelColor`) AND fire transient `OSDMessage.speed` on change; move persistent `RenderTierBadge` to top-right (`8 pt` below `IINATitleBarView`, `8 pt` from trailing edge/sidebar) styled as `IINATranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (12, 6))` with `12 pt bold` text and `.secondaryLabelColor` prefix `"Shader: "` | S |
| **Screenshot & Trim Export Capsules** (`PlayerOverlayViews.swift:12-135`) | Bottom-center capsule (`.black.opacity(0.7)`, `bottom: 80`) | Route screenshot preview through `IINAOSDView` at top-left (`"Screenshot Captured"` + `ScreenshootOSDView`-style preview image `border: 1 pt gridColor.opacity(0.6)`, `cornerRadius: 4`, `DELETE / EDIT / REVEAL` `13 pt bold` buttons, `5 s` timeout; `ScreenshootOSDView.swift:28-36`). Route Trim Export progress/completion through `IINAOSDView` (`"Exporting: 45%"` + `FixedProgressBar`, `"Trimmed File Saved"` + action buttons) | M |
| **`EnhancementSuggestionView` & `UpdateAvailableBanner`** (`EnhancementSuggestionView.swift`, `PlayerOverlayViews.swift:212-265`) | `.regularMaterial` card (`radius: 12`) at top-right; `.blue.opacity(0.85)` capsule at top-center | Wrap both in `IINATranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 8))` anchored `8 pt` below `IINATitleBarView`; use IINA’s `13 pt bold` title + `11 pt` `.secondaryLabelColor` subtitle + `.small` rounded buttons | S |
| **Playback Failure Overlay** (`PlayerView.swift:120-160`) | Full-bleed `.black.opacity(0.92)` with `40 pt` yellow triangle | Center a card styled like `GuideWindowController.xib` (`vEa-x6-5Uc`) / `BufferIndicatorView`: `IINATranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 12))` (`width: 360`) over the black canvas | S |

---

## 6. Sidebars and panels

| Element | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **6.1 & 6.2 Sidebar Container (`SideBarContainer` & `SidebarController`)** | `SideBar.swift:8-58`, `SidebarController.swift:13-360`, `LayoutValue.swift:61-67`:<br>• Width: default **`360 pt`** (`Preference.leadingSidebarWidth` / `trailingSidebarWidth`), resizable via `4 pt` inner-edge drag handle between **`300...500 pt`** (capped at `0.8 * window.width`)<br>• Material: `TranslucentView(liquidGlassCornerRadius: 0, vevCornerRadius: 0)` (`LayoutValue.panelCornerRadius = 0`) — full window height (`top: 0, bottom: 0`), `NSGlassEffectView(cornerRadius: 0)` on macOS 26 or `NSVisualEffectView(material: .popover, blendingMode: .withinWindow, state: .active)` on macOS ≤15<br>• Shadow (when undocked & visualEffect): `NSShadow(color: .black.withAlphaComponent(0.3), blurRadius: 6)`<br>• Open/Close animation: **`0.24 s`** (`SideBarAnimationDuration = 0.24`, `CAMediaTimingFunction(name: .easeIn)`), slides `edgeConstraint` from `-width` to `0` (or fades if `accessibilityDisplayShouldReduceMotion`)<br>• Header bar (`SidebarViewController.swift:107-267`): height **`52 pt`** (`48 pt` in compact UI), `10 pt` leading/trailing (`96 pt` leading when on left side to clear traffic lights). Contains close button (`chevron.forward` / `chevron.backward`, `36×36 pt` circular/glass button, `28×28` in compact) + `NSSegmentedControl` (`.extraLarge` on macOS 26, `.large` on macOS ≤15; icons `14 pt bold`, active segment shows label on trailing sidebar)<br>• Tab switch transition (`SidebarPane.swift:18-68`): `CATransition(type: .push, subtype: .fromRight/.fromLeft, duration: 0.3, timingFunction: .easeInEaseOut)` | `ContentView.swift:267-305`:<br>• `inspectorPanel` is `340 pt` wide, inset (`top: 36, trailing: 12, bottom: 132`), `cornerRadius: 18`, `.glassEffect(.clear.tint(.black.opacity(0.5)))`<br>• Only 2 tabs (`Playlist`, `Metadata`) | Restyle `inspectorPanel` to match IINA’s full-height edge-attached `SideBarContainer`:<br>• Width `360 pt` (resizable `300...500 pt`), `top: 0, bottom: 0, trailing: 0`, `cornerRadius: 0`<br>• `0.24 s` `.easeIn` slide transition<br>• `52 pt` top bar with `36×36` `chevron.forward` close button and `.extraLarge` segmented control | M |
| **Quick Settings Cards & Controls (`SidebarVideoPane`, `SidebarAudioPane`, `SidebarSubtitlesPane`)** | `SidebarPane.swift:75-90`, `LayoutValue.swift:62-66`:<br>• Outer scroll margins: `.horizontal(LayoutValue(16, 14))`, `.top(4)`, `.bottom(LayoutValue(16, 14))`<br>• Stack spacing between cards: `LayoutValue(18, 16)`<br>• Card container (`SidebarScrollView.Container`): `NSBox(boxType: .custom)`, `cornerRadius = 8`, `fillColor = .gray.withAlphaComponent(0.1)`, `borderColor = .sidebarContainerBorder` (Dark `sRGB(1,1,1,0.08)`, Light `sRGB(0,0,0,0.15)`), inner padding `LayoutValue(12, 10)`, item spacing `LayoutValue(12, 8)`<br>• Section header: `16×16` SF Symbol (`12 pt bold` on macOS 26, `12 pt regular` on ≤15) + `8 pt` gap + `12 pt bold` title label<br>• Track selector table (`SidebarTrackSelector.swift:8-158`): height `98 pt`, `rowHeight = 26 pt`, `.solidHorizontalGridLineMask`, selected row shows `4 pt` wide `controlAccentColor` vertical pill (`cornerRadius: 2`, `.vertical(5)` inset) at leading edge + `12 pt` leading text + trailing `controlColor` language pill (`11 pt`, `cornerRadius: 3`) | AMP’s `MetadataInspectorView` uses SwiftUI `List` with `.listStyle(.sidebar)` | Use IINA’s rounded `Container` cards (`cornerRadius: 8`, `fill: Color.gray.opacity(0.1)`, `1 pt` border `white.opacity(0.08)`, `12 pt` inner padding, `18 pt` card spacing, `16 pt` horizontal margin) for all Quick Settings / Metadata sections | M |
| **Playlist & Chapters Sidebar (`SidebarPlaylistPane`, `SidebarChaptersPane`)** | `SidebarPlaylistPane.swift:15-171`, `SidebarChaptersPane.swift:11-118`:<br>• Table background: `SidebarTableBackground` (Dark `sRGB(1,1,1,0.08)`, Light `sRGB(0,0,0,0.02)`), `.solidHorizontalGridLineMask`, `intercellSpacing = (4, 2)`<br>• Playlist row height: `LayoutValue(30, 26)` (`30 pt` normal, `26 pt` compact); Chapters row height: `40 pt`<br>• Playing indicator column (`width: 16 pt`): `"▶︎"` (`Constants.String.blackRightPointingTriangle`) in `.labelColor`<br>• Track cell: title (`13 pt` regular, `.byTruncatingMiddle`) + duration (`11 pt` monospacedDigit, `.secondaryLabelColor`) + bottom `3 pt` progress bar (`controlAccentColor` blended 20% white)<br>• Bottom toolbar (`SidebarPlaylistPane.swift:109-125`): padding `horizontal: 12, vertical: 10`, spacing `8 pt`; left `[repeat, shuffle, arrow.up.arrow.down]`, center `totalLengthLabel` (`11 pt` `.secondaryLabelColor`), right `[plus, minus, trash]` (`13 pt regular` SF Symbols) | `PlaylistSidebarView.swift:11-56`:<br>• Uses `List` with `.listStyle(.inset)`, `rowHeight = 30`, `play.fill` / `film` icon (`10 pt`), `12 pt` text | Restyle `PlaylistSidebarView`:<br>• Table background `Color.white.opacity(0.08)` with horizontal grid dividers<br>• Playing indicator column (`16 pt` wide) showing `"▶︎"` when current, empty otherwise (no `"film"` icon on non-playing rows)<br>• `13 pt` regular title + trailing monospaced-digit duration (`11 pt` `.secondaryLabelColor`) | S |
| **6.3 AMP Sidebar Mapping** | — | AMP has Playlist + Metadata in `inspectorPanel`, plus audio/subtitle/chapter menus in `ControlsView` | Map AMP’s sidebar tabs to IINA’s tab bar: **Video** (aspect/crop/rotation/speed/shader profile), **Audio** (track selector table + channel routing + LUFS), **Subtitles** (track selector table + load external), **Playlist** (folder siblings + chapters), **Info** (AMP `MetadataInspectorView` cards) | M |
| **6.4 AMP Floating Panels (`ScopeWindowController`, `AudioWaveformWindowController`, Loupe, Review Notes)** | `InspectorWindowController.xib:52-55`: `NSPanel` with `styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow, .hudWindow]`, `toolbarStyle = .compact`, `hidesOnDeactivate = true`, `frameAutosaveName = "IINAInspectorPanel"` | `ScopeWindowController.swift:56-68` & `AudioWaveformWindowController.swift:52-64` use `NSPanel` with `[.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel]`, `Color(nsColor: .windowBackgroundColor)` toolbar | Add `.hudWindow` to `styleMask`, set `panel.appearance = NSAppearance(named: .darkAqua)`, `panel.titlebarAppearsTransparent = true`, `panel.toolbarStyle = .compact`, and use `NSVisualEffectView(material: .hudWindow)` / `IINATranslucentView` for the top toolbar in `ScopeView` and `AudioWaveformView`. Style Loupe & Review Notes popovers with IINA’s `8 pt` container cards | S |

---

## 7. Fullscreen and fill-screen

| Element | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **7.1 Native vs Legacy Fullscreen** | `MainWindowController.swift:790-1085`:<br>• **Native fullscreen**: `window.toggleFullScreen(self)`, `window.appearance = NSAppearance(iinaTheme: theme)`, `window.titlebarAppearsTransparent = false`, `titleVisibility = .visible`, `window.toolbar = nil`, `videoView` fills screen on black background, `additionalInfoView` at top-right (if enabled), `blackOutOtherMonitors()` (if enabled)<br>• **Legacy fullscreen** (`legacyAnimateToFullscreen`, `MainWindowController.swift:1066-1096`):<br>  - `window.styleMask.insert(.borderless)`, `.remove(.resizable)`, `.remove(.titled)`<br>  - `window.hasShadow = false`, `forceKeyAndMain = true`, `window.level = .floating`, `window.resizeIncrements = NSSize(width: 1, height: 1)`<br>  - `NSApp.presentationOptions.insert([.autoHideMenuBar, .autoHideDock])`<br>  - Frame set to `screen.frame` minus `screen.cameraHousingHeight` (with black `cameraHousingWindow` at `.mainMenu` level over notch)<br>  - Animation: `useAnimation = false` on macOS 26 (`#unavailable(macOS 26)` guard), animated on macOS ≤15 | Native fullscreen via `window.toggleFullScreen(nil)`; `WindowConfigurator.maximize` fills `screen.visibleFrame` while keeping `.titled`, shadow, and corner radius | Keep native fullscreen for `⌃⌘F` / fullscreen button, and style VLC double-click / pinch "fill screen, stay windowed" to copy IINA’s clean borderless/frameless look within `visibleFrame` | S |
| **7.2 AMP’s VLC "Fill Screen, Stay Windowed" State** | Copy IINA’s fullscreen/borderless chrome values onto the `visibleFrame`-filling window:<br>• `window.hasShadow = false`<br>• `titleBarView` & traffic lights hidden until mouse hover (`fadeableViews` `.auto`, `0.25 s` fade, `2.5 s` hide timer)<br>• `window.toolbar = nil` while filling screen (so macOS 26 reduces the window corner radius to tight/flush corners)<br>• `window.contentAspectRatio = .zero` and `window.contentResizeIncrements = NSSize(width: 1, height: 1)`<br>• Background `.black`, OSC floating at saved relative position | `WindowConfigurator.maximize` (`WindowConfigurator.swift:117-121`) sets `window.setFrame(screen.visibleFrame, display: true, animate: false)` but leaves shadow and toolbar/corner radius unchanged | In `WindowConfigurator.maximize(_:)`: set `window.hasShadow = false` and `window.toolbar = nil` when entering fill-screen, and restore `window.hasShadow = true` and `window.toolbar` when exiting fill-screen or manually resizing | S |

---

## 8. Welcome / initial window and empty states

| Element | IINA exact value | AMP now | Change | Effort |
|---|---|---|---|---|
| **8.1 IINA `InitialWindowController`** | `InitialWindowController.swift:72-357`:<br>• Window: `CommonWindow(contentRect: 560×440)`, `styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView]`, `frameAutosaveName = "IINAWelcomeWindow"`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `isMovableByWindowBackground = true`, `paddingH = 30 pt`<br>• Background: `NSVisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow, state: .active)` + `overlayView` with `CAGradientLayer`:<br>  - Dark: `[black(0.4), black(0.1)]`<br>  - Light: `[black(0.1), black(0.0)]`<br>• Header (`top: 48, leading: 24, trailing: 30`): `hStack(spacing: 12)` of `appIcon` (`68×68 pt`) + `vStack(spacing: 4)` of app title (`20 pt bold`) & `versionLabel` (`13 pt regular`, `.secondaryLabelColor`)<br>• Action buttons (`top: 64, trailing: 30`): `hStack(spacing: 12)` of `Open…` and `Open URL…` (`NSButton`, `controlSize = .large`, standard push bezel)<br>• Resume Last File pill (`InitialWindowViewActionButton`, `spacing(.top(16), to: header)`, `.horizontal(30)`, `height: 32`, `cornerRadius: 8`):<br>  - Background (`InitialWindowLastFileBackground*`):<br>    * Normal: Dark `sRGB(1,1,1,0.10)`, Light `sRGB(0.15,0.15,0.15,0.10)`<br>    * Hover: Dark `sRGB(0.5,0.5,0.5,0.10)`, Light `sRGB(0.15,0.15,0.15,0.20)`<br>    * Pressed: Dark `sRGB(0,0,0,0.10)`, Light `sRGB(0,0,0,0.25)`<br>  - Content (`.horizontal(10), .vertical(6)`, `spacing: 6`): `16×16` icon `"clock.arrow.trianglehead.counterclockwise.rotate.90"` (fallback `"clock"`) + `"Resume"` label + `lastFileNameLabel` (`.byTruncatingMiddle`) + flexible space + `lastPositionLabel` (`11 pt` `.secondaryLabelColor`)<br>• Recent files table (`top: 24` from header when resume hidden, `60` when resume shown; `.bottom(24), .horizontal(24)`):<br>  - `rowHeight = 28 pt`, `style = .plain`, selection highlight `GrayHighlightRowView` (`cornerRadius: 4`, fill `initialWindowLastFileBackground`)<br>  - Cell: `.leading(8)` `16×16` file icon + `6 pt` gap + filename label (`.byTruncatingMiddle`) + `.trailing(8)` | • AMP’s `InitialWindowController.swift` uses an older IINA 1.4 two-column XIB layout (`leftOverlayView` gradient `[0.4, 0.0]`, no programmatic header/large buttons, no Resume pill, `WelcomeColor` hover uses old `0.65/0.25` values)<br>• AMP’s `DropZoneView.swift` (in-window empty state) uses a custom 2-column SwiftUI layout (`220 pt` left branding column with `96×96` icon + `Divider` + right actions column) | **Rewrite `InitialWindowController.swift` (and `DropZoneView.swift`)** to match IINA v1.5.0’s programmatic layout (`InitialWindowController.swift:72-196`):<br>1. `560×440` window, `underWindowBackground` + full-window gradient (`[0.4, 0.1]` Dark / `[0.1, 0.0]` Light)<br>2. Header at `top: 48, leading: 24`: `68×68` app icon + `12 pt` gap + `20 pt bold` title & `13 pt` `.secondaryLabelColor` version; `.large` `Open…` button at `top: 64, trailing: 30`<br>3. Add the `32 pt`-tall (`cornerRadius: 8`) Resume Last File pill (`clock.arrow.trianglehead.counterclockwise.rotate.90` + `"Resume"` + filename + timestamp) wired to VLC resume semantics<br>4. Recent files table at `horizontal: 24, bottom: 24`, `rowHeight: 28`, `GrayHighlightRowView` (`cornerRadius: 4`, fill `sRGB(1,1,1,0.10)`) | M |
| **8.2 & 8.3 Drag-and-Drop Highlight** | `InitialWindowContentView` (`InitialWindowController.swift:318-329`) and `VideoView` (`VideoView.swift:110-163`):<br>• IINA does **not** draw a dashed border on drag-over; it returns `.copy` cursor operation, and on `VideoView` hovering in the rightmost `20%` of the window for `0.3 s` (`draggingTimer`) slides open the playlist sidebar (`VideoView.swift:116-148`) | `DropZoneView.swift:30-37` draws a `2 pt` dashed accent-colour border (`padding(12), cornerRadius: 12`) | Remove the dashed border from `DropZoneView` so drag-over uses standard macOS copy cursor feedback (and optionally open playlist sidebar after `0.3 s` when dragging near the trailing 20% edge of a loaded player window) | S |

---

## 9. Menus

### 9.1 IINA Main Menu Bar Structure (`MainMenu.xib` + `MenuController.swift`) with VLC Shortcuts

AMP’s SwiftUI `CommandGroup` / `CommandMenu` definitions in `Aagedal_Media_PlayerApp.swift:63-267` should adopt IINA’s exact top-level menu order and item titles:

1. **App Menu (`Aagedal Media Player`)**: `About Aagedal Media Player`, `Check for Updates…`, `---`, `Settings…` (`⌘,`), `---`, `Services`, `---`, `Hide`, `Hide Others`, `Show All`, `---`, `Quit` (`⌘Q`).
2. **File**:
   - `Open…` (`⌘O`) / alt `Open in New Window…` (`⌥⌘O`)
   - `Open URL…` (`⇧⌘O`) *(or `Open Comparison File…` `⇧⌘D` in AMP)*
   - `Open Recent` → submenu (`Clear Menu`)
   - `---`
   - `New Window` (`⌘N`)
   - `---`
   - `Playback History` (`⇧⌘H`)
   - `---`
   - `Show Current File in Finder`
   - `Delete Current File`
   - `Save Current Playlist…`
   - `---`
   - `Close` (`⌘W`)
3. **Edit**: Standard `Undo`, `Redo`, `---`, `Cut`, `Copy`, `Paste`, `Delete`, `Select All`, `---`, `Copy Timecode` (`⇧⌘C`), `Paste Timecode` (`⇧⌘V`).
4. **Playback**:
   - `Pause` / `Resume` (`Space`) — *dynamic title (`MenuController.swift:373`)*
   - `Stop and Clear Playlists` (`⌘.`)
   - `---`
   - `Step Forward 5s` (`→` in AMP Pro / `⌘→` in VLC) & alt `Next Frame` (`E` in VLC / `.` in AMP Pro)
   - `Step Backward 5s` (`←` in AMP Pro / `⌘←` in VLC) & alt `Previous Frame` (`,` in AMP Pro)
   - `Jump to Beginning`
   - `Jump to…` (`⌘J`)
   - `---`
   - `Speed: 1.00x` *(disabled indicator item; `MenuController.swift:380`)*
   - `Speed Up by 2.0x` / `Speed Up by 1.1x` (`]`) / `Speed Down by 0.5x` / `Speed Down by 0.9x` (`[`) / `Reset Speed` (`=`)
   - `---`
   - `Take a Screenshot` (`⇧⌘S` / `⌥⌘S` in VLC) *(or `Export Comparison Still` when Compare Mode active)*
   - `Go to Screenshot Folder`
   - `Export Trim…` (`⌘E`) *(AMP item in Screenshot/Export group)*
   - `---`
   - `A-B Loop` (`⌘L`) *(or Trim In `I` / Trim Out `O` in AMP)*
   - `File Loop` (`L` in VLC)
   - `---`
   - `Show Playlist Panel` / `Hide Playlist Panel`
   - `Playlist Loop`
   - `Playlist` → submenu (checkmarked current item)
   - `---`
   - `Next Media` (`⌘]`)
   - `Previous Media` (`⌘[`)
   - `---`
   - `Show Chapters Panel` / `Hide Chapters Panel`
   - `Chapters` → submenu (monospaced-digit `00:00 – Title`, checkmarked active chapter; `MenuController.swift:346`)
   - `---`
   - `Next Chapter` (`⇧→`) / `Previous Chapter` (`⇧←`)
5. **Video**:
   - `Show Video Panel` / `Hide Video Panel`
   - `---`
   - `Cycle Video Tracks`
   - `Video Track` → submenu (`<None>`, `#1 ...`)
   - `---`
   - `Half Size` (`⌘0`)
   - `Normal Size` (`⌘1`)
   - `Normal Size (Retina)` (alt `⌥⌘1`)
   - `Double Size` (`⌘2`)
   - `Fit to Screen` (`⌘3`)
   - `---`
   - `Bigger Size` (`⌘=`) / `Smaller Size` (`⌘-`)
   - `---`
   - `Enter Picture-in-Picture` / `Exit Picture-in-Picture`
   - `Enter Full Screen` / `Exit Full Screen` (`⌘F` in VLC / `⌃⌘F`)
   - `Float on Top` (checkmarked when `isOntop`)
   - `Lock Window Aspect Ratio` (checkmarked)
   - `---`
   - `Aspect Ratio` → submenu (`Default`, `4:3`, `5:4`, `16:9`, `16:10`, `1:1`, `3:2`, `2.21:1`, `2.35:1`, `2.39:1`) (`A` in VLC cycles)
   - `Crop` → submenu (`None`, ratios..., `---`, `Custom…`) (`C` in VLC cycles)
   - `Rotation` → submenu (`0°`, `90°`, `180°`, `270°`)
   - `Flip` → submenu (`Horizontal (Mirror)`, `Vertical (Flip)`)
   - `Deinterlace` (`D` in VLC)
   - `---`
   - *AMP Inspection Group*: `Video Scopes` (`⇧⌘W`), `Toggle Parade` (`⇧⌘P`), `Inspection Loupe` (`⇧⌘L`), `Open Comparison File…` (`⇧⌘D`), `Comparison Review Notes` (`⇧⌘N`)
6. **Audio**:
   - `Show Audio Panel` / `Hide Audio Panel`
   - `---`
   - `Cycle Audio Tracks` (`B` in VLC)
   - `Audio Track` → submenu (`<None>`, `#1 ...`)
   - `Load External Audio…`
   - `---`
   - `Volume: 100` / `Volume: 100 (Muted)` *(disabled indicator item)*
   - `Volume + 5%` (`⌘↑` in VLC / `↑`) & alt `Volume + 1%` (`⌥↑`)
   - `Volume - 5%` (`⌘↓` in VLC / `↓`) & alt `Volume - 1%` (`⌥↓`)
   - `Mute` (`⌥⌘↓` or `M`) — checkmarked when muted
   - `---`
   - `Audio Delay: 0s` *(disabled indicator)* / `Audio Delay + 0.5s` (`G` in VLC `+0.05s`) / `Audio Delay - 0.5s` (`F` in VLC `-0.05s`) / `Reset Audio Delay`
   - `---`
   - `Audio Device` → submenu
   - `---`
   - `Audio Waveform` (`⇧⌘A`) *(AMP item)*
7. **Subtitles**:
   - `Show Subtitles Panel` / `Hide Subtitles Panel`
   - `---`
   - `Cycle Subtitles` (`S` in VLC)
   - `Subtitle` → submenu (`<None>`, `#1 ...`)
   - `Hide Subtitles` / `Show Subtitles` (`V` in VLC)
   - `Secondary Subtitle` → submenu
   - `Hide Secondary Subtitles` / `Show Secondary Subtitles`
   - `Load External Subtitle…`
   - `---`
   - `Encoding` → submenu
   - `---`
   - `Scale Up` / `Scale Down` / `Reset Subtitle Scale`
   - `---`
   - `Subtitle Delay: 0s` *(disabled indicator)* / `Subtitle Delay + 0.5s` (`J` in VLC) / `Subtitle Delay - 0.5s` (`H` in VLC) / `Reset Subtitle Delay`
   - `---`
   - `Font…`
8. **Window**: `Minimize` (`⌘M`), `Zoom`, `---`, `Inspector` (`⌘I`), `Log Viewer` (`⌃⌘L`), `---`, `Sync Transport Commands Across Windows`, `Align Windows to Current Timecode Once` (`⇧⌘S`), `---`, `Bring All to Front`.
9. **Help**: `Aagedal Media Player Help` (`⌘?`), `---`, `GitHub`, `Website`.

### 9.2 Video Right-Click Context Menu (VLC Item Set in IINA Menu Styling)

IINA formats track/chapter/aspect submenus with:
- Monospaced-digit font (`NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)`) on chapter items (`00:00 – Chapter Title`) (`MenuController.swift:346`).
- Checkmarks (`state = .on`) on active tracks, chapters, aspect ratios, crop modes, and toggles (`Float on Top`, `Deinterlace`, `Mute`).
- Disabled grey indicator rows (`Volume: 100%`, `Speed: 1.00x`) at the top of numeric groups.

Attach an AppKit `NSMenu` on right-click over the video canvas (`MPVVideoView` / `PlayerContainerView`) with VLC’s item set ordered and titled in IINA’s style:
1. `Pause` / `Resume`
2. `Stop`
3. `Next Media` / `Previous Media`
4. `---`
5. `Playback` → (`Speed: 1.00x`, `Speed Up`, `Speed Down`, `Reset Speed`, `---`, `Step Forward`, `Step Backward`, `Next Frame`, `Previous Frame`, `Jump to…`, `---`, `A-B Loop`, `File Loop`)
6. `Chapters` → (monospaced-digit `00:00 – Title` with checkmarks)
7. `---`
8. `Video` → (`Video Track` submenu, `---`, `Half Size`, `Normal Size`, `Double Size`, `Fit to Screen`, `---`, `Enter Full Screen`, `Float on Top`, `---`, `Aspect Ratio` submenu, `Crop` submenu, `Deinterlace`, `---`, `Take a Screenshot`)
9. `Audio` → (`Audio Track` submenu, `Load External Audio…`, `---`, `Volume: 100%`, `Volume + 5%`, `Volume - 5%`, `Mute`, `---`, `Audio Device` submenu)
10. `Subtitles` → (`Subtitle` submenu, `Hide/Show Subtitles`, `Load External Subtitle…`, `---`, `Subtitle Delay + 0.5s`, `Subtitle Delay - 0.5s`, `Reset Subtitle Delay`)
11. `---`
12. *AMP Inspection*: `Open Comparison File…`, `Video Scopes`, `Audio Waveform`, `Inspection Loupe`, `Toggle Inspector`
13. `---`
14. `Show Current File in Finder`

---

## 10. Mini player (music mode) and Picture in Picture

*(Visual specification recorded for future reference only — no new feature work proposed.)*

| Surface | IINA Exact Visual Specification |
|---|---|
| **Music Mode (`MiniPlayerWindowController.swift`)** | • Window width fixed at `300 pt`, min height `72 pt` (without album art/playlist), `372 pt` with `300×300` square `videoWrapperView` (`default-album-art.png`), `+ 300 pt` (`DefaultPlaylistHeight`) when playlist drawer expanded (`MiniPlayerWindowController.swift:10, 121, 560`)<br>• Background: `NSVisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow, state: .active)`<br>• Top-left floating pill (`closeButtonView`, `top: 6, leading: 8`): `NSVisualEffectView(material: .popover, blendingMode: .withinWindow, cornerRadius: 10)`, vertical stack (`padding: 3`, `spacing: 4/5`) of `xmark.circle.fill` (`12/13 pt`) and `arrow.uturn.backward.circle.fill` (`12/13 pt`)<br>• Media info (shown when not hovered, `alpha = 1`, fades out in `0.2 s` on hover): `titleLabel` (`ScrollingTextField`, `13 pt bold`, centered, `top: 6`) + `artistAlbumLabel` (`11 pt messageFont`, `.secondaryLabelColor`, `top: 4`)<br>• Transport controls (shown on hover in `0.2 s`, `height: 48`): `muteButton` (`leading: 10`) → `20 pt` → `prevBtn` (`nextl.pdf`, `28×28`) → `24 pt` → `playButton` (`28×28`) → `20 pt` → `nextBtn` (`nextr.pdf`, `28×28`) → `20 pt` → `togglePlaylistButton` (`list.bullet.rectangle`, `18×18`) → `16 pt` → `toggleAlbumArtButton` (`photo`, `18×18`)<br>• Volume popover (`volumeControlBackground`): `NSVisualEffectView(material: .popover, cornerRadius: 18)`, `1 pt` border `sidebarContainerBorder`, shadow `blurRadius = 2, alpha = 0.5`, expands trailing constraint from `10 pt` to `148 pt` (`volumeSlider` `100 pt` + `volumeLabel` `11 pt`)<br>• Bottom scrubber row: `leftLabel` (`9 pt` `.mini` monospacedDigit, `.secondaryLabelColor`, `minWidth >= 32`, `leading: 6`) → `6 pt` → `playSlider` (`bottom: LayoutValue(10, 8)`) → `6 pt` → `rightLabel` |
| **Picture-in-Picture (`MainWindowController.xib:26-50`)** | • OSC button: SF Symbol `"pip.enter"` / `"pip.exit"` at `13.5 pt medium`<br>• Window placeholder (`pipOverlayView`): `NSVisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow, state: .active)` covering contentView, centered SF Symbol `"pip"` (`pointSize: 80, weight: .thin`) + `20 pt` below it `"This video is playing in picture in picture"` (`13 pt system`, `.labelColor`) |

---

## 11. Typography, colour, materials, appearance, accessibility

### 11.1 Typography Token Table

| Token | Font Family / API | Size | Weight | Monospaced Digits | Where Used in IINA |
|---|---|---|---|---|---|
| `titleBar` | `NSFont.titleBarFont(ofSize: 13)` | `13 pt` | System Titlebar | No | `Titlebar.titleTextField` (`Titlebar.swift:145`) |
| `oscTime` | `NSFont.monospacedDigitSystemFont` | `11 pt` | `.regular` | **Yes** | `MainWindowController.leftLabel` / `rightLabel` (`MainWindowController.swift:390`) |
| `oscSpeed` | `NSFont.systemFont` | `10 pt` | `.regular` | No | `oscSpeedLabelLeft` / `oscSpeedLabelRight` (`MainWindowController.swift:377`) |
| `timePreview` | `NSFont.monospacedDigitFont(for: .small)` | `11 pt` | `.regular` | **Yes** | `TimePreviewView.textField` (`MainWindowController.swift:343`) |
| `osdPrimary` | `NSFont.monospacedDigitSystemFont` | `20 pt` | `.regular` | **Yes** | `OSDView.label` main value (`OSDView.swift:64, 79`) |
| `osdPrefix` | `NSFont.monospacedDigitSystemFont` | `18 pt` | `.regular` | **Yes** | `OSDMessage` colon prefix & seek `/ total` (`OSDView.swift:66`) |
| `osdSecondary` | `NSFont.monospacedDigitSystemFont` | `11 pt` | `.regular` | **Yes** | `OSDView.secondaryLabel` (`OSDView.swift:67, 80`) |
| `sidebarSectionHeader` | `NSFont.boldSystemFont` | `12 pt` | `.bold` | No | `SidebarLayoutPane`, `SidebarVideoPane`, `SidebarAudioPane`, `SidebarSubtitlesPane` |
| `sidebarBody` | `NSFont.systemFont` | `13 pt` | `.regular` | No | Sidebar labels, track names, playlist rows |
| `sidebarSmall` | `NSFont.systemFont` | `11 pt` | `.regular` | Optional | Playlist durations (`.monospacedDigit()`), language tags, total length |
| `sidebarSliderTick` | `NSFont.systemFont` | `10 pt` | `.regular` | No | `SidebarSliderView` indicator & tick labels (`SidebarSliderView.swift:34, 62`) |
| `welcomeTitle` | `NSFont.systemFont` | `20 pt` | `.bold` | No | `InitialWindowController` `"IINA"` header (`InitialWindowController.swift:114`) |
| `welcomeVersion` | `NSFont.systemFont` | `13 pt` | `.regular` | No | `InitialWindowController` version & table rows |

### 11.2 Colour Token Table (Light & Dark Appearances)

| Token Name | Light Appearance (sRGB) | Dark Appearance (sRGB) | Source |
|---|---|---|---|
| `windowBackground` | `(1, 1, 1, 1.0)` (`.white`) | `(0, 0, 0, 1.0)` (`.black`) | `PlayerWindowController.swift:242` |
| `titleBarBorder` | `(0.659, 0.659, 0.659, 1.0)` | `(0, 0, 0, 1.0)` | `TitleBarBorder.colorset` |
| `mainSliderBarLeft` | `(0, 0, 0, 0.40)` | `(1, 1, 1, 0.30)` | `MainSliderBarLeft.colorset` |
| `mainSliderBarRight` | `(0, 0, 0, 0.20)` | `(1, 1, 1, 0.10)` | `MainSliderBarRight.colorset` |
| `mainSliderKnob` | `(1, 1, 1, 0.96)` | `(1, 1, 1, 0.80)` | `MainSliderKnob.colorset` |
| `mainSliderKnobActive` | `(1, 1, 1, 0.75)` | `(1, 1, 1, 0.98)` | `MainSliderKnobActive.colorset` |
| `mainSliderLoopKnob` | `(0.41, 0.41, 0.41, 1.0)` | `(0.65, 0.65, 0.65, 1.0)` | `MainSliderLoopKnob.colorset` |
| `volumeSliderBarLeft` | `(0, 0, 0, 0.40)` | `(1, 1, 1, 0.30)` | `VolumeSliderBarLeft.colorset` |
| `volumeSliderBarRight` | `(0, 0, 0, 0.10)` | `(1, 1, 1, 0.10)` | `VolumeSliderBarRight.colorset` |
| `thumbnailPeekBorder` | `gray(0.6, alpha: 0.5)` | `gray(0.6, alpha: 0.5)` | `ThumbnailPeekView.swift:26` |
| `sidebarTableBackground` | `(0, 0, 0, 0.02)` | `(1, 1, 1, 0.08)` | `SidebarTableBackground.colorset` |
| `sidebarContainerFill` | `gray(0.5, alpha: 0.10)` | `gray(0.5, alpha: 0.10)` | `SidebarPane.swift:83` |
| `sidebarContainerBorder` | `(0, 0, 0, 0.15)` | `(1, 1, 1, 0.08)` | `SidebarContainerBorder.colorset` |
| `sidebarTabBtnBorder` | `(0, 0, 0, 0.25)` | `(1, 1, 1, 0.25)` | `SidebarTabBtnBorder.colorset` |
| `sidebarTabTint` | `(0, 0, 0, 0.50)` | `(1, 1, 1, 0.50)` | `SidebarTabTint.colorset` |
| `sidebarTabTintActive` | `(0, 0, 0, 1.00)` | `(1, 1, 1, 1.00)` | `SidebarTabTintActive.colorset` |
| `playlistProgressBar` | `controlAccentColor` + 20% `.white` | `controlAccentColor` + 20% `.white` | `SidebarPlaylistPane.swift:617` |
| `welcomeLastFileBg` | `(0.15, 0.15, 0.15, 0.10)` | `(1, 1, 1, 0.10)` | `InitialWindowLastFileBackground.colorset` |
| `welcomeLastFileHover` | `(0.15, 0.15, 0.15, 0.20)` | `(0.5, 0.5, 0.5, 0.10)` | `InitialWindowLastFileBackgroundHover.colorset` |
| `welcomeLastFilePressed` | `(0, 0, 0, 0.25)` | `(0, 0, 0, 0.10)` | `InitialWindowLastFileBackgroundPressed.colorset` |
| `welcomeGradient` | `[black(0.1), black(0.0)]` | `[black(0.4), black(0.1)]` | `InitialWindowController.swift:238-241` |

### 11.3 Materials & Blending Modes per Surface

| Surface | macOS 26 (`useLiquidGlass* == true`) | macOS ≤15 (or Liquid Glass off) | Blending Mode & State |
|---|---|---|---|
| **Titlebar** | `NSVisualEffectView(material: .titlebar)` | `NSVisualEffectView(material: .titlebar)` | `.withinWindow`, `.active` |
| **Floating OSC** | `NSGlassEffectView(cornerRadius: 12)` | `NSVisualEffectView(material: .popover, cornerRadius: 6)` | `.withinWindow`, `.active` |
| **Bottom OSC** | `NSGlassEffectView(cornerRadius: 0)` | `NSVisualEffectView(material: .popover, cornerRadius: 0)` | `.withinWindow`, `.active` |
| **OSD / Buffer / AdditionalInfo** | `NSGlassEffectView(cornerRadius: 16)` | `NSVisualEffectView(material: .popover, cornerRadius: 10)` | `.withinWindow`, `.active` |
| **TimePreviewView** | `NSGlassEffectView(cornerRadius: 16)` | `NSVisualEffectView(material: .popover, cornerRadius: 8)` | `.withinWindow`, `.active` |
| **Sidebar (`SideBarContainer`)** | `NSGlassEffectView(cornerRadius: 0)` | `NSVisualEffectView(material: .popover, cornerRadius: 0)` | `.withinWindow`, `.active` |
| **Welcome / OpenURL / PiP Overlay** | `NSVisualEffectView(material: .underWindowBackground)` | `NSVisualEffectView(material: .underWindowBackground)` | `.behindWindow`, `.active` |
| **Inspector / Utility Panels** | `NSPanel` with `.hudWindow` styleMask | `NSPanel` with `.hudWindow` styleMask | System HUD panel |

### 11.4 Forced Appearance & 11.5 Accessibility

- **Default Appearance**: `Preference.defaultPreference[.themeMaterial] = Theme.dark.rawValue` (`Preference.swift:591`). `PlayerWindowController.setMaterial` (`PlayerWindowController.swift:238-243`) and `InitialWindowController.setMaterial` (`InitialWindowController.swift:235`) set `window.appearance = NSAppearance(named: .darkAqua)`.
- **Reduce Motion & Disable Animations**: `AccessibilityPreferences.swift:15-39` provides `AccessibilityPreferences.adjustedDuration(_ duration: TimeInterval)` (returns `0` when `disableAnimations` is set) and `motionReductionEnabled` (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`). When Reduce Motion is enabled, `SidebarController` switches from sliding (`edgeConstraint`) to fading (`SidebarController.swift:198-200`).
- **VoiceOver**: Keep AMP’s comprehensive `.accessibilityLabel`, `.accessibilityValue`, `.accessibilityHint`, and `.accessibilityAdjustableAction` modifiers intact.

### 11.6 Proposed Single AMP Design-Token File (`IINADesignTokens.swift`)

Create `Aagedal Media Player/UI/IINADesignTokens.swift`:

```swift
// Aagedal Media Player
// Copyright © 2026 Truls Aagedal
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

enum IINADesignTokens {
    // MARK: - Window & Layout Metrics
    static let mainWindowMinSize = NSSize(width: 285, height: 120)
    static let defaultNoVideoSize = NSSize(width: 640, height: 360)
    static let welcomeWindowSize = NSSize(width: 560, height: 440)
    static let minimumInitialDragDistance: CGFloat = 3.0

    static var titleBarHeight: CGFloat {
        if #available(macOS 26.0, *) { return 40 }
        return 36
    }
    static let titleBarDocIconLeadingPadding: CGFloat = 86
    static let titleBarDocIconSize: CGFloat = 16

    // MARK: - OSC Metrics
    static let oscFloatingWidth: CGFloat = 460
    static let oscFloatingMinWidth: CGFloat = 200
    static let oscFloatingHeight: CGFloat = 67
    static var oscFloatingCornerRadius: CGFloat {
        if #available(macOS 26.0, *) { return 12 }
        return 6
    }
    static let oscTopPaddingTop: CGFloat = 14
    static let oscTopPaddingHorizontal: CGFloat = 12
    static let oscBottomPaddingBottom: CGFloat = 8
    static let oscBottomPaddingHorizontal: CGFloat = 8
    static let oscRowSpacing: CGFloat = 2 // 8 pt stack gap minus 6 pt alignmentRectInsets.top
    static let oscButtonFrameSize: CGFloat = 24
    static let oscTransportSpacingFloating: CGFloat = 24
    static let oscTransportSpacingBar: CGFloat = 16
    static let oscSpeedLabelContainerWidth: CGFloat = 30
    static let oscVolumeSliderWidth: CGFloat = 70
    static let oscTimeLabelMinWidth: CGFloat = 46
    static let oscCenterSnapThreshold: CGFloat = 5
    static let oscDragMarginX: CGFloat = 10
    static let oscDragMarginTop: CGFloat = 25

    // MARK: - Slider Metrics
    static let sliderBarHeight: CGFloat = 3
    static let sliderBarRadius: CGFloat = 1.5
    static let playSliderKnobWidth: CGFloat = 3
    static let playSliderKnobHeight: CGFloat = 15
    static let playSliderLoopKnobHeight: CGFloat = 11 // round(15 * 0.75)
    static let playSliderKnobRadius: CGFloat = 1
    static let thumbnailWidth: CGFloat = 120
    static let thumbnailCornerRadius: CGFloat = 4

    // MARK: - OSD Metrics
    static let osdLiquidGlassCornerRadius: CGFloat = 16
    static let osdVEVCornerRadius: CGFloat = 10
    static let timePreviewVEVCornerRadius: CGFloat = 8
    static let osdPaddingHorizontal: CGFloat = 16
    static let osdPaddingVertical: CGFloat = 8
    static let osdEdgeMargin: CGFloat = 8
    static let osdBaseTextSize: CGFloat = 20
    static let osdPrefixTextSize: CGFloat = 18
    static let osdSecondaryTextSize: CGFloat = 11
    static let osdProgressBarFrameHeight: CGFloat = 12
    static let osdProgressBarTrackHeight: CGFloat = 4
    static let osdProgressBarCornerRadius: CGFloat = 3

    // MARK: - Sidebar Metrics
    static let sidebarDefaultWidth: CGFloat = 360
    static let sidebarWidthRange: ClosedRange<CGFloat> = 300...500
    static let sidebarHeaderHeight: CGFloat = 52
    static let sidebarCloseButtonSize: CGFloat = 36
    static let sidebarMargin: CGFloat = 16
    static let sidebarStackSpacing: CGFloat = 18
    static let sidebarContainerPadding: CGFloat = 12
    static let sidebarItemSpacing: CGFloat = 12
    static let sidebarContainerCornerRadius: CGFloat = 8
    static let sidebarPlaylistRowHeight: CGFloat = 30
    static let sidebarChapterRowHeight: CGFloat = 40
    static let sidebarTrackRowHeight: CGFloat = 26

    // MARK: - Animation & Timers
    static let uiAnimationDuration: TimeInterval = 0.25
    static let osdFadeOutDuration: TimeInterval = 0.50
    static let sidebarAnimationDuration: TimeInterval = 0.24
    static let sidebarTabTransitionDuration: TimeInterval = 0.30
    static let oscAutoHideTimeout: TimeInterval = 2.5
    static let osdAutoHideTimeout: TimeInterval = 1.0
    static let osdScreenshotTimeout: TimeInterval = 5.0

    static func adjustedDuration(_ duration: TimeInterval) -> TimeInterval {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
    }

    // MARK: - Dynamic Colours
    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    static let titleBarBorder = dynamicColor(
        light: NSColor(srgbRed: 0.659, green: 0.659, blue: 0.659, alpha: 1.0),
        dark: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1.0)
    )
    static let mainSliderBarLeft = dynamicColor(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.40),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30)
    )
    static let mainSliderBarRight = dynamicColor(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.20),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )
    static let mainSliderKnob = dynamicColor(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.80)
    )
    static let mainSliderKnobActive = dynamicColor(
        light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.75),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.98)
    )
    static let mainSliderLoopKnob = dynamicColor(
        light: NSColor(srgbRed: 0.41, green: 0.41, blue: 0.41, alpha: 1.0),
        dark: NSColor(srgbRed: 0.65, green: 0.65, blue: 0.65, alpha: 1.0)
    )
    static let volumeSliderBarLeft = mainSliderBarLeft
    static let volumeSliderBarRight = dynamicColor(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )
    static let sidebarContainerBorder = dynamicColor(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.15),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    )
    static let sidebarTableBackground = dynamicColor(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.02),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
    )
    static let welcomeLastFileBackground = dynamicColor(
        light: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 0.10),
        dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
    )
    static let welcomeLastFileHover = dynamicColor(
        light: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 0.20),
        dark: NSColor(srgbRed: 0.50, green: 0.50, blue: 0.50, alpha: 0.10)
    )
    static let welcomeLastFilePressed = dynamicColor(
        light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25),
        dark: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.10)
    )
}
```

---

## 12. Icons and assets

| Asset Name | Type & Rendering | Size / Usage in IINA | Reuse in AMP |
|---|---|---|---|
| `play.pdf`, `pause.pdf` | Vector PDF, `template` | `24×24 pt` in MainWindow OSC, `28×28 pt` in MiniPlayer | Copy into AMP `Assets.xcassets/Icons` and use for OSC play/pause button |
| `speed.pdf`, `speedl.pdf` | Vector PDF, `template` | `24×24 pt` right/left arrow buttons in OSC (`arrowBtnFunction == .speed / .seek`) | Copy into AMP `Assets.xcassets/Icons` and use for OSC left/right transport buttons |
| `next.pdf` (`nextl`), `nextr.pdf` | Vector PDF, `template` | `24×24 pt` in OSC (`arrowBtnFunction == .playlist`), `28×28 pt` in MiniPlayer | Copy into AMP `Assets.xcassets/Icons` |
| `battery.pdf`, `battery-rtl.pdf` | Vector PDF, `template` | Used in `AdditionalInfoView` (fullscreen battery indicator) | Copy if `AdditionalInfoView` is added |
| `default-album-art.png` | `@2x` PNG, non-template | Audio-only cover art in `MiniPlayerWindowController` | Optional; AMP uses `AudioOnlyPresentationView` (restyle its card container with `IINATranslucentView`) |
| `remove.blackbars.symbolset` (`custom.rectangle.arrowtriangle.2.inward.square.svg`) | Custom SF Symbol SVG, `template` | `12 pt regular` in `Titlebar` (`removeBlackBarButton`) and `SidebarLayoutPane` | Copy into AMP `Assets.xcassets/Symbols` |
| `osc.floating.symbolset`, `osc.top.symbolset`, `osc.bottom.symbolset`, `osd.symbolset`, `liquid.glass.symbolset` | Custom SF Symbol SVGs, `template` / `hierarchical` | `16 pt` / `40×28 pt` in `SidebarLayoutPane` | Copy if Layout pane is shown |

- **12.2 Licence Compatibility & Attribution**:
  - IINA is licensed under **GNU General Public License v3.0** (`InfoPlist.strings`: `"Released under GPLv3."`, Copyright © 2017–2026 Collider LI, et al.).
  - AMP is licensed under **GPL-3.0-or-later** (`SPDX-License-Identifier: GPL-3.0-or-later`).
  - **Compatibility**: Fully compatible under GPLv3 Section 5. Add file-header attribution on any file or asset adapted from IINA (just as AMP already does in `Aagedal Media Player/UI/InitialWindowController.swift:5-6`):
    `// Adapted from IINA (https://github.com/iina/iina), Copyright © 2017-2026 Collider LI, et al., licensed under GPL-3.0.`
- **12.3 App Icon Note**: AMP keeps its own app icon (`NSApp.applicationIconImage`); on the Welcome window it is rendered at IINA’s exact `68×68 pt` size (`InitialWindowController.swift:111`).

---

## 13. Animations and timing (consolidated)

| Element | Trigger | IINA Duration, Curve & Delay (`Preference` key) | AMP Current Value | Exact Change |
|---|---|---|---|---|
| **OSC & Titlebar Show** | `mouseMoved` / `mouseEntered` in window | **`0.25 s`** (`UIAnimationDuration`), default `NSAnimationContext` easeInEaseOut, `0 s` delay (`MainWindowController.swift:16, 1219`) | `0.25 s` `.easeInOut` (`ContentView.swift:318`), traffic lights `0.2 s` (`WindowConfigurator.swift:95`) | Change traffic light fade in `WindowConfigurator.swift:95` to `0.25 s` |
| **OSC & Titlebar Auto-Hide + Cursor Hide** | Idle timer after `mouseMoved` outside OSC/Titlebar | Delay: **`2.5 s`** (`Preference.controlBarAutoHideTimeout`, `Preference.swift:583`); Fade-out: **`0.25 s`** (`UIAnimationDuration`) + `NSCursor.setHiddenUntilMouseMoves(true)` | `2.5 s` delay (`PlayerOverlayController.swift:24`), `0.25 s` fade, but **blocked when paused** (`isPlaying()` check at line 100) | Remove `isPlaying()` guard in `PlayerOverlayController.scheduleHide` so OSC/Titlebar/cursor auto-hide after `2.5 s` when paused too |
| **OSC & Titlebar Hide on Mouse Exit** | `mouseExited` window | Immediate (`0 s` delay), **`0.25 s`** fade-out (`MainWindowController.swift:729`) | Immediate (`setWindowHovered(false)` → `hide()`) | Matches IINA (`0.25 s` fade) |
| **OSD Show / Replace** | Any OSD event | Instant (`alphaValue = 1.0`, `0 s` fade-in), hold **`1.0 s`** (`Preference.osdAutoHideTimeout`, `Preference.swift:597`) or **`5.0 s`** for screenshot preview (`PlayerCore.swift:727`) | Speed/Tier badges use `0.25 s` fade; Screenshot/Export capsules stay until state clears | Show `IINAOSDView` instantly (`alpha = 1`), hold `1.0 s` (`5.0 s` for screenshot), then fade out |
| **OSD Fade-Out** | `hideOSDTimer` fires | **`0.50 s`** (`OSDAnimationDuration = 0.5`, `MainWindowController.swift:17, 1356`) | `0.25 s` | Set OSD fade-out duration to **`0.50 s`** |
| **OSD Accessory Reveal** | Screenshot OSD accessory added | **`0.30 s`** (`MainWindowController.swift:1339`) | N/A | Use `0.30 s` implicit animation when expanding OSD accessory |
| **Sidebar Open / Close** | Toolbar button / menu / click-outside | **`0.24 s`** (`SideBarAnimationDuration = 0.24`, `SidebarController.swift:9, 250, 279`), curve **`.easeIn`**, slide `edgeConstraint` (or fade if Reduce Motion) | SwiftUI `.move(edge: .trailing).combined(with: .opacity)` with default spring/ease | Use `.timingCurve(0.42, 0, 1.0, 1.0, duration: 0.24)` (`.easeIn`, `0.24 s`) slide without `.opacity` (unless Reduce Motion is enabled) |
| **Sidebar Tab Switch** | Clicking tab segment or horizontal swipe | **`0.30 s`** (`SidebarTabViewController.transitionDuration = 0.3`, `SidebarPane.swift:19, 58`), `CATransition` `.push` `.easeInEaseOut` | Instant `switch inspectorTab` (`ContentView.swift:287`) | Animate tab switch with `0.30 s` `.easeInEaseOut` horizontal push transition |
| **Hover Time & Thumbnail Preview** | Hovering `playSlider` | Instant (`isHidden = false` on hover, `isHidden = true` on exit; `MainWindowController.swift:1395-1450`) | Instant once `TimelineThumbnailLoader` resolves | Matches IINA |
| **Drag-to-Playlist Auto-Open** | Dragging file in rightmost 20% of window | **`0.30 s`** delay (`VideoView.swift:122`), then `0.24 s` sidebar slide | None | Optional `0.30 s` hover timer during drag |
| **Window Scale / Resize (`⌘0/1/2/3`)** | Menu or video size change | `window.setFrame(newFrame, display: true, animate: true)` (system duration, disabled when `disableAnimations` or macOS 26 legacy FS) | `animate: false` in `WindowConfigurator.swift:199` | Use `animate: true` on user-initiated `⌘0/1/2/3` window scale changes |

---

## 14. Conflicts (IINA Look vs VLC Behaviour Decisions)

Every collision below is resolved by **keeping IINA’s exact visual design and applying VLC’s decided interaction semantics**:

| # | Collision Area | IINA Default | Decided VLC Behaviour | Resolution (IINA Look + VLC Behaviour) |
|---|---|---|---|---|
| 1 | **Single-click on video** | `singleClickAction = .hideOSC` (`Preference.swift:659`) | Single click does nothing except drag window (`3 pt` threshold) | Keep IINA’s `minimumInitialDragDistance = 3.0 pt` drag threshold (`MainWindowController.swift:27`); do **not** toggle OSC or pause on single click (unless clicking outside an open sidebar, which dismisses the sidebar per `SidebarController.swift:168`). |
| 2 | **Double-click & Pinch on video** | `doubleClickAction = .fullscreen` (native fullscreen), `pinchAction = .windowSize` (`Preference.swift:660, 663`) | Double-click and pinch toggle "fill screen, stay windowed" (`screen.visibleFrame`) | Trigger AMP’s windowed fill-screen toggle on double-click and pinch, but apply IINA’s fullscreen/borderless chrome look while filled (`hasShadow = false`, `toolbar = nil`, titlebar & traffic lights auto-hidden until hover). |
| 3 | **Right-click on video** | `rightClickAction = .pause` (`Preference.swift:661`) | Right-click pops up a VLC-style context menu | Pop up an `NSMenu` on right-click over the video canvas using VLC’s item set styled with IINA’s menu titles, checkmarks, and monospaced-digit chapter timestamps (Section 9.2). |
| 4 | **Scroll wheel on video** | Vertical scroll = volume (`volumeMap[3] = 0.75x`), Horizontal scroll = seek (`seekAmountMapMouse[3] = 2x`) | Vertical scroll = volume **5% per step**, Horizontal scroll = seek **3 s per step** | Keep VLC’s exact step math (`5%` volume / `3 s` seek per scroll step) and display IINA’s `OSDView` (`Volume: %d` with progress bar; `cur / tot` with progress bar) on every scroll step. |
| 5 | **OSC Left/Right transport buttons** | `speedl.pdf` / `speed.pdf` (`arrowButtonAction = .speed`, tap/hold changes speed) | Standard transport seek (`±10 s`) or playlist prev/next | Use IINA’s exact `speedl.pdf` and `speed.pdf` `24×24 pt` template icons and `24 pt` spacing in `FloatingOSCView`, wired to AMP’s seek/shuttle action. |
| 6 | **Max volume** | `maxVolume = 100` (`Preference.swift:630`), configurable up to `1000` | Volume up to **125%** | Set `maxValue = 125` on `PlaybackVolumeSlider` and `PlayerController`. Because `maxValue > 100`, IINA’s `VolumeSliderCell` automatically renders the **`2 pt` clear notch at the 100% mark** (`VolumeSlider.swift:63-68`). |
| 7 | **OSC Auto-hide timing** | `controlBarAutoHideTimeout = 2.5 s` (`Preference.swift:583`) | VLC hides after `1.0 s`; IINA hides after `2.5 s` | Keep IINA’s **`2.5 s`** OSC auto-hide (`PlayerOverlayController.swift:24`) for visual parity with IINA’s chrome, and **`1.0 s`** for OSD messages (`Preference.osdAutoHideTimeout`). |
| 8 | **Resume playback** | Silent auto-resume (`resumeLastPosition = true`) + Welcome window `"Resume"` pill | VLC-style resume prompt + Welcome window `"Resume"` pill | Show IINA’s `"Resume"` pill (`InitialWindowViewActionButton`) in the Welcome window and render the in-player resume prompt inside `IINAOSDView` at top-left (using OSD’s accessory view slot, like `SubChooseViewController`) with `"Resume playback from 01:23?"` and `Resume` / `Start Over` buttons. |
| 9 | **Keymap & OSD for every hotkey** | `IINA Default` input.conf; OSD only on mpv property changes | Switchable `"VLC"` (default) or `"AMP Pro"` keymap; OSD on **every** hotkey | Add keymap selector (`VLC` default vs `AMP Pro`) in Settings → Shortcuts, and dispatch an `OSDMessage` to `IINAOSDView` for every hotkey action. |

---

## 15. Ranked task list

### 15.1 Ordered Implementation Tasks

#### Group A — Tokens & Shared Translucent Surfaces
1. **Create `IINADesignTokens.swift` and `IINATranslucentView.swift`**, adding all IINA colour sets, font tokens, layout metrics, and the `NSGlassEffectView` (macOS 26) / `NSVisualEffectView(material: .popover, blendingMode: .withinWindow)` (macOS ≤15) wrapper in `Aagedal Media Player/UI/IINADesignTokens.swift`.
   - *Verification*: Inspect rendered view hierarchy in Xcode View Debugger; confirm `NSGlassEffectView` on macOS 26 and `NSVisualEffectView(.popover)` on macOS 15 with zero custom border/shadow.
   - *Effort*: **S**

#### Group B — Window Chrome & Title Bar
2. **Update `WindowConfigurator.swift` and `ContentView.swift` to match IINA’s window chrome**, setting `baseMinWidth = 285, baseMinHeight = 120`, forcing `.darkAqua` appearance by default, attaching a `.unifiedCompact` `NSToolbar` when windowed, changing traffic-light fade duration from `0.2 s` to `0.25 s` (`alphaValue = 1e-100` when hidden), and dropping `hasShadow` + `toolbar` in fill-screen mode.
   - *Verification*: Side-by-side screenshot of windowed and fill-screen corners, shadow, and traffic-light position (`86 pt` clearance) against IINA.
   - *Effort*: **S**
3. **Add `IINATitleBarView.swift` and mount it at the top of `ContentView.swift`**, rendering `NSVisualEffectView(material: .titlebar, blendingMode: .withinWindow)` (`40 pt` tall on macOS 26, `36 pt` on ≤15), bottom `1 pt` `titleBarBorder` separator, `16×16` document icon at `leading: 86 pt`, `2 pt` gap, `13 pt` middle-truncated title with right-click path menu, and trailing `pin`/`pin.fill` float-on-top button (`12 pt regular`), fading with `overlayController.isVisible` (`0.25 s`).
   - *Verification*: Compare top title bar height, blur, bottom `1 pt` line, document icon, and title font side by side with IINA.
   - *Effort*: **M**

#### Group C — On-Screen Controller (OSC)
4. **Copy IINA’s vector transport icons (`play.pdf`, `pause.pdf`, `speed.pdf`, `speedl.pdf`, `next.pdf`, `nextr.pdf`, `remove.blackbars.svg`) into `Assets.xcassets`** with `template` rendering intent andGPLv3 attribution in `CREDITS`/` InitialWindowController.swift`.
   - *Verification*: Check asset catalog rendering mode and crispness at `@1x`/`@2x`.
   - *Effort*: **S**
5. **Update `FloatingOSCView.swift` to match `OSCFloatingView` pixel-for-pixel**, replacing `.ultraThinMaterial` + custom stroke/shadow with `IINATranslucentView(cornerRadius: 12 / 6)`, setting `volumeSlider` width to `70 pt` (`.leading(4)`, `4 pt` gap, `.trailing(6)`), fixing `VolumeButton` (`13 pt regular`, `speaker.fill` at `0` when unmuted), using `play`/`pause`/`speedl`/`speed` `24×24` icons with `30 pt` left/right `10 pt` `.secondaryLabelColor` speed labels, setting toolbar SF Symbols to `14 pt`/`13.5 pt` `.medium` with `.fill` active states, and setting scrubber row top spacing to `2 pt`.
   - *Verification*: Run `IINAParityChromeTests` and compare `chrome-2x.png` overlay against IINA’s `OSCFloatingView` (`460×67 pt`).
   - *Effort*: **M**
6. **Remove the `isPlaying()` gate in `PlayerOverlayController.scheduleHide`** (`Aagedal Media Player/Logic/PlayerOverlayController.swift:100`) so the OSC, title bar, and cursor auto-hide after `2.5 s` when paused as well as when playing.
   - *Verification*: Pause video, move mouse away from OSC, verify OSC and cursor hide after `2.5 s`.
   - *Effort*: **S**
7. **Restyle Compare Mode’s `ControlsView.swift` in IINA’s OSC visual language**, replacing `.ultraThinMaterial` + stroke/shadow with `IINATranslucentView`, using `16 pt` transport spacing, `70 pt` `IINAVolumeSliderCell`, and `11 pt` `.monospacedDigit()` timecode labels.
   - *Verification*: Enter Compare Mode and compare bar material, slider, and buttons with IINA’s bottom OSC.
   - *Effort*: **M**

#### Group D — Sliders & Time Labels
8. **Update `PlayerScrubber.swift` to match `PlaySliderCell` (`PlaySliderCell.swift:41-168`), `TimePreviewView`, and `ThumbnailPeekView`**, changing left bar fill to `white.opacity(0.30)`, right bar fill to `white.opacity(0.10)`, cutting `1 pt` clear gaps around the `3×15 pt` knob and at chapter positions, setting Dark-mode knob opacity to `0.80` idle / `0.98` active without shadow, and splitting the hover preview into a `120 pt`-wide thumbnail (`cornerRadius: 4`, `1 pt` border `gray(0.6, 0.5)`, `2 pt` black shadow) + `5 pt` gap + `TimePreviewView` pill (`padding: 4×4`, `11 pt` monospacedDigit).
   - *Verification*: Hover and scrub `PlayerScrubber`; compare bar alphas, `1 pt` chapter/knob gaps, and `120 pt` thumbnail + time pill against IINA.
   - *Effort*: **M**
9. **Replace `PlaybackVolumeSlider`'s cell in `Aagedal Media Player/UI/PlaybackVolumeSlider.swift` with `IINAVolumeSliderCell`**, setting `controlSize = .mini`, `maxValue = 125`, `1.5 pt` bar radius, `0.30` / `0.10` bar fills, and the `2 pt` clear notch at `100%`.
   - *Verification*: Set volume to `80%` and `120%`; verify the `2 pt` gap at `100%` and greyscale bar fills.
   - *Effort*: **S**
10. **Update `FloatingOSCView` time labels (`FloatingOSCView.swift:100-105`) to match `DurationDisplayTextField`**, using `.system(size: 11, weight: .regular).monospacedDigit()`, `.secondaryLabelColor`, click-to-toggle remaining time (`"-mm:ss"`), and right-click precision menu (`1s`, `100ms`, `10ms`, `1ms`).
    - *Verification*: Click right time label to toggle `-mm:ss`; right-click to switch precision.
    - *Effort*: **S**

#### Group E — On-Screen Display (OSD) & Overlays
11. **Create `IINAOSDView.swift` + `OSDMessage.swift` and mount in `ContentView.swift`** at top-left (`8 pt` below `IINATitleBarView`, `8 pt` from leading sidebar/edge), using `IINATranslucentView(liquidGlassCornerRadius: 16, vevCornerRadius: 10, padding: (16, 8))`, `20 pt` / `18 pt` colon-split monospaced-digit text, `11 pt` secondary label, `FixedProgressBar` (`12 pt` frame, `4 pt` bar, `3 pt` radius, `.controlAccentColor`), `1.0 s` timeout, and `0.50 s` fade-out.
    - *Verification*: Trigger volume, seek, pause, speed, aspect, crop, track, and trim hotkeys; compare top-left OSD card against IINA.
    - *Effort*: **M**
12. **Migrate `PlaybackSpeedIndicator`, `RenderTierBadge`, `MediaOperationFeedbackOverlay`, `EnhancementSuggestionView`, `UpdateAvailableBanner`, and `PlayerView.playbackStateOverlay` (`PlayerOverlayViews.swift`, `PlayerView.swift`, `RenderTierBadge.swift`) to `IINATranslucentView` and `IINAOSDView`**.
    - *Verification*: Capture screenshot, run trim export, and trigger shader tier badge; verify all overlays use IINA’s translucent material, fonts, and positions.
    - *Effort*: **M**

#### Group F — Sidebars & Floating Panels
13. **Restyle `ContentView.inspectorPanel`, `PlaylistSidebarView.swift`, and `MetadataInspectorView.swift` to match `SideBarContainer`, `SidebarPlaylistPane`, and `SidebarVideoPane`**, making the sidebar `360 pt` wide (resizable `300...500 pt`), full-height (`top: 0, bottom: 0, trailing: 0, cornerRadius: 0`), `0.24 s` `.easeIn` slide, `52 pt` header with `36×36` `chevron.forward` close button and segmented tabs (`Video`, `Audio`, `Subtitles`, `Playlist`, `Info`), `8 pt` rounded container cards (`fill: gray(0.1)`, `border: white(0.08)`), and playlist rows (`30 pt`, `"▶︎"` indicator column, `3 pt` bottom progress bar).
    - *Verification*: Open sidebar via OSC button or `⌘I`; compare header, tab switcher, card borders, and playlist table rows with IINA.
    - *Effort*: **L**
14. **Update `ScopeWindowController.swift` and `AudioWaveformWindowController.swift` (`ScopeView.swift`, `AudioWaveformView.swift`) to use IINA’s HUD panel chrome** (`.hudWindow` styleMask, `.darkAqua` appearance, `titlebarAppearsTransparent = true`, `.compact` toolbar style).
    - *Verification*: Open Scopes (`⇧⌘W`) and Audio Waveform (`⇧⌘A`) in window mode; compare panel chrome with IINA’s Inspector panel.
    - *Effort*: **S**

#### Group G — Welcome Window & Menus
15. **Update `Aagedal Media Player/UI/InitialWindowController.swift` and `DropZoneView.swift` to match IINA v1.5.0’s programmatic Welcome window (`560×440`)**, with `underWindowBackground` + `[0.4, 0.1]` gradient, `68×68` app icon + `20 pt bold` title at `top: 48, leading: 24`, `.large` `Open…` button at `top: 64, trailing: 30`, `32 pt`-tall (`cornerRadius: 8`) Resume Last File row, `28 pt` recent-files table rows with `GrayHighlightRowView` (`cornerRadius: 4`), and no dashed drag border.
    - *Verification*: Launch AMP without a file and compare Welcome window side by side with IINA v1.5.0.
    - *Effort*: **M**
16. **Restructure `Aagedal_Media_PlayerApp.swift` main menus and add the video right-click context menu** to match IINA’s menu hierarchy (`File`, `Edit`, `Playback`, `Video`, `Audio`, `Subtitles`, `Window`, `Help`), dynamic titles (`Pause`/`Resume`, `Mute`, `Enter/Exit Full Screen`, `Show/Hide ... Panel`), disabled indicator items (`Speed:`, `Volume:`, `Audio Delay:`, `Subtitle Delay:`), and VLC shortcuts.
    - *Verification*: Open each menu bar menu and right-click the video canvas; verify structure, dynamic titles, checkmarks, and shortcuts.
    - *Effort*: **M**

---

### 15.2 Elements in AMP That Already Match IINA Exactly (Do Not Touch)

1. **Floating OSC width & minimum width**: `FloatingOSCView.cardWidth = 460 pt`, `minCardWidth = 200 pt` (`FloatingOSCView.swift:14-15`) — matches `OSCFloatingView.swift:15, 48`.
2. **Floating OSC macOS 26 corner radius**: `FloatingOSCView.cornerRadius = 12 pt` (`FloatingOSCView.swift:16`) — matches `OSCFloatingView.swift:30` on macOS 26.
3. **Floating OSC internal paddings**: Top row `.padding(.top, 14)` and `.padding(.horizontal, 12)`; bottom scrubber row `.padding(.bottom, 8)` and `.padding(.horizontal, 8)` (`FloatingOSCView.swift:61-66`) — matches `OSCFloatingView.swift:35, 39` (`LayoutValue.oscPaddingTop = 14`, `oscPaddingBottom = 8`).
4. **Floating OSC button frame size & transport spacing**: `buttonSide = 24 pt`, `transportSpacing = 24 pt` (`FloatingOSCView.swift:17-18`) — matches `MainWindowController.swift:365, 382` and `Preference.ToolBarButton.frameSize = 24`.
5. **Floating OSC position persistence keys, defaults & center-snap haptics**: `controlBarPositionHorizontal` (`0.5`), `controlBarPositionVertical` (`0.1`), `5 pt` center snap threshold with `.alignment` haptic feedback, `10 pt` horizontal / `25 pt` top drag margins (`FloatingOSCView.swift:24-27, 198-215`, `OSCPosition.swift`) — matches `OSCFloatingView.swift:83-155` and `Preference.swift:580-582`.
6. **Play slider track & knob dimensions**: `barHeight = 3 pt`, `knobWidth = 3 pt`, `knobHeight = 15 pt`, `knobRadius = 1 pt`, `verticalPadding = 6 pt` (`PlayerScrubber.swift:13-17`) — matches `PlaySliderCell.swift:24-27` and `MainWindowController.swift:398`.
7. **OSC Time label minimum width & horizontal padding**: `minWidth: 46 pt`, `.padding(.horizontal, 2)`, `2 pt` spacing to slider (`FloatingOSCView.swift:92-105`) — matches `MainWindowController.swift:391, 395-397`.
8. **OSC auto-hide delay & fade duration**: `hideDelay = .seconds(2.5)` (`PlayerOverlayController.swift:24`) and `.easeInOut(duration: 0.25)` (`ContentView.swift:318`) — matches `Preference.controlBarAutoHideTimeout = 2.5` and `UIAnimationDuration = 0.25`.
9. **Cursor hiding & Apple FB11963121 workaround**: `NSCursor.setHiddenUntilMouseMoves(true)` re-armed on mouse-down when overlay is hidden (`PlayerOverlayController.swift:56-62, 90-92`) — matches `MainWindowController.workaroundCursorDefect()` (`MainWindowController.swift:588-591`).
10. **Playlist row height**: `PlaylistSidebarView.rowHeight = 30 pt` (`PlaylistSidebarView.swift:11`) — matches `LayoutValue.tableRowHeight = LayoutValue(30, 26)` (`SidebarPlaylistPane.swift:19`).
11. **Dock reopen behaviour & `quitWhenNoOpenedWindow` setting**: `applicationShouldHandleReopen` shows the welcome window when no windows are visible (`Aagedal_Media_PlayerApp.swift:311-323`) — matches `AppDelegate.swift:517-526`.
