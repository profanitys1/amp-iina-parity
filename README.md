<img width="200" height="200" alt="AagedalMediaPlayer" src="https://github.com/user-attachments/assets/e2234529-3fe6-458b-98ae-87761418c8d2" />

# Aagedal Media Player
![SCR-20260221-pzdf](https://github.com/user-attachments/assets/5c066416-8542-402f-83df-f49cc01a9bc4)

A fast, private professional media inspection player for macOS. Compare masters,
inspect picture and sound, verify metadata and timecode, and export review evidence
without uploading your media.

## Inspect a reference against an encode

1. Open the reference file as A, then use the toolbar's **Add comparison file**
   control to load its delivery encode as B. B starts silent.
2. Check the alignment status and overlapping interval. **Source timecode**
   aligns embedded timecodes; **Relative start** aligns file starts when either
   timecode is missing. Use [manual alignment](docs/COMPARE_MODE_ALIGNMENT.md)
   for an intentional offset in seconds or A frames.
3. Play, pause, scrub, or frame-step with the shared transport. Choose
   **Vertical Wipe** from **Compare view** and drag the divider across fine
   detail, or press **B** to switch between A and B. **Display Difference**
   highlights visible differences; it is not an objective quality score.
4. Press **Command-Shift-M**, enable **Show loupe**, and inspect a detail at
   2×, 4×, or 8×. **Pin picture position** keeps that location while you operate
   playback. The paired previews use the same normalized picture coordinate;
   their captures are independent, not frame-locked or exact source-pixel 1:1.
5. Pause at a useful comparison point and choose **File > Export Comparison
   Still** (**Command-S**). The annotated PNG places A and B side by side with
   filenames, timecodes, alignment, inspection view, and technical details. It uses that fixed
   layout regardless of the live wipe, overlay, or difference selection.

Loupe and still imagery are display-space previews; HDR appearance can differ
from the live display. For a repeatable local example, generate the reference
and encode pair in [the demo guide](docs/COMPARE_MODE_DEMO.md).

Ordinary windows can also share transport commands; see
[window synchronization](docs/WINDOW_SYNCHRONIZATION.md) for its scope and the
separate one-time timecode alignment command.

## Roadmap

See [PRODUCT_ROADMAP.md](PRODUCT_ROADMAP.md) for the release sequence from the
1.6.1 reliability foundation through Compare Mode, Audio QC, and review/report
workflows.

## Local verification

Media integration tests use tiny, locally generated clips so large binary
fixtures are never committed:

```bash
scripts/generate-test-fixtures.sh
xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination "platform=macOS" CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=
```

The signing overrides at the end are needed on a Mac with no "Mac Development" certificate:
without them the build fails to sign and the test run never starts.

The generator requires a full ffmpeg installation with libx264, libx265 and
alac. Set `FFMPEG=/path/to/ffmpeg` to select one explicitly. Without the
fixture tree **37 tests skip** (25 compare live-backend tests, 10
generated-media fixture tests, the timeline thumbnail loader and the
comparison still exporter); a 38th test,
`CompareReviewDiskFullTests.testRealVolumeExhaustionPreservesSidecarAndAllowsRetry`,
skips for a different reason and only runs through
`scripts/test-compare-review-disk-full.sh`, never in the ordinary suite. All
pure unit tests continue to run.

Eight further tests exercise the new player chrome and key layer against the
generated tree. They **fail** rather than skip when it is absent, so run
`scripts/generate-test-fixtures.sh` before the suite; a missing tree is reported
as a failure, never as a silent pass.

Verify review-save recovery on a real full filesystem with an isolated 32 MiB
HFS+ or 128 MiB APFS disk image:

```bash
scripts/test-compare-review-disk-full.sh -configuration Release
# Optional bounded APFS variant:
AAGEDAL_DISK_FULL_FILESYSTEM=APFS scripts/test-compare-review-disk-full.sh -configuration Release
```

The harness creates and validates its own temporary volume, checks production
atomic writes and retry, then detaches and removes the image. It retains the
test results and volume evidence in the printed artifact directory. The ordinary
test suite skips this opt-in check. See [review persistence](docs/COMPARE_REVIEW_SIDECAR.md)
for the recovery guarantees and remaining native acceptance.

Scope rendering has an optimized profiling matrix covering every available
scope resolution and the full 5–30 fps update-rate range:

```bash
scripts/profile-scopes.sh
```

The report includes luma and RGBY parade render time, sustainable update rate,
and estimated renderer load for every supported update-rate setting. Timings
are machine-dependent, so compare changes on the same hardware and profile on
the oldest Mac supported for release when changing scope capture or rendering.

Compare Mode has a separate opt-in production-resolution profile:

```bash
scripts/profile-compare-mode.sh | tee compare-mode-profile.txt
```

It generates disposable UHD 10-bit HDR sources, exercises all four MPV and
AVFoundation backend pairings with extended drift assertions, and drives the
real mixed-backend comparison canvas through every visual mode. See
[the Compare Mode performance methodology](docs/COMPARE_MODE_PERFORMANCE.md)
for configuration, pass criteria, and the complementary Instruments run.

Long-recording audio waveform aggregation has a separate 1, 8, and 24-hour
multichannel profile:

```bash
scripts/profile-audio-waveforms.sh
```

Its report includes decode time, fixed accumulator size, and resident-memory
growth. See [docs/AUDIO_WAVEFORM_PERFORMANCE.md](docs/AUDIO_WAVEFORM_PERFORMANCE.md)
for the current baseline and methodology.

Profile production timeline thumbnail requests against long recordings:

```bash
scripts/profile-timeline-thumbnails.sh /tmp/thumbnail-profile /path/to/long-recording.mov
```

The artifact directory must be new. The profile retains its environment,
input hashes, test results, and latency/memory measurements. See
[timeline profiling](docs/TIMELINE_THUMBNAIL_PERFORMANCE.md) for methodology
and the remaining playback/UHD/HDR and release-floor checks.

Profile production whole-file and selected-range loudness on long multichannel files:

```bash
scripts/profile-audio-loudness.sh /tmp/loudness-profile /path/to/long-5.1.m4a
```

This also requires a new artifact directory and retains separately sampled app
and FFmpeg memory. See [loudness profiling](docs/AUDIO_LOUDNESS_PERFORMANCE.md)
for the workload, reproducible fixtures, and measurement limits.

Optional original ITU voice/music and stereo/5.1 programme loudness checks use
externally downloaded reference files. The runner also compares programme LRA
with an independent PCM calculation, separately labeled from official targets:

```bash
scripts/check-itu-programme-loudness.sh /tmp/new-itu-results /path/to/references
```

An additional original ITU eight-channel gain reference verifies conventional
7.1 weighting after a documented lossless speaker-order preparation:

```bash
scripts/check-itu-seven-point-one-loudness.sh /tmp/new-itu-7-1-results /path/to/references
```

See [official programme references](docs/AUDIO_PROGRAMME_REFERENCES.md) for
source downloads, expected values, and the distinction from live-meter validation.

Release builds support Apple Silicon (`arm64`) on macOS 26 or later. Maintainer
preflight, signing, architecture, entitlement, and ffmpeg provenance guidance is
in [docs/RELEASE.md](docs/RELEASE.md).

## Features

### Compare Mode
Load a second master in the same window and inspect both with shared, frame-accurate
transport. Compare Mode aligns sources by embedded timecode when possible and offers
side-by-side, instant A/B, draggable wipe, opacity overlay, and display-space
difference views. Source B stays silent unless you explicitly switch monitoring,
with optional matching-channel isolation for multichannel A/B checks. Annotated
stills and review reports keep filenames, timecode, alignment, and technical
context attached. Selected-track audio details show A/B channel labels, layout
mismatches, and unmatched speaker roles; see [audio inspection](docs/COMPARE_MODE_AUDIO.md)
for semantic versus positional channel pairing. Review storage, schema, and
portability limits are documented in [comparison review sidecars](docs/COMPARE_REVIEW_SIDECAR.md).
Review findings support severity, category, status, and inclusive frame ranges.
Expand a note to classify it or set its end frame; search matches note text and
classifications. Reports include all findings, including filtered-out notes.
After moving media, use **Relink Notes…** in Comparison Review to map an old
sidecar to the loaded A/B pair. The confirmation shows both mappings; the
original sidecar and any existing destination review are preserved.
For older reviews with rounded broadcast rates, use **Notes → Migrate Rounded
Timebases…** to preview and save a corrected copy while keeping recorded frame
numbers. Use **Open Notes Copy…** to reopen it in a later session.

### Enhance (shader upscaling)
Enhance (Settings → Rendering) picks a sharpening or neural upscaling shader
tier automatically from how much the picture is enlarged, and steps down to a
lighter tier when the GPU cannot keep up. A badge over the picture names the
active tier. Shaders come only from your mpv shader folder
(`~/.config/mpv/shaders`); nothing is bundled. Enhancement alters the image, so
it is off by default and the default render path stays faithful to the source.

### Playlist and metadata panel
⌘I (or the Playlist button) floats a see-through Liquid Glass panel over the
picture with the folder's other media and the current file's metadata; ⌘I or
the ✕ closes it.

### Inspection loupe
Open the magnifying-glass control (Command-Shift-M) to enable a 2×, 4×, or 8×
preview. Move over the fitted picture, or pin the position to operate playback
controls. Position sliders and Center and pin support inspection without precise
pointer movement. Compare Mode shows paired A/B loupes at the same normalized
picture coordinate.

The preview uses display-space captures at up to 10 fps. HDR appearance may
differ from the live display, and the A/B samples are not frame-locked. Exact
source-pixel 1:1 inspection and whole-viewport zoom remain planned. See
[the loupe validation guide](docs/INSPECTION_LOUPE.md).

### File support
Playback (almost) every audio and video file in existence, through a combination of the mpv and AVFoundation.
As of 2026-02-21, it supports more codecs than IINA; ProRes RAW, Advanced Professional Video (APV), and VVC (H.266).

Some of the supported formats here:
| Containers | Video Codecs | Audio Codecs |
| :--- | :--- | :--- |
| MOV | ProRes / ProRes RAW | WAV |
| MXF | DNx and APV | ALAC |
| MP4 (`.mp4`, `.m4v`) | H.264 (AVC) | AAC |
| MKV (`.mkv`) | H.265 (HEVC) | MP3 |
| WebM (`.webm`) | VP9 | Opus |
| AVI (`.avi`) | AV1 | FLAC |

(Notable exceptions are other professional RAW video codecs.)

### Speed
Launches faster than IINA and QuickTime. 1 second vs 2 seconds.
Tested 2026-02-21 on an M1 Max MacBook Pro.


### Professional Shortcuts
Use proper JKL playback controls with up to 8x playback speed. Professionals can finally feel at home in a free and open source video player.
You can also hold Option while dragging the playhead for 10x more precise dragging. Useful for finding an exact scene in longer videos.


### Timecode display and input
Display timecode, with quick switching between source timecode, relative timecode and a frame counter view.
You can also input both absolute timecode, and use + and - before a number to jump relative to the current playhead position.


### Lossless Trim
One of the most missed features from QuickTime is now available in an open source app. Quickly set an in and out point using I and O keys, then use Command + E to export.
Select a default export location in the settings, or save next to the original, or always be asked where to save it. Including a few settings for format. Default is lossless trim.


### Screenshots
Take quick screenshots at source resolution in JPEG XL, JPEG or PNG. Command + S.
Select a default export location in the settings, or save next to the original, or always be asked where to save it.


### Video Scopes
Real-time waveform, waveform RGBY parade and vectorscope overlays for monitoring exposure and color. Toggle with Command + Shift + W. Configurable resolution and frame rate in scope settings. By default the waveform is overlayed over the video, but can also be opened in a separate window.
![SCR-20260309-ucop](https://github.com/user-attachments/assets/9fc2e4fb-8407-4b87-b71e-eb6d47ee383b)


### Audio waveform
Preview multichannel audio tracks as waveforms, with one waveform per channel. Toggle with Command + Shift + A. Supports multi track files. Changing the audio output track will update the preview to the audio channels from the selected audio track. Navigate by clicking on a point in the audio waveform to jump to that location in the video. By default the audio waveform is overlayed over the video, but can also be opened in a separate window.
![SCR-20260309-uczb](https://github.com/user-attachments/assets/55a05fce-6dd8-4fde-9c66-2b4ef312fd20)


### Metadata
Inspect resolution, frame rate, codec, color space, chroma subsampling, and audio metadata with Command + I. The inspector offers offline loudness analysis and displays Broadcast WAVE recording tags and embedded loudness separately from measured results. It also reads UTF-8/UTF-16/UTF-32 iXML recording labels and optional track names with explicit source-channel and file-interleave indexes. Classic big-endian RIFX supports metadata, waveforms, and offline loudness; playback and trim export show conversion guidance until the decoder supports its sample byte order. See [supported WAVE metadata](docs/WAVE_METADATA.md).
<img width="1227" height="691" alt="SCR-20260309-udpk" src="https://github.com/user-attachments/assets/52a86143-f944-4137-988a-e7a2c585bbaa" />




## Keyboard Shortcuts

### Playback

| Shortcut | Action |
| :--- | :--- |
| Space / P | Play / pause |
| K | Pause |
| J | Reverse playback |
| L | Fast forward |
| Option + J | Slow reverse |
| Option + L | Slow forward |
| F or Control + Command + F | Toggle fullscreen |
| M | Mute / unmute |
| Up Arrow / Down Arrow | Volume up / down 5 |
| Option + Up Arrow / Down Arrow | Volume up / down 1 |
| Control + Up Arrow / Down Arrow | Volume up / down 5 (menu item) |
| [ / ] | Playback rate down / up by 0.5 (outside Compare wipe mode) |

The rate steps by 0.5 and clamps between 0.25x and 8x; there is no reset
shortcut. Inside Compare Mode's wipe the brackets belong to the wipe instead:
`[`/`]` move it 2%, Shift with them 10%.

### Navigation

| Shortcut | Action |
| :--- | :--- |
| Left Arrow / Right Arrow | Seek back / forward 5 seconds |
| Shift + Left Arrow / Right Arrow | Seek back / forward 10 seconds |
| Option + Left Arrow / Right Arrow | Step back / forward one frame |
| Period / Comma | Step one frame forward / back |
| Shift + Up Arrow / Down Arrow | Jump back / forward 10 frames |
| Command + Up Arrow / Down Arrow | Seek to start / end |
| Cmd + [ or Cmd + Left Arrow | Open previous media file in folder |
| Cmd + ] or Cmd + Right Arrow | Open next media file in folder |

Option keeps its arrow handling inside the current window; every other arrow
route is synchronized across windows.

### Trim

| Shortcut | Action |
| :--- | :--- |
| I | Set in point |
| O | Set out point |
| Shift + I | Go to in point |
| Shift + O | Go to out point |
| Option + I | Clear in point |
| Option + O | Clear out point |
| Option + X | Clear all trim points |
| Cmd + E | Export trim |

### Compare Mode

| Shortcut | Action |
| :--- | :--- |
| B | Toggle source A / B |
| [ / ] | Move wipe 2% (while the wipe is showing) |
| Shift + [ / ] | Move wipe 10% (while the wipe is showing) |

### Timecode

| Shortcut | Action |
| :--- | :--- |
| T | Cycle timecode display mode |
| 0–9, +, -, :, ; | Activate timecode input |
| Cmd + Shift + C | Copy timecode |
| Cmd + Shift + V | Paste timecode |

### General

| Shortcut | Action |
| :--- | :--- |
| Cmd + O | Open file |
| Cmd + Shift + O | Open subtitle file |
| Cmd + N | New window |
| Cmd + W | Close window |
| Cmd + S | Save screenshot, or export an annotated still in Compare Mode |
| Cmd + I | Toggle inspector |
| Cmd + Shift + W | Toggle video scopes |
| Cmd + Shift + P | Toggle parade |
| Cmd + Shift + A | Audio waveform |
| Cmd + Shift + D | Open comparison file |
| Cmd + Shift + L | Inspection loupe |
| Cmd + Shift + N | Comparison review notes |
| Cmd + Shift + S | Sync timecode across windows |
| Cmd + Shift + R | Reload player |
