# IINA OSC design reference

Measured from IINA `master` (commit `a320321`). Source of the numbers this
fork's overlay chrome follows. IINA's default on-screen controller is the
*floating* one: a compact centred card, not a full-width bar.

> **Update — 2026-09-11:** the shipped build on this machine is IINA
> **1.5.0-beta1** (build 170), and its floating bar no longer matches the table
> below in one respect: it sits **flush with the bottom edge** (0 pt gap) and
> measures **460 × 80 pt** with a **≈7.5 pt** corner radius through its
> silhouette. See "Measured from the installed build" at the end of this file
> for the method and the full numbers. The chrome follows the *installed* build;
> the rows below are retained as the original source they were derived from.

## Container — `OSCFloatingView.swift`

| Property | Value |
|---|---|
| Width | 460 pt (priority 300), minimum 200 pt |
| Height | ~67 pt |
| Corner radius | 12 (macOS 26+), 6 below |
| Material | `NSVisualEffectView` `.popover`, `.withinWindow` blending, `.active` |
| Bottom margin from video | 25 pt (commit `a320321`); **0 pt in the installed 1.5.0-beta1** — the card is flush with the bottom edge |
| Position | draggable; snaps to centre with haptic feedback within ±5 pt |

Two stacked rows inside one card:

| Row | Padding |
|---|---|
| Top (buttons) | top 14 (10 compact), horizontal 12 |
| Bottom (slider) | bottom 8 (5 compact), horizontal 8, 8 pt below the top row |

## Top row — `MainWindowController.swift:479-566`

Three groups in one stack: **volume leading, play controls centred, toolbar
trailing**.

- Play controls: `[speed-left, play, speed-right]`, each 24×24, spacing 24.
  The arrows switch to prev/next track images when the user prefers that.
- Toolbar stack: spacing 0, height 24.

## Toolbar buttons — `Preference.swift:864-918`

Frame 24×24, compressed to 20 wide when five buttons share a floating OSC.
SF Symbols at 14 pt, `.medium` weight unless noted.

| Button | Symbol | Alternate |
|---|---|---|
| Settings | `gearshape` | `gearshape.fill` |
| Playlist | `list.bullet.rectangle` | `.fill` |
| PiP | `pip.enter` (13.5 pt) | `pip.exit` |
| Full screen | `arrow.up.backward.and.arrow.down.forward.rectangle` | inverse |
| Music mode | `music.microphone` | — |
| Subtitle track | `captions.bubble.fill` | — |
| Screenshot | `camera.shutter.button` | — |
| Plugins | `puzzlepiece.extension` (13.5 pt) | `.fill` |

## Slider row — `PlaySliderCell.swift`, `MainWindowController.swift:567-580`

- Knob 3 × 15 pt, corner radius 1.
- Slider vertical padding 6 pt.
- Time labels: monospaced-digit system font, 11 pt regular,
  `secondaryLabelColor`, minimum width 46 pt, 2 pt gap from the slider.

## What this fork does differently, and why

AMP carries more controls than IINA — volume, audio and subtitle track menus,
loop, fullscreen, and a SMPTE timecode readout. Those do not fit IINA's 460 pt
card, so the card is wider here and the timecode keeps its own trailing slot.
Proportions, materials, radii, row order, and the centred transport cluster
follow the table above.

## Measured from the installed build — IINA 1.5.0-beta1 (build 170)

Method (repeatable): launch IINA with a clip it can play, pause it, capture the
window twice with `screencapture -x -o -l <windowID>` — once with the pointer
moved outside so the chrome hides, once with the pointer over the video so the
chrome shows — then diff the two captures, split the changed rows into bands and
convert pixels to points at the display's 2x scale. A paused video makes the two
captures identical except for the chrome.

At a 640 × 360 pt window playing a 1280 × 720 clip:

| Band | Measurement |
|---|---|
| Title bar (with the filename and traffic lights) | 39.5 pt tall, full window width; hides with the chrome |
| Floating control bar | **460.0 pt wide × 80.0 pt tall, 0 pt gap to the bottom edge**, corner radius ≈7.5 pt through the silhouette |

Note on comparing values: measure both apps the same way. IINA's 80 pt and this
fork's card are both *rendered silhouettes* (body plus shadow); the card's
authored body height is smaller than the silhouette, so comparing an authored
constant against a rendered band overstates the difference.

What this fork does: the floating card is 460 pt wide and sits flush with the
bottom (no margin), matching the installed build. The card keeps its authored
corner radius. There is deliberately **no filename strip** over the picture —
the window title text is hidden, so nothing overlays the video, and the file name
is reachable from the Window menu and the playlist sidebar. That is a deliberate
departure from IINA, which shows a 39.5 pt title bar with the filename whenever
its chrome is visible.
