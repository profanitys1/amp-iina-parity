# amp backend quality review (2026-10-02)

Scope: everything except the choice of upscaling shader. Hardware: M1 Pro 14", ProMotion XDR. Content: compressed live action, 640p-1080p, mostly SDR.
Budget-capped research: primary sources for the top questions only. Tags: **[V]** verified against a primary source or code I read; **[S]** secondary or single-developer source; **[I]** inference, not tested. No GPU timings were measured; every cost figure is [I].

## 0. What amp runs today (verified in code and in the pinned MPVKit)

- `vo=gpu-next gpu-api=vulkan gpu-context=moltenvk wid=CAMetalLayer hwdec=videotoolbox` (`MPVPlayer.swift` setupMPV) [V].
- `video-sync`, `interpolation` and `tscale` are not set anywhere in the Swift sources (grep). amp sets only `display-fps-override` (line ~1562) [V].
- `moltenvk` is **not an upstream mpv context**. mpv 0.41.0 calls its macOS Vulkan context `macvk` ([context_mac.m @ v0.41.0](https://raw.githubusercontent.com/mpv-player/mpv/v0.41.0/video/out/vulkan/context_mac.m)). `moltenvk` comes from MPVKit's patch `0001-player-add-moltenvk-context.patch` ([patch](https://raw.githubusercontent.com/mpvkit/MPVKit/main/Sources/BuildScripts/patch/libmpv/0001-player-add-moltenvk-context.patch), fetched 2026-10-02). That patch uses `VK_PRESENT_MODE_FIFO_KHR` but has **no `get_vsync` / presentation-feedback hook** (grep for `vsync`: no match). Upstream `macvk` has one, driven by CVDisplayLink ([commit 2024-04-06 "add support for frame timing via presentation feedback"](https://github.com/mpv-player/mpv/commits/master/video/out/vulkan/context_mac.m)). [V]
- Consequence [I]: `display-resample` on amp runs on the nominal `display-fps-override` with no measured vsync timing. It still works, but it is less robust than upstream `macvk`.

## 1. Backend: MoltenVK vs native Metal

| | |
|---|---|
| amp now | libplacebo 7.360.1 (2026-03-13), MoltenVK 1.4.2 (2026-07-20), mpv 0.41.0 (2025-12-21), FFmpeg n8.1.2 |
| 2026 finding | **Stay on MoltenVK/Vulkan.** No usable native Metal path exists for gpu-next. |

Evidence:
- libplacebo has **no Metal backend upstream**. A third-party branch was announced as "ready for review" in [libplacebo issue #380](https://github.com/haasn/libplacebo/issues/380) (2026-09-28, user ab300819). It is Apple-GPU only, needs macOS 12+, translates SPIR-V to MSL via SPIRV-Cross, and lacks thread-safety guarantees, texel buffers and buffer/sync interop. CPU uploads block on in-flight GPU work. The author reports output "bit-identical" to MoltenVK and gives no performance numbers. No maintainer response on the page. [V]
- mpv has no Metal vo. `vo=libmpv` render API on macOS is OpenGL-only; IINA uses it ([Phoronix 2025-08](https://www.phoronix.com/news/MoltenVK-1.4), [mpv discussion #17223](https://github.com/mpv-player/mpv/discussions/17223)). [S]
- mpv's own upstream macOS Vulkan path (`macvk`) is also MoltenVK, still FIFO present mode, and its Metal layer carries the same workarounds amp copied: 1x1 `drawableSize` rejection ([PR #13651, merged 2024-03-06](https://github.com/mpv-player/mpv/pull/13651)) and forced opaque state (commit 2025-12-24). [V]

MoltenVK status ([Whats_New.md, fetched 2026-10-02](https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md)) [V]:
- 1.4.0 (2025-08-20) added `VK_KHR_present_id/present_wait` and fixed high latency on present wait.
- 1.4.1 (2025-11-24) added `VK_KHR_swapchain_maintenance1` and a new descriptor tracker.
- 1.4.2 (2026-07-20, amp's floor) fixed **"swapchain recreation giving 1x1 drawables"**, device loss with imported `MTLTexture` objects (zero-copy VideoToolbox), and Apple Silicon channel corruption.
- **1.4.3 is unreleased** and already lists fixes for `VkDeviceMemory` imported from an `MTLTexture` (not backing the bound image, over-release) and an `MTLBuffer` leak. These touch the zero-copy hwdec path. Worth tracking.
- Nothing in the changelog addresses ProMotion pacing or `displaySyncEnabled`. Not found does not mean not broken. [I]

Newer components than amp's pin:
- libplacebo master has **149 commits after v7.360.1** ([compare](https://github.com/haasn/libplacebo/compare/v7.360.1...master), 2026-10-01). No tag after 7.360.1 exists. Vulkan sync and threading fixes (Sep 2026: wait for all commands at sync points, present under recording lock, don't reuse a command a thread still waits on) matter for MoltenVK stability. Quality items are in section 6. [V]
- MPVKit upstream 1.0.0 (2026-07-25) equals amp's set (mpv 0.41.0, placebo 7.360.1, MoltenVK 1.4.2, FFmpeg n8.1.2). amp's fork head (2026-09-26) only adds CoreAudio fixes. **No newer MPVKit exists to bump to.** [V]

Recommendation:
1. Keep the backend. A native-Metal libplacebo is a 2027 watch item. Revisit when #380 gets maintainer review and mpv gains a wid-embeddable Metal context. Today it would also need an mpv vo change. Expected gain: unknown, no benchmarks. [I]
2. Medium effort, real smoothness upside: port upstream `macvk`'s CVDisplayLink `get_vsync` into the MPVKit `moltenvk` patch (about 30 lines from [video/out/mac/common.swift](https://raw.githubusercontent.com/mpv-player/mpv/master/video/out/mac/common.swift)). Risk: maintaining a fork patch. [I]

## 2. Smoothness

| | amp now | 2026 recommendation |
|---|---|---|
| `video-sync` | default `audio` | `display-resample` |
| `interpolation` | off | `yes` for 25 fps (and optionally 24/30) |
| `tscale` | default | `oversample` (default) |
| `hwdec-extra-frames` | default | raise (set at init) |

Evidence [V, mpv manual `options.rst` master, fetched 2026-10-02]:
- `audio` is the default and "can lead to occasional frame drops or repeats". `display-resample` is the manual's recommended mode for matching video to the display.
- `--interpolation` is **silently disabled unless `--video-sync` is a `display-` mode**. It "may require `--hwdec-extra-frames`" when enabled at runtime, because the hwdec surface pool is sized at decoder init.
- `tscale` default is `oversample`, the sharpest and least blurry choice. Smoother filters (`linear`, `mitchell`, `bicubic`) blur. `interpolation-threshold` default 0.01.
- Display modes need a vsync-blocked present: Vulkan FIFO. The MPVKit context sets FIFO. [V]

Cadence arithmetic on a 120 Hz panel [V, arithmetic]: 24 fps = 5 refreshes, 30 fps = 4. Both are exact, so `display-resample` alone is clean. **25 fps = 4.8 refreshes, which judders.** `display-resample` can only nudge speed by about 1 percent, not 4 percent. Use `interpolation=yes tscale=oversample` for 25 fps. Oversample blends only at the frame boundary, so blur stays minimal. A new libplacebo commit "blend frames in linear light v2" (2026-05-10, unreleased) improves this path. [V]

ProMotion caveats [I]:
- A ProMotion panel may not sit at a fixed 120 Hz. If amp's `display-fps-override` is derived from `maximumFramesPerSecond`, it can disagree with the actual refresh. A wrong override "can ruin video playback" (manual). Verify what value amp passes and what the panel really runs during fullscreen video. Without upstream-style vsync feedback (section 0) nothing corrects it.
- I did not verify `CAMetalDisplayLink` or `preferredFrameRateRange` on `CAMetalLayer` under MoltenVK. MoltenVK 1.4.x has no changelog entry for either. Treat as unverified. Note the idea: the layer could request 120 Hz (or a 24/25/30 multiple) during playback so the panel does not drop below the assumed rate.

GPU cost: interpolation adds a few frame-blend samples per output frame, negligible at 1080p on M1 Pro; the main cost is extra display frames at 120 Hz [I].
Risk: low-to-medium. Audio is resampled slightly (inaudible). Seeking and resizing skip frames in display modes (manual) [V]. Don't enable for inspection profiles.

## 3. Compressed-source handling

| | amp now | recommendation |
|---|---|---|
| mpv `deband` | off (on only for `.restore`) | on for compressed profiles if `hdeband.glsl` is not loaded; `deband-iterations=2`, `deband-threshold=48`, `deband-range=16`, `deband-grain=32` [I] |
| `vd-lavc-film-grain` | default `auto` | leave |
| `hwdec` | `videotoolbox` | leave |

Evidence:
- mpv defaults [V, `options.rst`]: iterations 1, threshold 48, range 16, grain 32. The manual says iterations above 4 are "practically useless" and to lower `range` when raising iterations. libplacebo C defaults are 1 / 3.0 / 16.0 / 4.0 ([sampling.h](https://raw.githubusercontent.com/haasn/libplacebo/master/src/include/libplacebo/shaders/sampling.h), [V]), a different scale from mpv's options, so do not copy numbers between them.
- libplacebo's own `pl_render_high_quality_params` **enables deband with default params** ([renderer.c, master, V](https://raw.githubusercontent.com/haasn/libplacebo/master/src/renderer.c)).
- amp's `.compressed` profile already loads `hdeband.glsl`. Running both mpv deband and hdeband is redundant (amp's own comment says hdeband replaces it). So the actionable item is for profiles **without** hdeband (Off, Chroma, Efficient): a mild mpv deband (iterations=1, threshold=32-48, grain=16-32) trades a little flat-area texture for fewer banding steps in dark gradients, which is the most visible artefact of 8-bit streamed video. [I] Cost: one cheap pass at video resolution, well under 1 ms on M1 Pro [I]. Risk: smears fine low-contrast detail; keep Off profile untouched for inspection.
- Film grain: `vd-lavc-film-grain=auto` applies AV1 grain on the GPU when the VO supports it (manual, V). H.264/HEVC streams carry no grain, so nothing changes for the stated content. M1 has no AV1 hardware decode (general Apple spec, not re-verified here), so AV1 goes through software dav1d. libplacebo fixed AV1 and H.274 grain bugs on 2026-06-01 (unreleased) [V].
- Decoder deblocking: VideoToolbox and FFmpeg expose **no post-processing option**; the decoder's in-loop deblocking is part of the bitstream spec. `hwdec=videotoolbox` and `videotoolbox-copy` give the same pixels. The copy variant only costs bandwidth. Keep zero-copy [I].
- libplacebo master dithering fix 2026-06-22 ("don't let the dither pattern lift true black off zero") is relevant to dark gradients [V, unreleased].

## 4. Scaling for perceived quality

| | amp now | recommendation |
|---|---|---|
| `scale` | `lanczos` | `ewa_lanczossharp` for non-`.sharpen` profiles on upscales of 1.3x-2x [I] |
| `scale-antiring` | 0 | 0.5 if sharpened [I] |
| `dscale` | `mitchell` | keep (libplacebo high-quality uses `hermite`; amp's reasoning for mitchell is sound) |
| `cscale` | `spline36` | keep |
| sigmoid/linear/correct-downscaling | all yes (default) | keep |

Evidence:
- libplacebo "high quality" preset today [V, `renderer.c` master]: upscaler `ewa_lanczossharp`, downscaler `hermite`, frame mixer `oversample`, default sigmoid, default dither, **default deband**, high-quality peak detection and colour mapping.
- amp's code comment argues plain `lanczos` is more faithful (PSNR 36.51 vs 36.07 at 2x) and 7.56 vs 5.98 ms. That is right for inspection. For **viewing soft, compressed footage**, a mild sharpening bias is generally what viewers prefer, and the 1080p-to-fullscreen factor is only 1.57x [I]. Recommend `ewa_lanczossharp` for the viewing profiles. I did not run a visual comparison; try it A/B on three clips before shipping.
- GPU cost: EWA at 3024x1964 output is the expensive scaler; amp's own numbers put it at 7.56 ms/frame vs 5.98 ms [V, amp comment, measured by amp's author]. Acceptable at 24-30 fps, tight at 120 Hz interpolation output [I].
- libplacebo master "preserve energy in ortho scaling" (2026-06-20) and "refactor `sigmoidize` for numeric stability" (2026-06-22) are unreleased [V].
- Keep `linear-downscaling=yes`: turning it off silently disables sigmoid upscaling (amp's comment, consistent with mpv). libplacebo re-reverted "never use linear downscaling on HDR sources" on 2026-05-18 [V].

## 5. Colour and HDR

SDR (amp now: ICC profile from display as a file, CAMetalLayer colourspace = screen colourspace, `target-colorspace-hint=yes`) [V in code]:
- mpv manual: `target-colorspace-hint` is "highly recommended" and "crucial for all non-sRGB content, even SDR"; avoid `no` ([options.rst, V](https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst)). The doc lists Wayland/D3D11/winvk as the contexts where `auto` fires; `yes` forces it anyway. amp uses `yes`, which is correct.
- **Potential conflict [I]:** amp's `MPVMetalLayer.apply` sets `layer.colorspace` after mpv/libplacebo has already told MoltenVK a Vulkan colourspace, and MoltenVK writes `CAMetalLayer.colorspace` from it (changelog since 1.2.x, [V]). Whichever writes last wins, and a swapchain recreation can overwrite amp's value. Log layer colourspace changes (as upstream does in `metal_layer.swift`, [V]) and confirm amp's value survives resizes and fullscreen.
- Two valid SDR designs: (a) ICC file + layer in the display's own space (current; consistent because both describe the same display), or (b) no ICC, `target-prim`/`target-trc` auto, layer in Display P3, macOS manages. (b) is simpler and matches mpv's guidance and IINA's HDR approach. mpv 0.41 now prefers an ICC profile's colourspace over any metadata ([release notes, S](https://github.com/mpv-player/mpv/releases)). A/B the two on a saturated BT.709 clip; neither is wrong. Cost: ICC adds a 3D LUT lookup, negligible [I].

HDR (amp: EDR layer with PQ colourspace, `target-peak` from EDR headroom, `target-trc`/`target-prim` set per state):
- `tone-mapping=auto` is **`spline` on gpu-next** [V, manual]. That is current best practice; keep default. Do not set `bt.2446a` or `st2094-40` explicitly unless a clip needs it [I].
- Phone clips (HDR10/HLG, Dolby Vision profile 8.4 is HLG-compatible): I did not verify libplacebo's profile-8.4 handling. Test one iPhone clip for hue shift and note if it falls back to the HLG base layer [I].
- Big pending item: libplacebo master rewrote parts of the HDR pipeline in Jul-Sep 2026 [V, unreleased]: spline uses hyperbolic segments (07-02), knee brightness fade below display floor (08-04), per-cone-channel tone mapping and mastering-peak soft clip (08-01/02), dynamic scene metadata with peak detection together (08-02), tone map in the mastering display's RGB space (08-07), gamut-map folding (08-06), HDR10+ scene max luminance (05-26), Dolby Vision FEL merging (05-16), and sRGB backgrounds kept display-referred on SDR targets (09-22). mpv master adds reference-white handling (06-14, Windows/Wayland only) and keeps peak-detected metadata across frames (08-28).
- None of this is in a tagged libplacebo. Adopting it means building libplacebo from master in the MPVKit fork. Expected benefit: smoother, more accurate HDR on EDR; no change for SDR. Risk: untagged code and API changes; mpv 0.41.0 may not match libplacebo master's API [I].

## 6. New in 2025-2026 worth adopting

- mpv 0.41.0 (2025-12-21): gpu-next default, Vulkan hwdec preferred, better default colour management, ICC colourspace over metadata, pure 2.2 sRGB linearisation, film grain when metadata present [S, releases page]. No mpv 0.42 tag exists as of 2026-10-02 [V, tags API]. amp already has these.
- libplacebo 7.360.0 (2026-02-11): `PL_DEINTERLACE_BWDIF`, clear-with-blur, YCgCo-Re/Ro; 7.360.1 (2026-03-13): MoltenVK timeline-semaphore workaround (amp's floor, in CLAUDE.md) [S, release summaries].
- mpv master: `vf_fruc_vulkan` (video frame-rate up-conversion, extensions enabled 2026-06-21) [V commit title only; unreleased, GPU motion-compensated interpolation to watch].
- mpv master 2026-09-29 "defer the queue reset until a new frame arrives" and 2026-09-01 "keep hwdec frames mapped while the queue holds them" improve interpolation and seek behaviour [V, unreleased].

## 7. Apple-native processing beside mpv

Short answer: none beats the GLSL path on integration cost today. Only `VTLowLatencyFrameInterpolation` and, narrowly, `VTLowLatencySuperResolution` are plausible, and both require frames outside mpv's Vulkan renderer.

| Option | M1 / OS | Quality | Cost | Integration into amp | Verdict |
|---|---|---|---|---|---|
| **MetalFX `MTLFXSpatialScaler`** | M1+, macOS 14.2+ [S, Glass Player README / secondary] | Game-oriented spatial upscaler. Apple says it "analyzes the input's spatial information"; best when input is tone mapped and perceptual ([WWDC22 10103](https://developer.apple.com/videos/play/wwdc2022/10103/), S). Not trained for compression artefacts. Expect FSR1-class. [I] | Well under 1 ms at 1080p to 4K on GPU [I] | Needs an `MTLTexture` input. mpv's Vulkan swapchain cannot hand you one. A third-party player claims a custom Metal pass after libmpv ([Glass Player](https://github.com/khr898/Glass-player-macOS), S, unverified). For amp that means replacing the renderer or reading back frames. | Low gain, high effort. Skip. |
| **VTLowLatencySuperResolutionScaler** | API macOS 26.0 ([Apple doc metadata, V](https://developer.apple.com/tutorials/data/documentation/videotoolbox/vtlowlatencysuperresolutionscalerconfiguration.json)). Single-developer report on macOS 26.7 / M4: source capped at **921,600 px** (max 960x960); the same budget is shared with interpolation ([FrameInterp v1.4 notes, S](https://github.com/lrylnx/frameinterp/releases/tag/v1.4)). Not tested on M1. | WWDC25 pitches it for conferencing, "reduces compression artifacts" ([WWDC25 300](https://developer.apple.com/videos/play/wwdc2025/300), V) | ML model load "may take longer than a frame time" (Apple doc, V). Latency unmeasured. | `CVPixelBuffer` in/out. Fits only 720p-and-below sources (1280x720 = 921,600 exactly [V arithmetic]). Needs mpv frames as pixel buffers. | Interesting for WhatsApp-size clips only; unproven. Prototype later. |
| **VTTemporalNoiseFilter / quality SR (4x only, model download)** | macOS 15.4+ for FRC/TNF/high-quality SR (Apple doc metadata, V) | Same report: TNF output **byte-identical to input** at every strength; quality SR needs an unavailable online model [S, M4, macOS 26.7] | TNF 12.48 ms/frame at 1080p [S] | n/a | Unusable on macOS 26.x per one report. Re-test on macOS 27. |
| **VTLowLatencyFrameInterpolation / `VTFrameRateConversion`** | macOS 26.0 / 15.4; works on macOS 26 and 27 per the same report; M1-M4 claimed [S, FrameInterp README] | ML interpolation, only 2x or 4x (1/8 phase grid) [S] | 0.12 CPU cores for 30 to 60 fps, off-GPU (ANE/media engine) [S, vendor claim] | Needs a pair of frames per call, so latency of one source frame. In amp the clean route is an own decode path or FFmpeg filter, not mpv's VO. | Strongest Apple-native idea for 24/25/30 to 120, since mpv's `oversample` only blends. Risk: ML artefacts on fast motion, HDR support unknown. Prototype only if blending judder remains objectionable after section 2. |
| **Core ML on Neural Engine** | Any M1, ANE is separate from the GPU | PiperSR 2x claims 44 fps / 22.5 ms on M2 Max ([PiperSR, S](https://github.com/ModelPiper/PiperSR)); `ane-superres` 1080p to 4x takes 103 ms/frame on an M4 Air ([S](https://github.com/blka/ane-superres)). Too slow for 1080p at 24 fps with margin on M1. | Frees the GPU for shaders [I] | Same pixel-buffer problem as above, plus a GPU-to-ANE copy each frame. | Only for sub-720p sources; not a net win over ArtCNN GLSL. Apple announced "Core AI" as Core ML's successor at WWDC26 for iOS/macOS 27, aimed at LLMs ([InfoQ 2026-06](https://www.infoq.com/news/2026/06/apple-core-ai-wwdc/), S). |
| **MLX per-frame models** | Runs on the GPU | Same models as Core ML | Competes with mpv's GPU work on the same M1 Pro GPU [I] | Unified memory avoids copies, but no mpv hook | Worse than GLSL for latency; MLX favours training and LLMs ([comparison, S](https://blog.ivan.digital/mlx-vs-coreml-on-apple-silicon-a-practical-guide-to-picking-the-right-backend-and-why-you-should-f77ddea7b27a)). Skip. |

Integration routes vs colour and HDR [I unless noted]:
- **libplacebo hooks / glsl-shaders (current):** inside the colour pipeline; runs on linear or native-luma data at the right stage; HDR safe. Lowest effort. Wins.
- **FFmpeg filter in mpv `vf`:** forces software frames. `hwdec=videotoolbox` frames are opaque ("A filter cannot read the opaque surface", amp's own comment [V]), so this breaks zero-copy and adds a CPU/GPU copy. HDR needs 10-bit and a pixel format the model accepts.
- **Metal post-pass on the CAMetalLayer:** mpv has already tone mapped and dithered to the swapchain; running a scaler after dither lifts noise. HDR would need the scaler to accept extended-range float (`colorProcessingMode` HDR exists, S). mpv cannot expose its swapchain image, so this requires owning the renderer.
- **Custom vo / render API:** the libmpv render API has no Vulkan or Metal backend [S], so replacing the VO means abandoning gpu-next features amp relies on.
- Latency: any pre-scaler needing neighbouring frames adds at least one frame (about 40 ms at 25 fps) before A/V sync compensation. Fine for movies, not for scrubbing.

## 8. Ranked changes

Do first (low risk, mpv options only):
1. `video-sync=display-resample` (all viewing profiles; leave inspection on `audio`). [V doc] Visible: fewer dropped or repeated frames at 24/30 fps on 120 Hz. Cost: none. Risk: low; verify the `display-fps-override` value (see section 2).
2. `interpolation=yes` + `tscale=oversample` + `hwdec-extra-frames=4` set before init, enabled for 25 fps and optionally for all. [V doc] Visible: removes 25 fps judder on 120 Hz. Cost: small [I]. Risk: low-medium.
3. Mild built-in `deband` (iterations=1, threshold 32-48, grain 16-32) on profiles that do not load `hdeband.glsl`. [I] Visible: fewer dark-gradient banding steps. Cost: sub-ms [I]. Risk: smears faint detail.
4. A/B `scale=ewa_lanczossharp` (+`scale-antiring=0.5`) for viewing profiles; this is libplacebo's own high-quality preset [V]. Visible: slightly crisper compressed footage. Cost: about +1.6 ms/frame by amp's own measurement [V]. Risk: ringing, so test.
5. Verify the SDR colour path: log `CAMetalLayer.colorspace` after resize and fullscreen to confirm amp's value survives MoltenVK's own writes; A/B ICC-file vs Display P3 + no ICC [I]. Visible: correct, stable colour. Cost: none.

Needs bigger work (each is a deliberate project):
6. Port upstream `macvk` `get_vsync` (CVDisplayLink) into the MPVKit `moltenvk` patch, giving `display-resample` real vsync data [V gap, I benefit]. Medium effort, fork maintenance.
7. Build libplacebo from master in the MPVKit fork for the Jul-Sep 2026 HDR rewrite, Dolby Vision FEL, linear-light frame blending and Vulkan sync fixes. Untagged, so pin by commit, and re-test the MoltenVK timeline-semaphore workaround. High reward for HDR phone clips, moderate risk.
8. Track MoltenVK 1.4.3 (imported-`MTLTexture` fixes relevant to zero-copy `videotoolbox`) and bump when tagged.
9. Do **not** pursue a Metal backend, MetalFX, MLX or Core ML now. Re-evaluate: libplacebo #380 after maintainer review, `VTFrameProcessor` super resolution and temporal noise on macOS 27, and VT low-latency frame interpolation as an opt-in 25-to-100/120 mode if `oversample` is not enough.

## Source index (fetched 2026-10-02 unless noted)

- mpv options manual: https://github.com/mpv-player/mpv/blob/master/DOCS/man/options.rst
- mpv `context_mac.m`, `metal_layer.swift`, `common.swift`; mpv releases and tags (0.41.0, 2025-12-21).
- mpv PR #13651 (2024-03-06): https://github.com/mpv-player/mpv/pull/13651
- MPVKit patch and releases (1.0.0, 2026-07-25): https://github.com/mpvkit/MPVKit; fork: https://github.com/aagedal/MPVKit
- MoltenVK Whats_New: https://github.com/KhronosGroup/MoltenVK/blob/main/Docs/Whats_New.md
- libplacebo: https://github.com/haasn/libplacebo (compare v7.360.1...master, issue #380 dated 2026-09-28)
- Apple VideoToolbox docs (JSON metadata) and WWDC25 session 300; WWDC22 10103.
- Secondary or single-developer: FrameInterp release notes, PiperSR, ane-superres, Glass Player, InfoQ Core AI.

## On-device check: display-resample (2026-10-02)

Tried `video-sync=display-resample` + `interpolation=yes` + `tscale=oversample` in amp.app (Release, fullscreen 3448x1940, 1280x720p25 H.264 test clip, M1 Pro, 120 Hz).
Result: about 20 dropped frames in 40 s with both the Compressed movie profile (16.2 ms GPU) and the light Chroma profile (7.0 ms GPU). GPU load is not the cause.
Likely cause: MPVKit's `moltenvk` gpu-context gives mpv no vsync feedback, so display-resample runs on the nominal `display-fps-override` (120) rather than the panel's real timing.
Decision: reverted, amp stays on `video-sync=audio`. Revisit after porting a vsync/CVDisplayLink hook into the MPVKit moltenvk context patch.
