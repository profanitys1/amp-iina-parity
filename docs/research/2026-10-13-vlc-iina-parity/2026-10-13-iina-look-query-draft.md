# Query 2 — Make AMP look exactly like IINA (VLC behaviour for standard interactions)

Attached: (a) IINA source at its latest release tag (github.com/iina/iina): every Swift file under iina/ that builds UI, all .xib files (as XML), Assets.xcassets Contents.json + image names, Preference.swift defaults, and the localized Main.strings for menu/OSD text; (b) AMP's full source; (c) AMP's existing IINA-parity tests (IINAParityChromeTests.swift) and notes.

## Goal
Make AMP LOOK exactly like IINA. The smallest detail matters: a 1 pt padding, a 0.05 alpha, a 0.25 s vs 0.3 s fade, an SF Symbol weight. Standard interactions BEHAVE like VLC for macOS (already decided, do not reopen):
- Mouse on video: single click does nothing except drag the window (3 pt threshold), double click toggles "fill screen, stay windowed" (not native fullscreen), right-click shows a VLC-style context menu, vertical scroll changes volume 5% per step, horizontal scroll seeks 3 s per step, pinch toggles fill.
- Keymap: switchable, "VLC" (default, VLC macOS defaults) or "AMP Pro" (JKL shuttle, arrows seek).
- Window sizing, ⌘0/1/2/3 sizes, float on top, volume up to 125%, elapsed/remaining toggle, resume prompt, on-screen messages for every hotkey — VLC semantics.
AMP's extra UI (render-profile tier badge, enhancement suggestion banner, Compare Mode controls/timeline, scopes/parade panels, inspection loupe, audio waveform, timecode readout/entry, trim in/out marks, speed indicator, transport-sync badge) STAYS. Only restyle it so it is visually indistinguishable in language from IINA. Do NOT propose new features, engine changes, or behaviour changes outside the list above.

## Output rules
- For every element: IINA value (file:line or xib object id + attribute), AMP current value (file:line), and the exact Swift/SwiftUI/AppKit change (code snippet when non-trivial).
- Use a table per section: Element | IINA exact value | AMP now | Change | Effort S/M/L.
- Values to capture wherever they apply: frame size, min/max size, insets/padding/margins, spacing, corner radius, border width/colour, shadow (radius, offset, opacity, colour), NSVisualEffectView material + blendingMode + state + emphasized + appearance, background colours with alpha, text colour, font family/size/weight/design, monospaced digits, line height, SF Symbol name + pointSize + weight + scale + rendering mode, image asset names and @2x sizes, hover/pressed/disabled states, tint, cursor type, animation duration + timing curve + delay, auto-hide delays, z-order, autoresizing/constraints.
- If a value lives in a xib you cannot see clearly, write UNCERTAIN and say which xib/object to inspect. Never invent a value. Note where IINA reads a value from Preference (and the default).
- Where IINA differs between light and dark appearance, or between windowed and fullscreen, give both.

## 1. Player window chrome
1.1 Window style mask, titlebarAppearsTransparent, titleVisibility, fullSizeContentView, toolbar, isMovableByWindowBackground, collectionBehavior, backgroundColor, hasShadow, isOpaque, corner radius (incl. rounded-corner masks on macOS 26).
1.2 Title bar: height, the top gradient/shade view (colours, alpha, height), title text font/colour, document proxy icon, traffic lights position/offset and whether IINA moves them, hover show/hide behaviour of title bar + traffic lights (delay, fade duration), "title bar style" preference variants.
1.3 Default/minimum window size, content min size, aspect-ratio locking calls, initial position, frame autosave name, how the window grows on open (IINA's resize-to-fit logic vs VLC semantics we keep — just the look of the transition: animated or not, duration).
1.4 Video view background colour, letterbox colour, padding around video, what shows before first frame (black? material? spinner?).
1.5 Window corner rounding in fullscreen and when filling visibleFrame.

## 2. On-screen controller (OSC)
For each IINA layout — floating (default), title bar, bottom bar, and "music mode" controls — give:
2.1 Container: size, minimum width, padding, corner radius, NSVisualEffectView material/blending/state, border/shadow, appearance (forced dark?), distance from window edges, default position, drag behaviour (drag handle, snapping to centre, haptic, position persistence key), resize behaviour when window is narrow.
2.2 Layout grid: rows, element order left→right, spacing between every pair, alignment, which elements hide at which widths.
2.3 Every button: play/pause, rewind/forward (and their long-press speed behaviour visuals), previous/next, volume/mute (icon states for 0/low/mid/high/muted), playlist, settings/quick settings, fullscreen, PiP, music mode, sub/audio track buttons, "more" — SF Symbol or asset name, point size, weight, tint, hover/pressed visuals, button frame size, tooltip text.
2.4 Show/hide: trigger (mouse move/enter/exit, keyboard), auto-hide delay (Preference default), fade-in and fade-out durations and curves, whether cursor hides with it, behaviour while hovered, while paused, while dragging the slider, in fullscreen.
2.5 Speed/state indicators shown inside the OSC (speed label, buffering spinner, A-B loop state).
2.6 How AMP's existing FloatingOSCView and ControlsView must change to match; which AMP-only controls (render tier badge, transport-sync badge, subtitle menu, settings) map to which IINA slot and how they must look.

## 3. Sliders
3.1 Play/seek slider (PlaySliderCell / PlaySlider): track height, corner radius, colours (played, unplayed, buffered/cache), knob shape (IINA's rounded rect?), knob size/colour/shadow, knob on hover vs idle, chapter marks (shape, size, colour), A-B loop marks, hover time label (font, background, offset), hover thumbnail preview (size, corner radius, border, shadow, time label placement, fade), click-to-seek vs drag behaviour visuals, scroll-on-slider visuals.
3.2 Volume slider (VolumeSliderCell): width, track/knob, colours, 100% marker when max > 100, tooltip.
3.3 AMP mapping: PlayerScrubber, PlaybackVolumeSlider, ControlsView timeline (Compare Mode keeps its markers, but in IINA style).

## 4. Time labels
4.1 Font, size, weight, monospaced digits, colour/alpha, alignment, min width, format (h:mm:ss vs mm:ss, when hours appear), click to toggle remaining (IINA's indicator, e.g. leading "-"), placement relative to slider.
4.2 AMP timecode readout (frames, modes) restyled to IINA's label look.

## 5. On-screen messages (OSD)
5.1 Position (top-left? offset), max width, font/size/weight, text colour, background material/colour/alpha, corner radius, padding, icon usage, accessory views (progress bar for volume/seek: size, colours), stacking/replace behaviour, display duration (Preference default), fade in/out duration, behaviour in fullscreen and with the title bar visible.
5.2 Full list of IINA OSD message types with exact text format (volume, seek "time / duration", speed, audio/sub track, delay, aspect, crop, rotate, screenshot taken, file loaded, chapter, A-B loop, deinterlace, etc.).
5.3 AMP: the OSD we will add (VLC message set) rendered in IINA's OSD style; AMP's existing PlaybackSpeedIndicator, render-tier badge, screenshot/export capsules, enhancement banner, update banner, buffering/preparing/failure overlays — how each must look to match IINA (position, material, font, timing).

## 6. Sidebars and panels
6.1 Quick settings sidebar: width, material, open/close animation (duration, slide vs fade), tab bar style (Video/Audio/Subtitles), every section and control (segmented controls, sliders with value labels, steppers, track tables: row height, fonts, selection style, checkmarks), section header style, spacing.
6.2 Playlist / chapters sidebar: width, row height, fonts, playing-item indicator, hover/selection colours, drag-reorder visuals, empty state, tab style.
6.3 AMP mapping: inspector (⌘I), playlist sidebar, subtitle menu, audio track picker, chapter picker, render profile settings — which IINA sidebar section each moves into (visually), exact styling.
6.4 AMP floating panels (scopes, parade, waveform, loupe, review notes): IINA-style panel chrome (window style, material, title bar, corner radius) so they look native to IINA's family.

## 7. Fullscreen and fill-screen
7.1 IINA native vs legacy fullscreen visuals: black background, title bar reveal at top hover (timing), OSC position/size changes, cursor hiding timing, corner radius, animation.
7.2 Look of AMP's VLC "fill screen, stay windowed" state: should it drop the window shadow/corner radius, hide traffic lights until hover, like IINA's fullscreen? Give exact IINA values to copy.

## 8. Welcome / initial window and empty states
8.1 IINA InitialWindow: size, layout, app icon size, title/version text styles, recent files list (row style, icons, hover), "Open file / Open URL / Resume last" buttons, material/background, behaviour on drag-over (highlight style).
8.2 AMP DropZoneView and InitialWindowController mapped to it.
8.3 Drag-and-drop highlight on the player window itself.

## 9. Menus
9.1 IINA's complete main menu bar structure (every menu, item, separator, submenu, shortcut) — AMP keeps VLC keymap shortcuts, so give IINA's structure and titles, and we will put VLC shortcuts on them.
9.2 IINA's video context menu structure and titles (we use VLC's item set; tell us how IINA styles/orders similar items, submenu titles, checkmark usage).
9.3 Menu-item titles that change with state (Pause/Resume, Mute/Unmute, Enter/Exit Full Screen).

## 10. Mini player (music mode) and Picture in Picture
10.1 Visual spec of IINA music mode window (sizes, album art, controls, playlist drawer) and PiP button/visuals. Say whether these are separable from behaviour — if AMP adds them later, what must they look like. Do not plan them as features, just record the visual spec.

## 11. Typography, colour, materials, appearance, accessibility
11.1 Every font IINA uses (system font sizes/weights, monospaced digit usage) — a token table.
11.2 Every colour/alpha (labels, tracks, backgrounds, separators, selection) — a token table, light and dark.
11.3 Materials used per surface (hudWindow, sidebar, menu, popover, underWindowBackground, etc.) and blending modes.
11.4 Forced appearance (does IINA force dark aqua on the player window/OSC?).
11.5 Reduce Transparency, Reduce Motion, Increase Contrast behaviour in IINA; VoiceOver labels/roles on controls.
11.6 Propose a single AMP design-token file (Swift) holding all these values, with names.

## 12. Icons and assets
12.1 Which IINA image assets (not SF Symbols) the OSC, OSD, sidebar and welcome window use; their sizes; whether they are template images.
12.2 Licence check: IINA is GPLv3, AMP is GPL-3.0-or-later — confirm reuse is compatible and what attribution to add.
12.3 App icon style differences (just note; no icon redesign).

## 13. Animations and timing (consolidated)
13.1 One table of every animation/timer in IINA's UI: element, trigger, duration, curve, delay, Preference key/default. Includes OSC fade, title bar fade, OSD show/hide, sidebar slide, thumbnail preview fade, window resize animation, fullscreen transition, cursor hide delay.
13.2 AMP's current values for the same (PlayerOverlayController 2.5 s hide, 0.25 s opacity, etc.) and the changes.

## 14. Conflicts
14.1 Every place where IINA's look and the VLC behaviour decisions collide (e.g. IINA's 1-click play/pause setting, IINA's double-click → fullscreen, IINA's scroll → seek default, IINA's arrow-key seek, IINA's OSC auto-hide timing vs VLC's 1 s, IINA's resize-on-open). For each: resolution = keep IINA's look, VLC's behaviour; state any visual adjustment the VLC behaviour needs (e.g. OSD wording, menu labels).

## 15. Ranked task list
15.1 Ordered list. Each item: one imperative sentence, AMP file(s) to change, exact IINA values to apply, verification (what to compare in a screenshot side by side), effort S/M/L. Group into: window chrome, OSC, sliders, labels, OSD, sidebars/panels, welcome window, menus, tokens/accessibility, animations.
15.2 List anything in AMP's current UI that already matches IINA exactly (so we don't touch it).
