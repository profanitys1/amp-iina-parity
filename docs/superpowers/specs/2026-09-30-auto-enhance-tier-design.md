# Auto-selected enhancement tier — design

Date: 2026-09-30. Status: approved in brainstorming, pending spec review.

## Goal

Improve playback quality for sources at 1080p and below by engaging a neural or
sharpening shader tier automatically, while keeping the default render path
faithful to the source. Must behave well on any Apple Silicon Mac, from M1 base to
Max, including under thermal throttling.

## Decisions carried in

- The default render path stays faithful (`RenderProfile.off`, shown as
  "Faithful"). Enhancement is opt-in. This landed in `02db529`.
- Shaders come only from the user's library, `~/.config/mpv/shaders`. Nothing is
  copied from elsewhere or bundled.
- The tier is chosen by upscale ratio and by measured GPU headroom, not by a
  hard-coded GPU table.
- A tier may change on resize and when frames drop. A badge names the active tier.
- There is one "Enhance" switch. When it is on, the tier is chosen automatically.
  The manual profiles remain under an Advanced section.

## Tier ladder

Revised 2026-09-30 (commit `2569bc3`): the heaviest tier is FSRCNNX, not ArtCNN C4F32. On gaia.mov, C4F32 matched C4F16's quality at three times the cost; FSRCNNX has the best PSNR-Y and SSIM and fits the 30 fps budget. See `docs/research/2026-09-30-gaia-upscaler-benchmark.md`.

Tiers are listed heaviest first. A tier is eligible only when its ratio condition
holds and every one of its shader files exists.

| Tier | Shaders | Scaler options | Eligible ratio |
|---|---|---|---|
| `fsrcnnx` | `FSRCNNX_x2_16-0-4-1.glsl` | `scale=lanczos` | ≥ 1.9 |
| `artcnnLight` | `ArtCNN_C4F16.glsl` | `scale=lanczos` | ≥ 1.9 |
| `ravuZoom` | `ravu-zoom-ar-r3.hook` | `scale=lanczos` | > 1.0 |
| `sharpen` | `SSimSuperRes.glsl` | `scale=ewa_lanczossharp`, `scaler-resizes-only=no` | > 1.0 |
| `faithful` | none | `scale=lanczos` | always |

The ArtCNN tiers start at 1.9 because they always emit exactly 2×. Below about
1.9 their overshoot would be downscaled by `dscale`. `ravuZoom` renders at the
target size directly, so it is eligible at every upscale ratio: it is the choice
below 1.9, and the step-down when ArtCNN does not fit. The ArtCNN tiers do not add a
chroma shader, because CfL counts as enhancement and stays a manual choice.

**Ratio** = min(drawable width ÷ source width, drawable height ÷ source height).
The source size is normalised for rotation. Use `MPVPlayer.videoSourceSize` and
the layer's `drawableSize`, which `MPVMetalLayer`'s setter reports on every
accepted change. Do not use mpv's `osd-width`/`osd-height`. The MPVKit fork's
`moltenvk` context (patch `0001-player-add-moltenvk-context.patch`) returns
`VO_NOTIMPL` from `control` and resizes only in `reconfig`, so mpv never sees a
`VO_EVENT_RESIZE`.

## Verified facts (2026-09-30)

These were checked against mpv v0.41.0 and libplacebo v7.360.1 source, and by
running `/opt/homebrew/bin/mpv` v0.41.0 / libplacebo v7.360.1 on an Apple M1 Pro
with a 120 Hz display.

- **`vo-passes` format.** Read as a string, `vo-passes` returns JSON:
  `m_option_type_node.print` is `print_node`, which calls `json_write`. The shape
  is `{"fresh":[{"desc","last","avg","peak","count","samples"}],"redraw":[…]}`,
  with every time in nanoseconds.
- **`vo-passes` counts.** Sample counts are kept per libplacebo pass, up to 256
  (`pl_dispatch_info.samples[256]`). After a shader change they restart from 0.
  One run measured an 81 ms compile spike while the smallest per-pass count was
  still 0.
- **Blocking.** Reading `vo-passes` blocks the caller: `vo_control` calls
  `mp_dispatch_run` and waits for the VO thread. Read it off the main thread.
- **Drop counters.** Only `frame-drop-count` applies ("Frames dropped by VO
  (when using `--framedrop=vo`)"). amp now sets `framedrop=vo`.
  `mistimed-frame-count` and `vo-delayed-frame-count` count only in display-sync
  mode, which amp does not use. There is no `vo-drop-frame-count` in 0.41.
- **Failed user shader.** libplacebo logs
  `[vo/gpu-next/libplacebo] Failed executing hook, disabling` at error level
  (`renderer.c:1103`).
- **Measured cost.** 720p source fullscreen at 3448×2164 (≈2.7×), with the total
  of fresh-pass `avg` values and the drop rate once warm:

  | Stack | 24 fps source | 60 fps source |
  |---|---|---|
  | faithful | — | 4.2 ms, 0 drops |
  | `SSimSuperRes` | 10.1 ms, 0 drops | — |
  | `ravu-zoom-ar-r3` | 9.3 ms, 2 drops (start-up only) | — |
  | `ArtCNN_C4F16` | 12.0 ms, 0 drops | — |
  | `ArtCNN_C4F32` | 28.2 ms, ~8 drops/s | 37.7 ms, ~43 drops/s |

  At 24 fps, C4F32 drops frames while using only 68% of the 41.7 ms frame period.
  C4F16 at 29% does not drop. So the budget fraction is **0.5**, not 0.7.

## Components

1. **`RenderTier`** (new, `Logic/MPV/RenderTier.swift`, alongside `TierSelector`). The ladder above as
   data: its shader file names, its `scaleOptions`, and its ratio predicate.
   `RenderProfile` is kept for the manual path. Tiers and profiles share
   `ShaderLibrary` to resolve paths.
2. **`TierSelector`** (new, pure). Input: `ratio: Double`, `available: Set<RenderTier>`,
   `floor: RenderTier`. Output: a `RenderTier`. It returns the heaviest eligible,
   available tier that is no heavier than `floor`, or `faithful` when nothing else
   qualifies. It has no mpv or UI dependency. The Enhance switch is checked by the
   caller.
3. **`GPUBudgetMonitor`** (new, `Logic/MPV/GPUBudgetMonitor.swift`).
   - Inputs, sampled once per second while playing: the `vo-passes` JSON and
     `frame-drop-count`.
   - Budget: 0.5 × 1 / min(source fps, display fps). Fresh frames are needed only
     at the lower of the two rates. Source fps is `container-fps`. Display fps is
     the value amp already passes to `applyDisplayRefreshRate`.
   - Warm-up: timing is judged only once every fresh pass has at least 30 samples.
   - It emits `overBudget` in either of two cases. The first is when the sum of
     fresh-pass `avg` values exceeds the budget. The second is when
     `frame-drop-count` rises by 3 or more within 2 s.
   - When no frame rate is known, only the drop counter judges.
   - It resets when the tier changes.
4. **`MPVPlayer` wiring.**
   - Re-select the tier when the drawable size or source size changes, with a
     300 ms debounce.
   - On `overBudget`, lower `floor` by one tier and re-select. `floor` resets when
     a new file opens.
   - Apply the chosen tier the same way as `setRenderProfile`: clear the shader
     list, append each shader, then set the scaler options.
   - Each player instance owns its own `floor`, so Compare panels are independent.
5. **UI.**
   - Settings gets an "Enhance" toggle. The existing profile picker moves under
     "Advanced".
   - The player gets a small badge naming the active tier. It adds "stepped down"
     when `floor` is below the tier the ratio allows. Its tooltip lists any
     missing shader files. The badge shows only while Enhance is on.
6. **Settings.** Add `AppSettings.enhance` (Bool, default `false`). A stored
   manual profile other than `.off` takes precedence over Enhance.

## Failure handling

- **`vo-passes` is empty or all zero under MoltenVK.** The monitor falls back to
  the drop counters only and logs this once.
- **A shader fails to compile or load.** A libplacebo "user shader" error while a
  tier is active is treated as `overBudget`. That tier is also marked broken for
  the session.
- **A shader file is missing.** The tier is ineligible and the badge tooltip names
  the file. Nothing is copied or bundled.
- **HDR source.** Selection is unchanged. libplacebo disables sigmoid and linear
  scaling for HDR by itself.
- **Oscillation.** It cannot happen, because `floor` only moves down. `faithful` is
  the bottom of the ladder.

## Build order and testing

1. **Swift 6.4 language mode.** The project is set to Swift 6 but did not build
   under Xcode 27 / Swift 6.4. Four isolation fixes make the full suite pass in
   Swift 6 mode: 615 passed, 0 failed, 5 skipped. The deployment target stays
   macOS 15.0. New tests use Swift Testing.
2. **Standalone mpv check (done).** `vo-passes` totals are non-zero and rise with
   shader load; see "Verified facts". The in-app check comes in the last step.
3. **`TierSelector`.** Table test over ratios {0.5, 1.0, 1.2, 1.57, 1.9, 2.0,
   3.0}, each crossed with all tiers available versus some files missing, and
   with every `floor`.
4. **`GPUBudgetMonitor`.** Test with injected samples in four cases: under budget,
   over budget, a counter spike, and empty `vo-passes`.
5. **Wiring and UI.**
6. **On-device check.**
   - Play 1080p and 720p sources in a window, fullscreen, and in Compare Mode.
     On this Mac (M1 Pro, fullscreen drawable 3448×2164), fullscreen 1080p is
     1.80× and fullscreen 720p is 2.69×.
   - Confirm the expected tier and the badge in each case.
   - Force an overload by playing a 720p 60 fps source fullscreen (2.69×), where
     `artcnnStrong` measured 37.7 ms. It should step down within about 3 s (1 s
     sampling plus the 2 s drop window) and not oscillate.

## Out of scope

- A per-GPU threshold table.
- Bundling shaders.
- `adaptive-sharpen.glsl`, which is not in the library.
- Automatic CfL or KrigBilateral.
- HDR/EDR colorspace work (`target-colorspace-hint`, `layer.colorspace`), which
  will get a separate spec.
