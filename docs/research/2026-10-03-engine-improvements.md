# amp engine improvements for WhatsApp-class sources (2026-10-03)

Read-only research. No source files in `/Users/filip/src/amp` were modified by this research.
No frames from `/Users/filip/Downloads/Movies/gaia.mov` were extracted, viewed, or referenced;
that file is not used anywhere in this report.

Repo claims carry `path:line` and were read directly. External claims carry a URL and
`checked 2026-10-03`. Every recommendation is tagged **[V]** verified from code or a primary
source, **[M]** measured on this machine, or **[I]** inference, not tested.

Fixture note: `/Users/filip/Downloads/whatsapp/` contains **11** mp4 files, not 13 **[M]**.

## Summary

Ranked by value for a 640x352 -> 1728x1117 WhatsApp upscale.

1. **`display-fps-override` defeats the vsync detection the MPVKit fork was built to provide.**
   `MPVPlayer.swift:353` and `:1636` set it unconditionally from
   `screen.maximumFramesPerSecond` (`MPVVideoView.swift:364`) — the panel's *maximum*, not its
   current rate. mpv's manual says a detected value is used by default and that an incorrect
   override "can ruin video playback". Fork patch `0004` adds CVDisplayLink feedback
   (`CLAUDE.md:38`); the override replaces it. **[V]**
2. **The GPU budget is computed against the source rate while interpolation makes mpv render at
   the display rate.** `GPUBudgetMonitor.swift:66-67` takes `min(sourceFPS, displayFPS)`; for a
   30 fps clip on 120 Hz that is a 16.7 ms budget against an 8.33 ms real deadline. Automatic
   therefore selects profiles that cannot meet it, then recovers only after visible stutter.
   **[V]**
3. **The cost model scales the whole profile cost by drawable pixels, but a fixed-2x neural
   prescaler's cost does not depend on the window.** `ProfilePicker.swift:71`. At a
   1728x1117 window this under-predicts by roughly 3x. **[V arithmetic, I magnitude]**
4. **The two 1280x720 WhatsApp fixtures classify as `clean` and get no debander at all.**
   `SourceClassifier.swift:106` uses `min(width, height) < 720`, so 720 exactly fails; their
   measured bpp (0.162, 0.134) is far above the 0.07 threshold at `:87`. `clean` selects
   `upscaleLight` = ArtCNN + CfL, and `enablesDeband` is false (`RenderProfile.swift:91`). **[M]**
5. **`.compressedGrain` adds grain at the wrong pipeline stage.** `noise_static_luma.hook` is
   `//!HOOK LUMA`, so grain lands on the 2x plane and is then resampled by the 1.35x lanczos
   pass. `filmgrain-smooth-SDR-light.glsl` hooks `OUTPUT` and is unwired. **[V]**
6. **Nothing anti-rings the residual upscale.** After a 2x neural prescaler, `scale=lanczos`
   still runs 1.35x (640x352 case) with `scale-antiring` at 0. `PixelClipper.glsl` hooks
   `POSTKERNEL` *and* `CHROMA_SCALED` — the only chroma anti-ringing in the library — and is
   unwired. **[V]**
7. **`Debandit.glsl` is the strongest unwired asset for this exact use case.** v3.4, GPL-3.0
   (compatible), hooks `MAIN` — which the manual defines as *before upscaling* — and exposes
   `db_block` for "16px DCT blocking (AVC web-dl)". **[V]**
8. **Two wired shaders contradict the project's own recorded findings**: `.efficient` uses
   `KrigBilateral.glsl` (inventory: "measured worse than CfL on 4:2:0") and `.restore` uses
   `ravu-zoom-ar-r3.hook` (Anime4K RAVU) plus `nlmeans.glsl` (inventory: non-functional on
   macOS). `.efficient` is the first fallback for `compressed` sources. **[V]**
9. **The decode path is already correct.** `hwdec=videotoolbox` zero-copy by default;
   `videotoolbox-copy` is *not* needed for GLSL shaders and is only forced for `vf` filters.
   No wasted GPU->CPU->GPU copies found. **[V]**
10. **The engine work is not in `PlayerController.swift`.** It is in `MPVPlayer.swift`
    (1663 lines). Three named seams below unblock items 1-4. **[V]**

---

## Findings

### 1. Decode path

**What is applied** **[V]**

- `AppSettings.swift:63` — `hardwareDecoder` default `"auto"`.
- `MPVPlayer.swift:228-234` — `hwdecOptionValue(preference:correctsReflection:)`:
  `"no"` -> `no`; `correctsReflection` -> `videotoolbox-copy`; explicit
  `"videotoolbox-copy"` -> copy; **everything else -> `videotoolbox`**. So the default
  resolves to zero-copy VideoToolbox.
- `MPVPlayer.swift:335-338` — set before `mpv_initialize`.
- `MPVPlayer.swift:236-243` — `applyCodecWhitelist()` narrows `hwdec-codecs` using
  `HardwareDecodeCapabilities`, so mpv does not attempt a path that silently falls back.
- `PlaybackSettingsView.swift:82-88` — UI offers Automatic / VideoToolbox /
  VideoToolbox (Copy Back) / Off, with the note "Mirrored files always use copy back."
- `MPVPlayer.swift:344` — `framedrop=vo`, with a correct comment explaining why `decoder`
  is rejected (frames the inspector never shows and never counts).

**Is `videotoolbox-copy` needed for the shader chain? No.** **[V]**

GLSL shaders run inside libplacebo on the GPU surface; they never need CPU-readable pixels.
amp already encodes this correctly: the *only* thing that forces copy-back is a `vf` filter
(reflection correction), because "a filter cannot operate on the opaque surface `videotoolbox`
hands back" (`MPVPlayer.swift:224-227`). The 2026-10-02 review reached the same conclusion
independently (`docs/research/2026-10-02-backend-quality-review.md`, section 3:
"`hwdec=videotoolbox` and `videotoolbox-copy` give the same pixels. The copy variant only costs
bandwidth").

**Cost for low-bitrate H.264 4:2:0.** For the measured corpus (640x352 / 320x640 / 1280x720,
all H.264 Baseline or High, `yuv420p`, 0.76-3.73 Mbit/s) **[M]**, hardware decode is trivially
within the media engine's capability. **No measurable waste found in the decode path** — there
is no extra GPU->CPU->GPU copy for WhatsApp-class sources. **[V]**

**One real defect: `hwdec-extra-frames=4` is a no-op on macOS.** **[V]**

`MPVPlayer.swift:350` sets it with the comment "The hwdec surface pool is sized when the decoder
opens, and mpv's manual says interpolation 'may require' extra frames."

mpv's manual, verbatim (`DOCS/man/options.rst:1575-1581`,
https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst, checked 2026-10-03):

> `--hwdec-extra-frames=<auto|N>`
> Number of extra GPU frames hardware decoding should preallocate, on top of what the codec
> itself requires (default: `auto`).
> This value is used only for hardware decoding APIs which require preallocating surfaces
> (known examples include `d3d11va` and `vaapi`). For other APIs, frames are allocated as needed.

VideoToolbox is not `d3d11va` or `vaapi`. The option does nothing here, and the comment gives
false confidence that the interpolation pool is sized. Fix the comment, not the value; removing
the line is also safe.

---

### 2. Rendering / libplacebo

**What is set** **[V]**

| Option | Value | Location |
|---|---|---|
| `vo` | `gpu-next` | `MPVPlayer.swift:332` |
| `gpu-api` | `vulkan` | `:333` |
| `gpu-context` | `moltenvk` | `:334` |
| `framedrop` | `vo` | `:344` |
| `hwdec-extra-frames` | `4` (no-op, see §1) | `:350` |
| `tscale` | `oversample` | `:351` |
| `display-fps-override` | `maximumFramesPerSecond` | `:353`, `:1636` |
| `screen-name` | `CGDirectDisplayID` | `:356`, `:1640` |
| `target-colorspace-hint` | `yes` | `:362` |
| `dscale` | `mitchell` | `:1301` |
| `cscale` | `spline36` | `:1302` |
| `scale` | `lanczos`, or `ewa_lanczossharp` for `.sharpen` | `RenderProfile.swift:104-105` |
| `scaler-resizes-only` | `yes`, or `no` for `.sharpen` | `RenderProfile.swift:104-105` |
| `deband` | `yes` only for `.restore` | `RenderProfile.swift:91`, `MPVPlayer.swift:1323` |

**Deliberately left at default** (documented at `MPVPlayer.swift:1275-1283`): `sigmoid-upscaling`,
`linear-downscaling`, `correct-downscaling`, `dither-depth`, `dither`, `temporal-dither`,
`scale-antiring`. The recorded reasoning is sound and was confirmed against the manual — in
particular the warning that mpv computes `disable_linear_scaling = !linear_downscaling &&
!linear_upscaling` with `linear-upscaling` defaulting to `no`, so turning `linear-downscaling`
off silently disables sigmoid upscaling too. **Do not touch these.** **[V]**

**What the chain actually does at 640x352 -> 1728x1117** **[V]**

Taking `.compressed` (`hdeband.glsl`, `ArtCNN_C4F16_DS.glsl`, `CfL_Prediction.glsl`,
`RenderProfile.swift:76-77`):

| Stage | Size | Driver |
|---|---|---|
| Source luma | 640x352 | — |
| `LUMA` hooks | hdeband at source res; ArtCNN_C4F16_DS emits **1280x704** (`//!WIDTH LUMA.w 2.0 *`, `//!HEIGHT LUMA.h 2.0 *`, lines 28-29), gate `OUTPUT.w LUMA.w / 1.3 >` fires at 2.70 | `ArtCNN_C4F16_DS.glsl:25-31` |
| `CHROMA` hooks | hdeband; CfL_Prediction reconstructs chroma at **luma size 640x352** (`//!WIDTH LUMA.w //!HEIGHT LUMA.h`, lines 114-115), gate `CHROMA.w < LUMA.w` fires for 4:2:0 | `CfL_Prediction.glsl:109-115` |
| `MAIN` | pre-upscale RGB | *(nothing wired here)* |
| `scale` | **1280x704 -> 1728x1117, a 1.35x residual upscale with `lanczos`, `scale-antiring=0`** | `RenderProfile.swift:105` |
| `cscale` | 640x352 -> 1728x1117, a 2.70x chroma upscale with `spline36` | `MPVPlayer.swift:1302` |

**This contradicts a code comment.** `RenderProfile.swift:~1095` states "Neural prescalers emit
at or above target size, so `scale` barely runs for them." That is true for the 1080p worked
example in the same comment (1080p -> fullscreen is 1.57x, a 2x prescaler overshoots, so
`dscale` decides). **It is false for the owner's primary use case**: a 640x352 source at 2x
emits 1280x704, still 1.35x short of 1728x1117, so `scale` runs on every frame and is the
pass that decides final sharpness. **[V]**

`scaler-resizes-only=yes` is *not* a problem here. Manual verbatim
(`options.rst:6131-6135`): "Disable the scaler if the video image is not resized. In that case,
`bilinear` is used instead of whatever is set with `--scale`. ... Enabled by default. Note that
this option never affects `--cscale`." A resize always happens in this case, so the option is
inert. `.sharpen` correctly sets it to `no` because SSimSuperRes is a `POSTKERNEL` supplement
that must run even at 1:1 (`RenderProfile.swift:104`). **[V]**

**Do `zimg` or `d3d11va`-style options matter on macOS? No.** **[V reasoning, not tested]**
`zimg` is a backend for the CPU `vf_scale` filter, not a libplacebo scaler name. Inserting any
`vf` forces software frames and destroys zero-copy `videotoolbox` — amp's own comment at
`MPVPlayer.swift:224-227` records that a filter cannot read the opaque surface. `d3d11va` is
Windows-only. Neither has a macOS/gpu-next meaning.

**libplacebo version gating: nothing recommended here is gated.** The fork already builds
libplacebo master at API 7.374 and mpv master `3186d369f9` (`CLAUDE.md:38`). The `MAIN` and
`CHROMA_SCALED` hooks are documented in mpv master's manual (`options.rst:6812`, `:6830`) and
are long-standing. **[V]**

**What would measurably help** **[I]**: anti-ringing on the residual upscale (§3c) and a
sharpening-biased scaler. `ewa_lanczossharp` is already wired for `.sharpen`
(`RenderProfile.swift:104`), so applying it to the residual pass of the neural profiles is a
one-line experiment — but note the 2026-10-02 review's item 4 proposed exactly this A/B and it
was never run.

---

### 3. The enhancement shader chain

**Wiring lives in exactly one place.** A grep for shader filenames across all non-test Swift
sources returns hits only in `RenderProfile.swift:62-89` (`shaderFileNames`). **[V]**

| Profile | Shaders, in load order | Line |
|---|---|---|
| `.off` (Faithful) | — | `:64-65` |
| `.chroma` | CfL_Prediction | `:67` |
| `.efficient` | FSRCNNX_x2_8-0-4-1, **KrigBilateral** | `:69` |
| `.sharpen` | SSimSuperRes | `:71` |
| `.upscaleLight` | ArtCNN_C4F16, CfL_Prediction | `:73` |
| `.compressed` | **hdeband**, ArtCNN_C4F16_DS, CfL_Prediction | `:76-77` |
| `.crisp` | ArtCNN_C4F16_DS, CfL_Prediction, adaptive-sharpen | `:79` |
| `.upscaleStrong` | **ArtCNN_C4F32**, CfL_Prediction | `:81` |
| `.compressedGrain` | hdeband, ArtCNN_C4F16_DS, CfL_Prediction, **noise_static_luma.hook** | `:83` |
| `.restore` | **nlmeans**, **ravu-zoom-ar-r3.hook**, CfL_Prediction, noise_static_luma.hook | `:85` |

Library: 27 files in `~/.config/mpv/shaders/`. **11 wired, 16 unwired.** Unwired and relevant:
`Debandit.glsl`, `PixelClipper.glsl`, `TextureClarity.glsl`, `CAS-scaled.glsl`,
`filmgrain-smooth-SDR-light.glsl`, `CfL_Prediction_Lite.glsl`, `SSimDownscaler.glsl`,
`ArtCNN_C4F16_DN`, `ArtCNN_C4F32_DS`, `FSRCNNX_x2_16-0-4-1`, `noise_static_chroma.hook`. **[M]**

**Authoritative hook-stage order** — mpv manual, verbatim
(`options.rst:6800-6856`, checked 2026-10-03). "Whenever a texture is rendered and saved by
vo_gpu, all of the passes that have hooked into it will run, **in the order they were added by
the user**."

| Hook | Manual definition |
|---|---|
| `RGB`, `LUMA`, `CHROMA`, `ALPHA`, `XYZ` | "Source planes (raw)" |
| `CHROMA_SCALED`, `ALPHA_SCALED` | "Source planes (upscaled). These only fire on subsampled content." |
| `NATIVE` | combined image, source colorspace, before RGB conversion |
| `MAIN` | "The main image, **after conversion to RGB but before upscaling**." |
| `LINEAR`, `SIGMOID` | before scaling |
| `PREKERNEL` -> scaler -> `POSTKERNEL` -> `SCALED` | around the scaler kernel |
| `OUTPUT` | "final output image, after color management but before dithering and drawing to screen" |

The `MAIN` definition matters: it is **pre-upscale**, not post-scale. That is what makes
`Debandit` a like-for-like competitor to `hdeband` rather than a downstream cleanup pass.

**(a) hdeband placement is correct. Leave it.** **[V]**

`hdeband.glsl:19-23` states in its own header: "This should run prior to any other shaders and
mpv's built in debanding should be disabled by setting `deband=no` in mpv.conf". amp puts it
first (`RenderProfile.swift:76`, `:83`) and keeps `enablesDeband` false for those profiles
(`:91`, comment at `:74-75`). Debanding before the 2x neural pass is right: the artifact lives
in the 8-bit source, so cleaning it at 640x352 prevents the network from learning to amplify it.

**(b) `.compressedGrain` puts grain at the wrong stage.** **[V placement, I consequence]**

`noise_static_luma.hook:1-2` is `//!HOOK LUMA` / `//!BIND HOOKED`, with no `WIDTH`/`HEIGHT`, so it
runs at the `LUMA` stage and inherits the hooked texture's size. ArtCNN_C4F16_DS's final pass
overwrites `LUMA` with a 2x texture, and hooks run in add order — so grain is applied to the
**1280x704** plane and then resampled by `scale=lanczos` at 1.35x to reach 1728x1117.
Low-pass filtering grain destroys the per-pixel character that makes it mask blocking, which is
the profile's entire stated purpose ("hides leftover blocking and the smooth 'plastic' look",
`RenderProfile.swift:56`).

`filmgrain-smooth-SDR-light.glsl:4-5` hooks **`OUTPUT`** — after scaling, 1:1 with display
pixels, never resampled. Swapping it in at `RenderProfile.swift:83` is a one-line change.

**(c) Nothing anti-rings the residual upscale or the chroma upscale.** **[V]**

`scale-antiring` stays 0, justified at `MPVPlayer.swift:1271-1274` — but that justification is
written for lanczos at 1:1 ("Antiringing only removes overshoot a sharp filter introduced, so it
has nothing to correct on top of lanczos"). It does not address a 1.35x residual upscale of a
neural prescaler's output, which is exactly where overshoot appears.

`PixelClipper.glsl` is purpose-built for this and unwired:
- `:23-27` — `//!HOOK POSTKERNEL`, `//!BIND POSTKERNEL`, `//!BIND PREKERNEL`,
  `//!WHEN POSTKERNEL.w PREKERNEL.w / 1.000 > POSTKERNEL.h PREKERNEL.h / 1.000 > *` — fires on
  **any** upscale, clipping overshoot to the local envelope.
- `:92-96` — `//!HOOK CHROMA_SCALED`, `//!BIND CHROMA`, `//!BIND CHROMA_SCALED`, same gate. This is
  **the only chroma anti-ringing pass in the library**, and the 2.70x chroma upscale
  (`cscale=spline36`) is precisely where 4:2:0 colour bleeding shows.
- `:161-164` — a third pass for downscaling AR.

Because PixelClipper *clips* rather than *adds*, it constrains detail instead of fabricating it —
which keeps it compatible with the fidelity constraint that governs this project.

**(d) `Debandit.glsl` is the highest-value unwired shader for this use case.** **[V facts, I benefit]**

- `:1-2` — "Debandit v3.4 — Detect-and-Reconstruct Deband, plane-fit estimator /
  Copyright (C) 2026 Agust Ari · **GPL-3.0**" → license-compatible with amp's GPL-3.0.
- `:403-407` — `//!HOOK MAIN`, `//!BIND HOOKED`, `//!SAVE DB2_DS`, `//!WIDTH HOOKED.w 4 /`,
  `//!HEIGHT HOOKED.h 4 /` → runs **pre-upscale in RGB**, building a quarter-resolution pyramid.
  136 structural directives total; further `MAIN` hooks at `:428`, `:455`, `:551`, `:602`.
- `:310-311` — `db_block`: "Grid-deblock evidence weight (AVC web-dl). 1 = absorb **16px DCT
  blocking** (shipped), 0 = bit-exact v2.1". Because `MAIN` is pre-upscale, the source's 8/16px
  H.264 block grid is still in source pixels, so this parameter is correctly tuned for WhatsApp
  H.264.
- `:254-255` — `db_thr`: "Banding step-size ceiling in 8-bit codes ... 1.5 protects faint soft
  structure; **2 = typical web**, 4 = brutal encodes."
- `:268-269` — `db_chroma`: independent chroma-opponent path, "fixes chroma banding even where
  steep luma shading shuts the luma gates" — directly relevant to 4:2:0.
- `:10-20` — a weighted least-squares plane fit replaces the Gaussian chains, which the author
  says tracks curved shading (faces, glows) that the previous estimator misread by ~1.7 codes.

hdeband is a homogeneous-region blur; Debandit is a ramp estimator. For skin tones and skies —
the two things WhatsApp compression ruins most visibly — a plane fit should preserve curvature
that region-blurring flattens. **This is inference; it needs the A/B in the table below.**
Also note its cost is unmeasured, so it cannot enter `ProfilePicker.costs` until it is.

**(e) Two wired shaders contradict the project's own recorded findings.** **[V]**

The project memory `amp-shader-library-inventory` records: `KrigBilateral.glsl`
"measured worse than CfL on 4:2:0", and `nlmeans.glsl` author-flagged "non-functional with NLM"
on macOS.

- `.efficient` wires `KrigBilateral.glsl` (`RenderProfile.swift:69`) — and `.efficient` is the
  **first fallback** for `compressed` sources (`ProfilePicker.swift:46`). So when `.compressed`
  is rejected for budget, WhatsApp content silently drops to a chroma method already measured as
  worse than `CfL_Prediction`, while `CfL_Prediction_Lite.glsl` sits unwired in the same
  directory.
- `.restore` wires `nlmeans.glsl` **and** `ravu-zoom-ar-r3.hook` (`RenderProfile.swift:85`).
  RAVU-Zoom-AR is Anime4K. This collides with the standing decision that anime-style enhancement
  is inappropriate for realistic video, and `.restore`'s UI copy is "Denoise, upscale and regrain
  **rough standard-definition sources**" (`:57`) — i.e. it is offered for exactly the WhatsApp
  case while using a model rejected for it. `.restore` is in no chain (`ProfilePicker.swift` doc
  comment), so it is manual-only, but it is visible in the picker UI.

**(f) Minor: CfL's gate compares width only.** **[V source, I consequence]**
`CfL_Prediction.glsl:40`, `:78`, `:113` all use `//!WHEN CHROMA.w LUMA.w <`. 4:4:0
(`chroma.w == luma.w`, `chroma.h == luma.h/2`) would not fire. Rare enough to ignore unless a
4:4:0 fixture appears.

**(g) Unverified: `ArtCNN_C4F32` declares an asymmetric output.** **[M local files, provenance unverified]**
Both `ArtCNN_C4F32.glsl:28-29` and `ArtCNN_C4F32_DS.glsl:28-29` declare
`//!WIDTH LUMA.w 4.0 *` with `//!HEIGHT LUMA.h 2.0 *`, and `//!COMPUTE 48 32 12 16` against
C4F16's `24 32 12 16`. Confirmed by two independent byte-exact reads. libplacebo still scales
the intermediate to `OUTPUT`, so the final image is not stretched — but the network's kernel runs
on an anisotropically sampled grid and the extra horizontal detail is then discarded by a
downscale. `.upscaleStrong` (`RenderProfile.swift:81`) is the only consumer and is in no chain,
so this is manual-only. A GitHub code search for the filename returned no results, so it could
not be established whether `4.0` is the upstream model's intent or a local conversion artifact.
**Worth five minutes of the owner's time; not worth a refactor.**

---

### 4. Frame sync / interpolation

**What shipped** **[V]**

- `RenderProfile.swift:116-120` — `playbackSyncOptions`: `.off` -> `video-sync=audio`,
  `interpolation=no`; **every other profile, Automatic included** -> `video-sync=display-resample`,
  `interpolation=yes`.
- Applied at init (`MPVPlayer.swift:1327-1329`) and re-applied on every profile switch
  (`:1341-1343`).
- `tscale=oversample` pinned at init (`:351`).
- This satisfies the manual's hard requirement (`options.rst:6181-6182`, verbatim):
  "This requires setting the `--video-sync` option to one of the `display-` modes, or it will be
  **silently disabled**."
- Fork patch `0004` supplies CVDisplayLink vsync feedback to the `moltenvk` context, with the
  display chosen through `screen-name` = `CGDirectDisplayID` (`CLAUDE.md:38`).
- `MPVVideoView.swift:361-366` — `applyDisplayRefreshRate()` reads
  `screen.deviceDescription["NSScreenNumber"]` and `screen.maximumFramesPerSecond`, then calls
  `player.applyDisplay(...)`; re-invoked on screen-parameter and fullscreen notifications
  (`:282`, `:288`, `:294`, `:296`).
- `MPVPlayer.swift:1633-1641` — `applyDisplay` sets `display-fps-override` (`:1636`) and
  `screen-name` (`:1640`) at runtime.
- No `CVDisplayLink`, `CAMetalDisplayLink`, `preferredFrameRateRange`, `displaySyncEnabled` or
  `presentsWithTransaction` anywhere in `MPVVideoView.swift` — amp relies entirely on the fork
  patch for timing. **[V grep]**

**Gap 1 (highest risk): the override defeats the detection.** **[V]**

`MPVVideoView.swift:364` passes `Double(screen.maximumFramesPerSecond)`. On a ProMotion MacBook
Pro that is **120**, which is the panel's *maximum*, not its current rate; macOS drops ProMotion
below 120 Hz for static content, on battery, and under Low Power Mode.

mpv manual, verbatim (`options.rst:1316-1324`, checked 2026-10-03):

> `--display-fps-override=<fps>`
> Set the display FPS used with the `--video-sync=display-*` modes. **By default, a detected
> value is used.** Keep in mind that setting an incorrect value (even if slightly incorrect)
> **can ruin video playback**. On multi-monitor systems, there is a chance that the detected
> value is from the wrong monitor.
> **Set this option only if you have reason to believe the automatically determined value is
> wrong.**

The comment justifying amp's use (`MPVVideoView.swift:359-360` — "mpv has no way to query this on
macOS and otherwise assumes 60 Hz") was true for the stock MPVKit build and is **now stale**:
patch `0004` exists precisely to give mpv that query. Meanwhile `screen-name` is still fed the
`CGDirectDisplayID` (`MPVVideoView.swift:363` -> `MPVPlayer.swift:1640`), which `CLAUDE.md:38`
says is how patch `0004` selects the display — so the detection path is fully wired and then
overridden by the line immediately above it.

This is not a hypothetical: the 2026-10-02 review recorded ~20 dropped frames in 40 s under
`display-resample` at only 7.0-16.2 ms GPU load, attributed to the missing vsync hook, and the
decision was "reverted, amp stays on `video-sync=audio`. Revisit after porting a
vsync/CVDisplayLink hook" (`docs/research/2026-10-02-backend-quality-review.md`, final section).
The precondition has been met and the decision reversed (`fbebae6`), but the override that
neutralises it was left in place. **[V]**

Recommendation: stop setting `display-fps-override` for the `display-*` profiles; keep
`screen-name`. If a fallback is wanted, set the override only when the fork reports no vsync.

**Gap 2: the GPU budget ignores the interpolation cadence.** **[V]**

`GPUBudgetMonitor.swift:65-67`:
```swift
init(sourceFPS: Double, displayFPS: Double) {
    let slowest = [sourceFPS, displayFPS].filter { $0.isFinite && $0 > 0 }.min()
    budgetMilliseconds = slowest.map { Self.budgetFraction * 1000 / $0 }
}
```
with `budgetFraction = 0.5` (`:56`). Called as
`GPUBudgetMonitor(sourceFPS: getDouble("container-fps"), displayFPS: displayRefreshRate)`
(`MPVPlayer.swift:1478-1480`), where `displayRefreshRate` is 120.

For a 30 fps WhatsApp clip: `min(30, 120) = 30` -> budget **16.7 ms**. But with
`interpolation=yes` + `display-resample`, mpv presents at the display rate, so the real deadline
is **8.33 ms** — and the monitor's own 0.5 fraction would put a conservative budget at
**4.17 ms**. The budget is 2-4x too generous.

The comment at `GPUBudgetMonitor.swift:~50-55` explains the 0.5 ("at 24 fps, ArtCNN C4F32 dropped
frames while using 68% of the period, and C4F16 at 29% did not") — reasoning that predates
interpolation, where "fresh frames are needed only at that rate" is no longer true.

Consequence: Automatic keeps `.compressed` (16.1 ms at 720p in the cost table,
`ProfilePicker.swift:29-37`) in a regime where it cannot meet the deadline. It *does* self-correct
— `evaluate` returns `.overBudget` on >=3 drops within 2 s (`:58-59`, `:73-75`), and
`AutomaticSelection.stepDown()` then rejects the active profile — but only after visible stutter,
and it steps a whole tier at a time.

Note also that the two budget fractions disagree: `ProfilePicker.budgetFraction = 0.8`
(`ProfilePicker.swift:20`) for prediction vs `GPUBudgetMonitor.budgetFraction = 0.5` (`:56`) for
measurement. The 0.5 has a recorded justification; the 0.8 has none.

**Gap 3: the cost table predates interpolation.** **[V]**
`ProfilePicker.costs` (`:29-37`) is documented as "GPU milliseconds per frame measured in amp.app
fullscreen (3448x1940 drawable) on an M1 Pro with 720p and 1080p sources". Commit `fbebae6`
(2026-10-03 00:21) enabled interpolation after those measurements. Frame blending at 120 Hz
output adds work the table does not include. The table needs re-measuring. **[I magnitude]**

**Gap 4: `estimatedMilliseconds` applies the drawable factor to the whole cost.** **[V]**
`ProfilePicker.swift:71` — `return base * drawablePixels / referenceDrawablePixels`, with
`referenceDrawablePixels = 3448.0 * 1940.0 = 6,689,120` (`:25`).

A fixed-multiplier neural prescaler's cost is a function of *source* pixels only: ArtCNN emits
`LUMA.w*2 x LUMA.h*2` regardless of `OUTPUT` size (`ArtCNN_C4F16_DS.glsl:28-29`). Only the final
`scale` pass and any `POSTKERNEL`/`OUTPUT` shader depend on the drawable.

At the owner's stated 1728x1117 window: `1,930,176 / 6,689,120 = 0.2886`. For a 640x352 source,
`.compressed` is predicted as `16.1 x (225,280 / 921,600) x 0.2886 = ` **1.14 ms**, while the
neural passes alone still cost most of the 720p figure. Under-prediction biases `pick()` toward
heavier profiles than the budget allows. **[V arithmetic; the "most of" is inference from
memory-recorded per-shader costs, not a fresh measurement]**

**Gap 5: Faithful's exemption is keyed to the selected profile, not the applied one.** **[V]**
`MPVPlayer.swift:1339-1343` documents this deliberately: "Automatic may apply Faithful's shader
stack (HDR), but only an explicit Faithful choice means inspection." So under Automatic an HDR
source gets `.off`'s shaders (`ProfilePicker.swift:42-43` -> `[.off]`) but still
`display-resample` + `interpolation=yes`. Defensible — but it means **HDR under Automatic is not
a faithful-inspection mode**. If the owner inspects HDR, he must select Faithful explicitly.

**Gap 6: the design doc's verification gates are unrecorded.** **[V]**
`docs/superpowers/specs/2026-10-03-mpvkit-fork-rebuild-design.md` specifies: "Smoothness: 24, 25,
30 and 60 fps clips, fullscreen, 40 s each, on Chroma and Compressed movie profiles. Pass: drop
counter does not rise after warm-up (today: about 20 per 40 s)" and "GPU cost: per-profile
ms/frame does not regress more than 10 % against the 2026-10-02 table."

Commit sequence: `fbebae6` (interpolation) 00:21, `4e619e8` (fork pin with vsync) 00:31,
`8fd237f` 00:38, `fbc3abd` (immutable `.2` release, current `Package.resolved` revision
`2a455c8f3f6cd918ca0b5ceb702f496e4a5494f0`) 00:39. `docs/research/` contains **no file dated
2026-10-03** and the 2026-10-02 doc still records the *reverted* result. **[V — absence of a
record, not proof the gate was not run]**

The fixture set makes this cheaply testable: **`P5.mp4` is 24.917 fps (`299/12`)** — on a 120 Hz
panel that is 4.816 refreshes per frame, exactly the case `display-resample` cannot fix by speed
nudging and `interpolation` must. It is the single best smoothness fixture available.

---

### 5. Architecture debt that blocks the above

**Redirect: the engine work is not in `PlayerController.swift`.** **[V]**

`PlayerController.swift` is 1715 lines with MARK sections at `:39` Published State, `:158` State,
`:170` Playback Backend State, `:209` Scope Frame Capture, `:213` Initialization, `:240` Media
Item Management, `:382` Playback Preparation, `:815` Unified Playback Control, `:1370` Audio
Track Selection, `:1448` Audio Channel Monitoring, `:1516` Subtitle Track Selection, `:1537`
Chapter Selection, `:1555` Trim Points, `:1577` Screenshot, `:1605` Trim Export, `:1624` Teardown.

Grepping it for render/profile/shader/scale/budget/sync/hwdec/display symbols returns **only**
surface-reload and AVPlayer-synchronisation hits: `:198` `surfaceReloadResumeTask`, `:202`
`resumeAfterReload`, `:427` `reloadPreservingPlaybackState()`, `:823` `syncIsPlaying()`, `:902`
`playForSynchronization(atRate:)`, `:915`/`:920` synchronization-rate helpers, `:1292` a `CMTime`
tolerance, `:1372`/`:1408`/`:1539` track refresh. **None of questions 1-4 requires touching this
file.** Splitting it would be refactor for its own sake.

The concentration is **`MPVPlayer.swift`** — 1663 lines, MARK sections at `:200` Metal Layer
Binding, `:441` Playback Control, `:634` Audio Tracks, `:780` Subtitle Tracks, `:862` Chapters,
`:876` Event Handling, `:1095` Screenshot, `:1230` MPV Commands & Properties, `:1232` Render
Profile, `:1385` Automatic Profile. Three seams, ordered by what they unblock:

**Seam 1 — extract the startup option list into a pure builder. Cost S. Unblocks Q1, Q2, Q4.**
`setupMPV()` (`MPVPlayer.swift:299-440`) sets ~25 options inline through
`mpv_set_option_string(mpv, name, value), context: name`. Extract the *values* into a
`nonisolated` `MPVStartupOptions` returning `[(name: String, value: String)]`, leaving `setupMPV`
to iterate and call `checkError`. Every option question in this report — dropping
`display-fps-override`, correcting `hwdec-extra-frames`, changing scaler defaults — then becomes a
**string assertion with no mpv handle**, matching the pattern `AutomaticSelection` and
`ProfilePicker` already use successfully. This is the highest-leverage extraction in the codebase.

**Seam 2 — extract the Render Profile section (`:1232-1384`) into a `RenderProfileApplier`.
Cost S/M. Unblocks Q3.**
Members: `applyScalerOptions()` (`:1300`), `applyRenderProfileOption()` (`:1307`),
`setRenderProfile(_:)` (`:1333`), `apply(profile:)` (`:1361`),
`applyShaderStack(paths:scaleOptions:deband:)` (`:1374`). The whole surface needs only three mpv
verbs — `setString`, `setFlag`, and `command("change-list", args:)` — so a 3-method protocol makes
shader switching testable, including the `clr`-then-`append` sequence at `:1375-1377` that guards
against a `:` in a shader path. Without this, every chain reorder in §3 is verified by eyeballing
a fullscreen video.

**Seam 3 — unify the budget definition. Cost M. Unblocks Q4 gaps 2 and 3 together.**
The Automatic Profile section (`:1385-1480`: `startAnalysis` `:1424`, `finishAnalysis` `:1435`,
`applyAutomatic` `:1446`, `drawableSizeDidChange` `:1453`, `scheduleAutomaticReselection` `:1460`,
`reselectAutomatic` `:1470`, `refreshBudgetMonitor` `:1478`) should stay where it is.
`AutomaticSelection` is *already* pure and mpv-free — its doc comment says so: "It touches no mpv
state, so the player only applies the profile it returns."

The actual gap is that `GPUBudgetMonitor`'s budget derivation is pure but its **inputs** are not,
and `ProfilePicker`'s prediction and the monitor's measurement answer the same question with two
different formulas and two different `budgetFraction`s. Extract one
`RenderBudget(sourceFPS:displayFPS:interpolating:drawablePixels:) -> deadline` beside
`ProfilePicker`, and have both the picker and the monitor consume it. Then gaps 2 and 3 are one
change with one unit test.

**Do not extract:** Event Handling (`:876-1094`), Screenshot (`:1095-1229`), Audio/Subtitle
Tracks and Chapters (`:634-875`). Unrelated to questions 1-4.

---

### 6. What is already solved or decided

**Already implemented — do not re-propose:**
- `video-sync=display-resample` + `interpolation=yes` + `tscale=oversample` for non-Faithful
  profiles: 2026-10-02 review items 1-2, now shipped (`RenderProfile.swift:116-120`).
- CVDisplayLink `get_vsync` in the `moltenvk` context: review item 6, now shipped as fork patch
  `0004` (`CLAUDE.md:38`).
- libplacebo master for the 2026 HDR rewrite: review item 7, now pinned (API 7.374).
- `hwdec=videotoolbox` zero-copy: review item "keep zero-copy", already the default
  (`MPVPlayer.swift:228-234`).
- Automatic profile picking with calibrated thresholds: `specs/2026-10-02-automatic-profile-picker-design.md`
  and `plans/2026-10-02-automatic-profile-picker.md`, shipped and calibrated over 79 local files
  (`SourceClassifier.swift:85-87`).
- Faithful/inspection default: decided 2026-09-30, still honoured (`RenderProfile.swift:117-118`).
- `.compressed` is the **validated** pick for WhatsApp: `SourceClassifier.swift:104-105` cites
  `docs/research/2026-10-02-compressed-quality-benchmark.md` — "the 2026-10-02 benchmark scored
  the Compressed movie stack best on exactly such 360p phone-grade encodes". Improve its chain;
  do not replace it.

**Explicitly rejected upstream of this report — agreed, nothing to add:**
- Native Metal libplacebo backend (`#380`, no maintainer review), MetalFX, MLX, Core ML,
  `VTFrameProcessor` super-resolution and temporal noise: surveyed with evidence in
  `docs/research/2026-10-02-backend-quality-review.md` §1 and §7.
- `temporal-dither=yes`: rejected at `MPVPlayer.swift:1281-1283` because libplacebo's header notes
  it "commonly flickers on LCDs", and a crawling still frame is fatal in an inspection tool.
- Turning off `linear-downscaling`: rejected at `MPVPlayer.swift:1275-1279` because it silently
  disables sigmoid upscaling.

**Still open from the 2026-10-02 review** (the design doc defers these as "a separate cheap
sub-project"): item 3 (mild built-in deband on profiles without hdeband), item 4 (A/B
`ewa_lanczossharp` for viewing profiles), item 5 (verify `CAMetalLayer.colorspace` survives
MoltenVK's own writes across resize and fullscreen). §3c partially overlaps item 4, which was
never A/B'd.

**Where these findings collide with existing docs:**

| Collision | Detail |
|---|---|
| **`RenderProfile.swift:~1095` comment vs reality** | "Neural prescalers emit at or above target size, so `scale` barely runs for them" is false for 640x352 -> 1728x1117, where a 1.35x residual `lanczos` pass decides final sharpness (§2). |
| **`MPVVideoView.swift:359-360` comment vs fork patch `0004`** | "mpv has no way to query this on macOS" was true for stock MPVKit and is now stale; the override built on that premise defeats the new detection (§4 Gap 1). |
| **`docs/research/2026-10-02-backend-quality-review.md` final section vs shipped code** | Records "Decision: reverted, amp stays on `video-sync=audio`". False since `fbebae6`. Anyone reading it today gets the wrong current state. |
| **`.restore`'s shader list vs the standing no-anime decision** | `ravu-zoom-ar-r3.hook` is Anime4K RAVU, wired into the profile whose UI copy targets "rough standard-definition sources" (§3e). |
| **`.efficient` / `.restore` vs the project's own shader inventory** | `KrigBilateral.glsl` (recorded "measured worse than CfL on 4:2:0") is the first fallback for `compressed`; `nlmeans.glsl` (recorded non-functional on macOS) is in `.restore` (§3e). |
| **`MPVPlayer.swift:350` comment vs the mpv manual** | The pool-sizing rationale applies to `d3d11va`/`vaapi`, not VideoToolbox (§1). |
| **Two disagreeing `budgetFraction`s** | 0.8 in `ProfilePicker.swift:20`, 0.5 in `GPUBudgetMonitor.swift:56`; only the latter is justified (§4 Gap 2). |

---

## Measured fixture data

All 11 files in `/Users/filip/Downloads/whatsapp/`, via `ffprobe` **[M]**.
`bpp = video_bitrate / (width x height x fps)`.

| File | Profile | Size | pix_fmt | fps | Mbit/s | bpp | Classified by |
|---|---|---|---|---|---|---|---|
| P1.mp4 | Baseline | 640x352 | yuv420p | 30 | 1.51 | 0.224 | short side <720 |
| P2.mp4 | Baseline | 320x640 | yuv420p | 16.67 | 2.11 | 0.620 | short side <720 |
| P3.mp4 | Baseline | 640x352 | yuv420p | 30 | 0.76 | 0.112 | short side <720 |
| P4.mp4 | Baseline | 320x640 | yuv420p | 30 | 1.80 | 0.293 | short side <720 |
| **P5.mp4** | **High** | **1280x720** | yuv420p | **24.917** | 3.73 | **0.162** | **frame stats, else `clean`** |
| **Patricia114747.mp4** | **High** | **1280x720** | yuv420p | 30 | 3.70 | **0.134** | **frame stats, else `clean`** |
| Patty2.mp4 | Baseline | 640x352 | yuv420p | 30 | 1.17 | 0.174 | short side <720 |
| Patty4.mp4 | Baseline | 640x352 | yuv420p | 30 | 1.52 | 0.226 | short side <720 |
| Patty5.mp4 | Baseline | 640x352 | yuv420p | 30 | 1.72 | 0.255 | short side <720 |
| Patty6.mp4 | Baseline | 640x352 | yuv420p | 30 | 1.76 | 0.261 | short side <720 |
| Patty7.mp4 | Baseline | 640x352 | yuv420p | 30 | 1.88 | 0.278 | short side <720 |

**The `lowBitsPerPixel = 0.07` rule never fires on any fixture.** The minimum measured bpp is
0.112 (P3.mp4), 1.6x the threshold. The calibration note at `SourceClassifier.swift:85-87`
("0.07 moves 1-4 Mbit web encodes (0.053-0.064 bpp) to compressed") describes files that are not
these: WhatsApp's 640x352 clips reach 0.11-0.28 bpp precisely *because* the resolution is small.
The rule that actually classifies this corpus is `min(width, height) < 720` at
`SourceClassifier.swift:106-107`, which catches 9 of 11.

**The two 1280x720 clips fall through both metadata rules** — `min = 720` fails `< 720`, and
0.162/0.134 fail `< 0.07` — so they reach the frame-stats test at `:114-118` and become **`clean`**
unless `blockiness >= 1.6` or `detailRatio < 0.54`. `clean` selects
`[upscaleLight, sharpen, chroma, off]` (`ProfilePicker.swift:44-45`); `upscaleLight` is
ArtCNN_C4F16 + CfL_Prediction (`RenderProfile.swift:72-73`) with **no debander**, and
`enablesDeband` is false (`:91`).

**The stats path is not slow.** The actual analysis pattern was measured
(`ffmpeg -ss <t> -i <file> -frames:v 1 -pix_fmt gray -f image2pipe -c:v pgm`, 8 samples at
`duration * (0.05 + 0.9 * (i + 0.5) / 8)` per `FrameMath.swift:16-19`):

| File | Duration | 8 samples total | Per sample | Tag probe |
|---|---|---|---|---|
| P3.mp4 | 526.4 s | **0.30 s** | 0.04 s | 0.04 s |
| Patricia114747.mp4 | 26.0 s | **0.30 s** | 0.04 s | 0.05 s |
| P1.mp4 | 152.3 s | **0.30 s** | 0.04 s | 0.04 s |

So the 5 s timeout at `FrameAnalyzer.swift:39` has ~15x headroom. **The initial hypothesis that
the timeout was killing the stats path is disproved by measurement.** The real weakness is
coverage, not speed: `decodeFrame` requests `-pix_fmt gray` and emits PGM, and
`FrameMath.parsePGM` (`:22-27`) reads a single plane, so `blockiness`, `detailRatio` and `noise`
are **all luma-only**. Chroma damage — colour bleeding at edges and chroma banding in skies and
skin, a headline WhatsApp 4:2:0 defect and the entire reason CfL_Prediction is wired into six
profiles — is invisible to the classifier. A 720p clip with clean luma and badly bleeding chroma
classifies `clean`.

Secondary: `minimumUsableFrames = 4` of 8 (`FrameAnalyzer.swift:21`, `:104`), so if 5 samples
fail the stats are `nil` and `finishAnalysis` silently keeps the metadata-only pick
(`MPVPlayer.swift:1435-1443`, logging "No frame stats, keeping the metadata pick") — which for a
720p clip means `clean`.

---

## Ranked recommendations

Target case throughout: 640x352 -> 1728x1117 on a 120 Hz ProMotion M1 Pro.

| # | Change | Expected effect | Cost | Risk | Evidence that proves it worked |
|---|---|---|---|---|---|
| 1 | Stop setting `display-fps-override`; keep `screen-name`. `MPVPlayer.swift:352-354`, `:1636`; `MPVVideoView.swift:364` | Lets fork patch `0004`'s CVDisplayLink detection drive `display-resample` instead of a hard-coded 120. Manual: an incorrect value "can ruin video playback" **[V]** | S | **Medium** — if patch `0004`'s detection is wrong on an external monitor, timing regresses. Mitigate by logging the detected value before removing the override | Drop counter over 40 s fullscreen on **P5.mp4** (24.917 fps, the worst case for `display-resample`) and on a 30 fps fixture. Design doc's gate: "does not rise after warm-up (today: about 20 per 40 s)" |
| 2 | Make the GPU budget display-rate aware when interpolation is on. `GPUBudgetMonitor.swift:65-67` | Budget for a 30 fps clip goes 16.7 ms -> 8.33 ms (4.17 at fraction 0.5), so Automatic stops selecting profiles that cannot meet a 120 Hz deadline **[V]** | S | Low — may step down one tier more often: slightly lighter picture, no stutter | Log chosen profile + measured `vo-passes` ms at 120 Hz across the 7x 640x352 fixtures; assert no sustained drops and that the first pick survives |
| 3 | Split `estimatedMilliseconds` into a source-pixel term (prescaler passes) and a drawable-pixel term (final scale + `POSTKERNEL`/`OUTPUT`). `ProfilePicker.swift:57-72` | At a 1728x1117 window the prediction stops under-estimating ~3x, so the first pick is right instead of relying on step-down **[V arithmetic]** | M | Low — pure function, already in the tested shape | Re-measure the cost table at two window sizes; assert prediction within ~20% of measured `vo-passes` |
| 4 | Move `.compressedGrain` grain from `noise_static_luma.hook` (`LUMA`) to `filmgrain-smooth-SDR-light.glsl` (`OUTPUT`). `RenderProfile.swift:83` | Grain lands 1:1 on display pixels instead of being low-passed by the 1.35x lanczos pass, so it actually masks blocking **[V placement, I benefit]** | S | Low — different grain character; may need a strength tweak | Fixed-frame A/B on **Patty7.mp4** (1.88 Mbit/s, blockiest of the set) |
| 5 | Add `PixelClipper.glsl` (`POSTKERNEL` + `CHROMA_SCALED`) to `.compressed`, `.upscaleLight`, `.crisp`. `RenderProfile.swift:73`, `:77`, `:79` | Anti-rings the 1.35x residual luma upscale *and* the 2.70x chroma upscale. Clips overshoot to the local envelope rather than fabricating detail, so it respects the fidelity constraint **[V hook gates]** | S | Low-medium — over-clipping can soften edges; it self-gates on upscale >1.0 | Fixed-frame A/B on high-contrast edges (text, fence lines) in **P1.mp4**; confirm no edge darkening and check colour-edge bleeding is reduced |
| 6 | A/B `Debandit.glsl` against `hdeband.glsl` in `.compressed`. Both pre-upscale (`MAIN` vs `LUMA`/`CHROMA`/`RGB`) | Adds explicit `db_block` 16px AVC grid deblocking and a plane-fit ramp estimator that should preserve curved shading hdeband flattens. GPL-3.0, license-compatible **[V facts, I benefit]** | S | **Medium** — 15 params and 136 directives; GPU cost unmeasured, so it cannot enter `ProfilePicker.costs` until measured | Measure ms/frame first; if within budget, fixed-frame A/B on **Patty2.mp4** (1.17 Mbit/s, lowest bitrate) in dark gradients and on skin |
| 7 | Close the 1280x720 classification gap. `SourceClassifier.swift:106` | The owner's two 720p WhatsApp fixtures currently classify `clean` and get **no debander**; this puts them on the `.compressed` chain **[M]** | S | **Medium** — `<= 720` also catches genuinely clean 720p. Better paired with #8 | Run `scripts/calibrate-profile-picker` over the 11 fixtures; assert both 720p files classify `compressed` and that no known-clean 720p file regresses |
| 8 | Give the classifier a chroma signal alongside luma. `FrameAnalyzer.swift` `decodeFrame` (`-pix_fmt gray`), `FrameMath.swift:22-27` | 4:2:0 chroma bleeding becomes visible to the picker, so luma-clean/chroma-bad clips stop classifying `clean`. Headroom exists: the 8-sample pass costs 0.30 s against a 5 s timeout **[M]** | M | Low — additive statistic, no change to existing thresholds | Decode one extra `yuv420p` sample; add a chroma-edge-bleed metric; check it separates the 11 fixtures and correlates with what you see |
| 9 | Re-run and record the design doc's verification gates; correct the stale "reverted" note in `docs/research/2026-10-02-backend-quality-review.md` | The doc currently tells any future reader that amp is on `video-sync=audio`, which has been false since `fbebae6` **[V]** | S | None | A `docs/research/2026-10-03-*.md` with drop counters at 24.917/30/60 fps and per-profile ms/frame at 120 Hz |
| 10 | Replace `KrigBilateral.glsl` with `CfL_Prediction_Lite.glsl` in `.efficient`. `RenderProfile.swift:69` | `.efficient` is the first fallback for `compressed` sources; the project's own inventory records KrigBilateral as measured worse than CfL on 4:2:0 **[V]** | S | Low | A/B on **Patty5.mp4**; compare colour-edge fidelity and ms/frame |

Sequencing note: **do #1 and #2 before #3**, and #9 immediately after. #1 and #2 change what the
correct budget even is; re-measuring the cost table (#3) before them would bake in the wrong
deadline. #4, #5, #6, #10 are independent and can be A/B'd in any order once Seam 2 (§5) exists —
without it each one is verified by eyeballing a fullscreen video.

---

## Explicitly not recommended

| Tempting | Why not |
|---|---|
| **`videotoolbox-copy` for the shader chain** | Not needed. GLSL shaders run inside libplacebo on the GPU surface and never need CPU-readable pixels. Only a `vf` filter does, and amp already forces copy-back for exactly that case (`MPVPlayer.swift:228-234`). Copy-back adds a GPU->CPU->GPU round trip for zero quality gain. The 2026-10-02 review reached the same conclusion independently. |
| **`scale=zimg` or any `vf`-based scaling** | `zimg` is a CPU `vf_scale` backend, not a libplacebo scaler name. Inserting any `vf` forces software frames and destroys zero-copy VideoToolbox — amp's own comment at `MPVPlayer.swift:224-227` records that a filter cannot read the opaque surface. `d3d11va` is Windows-only. Neither has a macOS/gpu-next meaning. |
| **Turning off `sigmoid-upscaling` or `linear-downscaling`** | mpv computes `disable_linear_scaling = !linear_downscaling && !linear_upscaling` and `linear-upscaling` defaults to `no`, so that one change silently disables sigmoid upscaling too. Already correctly documented at `MPVPlayer.swift:1275-1279`. |
| **`temporal-dither=yes`** | libplacebo's own header notes it "commonly flickers on LCDs"; a crawling still frame is worse than useless in an inspection tool. Correctly rejected at `MPVPlayer.swift:1281-1283`. |
| **Interpolation for `.off`/Faithful** | The exemption at `RenderProfile.swift:117-118` is correct: Faithful's contract is that each decoded frame is shown exactly once. |
| **Stacking `Debandit` on top of `hdeband`** | They sit at nearly the same pipeline position (both pre-upscale). Double debanding is how you get the "plastic" look `.compressedGrain` exists to hide. Pick one. |
| **Raising `hwdec-extra-frames` above 4** | The manual restricts it to APIs that preallocate surfaces (`d3d11va`, `vaapi`); VideoToolbox allocates as needed. The existing value is already inert on macOS. Fix the comment, not the number. |
| **Replacing `.compressed` as the WhatsApp pick** | `docs/research/2026-10-02-compressed-quality-benchmark.md` is cited at `SourceClassifier.swift:104-105` as having scored that stack best on 360p phone-grade encodes. Improve its chain; don't swap it. |
| **Native Metal / MetalFX / MLX / Core ML / `VTFrameProcessor`** | Surveyed and rejected with evidence in `docs/research/2026-10-02-backend-quality-review.md` §1 and §7. Nothing has changed: libplacebo `#380` still has no maintainer review, and `VTLowLatencySuperResolutionScaler` is macOS 26-only with a 921,600-pixel source cap shared with interpolation. |
| **Splitting `PlayerController.swift`** | 1715 lines, but it contains no render-engine logic (§5). Splitting it unblocks none of questions 1-4 and would be refactor for its own sake. |
| **A general `MPVPlayer.swift` refactor** | 1663 lines and genuinely overloaded, but only the three seams in §5 matter here. Event Handling, Screenshot, and track/chapter handling are unrelated to this work. |

---

## Open questions for the owner

1. **Is the ProMotion panel actually at 120 Hz during fullscreen video — on battery, on AC, and in
   Low Power Mode?** If macOS drops it below 120, `display-fps-override=120` is actively wrong and
   recommendation #1 is urgent rather than merely tidy. What does fork patch `0004`'s CVDisplayLink
   report in those states? (This determines whether #1 is a 10-minute change or the start of a
   timing investigation.)

2. **Was the design doc's smoothness gate run after `fbc3abd` landed, and what were the numbers?**
   No 2026-10-03 measurement was found in `docs/research/`, and the 2026-10-02 doc still records
   the *reverted* ~20 drops/40 s. If it was run and passed, that changes the priority of #1 and #2
   substantially; if it was not, they are the top of the list.

3. **`.restore` wires `ravu-zoom-ar-r3.hook` (Anime4K RAVU) and `nlmeans.glsl`.** Your standing
   decision is no anime-style enhancement for realistic video, and your own shader inventory
   records nlmeans as non-functional on macOS. Should `.restore` be removed from the picker UI, or
   rebuilt from Debandit + ArtCNN + grain-at-`OUTPUT`? It is currently the profile whose copy most
   directly promises the WhatsApp use case.

4. **For 1280x720 WhatsApp clips, do you want them forced to `compressed`** (blunt: change `< 720`
   to `<= 720`, at the cost of misclassifying genuinely clean 720p), **or do you want the
   classifier to earn it** via a chroma statistic (recommendation #8, more work, no false
   positives)? The two 720p fixtures are the only files in your corpus affected today.

5. **Is `ArtCNN_C4F32`'s `//!WIDTH LUMA.w 4.0 *` against `//!HEIGHT LUMA.h 2.0 *` the upstream
   model's intent, or a local conversion artifact?** It only affects `.upscaleStrong`, which is in
   no chain and therefore manual-only — but if it is an artifact, that profile is quietly wasting
   half its horizontal work.
