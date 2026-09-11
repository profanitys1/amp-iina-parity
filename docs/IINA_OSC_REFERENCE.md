# IINA OSC design reference

Measured from IINA `master` (commit `a320321`). Source of the numbers this
fork's overlay chrome follows. IINA's default on-screen controller is the
*floating* one: a compact centred card, not a full-width bar.

## Container — `OSCFloatingView.swift`

| Property | Value |
|---|---|
| Width | 460 pt (priority 300), minimum 200 pt |
| Height | ~67 pt |
| Corner radius | 12 (macOS 26+), 6 below |
| Material | `NSVisualEffectView` `.popover`, `.withinWindow` blending, `.active` |
| Bottom margin from video | 25 pt |
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
