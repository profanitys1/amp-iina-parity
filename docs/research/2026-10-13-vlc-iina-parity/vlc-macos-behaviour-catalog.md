# VLC macOS GUI behaviour catalog (from VLC source)

Read from VLC source on 2026-10-13: `videolan/vlc` branch `3.0.x` and `master` (4.0), `modules/gui/macosx`, plus `src/libvlc-module.c`, `modules/control/hotkeys.c`, `src/misc/actions.c`. Line numbers drift. This is ground truth for AMP's "behave like VLC" work.

## 1. Mouse on video
| Input | Behaviour | Source |
|---|---|---|
| Single left click | 3.0: nothing except window drag (`mouseDownCanMoveWindow` YES, `setMovableByWindowBackground:YES`). Does NOT pause. 4.0 reports click to core; macOS GUI does not pause itself. | 3.0 `VLCVoutView.m:198-209,341`; 4.0 `VLCVoutView.m:163-181` |
| Double left click | `toggleFullscreen`, no pause first, first click has no side effect. | 3.0 `VLCVoutView.m:201-202`; 4.0 `:172-173` |
| Right click / Ctrl-click | `voutMenu`: Play/Pause, Stop, Previous, Next, Volume Up, Volume Down, Mute, Fullscreen, Snapshot. | 3.0 `VLCVoutView.m:203-225`, `MainMenu.xib` |
| Middle click | No handler. | |
| Drag | Moves the window; disabled in fullscreen. | 3.0 `Windows.m` |
| Pinch | > +0.3 cumulative enters fullscreen, < -0.3 exits. | 4.0 `VLCVoutView.m:~375-390` |

Scroll wheel (identical 3.0/4.0, `VLCVoutView.m:244-300`): synthesises core key events. Accumulates `[event deltaY]`/`deltaX`; threshold 1.0 on Y, 0.8 on X; each crossing fires one step; a wheel notch always fires at least one step; deltas negated when `isDirectionInvertedFromDevice`; opposite axis ignored for 0.4 s after the last event; deltaY < 0.05 treated as zero. Vertical = volume, 5 % per step (`volume-step` 12.8/256). Horizontal = seek ±3 s (`extrashort-jump-size`). Cmd+wheel = subtitle text scale.

Cursor/controls hide: `mouse-hide-timeout` 1000 ms. 4.0 control overlay fades after 1 s, fade 0.4 s; never hides while hovering controls.

## 2. Keyboard (macOS defaults, `__APPLE__` block of libvlc-module.c)
Esc always exits fullscreen. Unmodified Up/Down/Delete/Return are NOT hotkeys (plain arrows = DVD nav only).

| Action | Key | OSD |
|---|---|---|
| Play/Pause | Space | icon |
| Fullscreen | Cmd+F; Esc exits | — |
| Stop | Cmd+. | — |
| Previous / Next | Cmd+Left / Cmd+Right | "Previous"/"Next" |
| Jump ±3 s | Cmd+Ctrl+Left/Right | "m:ss / m:ss" |
| Jump ±10 s | Cmd+Alt+Left/Right | same |
| Jump ±60 s | Cmd+Shift+Left/Right | same |
| Jump ±5 min | Cmd+Shift+Alt+Left/Right | same |
| Volume ±5 % | Cmd+Up / Cmd+Down | "Volume N%" |
| Mute | Cmd+Alt+Down | icon |
| Faster / Slower | Cmd+= / Cmd+- | "Speed: 1.25x" |
| Normal rate / fine rate | unbound on macOS | |
| Next frame | E (pauses) | "Next frame" |
| Aspect ratio cycle | A | "Aspect ratio: X" |
| Crop cycle | C | "Crop: X" |
| Zoom mode | Z / Shift+Z | "Zoom mode: X" |
| Autoscale toggle | O | "Scaled to screen"/"Original Size" |
| Subtitle track | S (Alt+S reverse, Shift+S toggle) | "Subtitle track: X" |
| Audio track | L | "Audio track: X" |
| Time OSD | T | "m:ss / m:ss" |
| Subtitle delay -/+50 ms | H / J | "Subtitle delay N ms" |
| Audio delay -/+ | F / G | "Audio delay N ms" |
| Deinterlace | D / Shift+D | "Deinterlace on (x)"/"off" |
| Audio device cycle | Shift+A | "Audio Device: X" |
| Snapshot | Cmd+Alt+S (menu Cmd+Shift+S) | — |
| Loop / Random | Shift+L / Cmd+Z | "Loop: x"/"Random: x" |
| Half / Normal / Double size | Cmd+0 / Cmd+1 / Cmd+2 | — |
| Fit to screen | Cmd+3 | — |
| Jump to time | Cmd+J | — |
| Fullscreen controller | I | — |
4.0 adds Shift+E previous frame, Cmd+Shift+V subtitle control.

## 3. Window
- Open: window animates to native video size (`macosx-video-autoresize` default true), top-left anchored, clamped to `visibleFrame`.
- Aspect lock on user resize (`macosx-lock-aspect-ratio` default true).
- Half/Normal/Double set vout zoom 0.5/1/2; Fit to Screen = `performZoom`.
- Float on top: `NSStatusWindowLevel`, restored after fullscreen/minimize.
- Fullscreen: 3.0 default non-native (`macosx-nativefullscreenmode` false), 4.0 native.
- Title: media title, `representedURL` (proxy icon) for local files.
- Closing the video window stops playback. `macosx-pause-minimized` default false.

## 4. Fullscreen controller
3.0: floating HUD NSPanel (play/pause, prev, next, jumps, title, time slider, elapsed/remaining, volume, fullscreen), appears on mouse move, fade 0.4 s, hides after 1 s idle unless hovered; time defaults to remaining in fullscreen. 4.0: in-video overlay, same timings.

## 5. Controls bar
- Time field click toggles elapsed/remaining (persisted, default elapsed); double click opens Jump to Time.
- Seek slider seeks on mouse-down and drag; scroll on slider = 1 % per notch (trackpad 0.2 % × deltaY).
- Volume slider max `macosx-max-volume` default 125 % (range 60–200), tick at 100 %, tooltip "Volume: N %".

## 6. Menus (3.0/4.0 MainMenu.xib)
File (Open File ⌘O, Advanced Open ⇧⌘O, Open Disc ⌘D, Open Network ⌘N, Capture ⌘R, Open Recent, Close ⌘W, Reveal in Finder ⇧⌘R, Convert/Save ⇧⌘S, Save Playlist ⌘S) · Playback (Play/Pause, Stop ⌘., Record, Rate, Step Fwd/Back ⌥⌘→/←, Jump to Time ⌘J, Previous/Next ⌘←/→, Shuffle ⌘Z, Repeat, A→B loop, Quit after playback, Renderer, Program/Title/Chapter) · Audio (Volume Up/Down, Mute, Audio Track, Stereo Mode, Visualizations, Audio Device) · Video (Half ⌘0, Normal ⌘1, Double ⌘2, Fit ⌘3, Fullscreen ⌘F, Float on Top, Snapshot, Aspect Ratio, Crop, Deinterlace, Deinterlace mode, Post processing, Video Track) · Subtitles (Open File, Track, Size, Text Color, Outline, BG Opacity/Color, Teletext) · Window (Minimize ⌘M, Zoom, Playlist ⌥⌘P, Media Information ⌘I, Video Effects ⌘E, Audio Effects ⇧⌘E, Track Synchronization, Bookmarks ⌘B, Messages ⇧⌘M) · Help.

## 7. Other
- Drag-drop: single file during playback is tried as subtitle first, else enqueued.
- Resume ("Continue playback?"): `macosx-continue-playback` 0 ask (default) / 1 always / 2 never; stored per URL in NSUserDefaults `recentlyPlayedMedia`; local existing files only; skip if duration < 3 min, if position < 5 % and < 60 s from start, if > 95 % and < 60 s remain. Dialog: Continue / Restart, "Always continue" checkbox, 10 s countdown defaulting to restart.
- Media keys / Now Playing: 3.0 SPMediaKeyTap + MPRemoteCommandCenter; 4.0 MPRemoteCommandCenter + MPNowPlayingInfoCenter, skip ±60 s.
- Sleep: video uses user-activity + no-display-sleep assertions; audio no-idle-sleep; released on pause/stop.
- OSD texts (core hotkeys.c): "Volume N%", "m:ss / m:ss", "Speed: %.2fx", "Next frame", "Subtitle delay N ms", "Audio delay N ms", "Aspect ratio: X", "Crop: X", "Audio track: X", "Subtitle track: X", "Next", "Previous", "Loop: X", "Random: X". No OSD for resize/fullscreen/snapshot.
