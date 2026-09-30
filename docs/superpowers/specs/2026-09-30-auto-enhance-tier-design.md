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

Tiers are listed heaviest first. A tier is eligible only when its ratio condition
holds and every one of its shader files exists.

| Tier | Shaders | Scaler options | Eligible ratio |
|---|---|---|---|
| `artcnnStrong` | `ArtCNN_C4F32.glsl` | `scale=lanczos` | ≥ 1.9 |
| `artcnnLight` | `ArtCNN_C4F16.glsl` | `scale=lanczos` | ≥ 1.9 |
| `ravuZoom` | `ravu-zoom-ar-r3.hook` | `scale=lanczos` | > 1.0 and < 1.9 |
| `sharpen` | `SSimSuperRes.glsl` | `scale=ewa_lanczossharp`, `scaler-resizes-only=no` | > 1.0 |
| `faithful` | none | `scale=lanczos` | always |

The ArtCNN tiers start at 1.9 because they always emit exactly 2×. Below about
1.9 their overshoot would be downscaled by `dscale`, so `ravuZoom` is used there
instead: it renders at the target size directly. The ArtCNN tiers do not add a
chroma shader, because CfL counts as enhancement and stays a manual choice.

**Ratio** = min(drawable width ÷ source width, drawable height ÷ source height).
The source size is normalised for rotation. Use `MPVPlayer.videoSourceSize` and
the layer's `drawableSize`.

## Components

1. **`RenderTier`** (in `Logic/MPV/RenderProfile.swift`). The ladder above as
   data: its shader file names, its `scaleOptions`, and its ratio predicate.
   `RenderProfile` is kept for the manual path. Tiers and profiles share
   `ShaderLibrary` to resolve paths.
2. **`TierSelector`** (new, pure). Input: `ratio: Double`, `available: Set<RenderTier>`,
   `floor: RenderTier`, `enhance: Bool`. Output: a `RenderTier`. It returns the
   heaviest eligible, available tier that is no heavier than `floor`. It returns
   `faithful` when `enhance` is false or nothing else qualifies. It has no mpv or
   UI dependency.
3. **`GPUBudgetMonitor`** (new, `Logic/MPV/GPUBudgetMonitor.swift`).
   - Inputs: `vo-passes` samples, and the counters `frame-drop-count`,
     `vo-drop-frame-count` and `mistimed-frame-count`.
   - Budget: 0.7 × min(1 / display fps, 1 / source fps).
   - It emits `overBudget` in either of two cases. The first is when the mean
     total pass time over 30 frames exceeds the budget. The second is when the
     combined counters rise by 3 or more within 2 s.
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

1. **Spike (throwaway).** In the app, log `vo-passes` totals at 1080p fullscreen
   under `faithful`, `sharpen` and `artcnnLight`.
   - Pass: the totals are non-zero and rise with shader load.
   - Fail: build the monitor on drop counters only.
   - Record the outcome in this spec.
2. **`TierSelector`.** Table test over ratios {0.5, 1.0, 1.2, 1.57, 1.9, 2.0,
   3.0}, each crossed with all tiers available versus some files missing, and
   with every `floor`.
3. **`GPUBudgetMonitor`.** Test with injected samples in four cases: under budget,
   over budget, a counter spike, and empty `vo-passes`.
4. **Wiring and UI.**
5. **On-device check.**
   - Play 1080p and 720p sources in a window, fullscreen on a 14" display (1.57×),
     and in Compare Mode.
   - Confirm the expected tier and the badge in each case.
   - Force an overload with `artcnnStrong` at 3×. It should step down within
     about 1 s and not oscillate.

## Out of scope

- A per-GPU threshold table.
- Bundling shaders.
- `adaptive-sharpen.glsl`, which is not in the library.
- Automatic CfL or KrigBilateral.
- HDR/EDR colorspace work (`target-colorspace-hint`, `layer.colorspace`), which
  will get a separate spec.
