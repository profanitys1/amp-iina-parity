# Compressed-input upscaler / restoration benchmark — 2026-10-02

Source: /Users/filip/Downloads/Movies/gaia.mov (ProRes 422 HQ 1280x720p30, BT.601), 10 s from t=120 s (300 frames).
Reference = that segment as-is (720p, converted to yuv420p). Metrics only; no frames viewed. One clip.
Scope was trimmed for budget mid-run: the requested set was scored; rows marked "extra" had already finished before the trim and are kept.
Not run: ravu-zoom-ar-r3 (segfaults in ffmpeg libplacebo), and case B's ArtCNN DN 2x-then-mitchell-downscale (cut by the trim).

## Method
Tooling: /Users/filip/ffmpeg-apple-silicon/dist/9.0.1/full/ffmpeg, `DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib`.
The libplacebo filter needs `-init_hw_device vulkan=vk -filter_hw_device vk` (plain run fails "Failed initializing vulkan device").
Render to ffv1 (`-level 3 -slicecrc 1`) first, then score in a separate command. All outputs verified to decode with zero errors and 300 frames.

Reference and degraded inputs (BT.601 tags `-colorspace smpte170m -color_primaries smpte170m -color_trc smpte170m -color_range tv`):
```
ffmpeg -ss 120 -t 10 -i gaia.mov -vf format=yuv420p -c:v ffv1 -slicecrc 1 $CT ref.mkv
# A (2x case)
ffmpeg -i ref.mkv -vf scale=640:360:flags=bicubic -c:v ffv1 -slicecrc 1 $CT a_src.mkv
ffmpeg -i a_src.mkv -c:v libx264 -preset medium -profile:v main -pix_fmt yuv420p -b:v 700k -pass 1 -passlogfile pa $CT -an -f null /dev/null
ffmpeg -i a_src.mkv -c:v libx264 -preset medium -profile:v main -pix_fmt yuv420p -b:v 700k -pass 2 -passlogfile pa $CT -an A.mp4
# B (1x case): same 2-pass, from ref.mkv, -profile:v high -b:v 1500k -> B.mp4
```
Resulting bitrates (ffprobe): A.mp4 640x360 = 705 kbit/s; B.mp4 1280x720 = 1517 kbit/s (WhatsApp fixtures are 0.75-3.7 Mbit/s).

Render (one example; shader stacks are the .glsl/.hook files concatenated in stack order into one `custom_shader_path`):
```
ffmpeg -init_hw_device vulkan=vk -filter_hw_device vk -i A.mp4 \
  -vf "libplacebo=w=1280:h=720:upscaler=lanczos:downscaler=mitchell:custom_shader_path=STACK.glsl[:upscaler override],format=yuv420p" \
  -c:v ffv1 -level 3 -slicecrc 1 $CT out.mkv
```
Case B uses `w=iw:h=ih`. Scalers: the ffmpeg filter exposes only `upscaler`/`downscaler` (no `cscale`), so spline36 chroma scaling is
not selectable; chroma uses the filter's internal default. Candidate "ewa_*" and "SSimSuperRes" set `upscaler=` accordingly; everything else lanczos.
Score:
```
ffmpeg -i out.mkv -i ref.mkv -lavfi "[0:v]setpts=PTS-STARTPTS,setsar=1[d];[1:v]setpts=PTS-STARTPTS,setsar=1[r];[d][r]libvmaf=model=version=vmaf_v0.6.1\\:name=vmaf|version=vmaf_v0.6.1neg\\:name=neg:feature=name=psnr|name=float_ssim:log_fmt=json:log_path=out.json:n_threads=4" -f null -
```
Libplacebo deband default = `deband=1` (iterations 1, threshold 4, radius 16, grain 6). Strong deband = `deband=1:deband_iterations=4:deband_threshold=8:deband_radius=24:deband_grain=0`.
Substitutions: Restoration stack ran as nlmeans -> CfL (-> noise_static_luma) with plain lanczos in place of ravu-zoom-ar-r3.
Pitfall hit again: the first Case B hdeband render came out corrupt-scored (VMAF 48.6, SSIM 0.859) when rendered while 3 jobs ran in parallel; one retry gave 92.97. The retry value is reported.

## Case A: 640x360 @ 705 kbit/s H.264 -> 1280x720 (sorted by VMAF-NEG)
| Candidate | VMAF | VMAF-NEG | PSNR-Y dB | SSIM |
|---|---|---|---|---|
| amp Crisp (DS -> CfL -> adaptive-sharpen) | 92.642 | 86.911 | 40.310 | 0.99280 |
| ArtCNN_C4F16_DS | 92.027 | 86.999 | 40.624 | 0.99303 |
| FSRCNNX_x2_8 + KrigBilateral | 88.088 | 85.430 | 39.705 | 0.99240 |
| FSRCNNX_x2_16 (extra) | 87.939 | 85.361 | 40.014 | 0.99100 |
| ArtCNN_C4F16 | 88.496 | 84.975 | 39.852 | 0.99237 |
| amp Upscale light (C4F16 -> CfL) (extra) | 88.498 | 84.975 | 39.853 | 0.99237 |
| SSimSuperRes + ewa_lanczossharp (extra) | 88.128 | 83.764 | 39.203 | 0.99176 |
| ArtCNN_C4F16_DN | 84.997 | 82.921 | 39.492 | 0.99296 |
| amp Compressed movie (hdeband -> DN -> CfL) | 84.821 | 82.716 | 39.486 | 0.99279 |
| lanczos (Faithful) | 82.665 | 80.264 | 37.899 | 0.99199 |
| lanczos + hdeband.glsl (extra) | 82.662 | 80.212 | 37.888 | 0.99206 |
| lanczos + libplacebo deband default (extra) | 82.485 | 80.139 | 37.809 | 0.99136 |
| ewa_lanczossharp | 82.507 | 79.989 | 37.831 | 0.99212 |
| ewa_lanczos (extra) | 82.401 | 79.855 | 37.761 | 0.99210 |
| amp Restoration, nlmeans -> CfL, no ravu (extra) | 79.870 | 77.866 | 37.616 | 0.98940 |
| same + noise_static_luma (extra) | 79.944 | 77.970 | 37.630 | 0.98964 |

## Case B: 1280x720 @ 1517 kbit/s H.264, processed at 1x (sorted by VMAF-NEG)
| Candidate | VMAF | VMAF-NEG | PSNR-Y dB | SSIM |
|---|---|---|---|---|
| none (lanczos passthrough) | 93.005 | 90.894 | 43.086 | 0.99488 |
| hdeband.glsl | 92.970 | 90.797 | 42.923 | 0.99499 |
| libplacebo deband default | 92.786 | 90.751 | 42.669 | 0.99487 |
| libplacebo deband strong (extra) | 92.301 | 90.384 | 42.644 | 0.99462 |
| nlmeans.glsl | 92.148 | 90.305 | 43.238 | 0.99496 |
(ArtCNN_C4F16_DN 2x-then-mitchell-down was cut by the budget trim; not run.)

## Findings
- Best on compressed input (objective): ArtCNN_C4F16_DS and amp Crisp lead on VMAF-NEG (87.0 / 86.9); Crisp wins plain VMAF (92.6) but its adaptive-sharpen adds enhancement gain, and its NEG is slightly below DS alone, PSNR 0.3 dB lower. DS alone is the safest objectively best pick (best NEG, PSNR-Y, SSIM among the top group). All CNN stacks beat lanczos by +4 to +7 NEG and +1.5 to +2.7 dB PSNR-Y.
- Plain C4F16 (84.98 NEG) is behind DS and a hair behind FSRCNNX8+Krig (85.43); FSRCNNX_x2_8+Krig is the best non-ArtCNN-DS option and cheaper than DS-class stacks only marginally. SSimSuperRes and EWA scalers add nothing meaningful (ewa within +-0.4 of lanczos).
- DN vs plain/DS on compressed input: DN does NOT win. NEG 82.9 vs 85.0 (plain) vs 87.0 (DS); PSNR-Y 39.49 vs 39.85 vs 40.62. Only SSIM is marginally higher for DN (0.99296 vs 0.99237), same as DS (0.99303). So DN denoising does not pay off in these metrics, same ordering as on clean input (DN worst of the ArtCNN trio), but the gap to lanczos is still large (+2.7 NEG).
- amp Compressed movie (hdeband -> DN -> CfL) scores 82.7 NEG, ~ the same as DN alone; hdeband changes nothing (-0.05 NEG on lanczos). Per these metrics Crisp/DS stacks beat it by ~4 NEG.
- Deband/hdeband: neutral-to-slightly-negative everywhere. Case A: lanczos 80.26 NEG, +hdeband 80.21, +libplacebo deband 80.14. Case B: passthrough 90.89 NEG; hdeband 90.80, default deband 90.75, strong deband 90.38 (grain 0). None get closer to the clean reference. nlmeans: lower VMAF/NEG (-0.6) but highest PSNR-Y (+0.15 dB) and SSIM tie at 1x (mild gain), and in the 2x case (Restoration stack with lanczos in place of ravu) it is clearly worse (-2.4 NEG, -0.3 dB) than lanczos alone; adding static noise barely changes anything (+0.1), so the grain penalty is below the measurable level here.
- Case B conclusion: at 1x, H.264 at 1.5 Mbit/s is already within 3 NEG points of the reference and no restoration candidate improves on passthrough in VMAF.

## Caveats
- Metrics are not perception: VMAF rewards sharpening (DS, Crisp gain +5 VMAF points over NEG), debanding/denoise/grain are exactly what these metrics do not credit. Banding and mosquito noise reduction are likely under-valued by VMAF/PSNR/SSIM.
- One clip, one content type, synthetic degradation (bicubic downscale + x264 medium, 2-pass), not real WhatsApp encodes. Single run per candidate; no confidence intervals.
- ffmpeg libplacebo cannot set cscale and ravu-zoom-ar-r3 crashes; mpv playback in amp may differ slightly from these filter renders.
- Trimmed run set: DN-at-1x via 2x+mitchell downscale in case B was not measured.

## Wicket / PixelClipper shaders

Same clip, inputs (A.mp4 / B.mp4 / ref.mkv), render and scoring commands as above; all renders decode with zero errors and 300 frames, no retries needed. Rendered one at a time (no parallel jobs). Shaders downloaded to ~/.config/mpv/shaders (none pre-existed): Debandit v3.4, TextureClarity, filmgrain-smooth-SDR-light from sup3rflyer/Wicket-shaders (GPL-3.0, (C) 2026 Agust Ari); PixelClipper from Artoriuz/glsl-pixel-clipper (MIT, (C) 2023 Joao Chrisostomo).

### Header notes
| Shader | Purpose | Hook | Required options | Tunables (defaults) | Load order |
|---|---|---|---|---|---|
| Debandit.glsl | Detect-and-reconstruct deband (plane fit + gated snap, chroma path, grid-deblock evidence for AVC web-dl). 16 passes, compute + SSBO noise-floor | MAIN (1/4-res analysis passes, full-res Apply) | `vo=gpu-next` (README); no explicit deband setting stated, built-in `deband` should be off to avoid double work (my inference). Needs compute/SSBO; sources up to 4096x2304 | db_strength 1.0, db_thr 1.5 (use 2 web, 4 brutal), db_flat, db_chroma, db_chroma_flat, db_ms, db_snr, db_aniso, db_snap, db_block, db_curve, db_fsnap (DYNAMIC); db_rw 16, db_rs 3, db_debug (DEFINE, recompile) | Header: list BEFORE CelFlare (same-hook passes run in load order). Not stated vs. upscalers; MAIN hooks run in load order, so placed before ArtCNN here |
| TextureClarity.glsl | Luma-only texture sharpening, variance-based grain/texture discrimination, Sobel edge exclusion, cinematic boost | LUMA | `vo=gpu-next` | tc_strength 12 (0-24), tc_coring 0.0005, tc_texture_thresh 0.02, tc_max_delta 0.012 (all DYNAMIC) | Runs at LUMA (native res, before MAIN upscalers), so it sharpens pre-upscale; none stated |
| filmgrain-smooth-SDR-light.glsl | Film grain synthesis, per-channel tap counts, Tukey luma response; SDR "light" preset (INTENSITY 0.05, SATURATION 0.10) | OUTPUT, COMPUTE 32x32 | `vo=gpu-next`, SDR output (HDR variants for PQ) | #define INTENSITY, SATURATION, GRAIN_RATE, per-channel TAPS/MULTIPLIER/MID/STEEPNESS (compile-time) | Last (OUTPUT, after scaling/CfL/sharpen); README says grain sits after CelFlare |
| PixelClipper.glsl | Anti-ringing clamp to pre-kernel neighbourhood; 3 passes: upscale AR, chroma AR, downscale AR | POSTKERNEL (x2), CHROMA_SCALED | none; `WHEN` gates make each pass fire only on up/down/chroma scaling; native libplacebo AR (`scaler-antiring`) makes it largely redundant per its README | `strength` 0.8 up / 1.0 down; `TWELVE_TAP_AR` define | After the scaler it clamps; with ArtCNN doing the 2x in MAIN, POSTKERNEL scaling is 1:1 so only the chroma pass fires |

## Case A: 640x360 @ 705 kbit/s -> 1280x720 (sorted by VMAF-NEG)
| Candidate | VMAF | VMAF-NEG | PSNR-Y dB | SSIM |
|---|---|---|---|---|
| ArtCNN_C4F16_DS (baseline) | 92.027 | 86.999 | 40.624 | 0.99303 |
| DS + PixelClipper | 91.985 | 86.991 | 40.620 | 0.99303 |
| Debandit -> DS | 91.984 | 86.991 | 40.616 | 0.99306 |
| DS + TextureClarity | 92.161 | 86.949 | 40.520 | 0.99288 |
| DS + filmgrain-smooth-SDR-light | 91.570 | 86.659 | 40.252 | 0.99100 |

## Case B: 1280x720 @ 1517 kbit/s, 1x (sorted by VMAF-NEG)
| Candidate | VMAF | VMAF-NEG | PSNR-Y dB | SSIM |
|---|---|---|---|---|
| none (lanczos passthrough) | 93.005 | 90.894 | 43.086 | 0.99488 |
| Debandit | 92.946 | 90.864 | 43.045 | 0.99495 |
| TextureClarity | 93.002 | 90.833 | 42.750 | 0.99471 |

### Findings
- Nothing here beats plain ArtCNN_C4F16_DS on the objective metrics. Every add-on is within 0.05 NEG of baseline except film grain (-0.34 NEG, -0.37 dB, SSIM 0.993 -> 0.991), which is expected: grain is added noise the reference does not contain, and these metrics cannot credit its perceptual masking.
- PixelClipper is a measured no-op here (NEG -0.008, PSNR -0.004 dB). With ArtCNN doing the 2x in MAIN, the final libplacebo scale is 1:1, so only its chroma pass can fire; the bytes differ but the metrics do not. It could only matter with a polar/ewa luma scaler, and libplacebo's native antiring already covers that.
- Debandit is metric-neutral (Case A -0.008 NEG, SSIM +0.00003; Case B -0.03 NEG, SSIM +0.00007, vs hdeband -0.10 NEG on the same clip). It behaves like hdeband but with slightly smaller metric cost; this clip has little banding, so a neutral score does not show whether it removes banding. It is also by far the heaviest (16 passes, compute + SSBO, 94 KB) and ran fine under ffmpeg's libplacebo/MoltenVK.
- TextureClarity trades fidelity for sharpness: VMAF +0.13 (sharpening gain) but NEG -0.05 and PSNR-Y -0.10 dB after DS, and at 1x -0.06 NEG, -0.34 dB, SSIM -0.0002. DS already restores detail, so a second sharpener adds only enhancement; it is the opposite of what a "faithful" restoration profile wants.
- Compared with the Crisp profile (DS -> CfL -> adaptive-sharpen: 92.64 VMAF / 86.91 NEG), TextureClarity gives similar sharpening gain with a slightly better NEG but no CfL; neither is a fidelity win over DS alone.

### Recommendation for amp "Compressed movie" (ArtCNN_C4F16_DS + CfL, hdeband first)
No change justified by these metrics. Do not add PixelClipper (no-op) or film grain (measured loss; only worth it as an opt-in aesthetic). TextureClarity is an opt-in sharpening choice at best, not a Compressed-movie default. Debandit is the only candidate worth a visual check as a hdeband replacement: it is metric-neutral like hdeband, handles chroma banding and AVC grid blocking (the real WhatsApp failure mode), but costs far more GPU and needs a banded clip to evaluate; metrics cannot decide that. Caveats from above (one clip, synthetic degradation, ffmpeg libplacebo without cscale) apply. Note the earlier section's profile row (hdeband -> DN -> CfL, 82.7 NEG) used DN; the DS-based variant of that profile was not measured.
