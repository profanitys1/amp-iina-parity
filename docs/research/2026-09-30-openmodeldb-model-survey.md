> Produced by a research subagent on 2026-09-30. The VideoToolbox limits in section C were re-verified with a probe on this Mac (see the gaia benchmark doc). Other claims have not been re-verified; each cites its source.

# Real-time upscaling survey: 1280x720 live-action -> ~3448x2164 on M1 Pro

Date: 2026-09-30. Read-only survey. No weights downloaded. Shallow clone of OpenModelDB at `scratchpad/omdb` (671 model records). Params/GFLOP figures marked **[derived]** were computed by me by instantiating the upstream architectures from the `spandrel` package (torch FlopCounter, 64x64 probe scaled to 1280x720; FLOPs = 2xMAC) -- not published numbers. Probe script: `scratchpad/src/cnt.py`. VideoToolbox values marked **[runtime probe]** were obtained by calling the macOS 27 SDK classes on this machine (`scratchpad/vt.m`).

## 0. Headline findings (read first)

1. **Budget arithmetic [derived].** ArtCNN C4F16 = ~12k params (README) -> ~22 GFLOP per 720p luma frame, measured 13.7 ms (your number) => ~1.6 TFLOP/s effective in mpv GLSL. C4F32 (~48k params, ~88 GFLOP) 39.1 ms => ~2.3 TFLOP/s. So the 16.7 ms budget is roughly **30-40 GFLOP/frame, i.e. about 15-20k MAC per source pixel (luma-only)**.
2. **Every OpenModelDB real-life model that is actually good for live-action is 30x-600x over that budget** at 720p input (table in section A2). Cheapest realistic RGB 2x (Compact nf64/nc16, SPAN-48) is ~1.1 TFLOP/frame; RealPLKSR default is ~13.6 TFLOP/frame. Even at 100% of a 10 TFLOP/s-class GPU they would run ~1/10 real time. They are viable only for **offline pre-rendering**, not playback.
3. **No pre-made real-time GLSL model trained on live-action exists** that I could find (GitHub search, see section A3). ArtCNN (anime), CuNNy (visual novels), Anime4K (anime) are all non-photo training sets. FSRCNNX and RAVU/NNEDI3 are the only NN/classical-prescaler GLSL families not advertised as anime-only.
4. **Apple VideoToolbox SR cannot do 2x at 720p (runtime probe).** Low-latency SR at 1280x720 input offers only **1.5x** (-> 1920x1080, 8-bit 4:2:0 only). The high-quality VTSuperResolutionScaler offers only **4x** with max 1920x1080 video input (-> 7680x4320, unusable for you).
5. Best "honest" real-time options: (i) ArtCNN C4F16 / C4F16_DS as-is, (ii) FSRCNNX 8-0-4-1, (iii) VT low-latency SR 1.5x -> then your own 1.8x final scaler, (iv) train a new ~12-40k-param ArtCNN-sized net on live-action data and export via ArtCNN/CuNNy-style GLSL generator.

## A. Ranked shortlist

Ranking = likelihood of actually achieving real-time on this Mac for clean live-action, then expected quality. Tier 1 = fits budget today. Tier 2 = needs work or unproven. Tier 3 = best quality fit but over budget (offline / reference only).

### Tier 1: fits 16.7 ms now (or plausibly)

| # | Name | Arch | Scale | Params | Format | License | Download | Real-time path | Cost evidence | Live-action fit |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | ArtCNN_C4F16_DS | ArtCNN "C" (conv stack + long skip) | 2x luma | ~12k | GLSL + ONNX | MIT | https://github.com/Artoriuz/ArtCNN/releases/tag/v1.6.2 (asset ArtCNN_C4F16_DS.glsl) | mpv GLSL as-is (`vo=gpu-next`) | Same topology as C4F16 => ~13.7 ms measured by you (assumption: DS variant same layer shapes; verify). README: C4F16 "lightweight option for real-time" | DS = "denoise and sharpen". Trained "aimed at anime" (README), but luma-only doubler with no GAN => conservative; sharpen may be mild help on soft 720p master. Try neutral vs DS. |
| 2 | ArtCNN_C4F16 (neutral) | ArtCNN C | 2x luma | ~12k | GLSL + ONNX | MIT | https://github.com/Artoriuz/ArtCNN/releases/tag/v1.6.2 | mpv GLSL as-is | 13.7 ms measured (user) | Neutral doubler = least risk of altering a clean master. Anime training set is the caveat. |
| 3 | ArtCNN_C4F16_DN | ArtCNN C | 2x luma | ~12k | GLSL + ONNX | MIT | same release | mpv GLSL as-is | as #2 (assumed) | "denoise and soften" -- not wanted for a clean master; listed for completeness |
| 4 | FSRCNNX_x2_8-0-4-1 | FSRCNN + local residual + recursive blocks (igv) | 2x luma | small (d=8; not stated in README, **unknown**) | GLSL | not stated in README (**unknown**) | https://github.com/igv/FSRCNN-TensorFlow/releases/tag/1.1 | mpv GLSL as-is (`glsl-shader=`) | No ms figure in repo. 8-0-4-1 is the smaller of the two 1.1 releases => expected cheaper than C4F16 (**unverified; benchmark it**) | Not advertised as anime (LineArt variant exists separately and README warns it looks "like an oil painting on natural content" => the non-LineArt builds are the natural-image ones). Trained with distortion augmentation (mild compression-artifact reduction). Best-documented non-anime NN GLSL. |
| 5 | FSRCNNX_x2_16-0-4-1 | same, d=16 | 2x luma | unknown | GLSL | unknown | same release | mpv GLSL as-is | unknown; larger than #4 | Higher quality than 8-0-4-1, cost must be measured |
| 6 | VT Low-Latency Super Resolution (VTLowLatencySuperResolutionScaler) | Apple ML (closed) | **1.5x only at 1280x720** | n/a | system framework (macOS 26+/27 SDK) | Apple SDK | `/Applications/Xcode.app/.../MacOSX27.0.sdk/.../VideoToolbox.framework/Headers/VTFrameProcessor_LowLatencySuperResolutionScaler.h` | VideoToolbox: 720p 420v -> 1080p 420v, then Metal/mpv scales 1080p -> 3448x2164 (1.8x) | No cost numbers in headers. "low-latency" by name; header warns model load may exceed a frame time. **Unmeasured** | Generic (not anime-specific as far as headers say). 8-bit 4:2:0 '420v' only => loses ProRes 10-bit precision and requires your pipeline to convert; BT.601 handling is yours. |

### Tier 2: real-time only with extra work / unproven

| # | Name | Arch | Scale | Params | Format | License | Download | Real-time path | Cost evidence | Fit |
|---|---|---|---|---|---|---|---|---|---|---|
| 7 | CuNNy (4x12 / 3x12 / "fast") | CuNNy conv net (funnyplanter) | 2x | small; README orders quality 8x32>4x32>4x24>4x16>4x12>3x12>2x12>fast | GLSL (mpv, plus dp4a variants) + own `mpv.py` pickle->GLSL exporter | see repo LICENSE | https://github.com/funnyplanter/CuNNy | GLSL as-is; dp4a variants need Vulkan (not macOS) | none measured on Apple. Pre-generated shaders in `mpv/` | Trained on visual-novel CG (README) => poor domain match. Main value: **converter + trainer you could retrain on live-action** |
| 8 | ArtCNN-architecture fine-tune/retrain on live-action | ArtCNN C4F16 | 2x luma | ~12k | train in PyTorch/TF (repo has Notebooks/ Scripts/), export ONNX; GLSL generated by repo | MIT | https://github.com/Artoriuz/ArtCNN | GLSL (same cost as #2) | 13.7 ms (same arch) | Only way to get a real-time model with correct domain prior. Needs a live-action dataset (e.g. your own clean masters). Effort: high. |
| 9 | ArtCNN Experiments: R4F32_YCbCr (+_DN/_DS) | ArtCNN "R4F32", YCbCr, chroma-aware | 2x | ~4 residual blocks x 32 filters (cost **unknown**, likely > C4F32) | GLSL | MIT | https://github.com/Artoriuz/ArtCNN/tree/main/GLSL/Experiments | mpv GLSL (`--cscale=bilinear`) | C4F32 is already 39 ms => assume **too slow** | Experimental; README says intended for 4:2:0 YCbCr. Likely over budget; measure before discarding |
| 10 | 1xSkinContrast-SuperUltraCompact | SRVGGNetCompact nf24 nc8 | 1x | **0.043M [derived]** | .pth (0.1 MB) | CC0-1.0 | https://openmodeldb.info/models/1x-SkinContrast-SuperUltraCompact | needs conversion: Compact->GLSL (no public tool found); RGB net => ~79 GFLOP/frame [derived] ~= 2-3x over budget | derived only | photo/skin contrast enhancer, 1x -- not an upscaler. Included only as the smallest photo-tagged RGB Compact in OMDB (shows the scale of network that would fit) |
| 11 | PiperSR 2x | 6 residual blocks x 64 ch, SiLU, PixelShuffle | 2x (locked 360p->720p) | 453k | Core ML FP16 (.mlpackage, 928 KB) | code AGPL-3.0 (repo API), weights CC BY 4.0 (MODEL_CARD) | https://github.com/ModelPiper/PiperSR | Core ML on ANE | **22.5 ms/frame for 640x360 on M2 Max** (README). At 1280x720 input that is ~4x pixels => ~90 ms [derived]. Too slow; M1 Pro slower than M2 Max. | Training data not stated in what I read; Set5 37.54 dB. Near-miss: would only work if source were downscaled, which defeats the point |

### Tier 3: best quality fit for live-action, NOT real-time here (offline transcode or reference)

| # | Name | Arch | Scale | Params / GFLOP@720p [derived] | Format | License | Download | Cost evidence | Fit |
|---|---|---|---|---|---|---|---|---|---|
| 12 | 2xLiveActionV1_SPAN | SPAN nf48 | 2x | ~0.4M deployed (2.22M in training-form module) / ~0.8-1.1 TFLOP | onnx, pth (8.9 MB) | CC-BY-NC-SA-4.0 | https://openmodeldb.info/models/2x-LiveActionV1-SPAN | 30-50x over budget. Author states it is trained for live action & digital video, no denoise, consistency loss to avoid colour shift | **Best domain match in OMDB.** Non-commercial license. |
| 13 | 2x Parimg Compact / 4x LSDIR Compact v2 / realesr-general-x4v3 | SRVGGNetCompact nf64 nc16 / nc32 | 2x / 4x | 0.60M / 1.21M; 1.10 / 2.2 TFLOP | pth (+ MLX safetensors for general-x4v3) | CC-BY-4.0 / BSD-3 | https://openmodeldb.info/models/2x-ParimgCompact ; https://openmodeldb.info/models/4x-LSDIRCompact-v2 ; https://openmodeldb.info/models/4x-realesr-general-x4v3 | ~65x over budget. MLX-Swift port `xocialize/realesrgan-mlx-swift` (MIT, tile-based, no fps stated in README) | photo-trained compact nets; the cheapest "serious" RGB family |
| 14 | 2x VHS2HD / 1xDeH264 / 4xNomosWebPhoto RealPLKSR | RealPLKSR dim64 nb28 ks17 | 2x/1x/4x | 7.4M / ~13.6 TFLOP | pth, onnx, safetensors | CC-BY-SA / CC-BY-4.0 | https://openmodeldb.info/models/2x-VHS2HD | ~800x over budget | VHS2HD is VHS-restoration, wrong for clean master |
| 15 | 2x OmniSR DF2K | OmniSR nf64 | 2x | 0.74M / ~1.5 TFLOP | pth | Apache-2.0 | https://openmodeldb.info/models/2x-OmniSR-DF2K | ~90x over budget | research model (DF2K photos) |

Real-time conversion note: no public .pth/.onnx -> mpv-GLSL converter for Compact/SPAN/RealPLKSR was found (section A3). Existing GLSL exporters are model-specific (ArtCNN repo, CuNNy `mpv.py`, igv FSRCNN scripts).

### A2. Architecture cost table

Column "GFLOP@720p in" is my derived FLOP count for one 1280x720 RGB input frame with the stated config (upstream `spandrel` implementations; `scratchpad/src/cnt.py`). Budget ~30-40 GFLOP/frame.

| Architecture / config | Params [derived] | GFLOP per 720p frame [derived] | x over budget (vs ~35) | Note |
|---|---|---|---|---|
| ArtCNN C4F16 (luma) | ~12k (README) | ~22 (from params) | 0.6 (measured 13.7 ms) | reference |
| ArtCNN C4F32 (luma) | ~48k (README) | ~88 | 2.5 (measured 39.1 ms) | reference |
| Compact nf24 nc8 x1 | 0.043M | 79 | 2.3 | SuperUltraCompact |
| Compact nf64 nc16 x2 | 0.601M | 1103 | 32 | |
| Compact nf64 nc16 x4 | 0.621M | 1141 | 33 | |
| Compact nf64 nc32 x4 (realesr-general-x4v3) | 1.213M | 2228 | 64 | |
| SPAN nf48 x2 (spandrel module, eval) | 2.221M as loaded (over-parameterised Conv3XC); ~0.4M when re-parameterised | 1079 | ~31 | deployed cost should be lower than this FlopCounter figure if Conv3XC is fused; unverified |
| OmniSR nf64 x2 | 0.740M | 1498 | 43 | |
| RealPLKSR dim32 nb12 ks13 x2 | 0.702M | 1289 | 37 | hypothetical small config (not an OMDB model) |
| RealPLKSR dim48 nb12 ks13 x2 | 1.575M | 2894 | 83 | hypothetical |
| RealPLKSR dim64 nb28 ks17 x2 (default) | 7.369M | 13558 | 387 | what OMDB RealPLKSR models use |
| DAT / HAT / ATD / SwinIR / SRFormer / RGT / DRCT / GRL | multi-M (10-20M typical; HAT 20.8M per PiperSR table) | >>10,000 | hundreds+ | transformer archs, not considered; not instantiated |
| ESRGAN RRDB (nf64 nb23) | ~16.7M (Real-ESRGAN row in PiperSR README) | not computed | hundreds+ | |

Published speed numbers for these archs on Apple Silicon: **none found** from primary sources. Community/vendor only: PiperSR README (22.5 ms for 360p->720p on M2 Max ANE, vendor benchmark, unverified by me). Upstream SPAN README only states runtime-track wins in NTIRE challenges on NVIDIA hardware (https://github.com/hongyuanyu/SPAN); no Apple numbers. Real-ESRGAN MLX port README lists no fps (https://github.com/xocialize/realesrgan-mlx-swift).

### A3. GitHub search results (beyond OMDB)

- **ArtCNN** https://github.com/Artoriuz/ArtCNN (MIT, pushed 2026-09-13, latest release v1.6.2 2026-03-14). GLSL: C4F16, C4F16_DN, C4F16_DS, C4F32, C4F32_DN, C4F32_DS, plus Experiments R4F32_YCbCr[_DN|_DS]. ONNX also: R8F64 (~926k), R16F96 (~4M), Chroma/JPEG variants, Experiments incl. R16F128_RGB_GAN_4x, R8F64_DEINT, R8F64_YCbCr_DEHALO/RESTORER. README: "aimed at anime content"; R models are ONNX-only (non real-time). Also `Artoriuz/iree-inferencer` (IREE-based inference, 0 stars, 2025).
- **FSRCNNX** https://github.com/igv/FSRCNN-TensorFlow releases 1.0/1.1 (GLSL 8-0-4-1, 16-0-4-1 + checkpoints_params.7z).
- **CuNNy** https://github.com/funnyplanter/CuNNy (*169): has training code + `mpv.py` exporter + Magpie effects; webapp https://funnyplanter.github.io/ generates other backends. Domain: visual novels.
- **Anime4K** https://github.com/bloc97/Anime4K (*21k), **Anime4KMetal** https://github.com/imxieyi/Anime4KMetal (Apple Metal port, anime only).
- **mpv-prescalers** https://github.com/bjin/mpv-prescalers (NNEDI3, RAVU; `gather/` and `compute/` variants).
- **AnimeJaNai** https://github.com/the-database/mpv-upscale-2x_animejanai: Compact ONNX via TensorRT/DirectML, Windows only, per its README -> not usable on macOS.
- **vs-mlrt** https://github.com/AmusementClub/vs-mlrt lists "Apple SoC: vsort-coreml" (ONNX Runtime CoreML) -- runs ONNX models in VapourSynth (offline or a VS-fed pipeline), not mpv GLSL.
- **Core ML / MLX**: `ModelPiper/PiperSR` (above), `xocialize/realesrgan-mlx-swift` (SRVGGNetCompact x4, MIT, tile-based), `Targhib49/SuperResolution-CoreML-Demo` (conversion demo, 1 star). HF: `mlx-community/Real-ESRGAN-general-x4v3` (cited by the MLX repo README; not fetched).
- **Searches with no hits**: `gh search code` for `//!HOOK LUMA` + COMPUTE, onnx/pth/safetensors -> glsl/mpv converter, "compact to glsl", "onnx2glsl": zero repositories returned (note: GitHub code search via gh returned empty for all four; treat as "not found", not "does not exist"). Web search (community/secondary) also surfaced no SPAN/Compact->GLSL converter.
- Not evaluated (found in results, tangential): `ajccarlson/flux-fidelity` (WebGPU video upscaling, *3), `Cryspia/fsrcnnx-cudnn`, `navik677/mpv-upscaler`.


## B. OpenModelDB real-life / video-relevant models (scale 1x/2x/4x)

Source: https://github.com/OpenModelDB/open-model-database (data/models/*.json, data/architectures.json, data/tags.json). URL column = https://openmodeldb.info/models/<json filename>. Filter described in section D.

| Name | Arch | Scale | Size hyperparams | Tags | License | Formats | First file | URL | Author |
|---|---|---|---|---|---|---|---|---|---|
|  4xNomos8k_atd_jpg | atd | 4x |  | general-upscaler, photo, restoration | CC-BY-4.0 | pth,safetensors | 81.9MB | https://openmodeldb.info/models/4x-Nomos8k-atd-jpg | helaman |
|  4xRealWebPhoto_v3_atd | atd | 4x |  | general-upscaler, photo, restoration | CC-BY-4.0 | pth,safetensors | 81.6MB | https://openmodeldb.info/models/4x-RealWebPhoto-v3-atd | helaman |
| 4xNomos2_hq_atd | atd | 4x |  | general-upscaler, photo | CC-BY-4.0 | pth,safetensors | 81.8MB | https://openmodeldb.info/models/4x-Nomos2-hq-atd | helaman |
| 4xNomosWebPhoto_atd | atd | 4x | 210dim/16w/256cat | photo, restoration | CC-BY-4.0 | pth,safetensors | 81.9MB | https://openmodeldb.info/models/4x-NomosWebPhoto-atd | helaman |
| cainREALTIME | cain | 2x |  | photo | MIT | pth | 18.9MB | https://openmodeldb.info/models/2x-cainREALTIME | hubert |
| 1xSkinContrast-High-SuperUltraCompact | compact | 1x | 24nf/8nc | ai-generated, cgi, colorization, faces, game-screenshots, game-textures, photo, restoration, texture-generation, video-frame | CC0-1.0 | pth | 0.1MB | https://openmodeldb.info/models/1x-SkinContrast-High-SuperUltraCompact | brigadeiro |
| 1xSkinContrast-HighAlternative-SuperUltraCompact | compact | 1x | 24nf/8nc | ai-generated, cgi, colorization, faces, game-screenshots, game-textures, photo, restoration, texture-generation, video-frame | CC0-1.0 | pth | 0.1MB | https://openmodeldb.info/models/1x-SkinContrast-HighAlternative-SuperUltraCompact | brigadeiro |
| 1xSkinContrast-SuperUltraCompact | compact | 1x | 24nf/8nc | ai-generated, cgi, colorization, faces, game-screenshots, game-textures, photo, restoration, texture-generation, video-frame | CC0-1.0 | pth | 0.1MB | https://openmodeldb.info/models/1x-SkinContrast-SuperUltraCompact | brigadeiro |
| Book Compact | compact | 1x | 2,27mb | restoration, text | CC-BY-SA-4.0 | safetensors | 2.3MB | https://openmodeldb.info/models/1x-Book-Compact | asterixcool |
| ExposureCorrection compact | compact | 1x | 64nf/16nc | restoration | CC-BY-4.0 | pth | 2.3MB | https://openmodeldb.info/models/1x-ExposureCorrection-compact | helaman |
| NES-Composite-2-RGB-Small | compact | 1x |  | debanding, denoise, game-screenshots, restoration, video-frame | MIT | pth | 8MB | https://openmodeldb.info/models/1x-NES-Composite-2-RGB-Small | pokepress |
| OverExposureCorrection compact | compact | 1x | 64nf/16nc | restoration | CC-BY-4.0 | pth | 2.3MB | https://openmodeldb.info/models/1x-OverExposureCorrection-compact | helaman |
| Sega Genesis Cleanup-Small | compact | 1x |  | compression-removal, denoise, game-screenshots, restoration, video-frame | MIT | pth | 8MB | https://openmodeldb.info/models/1x-Sega-Genesis-Cleanup-Small | pokepress |
| UnderExposureCorrection compact | compact | 1x | 64nf/16nc | restoration | CC-BY-4.0 | pth | 2.3MB | https://openmodeldb.info/models/1x-UnderExposureCorrection-compact | helaman |
| Where On Earth-Deinterlace Fix-Small | compact | 1x |  | cartoon, restoration, video-frame | MIT | pth | 2.3MB | https://openmodeldb.info/models/1x-WhereOnEarthDeintFixS | pokepress |
| 2xHFA2kAVCCompact | compact | 2x |  | anime, video-frame | CC-BY-4.0 | pth | 4.8MB | https://openmodeldb.info/models/2x-HFA2kAVCCompact | helaman |
| 90s Sonic 2x (Small) | compact | 2x |  | cartoon, restoration, video-frame | MIT | pth | 2.4MB | https://openmodeldb.info/models/2x-90s-Sonic | pokepress |
| NomosUni compact otf medium | compact | 2x | 64nf/16nc | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 2.4MB | https://openmodeldb.info/models/2x-NomosUni-compact-otf-medium | helaman |
| Parimg Compact | compact | 2x | 64nf/16nc | photo | CC-BY-4.0 | pth | 2.4MB | https://openmodeldb.info/models/2x-ParimgCompact | helaman |
| RealESRGANv2 AnimeVideo xs-x2 | compact | 2x | 64nf/16nc | anime, cartoon, compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 2.4MB | https://openmodeldb.info/models/2x-realesrganv2-animevideo-xsx2 | xinntao |
| Where On Earth-Upscale-Small | compact | 2x |  | cartoon, general-upscaler, video-frame | MIT | pth | 2.4MB | https://openmodeldb.info/models/2x-Where-On-Earth-Upscale-Small | pokepress |
| LSDIR Compact C | compact | 4x | 64nf/16nc | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | pth | 5MB | https://openmodeldb.info/models/4x-LSDIRCompactC | helaman |
| LSDIR Compact C3 | compact | 4x | 64nf/16nc | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | pth | 5MB | https://openmodeldb.info/models/4x-LSDIRCompactC3 | helaman |
| LSDIR Compact R | compact | 4x | 64nf/16nc | compression-removal, photo, restoration | CC-BY-4.0 | pth | 5MB | https://openmodeldb.info/models/4x-LSDIRCompactR | helaman |
| LSDIR Compact R3 | compact | 4x | 64nf/16nc | photo, restoration | CC-BY-4.0 | pth | 5MB | https://openmodeldb.info/models/4x-LSDIRCompactR3 | helaman |
| LSDIR Compact v2 | compact | 4x | 64nf/16nc | photo, restoration | CC-BY-4.0 | pth | 2.5MB | https://openmodeldb.info/models/4x-LSDIRCompact-v2 | helaman |
| LSDIR Compact | compact | 4x | 64nf/16nc | photo | CC-BY-4.0 | pth | 5MB | https://openmodeldb.info/models/4x-LSDIRCompact | helaman |
| LSDIRCompactN | compact | 4x | 64nf/16nc | photo | CC-BY-4.0 | pth | 5MB | https://openmodeldb.info/models/4x-LSDIRCompactN | helaman |
| RealESR AnimeVideo v3 | compact | 4x | 64nf/16nc | anime, cartoon, compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 2.5MB | https://openmodeldb.info/models/4x-realesr-animevideo-v3 | xinntao |
| RealESR General WDN x4 v3 | compact | 4x | 64nf/32nc | compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 4.8MB | https://openmodeldb.info/models/4x-realesr-general-wdn-x4v3 | xinntao |
| RealESR General x4 v3 | compact | 4x | 64nf/32nc | compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 4.8MB | https://openmodeldb.info/models/4x-realesr-general-x4v3 | xinntao |
| RealESRGANv2 AnimeVideo xs-x4 | compact | 4x | 64nf/16nc | anime, cartoon, compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 2.5MB | https://openmodeldb.info/models/4x-realesrganv2-animevideo-xsx4 | xinntao |
| Rybu | compact | 4x | 64nf/16nc | general-upscaler, photo, restoration | CC0-1.0 | pth | 5MB | https://openmodeldb.info/models/4x-Rybu | musl |
| 4xFFHQDAT | dat | 4x |  | compression-removal, faces, jpeg, photo, restoration | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-FFHQDAT | helaman |
| 4xFFHQLDAT | dat | 4x |  | compression-removal, denoise, faces, jpeg, photo, restoration | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-FFHQLDAT | helaman |
| 4xFaceUpDAT | dat | 4x |  | faces, photo | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-FaceUpDAT | helaman |
| 4xFaceUpLDAT | dat | 4x |  | compression-removal, denoise, faces, jpeg, photo, restoration | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-FaceUpLDAT | helaman |
| 4xFaceUpSharpDAT | dat | 4x |  | faces, photo | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-FaceUpSharpDAT | helaman |
| 4xFaceUpSharpLDAT | dat | 4x |  | compression-removal, denoise, faces, jpeg, photo, restoration | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-FaceUpSharpLDAT | helaman |
| 4xLSDIRDAT | dat | 4x |  | compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-LSDIRDAT | helaman |
| 4xNomos2_hq_dat2 | dat | 4x |  | general-upscaler, photo | CC-BY-4.0 | onnx,pth | 140.1MB | https://openmodeldb.info/models/4x-Nomos2-hq-dat2 | helaman |
| 4xNomos8kDAT | dat | 4x |  | anime, compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | onnx,pth | 309.3MB | https://openmodeldb.info/models/4x-Nomos8kDAT | helaman |
| 4xNomosUniDAT2_box | dat | 4x |  | anime, general-upscaler, photo | CC-BY-4.0 | pth | 140.3MB | https://openmodeldb.info/models/4x-NomosUniDAT2-box | helaman |
| 4xNomosUniDAT_bokeh_jpg | dat | 4x |  | anime, compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-NomosUniDAT-bokeh-jpg | helaman |
| 4xRealWebPhoto_v4_dat2 | dat | 4x |  | general-upscaler, photo, restoration | CC-BY-4.0 | onnx,pth,safetensors | 140.2MB | https://openmodeldb.info/models/4x-RealWebPhoto-v4-dat2 | helaman |
| 4xReal_SSDIR_DAT_GAN | dat | 4x |  | compression-removal, denoise, jpeg, manga, photo, restoration | CC-BY-4.0 | pth | 154.7MB | https://openmodeldb.info/models/4x-Real-SSDIR-DAT-GAN | helaman |
| 4xSSDIRDAT | dat | 4x |  | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-SSDIRDAT | helaman |
| DWTP DS dat2 v3 2 | dat | 4x | medium/s64|8x32/64nf/180dim/2.0ef/1conv | restoration | CC-BY-4.0 | pth | 140.2MB | https://openmodeldb.info/models/4x-DWTP-DS-dat2-v3-2 | umzi-x-dead |
| DWTP DS dat2 v3 | dat | 4x | medium/s64|8x32/64nf/180dim/2.0ef/1conv | dehalftone, restoration | CC-BY-4.0 | pth | 140.2MB | https://openmodeldb.info/models/4x-DWTP-DS-dat2-v3 | umzi-x-dead |
| NomosUniDAT2 multijpg ldl sharp | dat | 4x | medium/s64|8x32/64nf/180dim/2.0ef/1conv | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 140.2MB | https://openmodeldb.info/models/4x-NomosUniDAT2-multijpg-ldl-sharp | helaman |
| NomosUniDAT2 multijpg ldl | dat | 4x | medium/s64|8x32/64nf/180dim/2.0ef/1conv | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 140.2MB | https://openmodeldb.info/models/4x-NomosUniDAT2-multijpg-ldl | helaman |
| NomosUniDAT_otf | dat | 4x |  | general-upscaler, photo | CC-BY-4.0 | pth | 154.6MB | https://openmodeldb.info/models/4x-NomosUniDAT-otf | helaman |
| UltraSharpV2 | dat | 4x | DAT2 | ai-generated, anime, anti-aliasing, compression-removal, deblur, game-textures, general-upscaler, jpeg, photo, restoration, text | CC-BY-NC-SA-4.0 | onnx,safetensors | 139.7MB | https://openmodeldb.info/models/4x-UltraSharpV2 | kim2091 |
| 4xNomos2_hq_drct-l | drct | 4x |  | general-upscaler, photo | CC-BY-4.0 | pth,safetensors | 242.7MB | https://openmodeldb.info/models/4x-Nomos2-hq-drct-l | helaman |
| 4xRealWebPhoto_v4_drct-l | drct | 4x |  | photo, restoration | CC-BY-4.0 | onnx,pth | 242.7MB | https://openmodeldb.info/models/4x-RealWebPhoto-v4-drct-l | helaman |
| 2xHFA2kAVCEDSR_M | edsr | 2x | EDSR-M | anime, video-frame | CC-BY-4.0 | pth | 11MB | https://openmodeldb.info/models/2x-HFA2kAVCEDSR-M | helaman |
| Artifacts Dithering alsa | esrgan | 1x | 64nf/23nb | dedither, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-artifacts-dithering-alsa | alsa |
| BSChroma | esrgan | 1x | 64nf/23nb | deblur, restoration | GPL-3.0-only | pth | 66.6MB | https://openmodeldb.info/models/1x-BSChroma | blackscout |
| BSLuma | esrgan | 1x | 64nf/23nb | restoration | GPL-3.0-only | pth | 66.6MB | https://openmodeldb.info/models/1x-BSLuma | blackscout |
| BaldrickVHSFix V0.2 | esrgan | 1x | 64nf/23nb | video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-BaldrickVHSFixV0-2 | nimrodzorg |
| Bandage Smooth | esrgan | 1x | 64nf/23nb | debanding, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-Bandage-Smooth | mutin-choler |
| DeBLR | esrgan | 1x | 64nf/23nb | deblur, restoration | ? | pth | 66.6MB | https://openmodeldb.info/models/1x-DeBLR | blackscout |
| DeBink Lite | esrgan | 1x | 32nf/12nb | compression-removal, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 20MB | https://openmodeldb.info/models/1x-DeBink-Lite | kim2091 |
| DeBink v4 | esrgan | 1x | 64nf/23nb | compression-removal, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-DeBink-v4 | kim2091 |
| DeBink v5 | esrgan | 1x | 64nf/23nb | compression-removal, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-DeBink-v5 | kim2091 |
| DeBink v6 | esrgan | 1x | 64nf/23nb | compression-removal, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-DeBink-v6 | kim2091 |
| DeEdge | esrgan | 1x | 64nf/23nb | dehalo, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-DeEdge | mutin-choler |
| DeJpeg Fatality PlusULTRA! | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-DeJpeg-Fatality-PlusULTRA | twittman |
| DeRoqBeta-lite | esrgan | 1x | 32nf/12nb | compression-removal, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 20MB | https://openmodeldb.info/models/1x-DeRoqBeta-lite | kim2091 |
| DeSharpen | esrgan | 1x | 64nf/23nb | restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-DeSharpen | loinne |
| Debandurh_FS Ultra-lite | esrgan | 1x | 8nf/3nb | debanding, restoration | CC-BY-NC-SA-4.0 | pth | 2.7MB | https://openmodeldb.info/models/1x-Debandurh-FS-Ultra-lite | twittman |
| DitherDeleter Smooth | esrgan | 1x | 64nf/23nb | dedither, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-DitherDeleterV2-Smooth | mutin-choler |
| DitherDeleterV3 Smooth | esrgan | 1x | 64nf/23nb | dedither, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-DitherDeleterV3-Smooth | mutin-choler |
| Fatality DeBlur | esrgan | 1x | 64nf/23nb | deblur, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-Fatality-DeBlur | twittman |
| Film-Degrainer_1-000 | esrgan | 1x | 47nf/17nb | denoise, restoration | CC0-1.0 | pth | 37.8MB | https://openmodeldb.info/models/1x-Film-Degrainer-1-000 | tika |
| Filmify4K v2 | esrgan | 1x | 64nf/23nb | compression-removal, restoration, video-frame | CC0-1.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-Filmify4K-v2 | muf |
| Focus Moderate | esrgan | 1x | 64nf/23nb | deblur, restoration | CC-BY-NC-SA-4.0 | pth | 66.7MB | https://openmodeldb.info/models/1x-Focus-Moderate | kim2091 |
| Focus | esrgan | 1x | 64nf/23nb | deblur, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-Focus | kim2091 |
| ISO denoise v1 | esrgan | 1x | 64nf/23nb | denoise, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-ISO-denoise-v1 | alpha |
| ISO denoise v2 | esrgan | 1x | 64nf/23nb | denoise, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-ISO-denoise-v2 | alpha |
| JPEGDestroyer | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | GPL-3.0-only | pth | 66.6MB | https://openmodeldb.info/models/1x-JPEGDestroyer | blackscout |
| JPG (00-20%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-00-20 | blueamulet |
| JPG (00-20%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-00-20-alsa | alsa |
| JPG (20-40%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-20-40 | blueamulet |
| JPG (20-40%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-20-40-alsa | alsa |
| JPG (40-60%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-40-60 | blueamulet |
| JPG (40-60%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-40-60-alsa | alsa |
| JPG (60-80%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-60-80 | blueamulet |
| JPG (60-80%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-60-80-alsa | alsa |
| JPG (80-100%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-80-100 | blueamulet |
| JPG (80-100%) | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-JPG-80-100-alsa | alsa |
| KDM003 scans | esrgan | 1x | 64nf/23nb | restoration | ? | pth | 66.6MB | https://openmodeldb.info/models/1x-KDM003-scans | boxdrop |
| Kim2091 DeJpeg v0 | esrgan | 1x | 16nf/8nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 9.1MB | https://openmodeldb.info/models/1x-Kim2091-DeJpeg-v0 | kim2091 |
| NMKD Jaywreck3 (Lite) | esrgan | 1x | 32nf/12nb | compression-removal, jpeg, restoration | WTFPL | pth | 20MB | https://openmodeldb.info/models/1x-NMKD-Jaywreck3-Lite | nmkd |
| NMKD Jaywreck3-Soft (Lite) | esrgan | 1x | 32nf/12nb | compression-removal, jpeg, restoration | WTFPL | pth | 20MB | https://openmodeldb.info/models/1x-NMKD-Jaywreck3-Soft-Lite | nmkd |
| NMKD h264Texturize | esrgan | 1x | 64nf/23nb | compression-removal, restoration, video-frame | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-NMKD-h264Texturize | nmkd |
| NoiseToner Poisson Detailed | esrgan | 1x | 64nf/23nb | denoise, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-NoiseToner-Poisson-Detailed | mutin-choler |
| NoiseToner Poisson Soft | esrgan | 1x | 64nf/23nb | denoise, restoration | ? | pth | 66.6MB | https://openmodeldb.info/models/1x-NoiseToner-Poisson-Soft | mutin-choler |
| NoiseToner Poisson | esrgan | 1x | 64nf/23nb | denoise, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-NoiseToner-Poisson | mutin-choler |
| NoiseToner Uniform Detailed | esrgan | 1x | 64nf/23nb | denoise, restoration | ? | pth | 66.6MB | https://openmodeldb.info/models/1x-NoiseToner-Uniform-Detailed | mutin-choler |
| NoiseToner Uniform Soft | esrgan | 1x | 64nf/23nb | denoise, restoration | ? | pth | 66.6MB | https://openmodeldb.info/models/1x-NoiseToner-Uniform-Soft | mutin-choler |
| NoiseToner Uniform | esrgan | 1x | 64nf/23nb | denoise, restoration | WTFPL | pth | 66.6MB | https://openmodeldb.info/models/1x-NoiseToner-Uniform | mutin-choler |
| Plants | esrgan | 1x | 64nf/23nb | photo | CC0-1.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-Plants | muf |
| ReFocus Cleanly | esrgan | 1x | 64nf/23nb | deblur, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-ReFocus-Cleanly | twittman |
| ReFocus V3 | esrgan | 1x | 64nf/23nb | deblur, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-ReFocus-V3 | twittman |
| RedImage10000 | esrgan | 1x | 64nf/23nb | cgi, photo | CC-BY-NC-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-RedImage | 3majsie1995 |
| RoQ_nRoll | esrgan | 1x | 64nf/23nb | compression-removal, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-RoQ-nRoll | kim2091 |
| SBDV-DeJPEG Lite | esrgan | 1x | 32nf/12nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 20MB | https://openmodeldb.info/models/1x-SBDV-DeJPEG-Lite | joey |
| SaiyaJin DeJpeg | esrgan | 1x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-SaiyaJin-DeJpeg | twittman |
| ToonVHS | esrgan | 1x | 64nf/23nb | anime, cartoon, video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-ToonVHS | redslam |
| UnResize V3 | esrgan | 1x | 64nf/23nb | deblur, restoration | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-UnResize-V3 | twittman |
| VHS-Sharpen | esrgan | 1x | 64nf/23nb | video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-VHS-Sharpen | rtx-2080-ti-hoarder |
| cinepak | esrgan | 1x | 64nf/23nb | compression-removal, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 66.6MB | https://openmodeldb.info/models/1x-cinepak | twittman |
| mdeblur | esrgan | 1x | 64nf/23nb | deblur, restoration | ? | pth | 66.6MB | https://openmodeldb.info/models/1x-mdeblur | lyonhrt |
| BSRGANx2 | esrgan | 2x | 64nf/23nb | compression-removal, faces, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 66.8MB | https://openmodeldb.info/models/2x-BSRGAN | cszn |
| BSWolly | esrgan | 2x | 64nf/23nb | cgi, restoration | GPL-3.0-only | pth | 66.8MB | https://openmodeldb.info/models/2x-BS-Wolly | blackscout |
| DeGif | esrgan | 2x | 64nf/23nb | compression-removal, dedither, restoration | WTFPL | pth | 66.8MB | https://openmodeldb.info/models/2x-DeGif | nmkd |
| DigiGradients Lite | esrgan | 2x | 32nf/12nb | debanding, restoration | CC-BY-NC-SA-4.0 | pth | 20.1MB | https://openmodeldb.info/models/2x-DigiGradients-Lite | saurusx |
| NomosUni esrgan multijpg | esrgan | 2x | 64nf/23nb | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/2x-NomosUni-esrgan-multijpg | helaman |
| RealESRGAN_x2Plus | esrgan | 2x | 64nf/23nb | compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 67MB | https://openmodeldb.info/models/2x-realesrgan-x2plus | xinntao |
| VHS upscale and denoise Film | esrgan | 2x | 64nf/23nb | denoise, restoration, video-frame | CC-BY-NC-SA-4.0 | pth | 66.8MB | https://openmodeldb.info/models/2x-VHS-upscale-and-denoise-Film | itewreed |
| 4xLSDIR | esrgan | 4x |  | photo | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-LSDIR | helaman |
| 4xLSDIRplus | esrgan | 4x |  | compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-LSDIRplus | helaman |
| 4xLSDIRplusC | esrgan | 4x |  | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-LSDIRplusC | helaman |
| 4xLSDIRplusN | esrgan | 4x |  | photo | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-LSDIRplusN | helaman |
| 4xLSDIRplusR | esrgan | 4x |  | compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-LSDIRplusR | helaman |
| 4xNomos2_otf_esrgan | esrgan | 4x | 64nf/23nb | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | onnx,pth,safetensors | 33.6MB | https://openmodeldb.info/models/4x-Nomos2-otf-esrgan | helaman |
| 4xNomosWebPhoto_esrgan | esrgan | 4x | 64nf/23nb | photo, restoration | CC-BY-4.0 | onnx,pth,safetensors | 33.6MB | https://openmodeldb.info/models/4x-NomosWebPhoto-esrgan | helaman |
| BSRGAN | esrgan | 4x | 64nf/23nb | compression-removal, faces, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 67MB | https://openmodeldb.info/models/4x-BSRGAN | cszn |
| Box | esrgan | 4x | 64nf/23nb | photo | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-Box | buildist |
| Cat_Patch | esrgan | 4x | 64nf/23nb | photo, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-Cat-Patch | twittman |
| CountryRoads | esrgan | 4x | 64nf/23nb | general-upscaler | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-CountryRoads | ezogaming |
| DeIndeo | esrgan | 4x | 64nf/23nb | compression-removal, restoration, video-frame | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-DeIndeo | wild-west-quest |
| Deoldify | esrgan | 4x | 64nf/23nb | colorization, photo | CC0-1.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-Deoldify | rastrum |
| FSDedither | esrgan | 4x | 64nf/23nb | dedither, restoration | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-FSDedither | jacob |
| FuzzyBox | esrgan | 4x | 64nf/23nb | general-upscaler | CC-BY-NC-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-FuzzyBox | blueamulet |
| Ground | esrgan | 4x | 64nf/23nb | game-textures, photo, restoration | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-Ground | tldr-coder |
| Jaypeg90 | esrgan | 4x | 64nf/23nb | compression-removal, jpeg, restoration | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-Jaypeg90 | jacob |
| LADDIER1 | esrgan | 4x | 64nf/23nb | deblur, denoise, restoration | ? | pth | 66.9MB | https://openmodeldb.info/models/4x-LADDIER1 | alexander-syring |
| Lollypop | esrgan | 4x | 64nf/23nb | dedither, general-upscaler, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-Lollypop | lyonhrt |
| MinecraftAlphaUpscaler with Good data | esrgan | 4x | 64nf/23nb | game-screenshots, restoration | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-MinecraftAlphaUpscaler-with-Good-data | washed-up |
| Minepack | esrgan | 4x | 64nf/23nb | game-screenshots, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-Minepack | blackscout |
| NMKD PatchySharp | esrgan | 4x | 64nf/23nb | cgi, compression-removal, jpeg, restoration | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-NMKD-PatchySharp | nmkd |
| NMKD Siax ("CX") | esrgan | 4x | 64nf/23nb | compression-removal, general-upscaler, jpeg, restoration | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-NMKD-Siax-CX | nmkd |
| NMKD Superscale | esrgan | 4x | 64nf/23nb | denoise, photo, restoration | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-NMKD-Superscale | nmkd |
| Nickelback | esrgan | 4x | 64nf/23nb | photo | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-Nickelback | blackscout |
| NickelbackFS | esrgan | 4x | 64nf/23nb | photo | GPL-3.0-only | pth | 67MB | https://openmodeldb.info/models/4x-NickelbackFS | blackscout |
| Nickelfront | esrgan | 4x | 64nf/23nb | photo, restoration | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-Nickelfront | blackscout |
| Nomos8kSC | esrgan | 4x | 64nf/23nb | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-Nomos8kSC | helaman |
| PackCraft v4 | esrgan | 4x | 64nf/23nb | game-screenshots, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-PackCraft-v4 | joey |
| RealESRGAN_x4Plus Anime 6B | esrgan | 4x | 64nf/6nb | anime, cartoon, compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 17.9MB | https://openmodeldb.info/models/4x-realesrgan-x4plus-anime-6b | xinntao |
| RealESRGAN_x4Plus | esrgan | 4x | 64nf/23nb | compression-removal, general-upscaler, jpeg, photo, research, restoration | BSD-3-Clause | pth | 67MB | https://openmodeldb.info/models/4x-realesrgan-x4plus | xinntao |
| RealSR DF2K (JPEG) | esrgan | 4x | 64nf/23nb | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-realsr-df2k-jpeg | jixiaozhong |
| RealSR DF2K | esrgan | 4x | 64nf/23nb | general-upscaler, photo, research | Apache-2.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-realsr-df2k | jixiaozhong |
| RealSR DPED | esrgan | 4x | 64nf/23nb | general-upscaler, photo, research | Apache-2.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-realsr-dped | jixiaozhong |
| Realistic Misc | esrgan | 4x | 64nf/23nb | general-upscaler, photo | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-Misc | alsa |
| RealisticRescaler | esrgan | 4x | 64nf/23nb | compression-removal, dds, game-textures, jpeg, photo, restoration | WTFPL | pth | 134MB | https://openmodeldb.info/models/4x-RealisticRescaler | mutin-choler |
| Rek's Effeks Photoanime v2 | esrgan | 4x | 64nf/23nb | compression-removal, jpeg, restoration | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-Rek-s-Effeks-Photoanime-v2 | rek |
| Remacri | esrgan | 4x | 64nf/23nb | general-upscaler | CC-BY-NC-SA-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-Remacri | foolhardy |
| SGI | esrgan | 4x | 64nf/23nb | cgi, dedither, restoration | GPL-3.0-only | pth | 66.9MB | https://openmodeldb.info/models/4x-SGI | chrisnonyminus |
| ScreenBooster V2 | esrgan | 4x | 64nf/23nb | cgi, game-screenshots, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-ScreenBooster-V2 | blackscout |
| UltraSharp | esrgan | 4x | 64nf/23nb | compression-removal, general-upscaler, jpeg, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-UltraSharp | kim2091 |
| UniScale Balanced | esrgan | 4x | 64nf/23nb | general-upscaler | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-UniScale-Balanced | kim2091 |
| UniScale Restore | esrgan | 4x | 64nf/23nb | compression-removal, denoise, general-upscaler, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-UniScale-Restore | kim2091 |
| UniScale Strong | esrgan | 4x | 64nf/23nb | general-upscaler | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-UniScale-Strong | kim2091 |
| UniScaleNR Balanced | esrgan | 4x | 64nf/23nb | denoise, general-upscaler, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-UniScaleNR-Balanced | kim2091 |
| UniScaleNR Strong | esrgan | 4x | 64nf/23nb | denoise, general-upscaler, restoration | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-UniScaleNR-Strong | kim2091 |
| UniScaleV2 Moderate | esrgan | 4x | 64nf/23nb | general-upscaler | CC-BY-NC-SA-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-UniScaleV2-Moderate | kim2091 |
| UniScaleV2 Sharp | esrgan | 4x | 64nf/23nb | general-upscaler | CC-BY-NC-SA-4.0 | pth | 66.9MB | https://openmodeldb.info/models/4x-UniScaleV2-Sharp | kim2091 |
| UniScaleV2 Soft | esrgan | 4x | 64nf/23nb | general-upscaler | CC-BY-NC-SA-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-UniScaleV2-Soft | kim2091 |
| UniversalUpscalerV2 Neutral | esrgan | 4x | 64nf/23nb | general-upscaler | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-UniversalUpscalerV2-Neutral | mutin-choler |
| UniversalUpscalerV2 Sharp | esrgan | 4x | 64nf/23nb | general-upscaler | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-UniversalUpscalerV2-Sharp | mutin-choler |
| UniversalUpscalerV2 Sharper | esrgan | 4x | 64nf/23nb | general-upscaler | WTFPL | pth | 66.9MB | https://openmodeldb.info/models/4x-UniversalUpscalerV2-Sharper | mutin-choler |
| WTP ColorDS | esrgan | 4x | 64nf/23nb | dehalftone, restoration | CC-BY-4.0 | pth | 67MB | https://openmodeldb.info/models/4x-WTP-ColorDS | umzi-x-dead |
| detoon alt | esrgan | 4x | 64nf/23nb | cartoon, photo, restoration | ? | pth | 66.9MB | https://openmodeldb.info/models/4x-detoon-alt | lyonhrt |
| detoon | esrgan | 4x | 64nf/23nb | cartoon, photo, restoration | ? | pth | 66.9MB | https://openmodeldb.info/models/4x-detoon | lyonhrt |
| realesrgan-x4minus | esrgan | 4x | 64nf/23nb | general-upscaler | WTFPL | pth | 67MB | https://openmodeldb.info/models/4x-realesrgan-x4minus | dinjerr |
| Valar | esrgan+ | 4x | 64nf/23nb | photo | CC0-1.0 | pth | 67.5MB | https://openmodeldb.info/models/4x-Valar | musl |
| 4xHFA2kLUDVAEGRL_small | grl | 4x | GRL-small/img_size: 64 | anime, video-frame | CC-BY-4.0 | pth | 31.5MB | https://openmodeldb.info/models/4x-HFA2kLUDVAEGRL-small | helaman |
| 4xNomos8kSCHAT-L | hat | 4x | HAT-L | anime, compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | onnx,pth | 161.5MB | https://openmodeldb.info/models/4x-Nomos8kSCHAT-L | helaman |
| 4xNomos8kSCHAT-S | hat | 4x | HAT-S | anime, compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | onnx,pth | 59.2MB | https://openmodeldb.info/models/4x-Nomos8kSCHAT-S | helaman |
| HAT-L_SRx4_ImageNet-pretrain | hat | 4x | HAT-L | general-upscaler, research | Apache-2.0 | pth | 165.7MB | https://openmodeldb.info/models/4x-HAT-L-SRx4-ImageNet-pretrain | xpixelgroup |
| HAT-S_SRx4 | hat | 4x | HAT-S | general-upscaler, research | Apache-2.0 | pth | 81MB | https://openmodeldb.info/models/4x-HAT-S-SRx4 | xpixelgroup |
| Nomos8kHAT-L_otf | hat | 4x | HAT-L | faces, general-upscaler, photo, restoration | CC-BY-4.0 | pth | 165.7MB | https://openmodeldb.info/models/4x-Nomos8kHAT-L-otf | helaman |
| Ludvae200 | ludvae | 1x |  | photo | CC-BY-4.0 | pth | 22.8MB | https://openmodeldb.info/models/1x-Ludvae200 | helaman |
| 4xNomos2_hq_mosr | mosr | 4x |  | general-upscaler, photo | CC-BY-4.0 | onnx,pth | 17.2MB | https://openmodeldb.info/models/4x-Nomos2-hq-mosr | helaman |
| DeJPG_OmniSR | omnisr | 1x |  | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 6.5MB | https://openmodeldb.info/models/1x-DeJPG-OmniSR | helaman |
| NES Composite to RGB | omnisr | 1x |  | debanding, denoise, game-screenshots, restoration, video-frame | MIT | pth | 3.2MB | https://openmodeldb.info/models/1x-NES-Composite-2-RGB | pokepress |
| SEGA Genesis Cleanup | omnisr | 1x |  | deblur, game-screenshots, general-upscaler, restoration, video-frame | MIT | pth | 3.2MB | https://openmodeldb.info/models/1x-SEGA-Genesis-Cleanup | pokepress |
| Where On Earth-Deinterlace Fix-Large | omnisr | 1x |  | cartoon, restoration, video-frame | MIT | pth | 3.2MB | https://openmodeldb.info/models/1x-WhereOnEarthDeintFixL | pokepress |
| 2xHFA2kAVCOmniSR | omnisr | 2x |  | anime, video-frame | CC-BY-4.0 | pth | 6.5MB | https://openmodeldb.info/models/2x-HFA2kAVCOmniSR | helaman |
| OmniSR 2x DF2K | omnisr | 2x | 64nf/5nr | general-upscaler, photo, research | Apache-2.0 | pth | 3.4MB | https://openmodeldb.info/models/2x-OmniSR-DF2K | hang-wang |
| OmniSR 2x DIV2K | omnisr | 2x | 64nf/5nr | general-upscaler, photo, research | Apache-2.0 | pth | 3.4MB | https://openmodeldb.info/models/2x-OmniSR-DIV2K | hang-wang |
| Where On Earth-Upscale-Large | omnisr | 2x |  | cartoon, general-upscaler, video-frame | MIT | pth | 3.2MB | https://openmodeldb.info/models/2x-Where-On-Earth-Upscale-Large | pokepress |
| OmniSR 4x DF2K | omnisr | 4x | 64nf/5nr | general-upscaler, photo, research | Apache-2.0 | pth | 3.4MB | https://openmodeldb.info/models/4x-OmniSR-DF2K | hang-wang |
| OmniSR 4x DIV2K | omnisr | 4x | 64nf/5nr | general-upscaler, photo, research | Apache-2.0 | pth | 3.4MB | https://openmodeldb.info/models/4x-OmniSR-DIV2K | hang-wang |
| UnResizeOnly_RCAN | rcan | 1x |  | anti-aliasing, restoration | CC-BY-NC-SA-4.0 | pth | 31.2MB | https://openmodeldb.info/models/1x-UnResizeOnly-RCAN | kim2091 |
| 1xDeH264_realplksr | realplksr | 1x |  | compression-removal, photo, restoration | CC-BY-4.0 | onnx,pth,safetensors | 29.5MB | https://openmodeldb.info/models/1x-DeH264-realplksr | helaman |
| 1xDeJPG_realplksr_otf | realplksr | 1x |  | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | onnx,pth,safetensors | 29.5MB | https://openmodeldb.info/models/1x-DeJPG-realplksr-otf | helaman |
| 1xDeNoise_realplksr_otf  | realplksr | 1x |  | denoise, photo, restoration | CC-BY-4.0 | onnx,pth,safetensors | 29.5MB | https://openmodeldb.info/models/1x-DeNoise-realplksr-otf | helaman |
| SuperScale_Alt_RPLKSR_S | realplksr | 1x | Small/Tiny | anti-aliasing, game-screenshots, photo, restoration | CC-BY-NC-SA-4.0 | safetensors | 9.3MB | https://openmodeldb.info/models/1x-SuperScale-Alt-RPLKSR-S | kim2091 |
| SuperScale_RPLKSR_S | realplksr | 1x |  | anti-aliasing, game-screenshots, photo, restoration | CC-BY-NC-SA-4.0 | safetensors | 9.3MB | https://openmodeldb.info/models/1x-SuperScale-RPLKSR-S | kim2091 |
| 90s Sonic 2x (Large) | realplksr | 2x |  | cartoon, restoration, video-frame | MIT | pth | 9.4MB | https://openmodeldb.info/models/2x-90s-Sonic-LG | pokepress |
| Text2HD v.1 | realplksr | 2x |  | compression-removal, denoise, general-upscaler, jpeg, restoration, text | CC-BY-SA-4.0 | pth | 29.5MB | https://openmodeldb.info/models/2x-Text2HD-v-1 | asterixcool |
| VHS2HD | realplksr | 2x |  | compression-removal, dehalo, photo, restoration, video-frame | CC-BY-SA-4.0 | pth | 29.5MB | https://openmodeldb.info/models/2x-VHS2HD | asterixcool |
| 4xNomos2_realplksr_dysample | realplksr | 4x |  | compression-removal, jpeg, photo, restoration | CC-BY-4.0 | onnx,pth | 29.7MB | https://openmodeldb.info/models/4x-Nomos2-realplksr-dysample | helaman |
| 4xNomosWebPhoto_RealPLKSR | realplksr | 4x | 64dim/28nb/17ks/Real | photo, restoration | CC-BY-4.0 | pth | 29.6MB | https://openmodeldb.info/models/4x-NomosWebPhoto-RealPLKSR | helaman |
| 4xPurePhoto-RealPLSKR | realplksr | 4x |  | ai-generated, compression-removal, jpeg, photo, restoration | CC-BY-SA-4.0 | pth | 29.6MB | https://openmodeldb.info/models/4x-PurePhoto-RealPLSKR | asterixcool |
|  4xRealWebPhoto_v2_rgt_s | rgt | 4x |  | general-upscaler, photo, restoration | CC-BY-4.0 | onnx,pth,safetensors | 135.9MB | https://openmodeldb.info/models/4x-RealWebPhoto-v2-rgt-s | helaman |
| NomosUni rgt multijpg | rgt | 4x |  | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 180.3MB | https://openmodeldb.info/models/4x-NomosUni-rgt-multijpg | helaman |
| NomosUni rgt s multijpg | rgt | 4x |  | compression-removal, jpeg, restoration | CC-BY-4.0 | onnx,pth | 135.9MB | https://openmodeldb.info/models/4x-NomosUni-rgt-s-multijpg | helaman |
| VimeoScale Unet | sofvsr | 2x | 32nf/12nb | photo | CC-BY-SA-4.0 | pth | 21.9MB | https://openmodeldb.info/models/2x-VimeoScale-Unet | sazoji |
| REDSVAL-7f-RRDB Lite | sofvsr | 4x | 32nf/12nb | photo | CC-BY-NC-SA-4.0 | pth | 22.3MB | https://openmodeldb.info/models/4x-REDSVAL-7f-RRDB-Lite | joey |
| VESRGAN_G | sofvsr | 4x |  | restoration, video-frame | ? | pth | 69MB | https://openmodeldb.info/models/4x-VESRGAN-G | victorca25 |
| VimeoScale | sofvsr | 4x |  | photo | CC-BY-SA-4.0 | pth | 69.2MB | https://openmodeldb.info/models/4x-VimeoScale | sazoji |
| SuperScale | span | 1x |  | anti-aliasing, game-screenshots, photo, restoration | CC-BY-NC-SA-4.0 | safetensors | 8.8MB | https://openmodeldb.info/models/1x-SuperScale | kim2091 |
| 2xLiveActionV1_SPAN | span | 2x | 48nf | compression-removal, deblur, dehalo, general-upscaler, jpeg, photo, restoration, video-frame | CC-BY-NC-SA-4.0 | onnx,pth | 8.9MB | https://openmodeldb.info/models/2x-LiveActionV1-SPAN | jcj83429 |
| NomosUni span multijpg ldl | span | 2x | 48nf | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 8.9MB | https://openmodeldb.info/models/2x-NomosUni-span-multijpg-ldl | helaman |
| ClearRealityV1 | span | 4x |  | general-upscaler, photo, restoration | CC-BY-NC-SA-4.0 | pth | 7.4MB | https://openmodeldb.info/models/4x-ClearRealityV1 | kim2091 |
| Nomos8k_span_otf_medium | span | 4x |  | general-upscaler, photo, restoration | CC-BY-4.0 | onnx,pth | 9MB | https://openmodeldb.info/models/4x-Nomos8k-span-otf-medium | helaman |
| Nomos8k_span_otf_strong | span | 4x |  | general-upscaler, photo, restoration | CC-BY-4.0 | onnx,pth | 9MB | https://openmodeldb.info/models/4x-Nomos8k-span-otf-strong | helaman |
| Nomos8k_span_otf_weak | span | 4x |  | general-upscaler, photo, restoration | CC-BY-4.0 | onnx,pth | 9MB | https://openmodeldb.info/models/4x-Nomos8k-span-otf-weak | helaman |
| PurePhoto span | span | 4x | 48nf | general-upscaler, photo | CC-BY-SA-4.0 | pth | 9MB | https://openmodeldb.info/models/4x-PurePhoto-span | asterixcool |
| SPANkendata | span | 4x |  | general-upscaler, photo | CC-BY-SA-4.0 | onnx | 1.7MB | https://openmodeldb.info/models/4x-SPANkendata | crustaceous-d |
| 4x SPSR | spsr | 4x | 64nf/23nb | general-upscaler, photo, research | ? | pth | 99.5MB | https://openmodeldb.info/models/4x-SPSR | cheng-ma |
| BS_ScreenBooster_SPSR | spsr | 4x | 64nf/23nb | cgi, game-screenshots, restoration | CC-BY-NC-SA-4.0 | pth | 99.6MB | https://openmodeldb.info/models/4x-BS-ScreenBooster-SPSR | blackscout |
| DeJPG_SRFormer_light | srformer | 1x |  | compression-removal, jpeg, restoration | CC-BY-4.0 | pth | 38.6MB | https://openmodeldb.info/models/1x-DeJPG-SRFormer-light | helaman |
| Frankenfixer_SRFormerLight | srformer | 1x | s64/w16 | photo, restoration | CC-BY-SA-4.0 | pth | 19.3MB | https://openmodeldb.info/models/1x-Frankenfixer-SRFormerLight | crustaceous-d |
| 2xHFA2kAVCSRFormer_light | srformer | 2x |  | anime, compression-removal, restoration, video-frame | CC-BY-4.0 | onnx,pth | 38.6MB | https://openmodeldb.info/models/2x-HFA2kAVCSRFormer-light | helaman |
| 4xHFA2kLUDVAESRFormer_light | srformer | 4x | SRFormer-light | anime, video-frame | CC-BY-4.0 | pth | 38.8MB | https://openmodeldb.info/models/4x-HFA2kLUDVAESRFormer-light | helaman |
| 4xNomos8kSCSRFormer | srformer | 4x | base model/img_size: 48/window_size: 22 | anime, compression-removal, general-upscaler, jpeg, photo, restoration | CC-BY-4.0 | onnx,pth | 47.9MB | https://openmodeldb.info/models/4x-Nomos8kSCSRFormer | helaman |
| Frankendata_FullDegradation_SRFormer | srformer | 4x |  | compression-removal, denoise, photo, restoration | ? | pth | 180.4MB | https://openmodeldb.info/models/4x-Frankendata-FullDegradation-SRFormer | crustaceous-d |
| Bendel_Halftone | swinir | 1x | Small/s48/w8 | dehalftone, restoration | CC-BY-4.0 | pth | 23.5MB | https://openmodeldb.info/models/1x-Bendel-Halftone | bendel |
| SwinIR-M-x2 (classicalSR-DF2K-s64w8) | swinir | 2x | Medium/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 67.2MB | https://openmodeldb.info/models/2x-classicalSR-DF2K-s64w8-SwinIR-M | jingyunliang |
| SwinIR-M-x2 (classicalSR-DIV2K-s64w8) | swinir | 2x | Medium/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 59MB | https://openmodeldb.info/models/2x-classicalSR-DIV2K-s64w8-SwinIR-M | jingyunliang |
| SwinIR-M-x2 (lightweightSR-DIV2K-s64w8) | swinir | 2x | Small/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 17.1MB | https://openmodeldb.info/models/2x-lightweightSR-DIV2K-s64w8-SwinIR-S | jingyunliang |
| SwinIR-M-x2-GAN (realSR-BSRGAN-DFO-s64w8) | swinir | 2x | Medium/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 66.9MB | https://openmodeldb.info/models/2x-realSR-BSRGAN-DFO-s64w8-SwinIR-M-x2-GAN | jingyunliang |
| 4xHFA2kLUDVAESwinIR_light | swinir | 4x | SwinIR-light | anime, video-frame | CC-BY-4.0 | pth | 17.2MB | https://openmodeldb.info/models/4x-HFA2kLUDVAESwinIR-light | helaman |
| SwinIR-L-x4-GAN (realSR-BSRGAN-DFOWMFC-s64w8) | swinir | 4x | Large/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 142.4MB | https://openmodeldb.info/models/4x-realSR-BSRGAN-DFOWMFC-s64w8-SwinIR-L-x4-GAN | jingyunliang |
| SwinIR-M-x4 (classicalSR-DF2K-s64w8) | swinir | 4x | Medium/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 67.8MB | https://openmodeldb.info/models/4x-classicalSR-DF2K-s64w8-SwinIR-M | jingyunliang |
| SwinIR-M-x4 (classicalSR-DIV2K-s64w8) | swinir | 4x | Medium/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 59.6MB | https://openmodeldb.info/models/4x-classicalSR-DIV2K-s64w8-SwinIR-M | jingyunliang |
| SwinIR-M-x4 (lightweightSR-DIV2K-s64w8) | swinir | 4x | Small/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 17.2MB | https://openmodeldb.info/models/4x-lightweightSR-DIV2K-s64w8-SwinIR-S | jingyunliang |
| SwinIR-M-x4-GAN (realSR-BSRGAN-DFO-s64w8) | swinir | 4x | Medium/s64/w8 | compression-removal, general-upscaler, jpeg, photo, research, restoration | Apache-2.0 | pth | 67.1MB | https://openmodeldb.info/models/4x-realSR-BSRGAN-DFO-s64w8-SwinIR-M-x4-GAN | jingyunliang |
| GameUp-TSCUNet | tscunet | 2x |  | anti-aliasing, compression-removal, deblur, game-screenshots, restoration, video-frame | CC-BY-NC-SA-4.0 | onnx,pth | 116.8MB | https://openmodeldb.info/models/2x-GameUp-TSCUNet | kim2091 |
| GameUpV2-TSCUNet | tscunet | 2x |  | anti-aliasing, compression-removal, deblur, game-screenshots, restoration, video-frame | CC-BY-NC-SA-4.0 | onnx,pth | 116.8MB | https://openmodeldb.info/models/2x-GameUpV2-TSCUNet | kim2091 |
| GameUpV2-TSCUNet-Small | tscunet | 2x | Small | anti-aliasing, compression-removal, deblur, game-screenshots, restoration, video-frame | CC-BY-NC-SA-4.0 | onnx,pth | 83.6MB | https://openmodeldb.info/models/2x-GameUpV2-TSCUNet-Small | kim2091 |

## C. Apple-native SR (from SDK headers + runtime probe)

SDK: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/VideoToolbox.framework/Headers/`

### C1. VTLowLatencySuperResolutionScalerConfiguration (`VTFrameProcessor_LowLatencySuperResolutionScaler.h`)
- Availability: macOS/iOS/tvOS/visionOS 26.0+; `supportedScaleFactors`, `maximumDimensionForSpatialScaleFactor:`, `maximumPixelCountForSpatialScaleFactor:` are 27.0+. Unavailable in simulator and watchOS.
- Init: `initWithFrameWidth:frameHeight:scaleFactor:` (float scale; must be in `supportedScaleFactorsForFrameWidth:frameHeight:`).
- Header warning: ML model loading at `startSessionWithConfiguration:` "may take longer than a frame time" -- do it off the render path.
- Parameters object takes only source frame + destination frame (no temporal inputs: single-frame SR, hence low latency).
- **Runtime probe on this machine [runtime probe]**: `isSupported=1`; min dims 96x96; max dim 1280 (class-level); global supported scales {1.5, 2, 4}. Per-scale limits:
  | scale | max source dimension | max source pixel count | max source frame |
  |---|---|---|---|
  | 1.5 | 1280 | 1,638,400 | 1280x1280-ish; 1280x720 OK |
  | 2 | 960 | 921,600 | 960x540 OK; **1280x720 NOT allowed** (width 1280 > 960) |
  | 4 | 480 | 230,400 | 640x360 max |
  For 1280x720, `supportedScaleFactorsForFrameWidth:1280 frameHeight:720` = **{1.5}** only. Output 1920x1080.
- Pixel format [runtime probe]: source and destination both `875704438` = `'420v'` (8-bit 4:2:0 video-range biplanar). No 10-bit, no RGB reported. Source attrs include IOSurface properties; dst 1920x1080.
- Implication: a 720p -> 1080p 1.5x neural step, then your own 1080p -> 3448x2164 (1.8x) scaler. 2x then downscale is possible only for sources <= 960x540.
- Cost on M1 Pro: **not measured**. Headers give no latency figure.

### C2. VTSuperResolutionScalerConfiguration (`VTFrameProcessor_SuperResolutionScaler.h`)
- macOS/iOS 26.0+, not tvOS/visionOS. Temporal (uses previousFrame, previousOutputFrame, optical flow computed on the fly or precomputed), `QualityPrioritizationNormal` only, revision 1 only.
- Header: video max source 1920x1080 on macOS; image max 1920x1920 on macOS.
- Requires downloadable ML model (`configurationModelStatus`, `downloadConfigurationModelWithCompletionHandler:`).
- **Runtime probe**: `supportedScaleFactors = {4}`; `initWithFrameWidth:1280 frameHeight:720 scaleFactor:2 ...` returned **nil** ("unsupported scaleFactor"). So 720p -> 2880x1620 (4x) -> 5120x2880 at 4x is the only option: output would be 5120x2880 (more than fullscreen needs) and is the heavy temporal model -> assumed not real-time (unmeasured).
- Conclusion: use only C1 for real-time.


## D. Gaps and unknowns

- **No Apple Silicon latency measurements** for any OMDB architecture from a primary source. All ms/FLOP statements for them are my arithmetic. Needed: benchmark C4F16_DS, FSRCNNX 8-0-4-1/16-0-4-1 in your mpv harness (quick) and VT low-latency SR at 720p->1080p (Swift/Obj-C harness; I did not run a session because it needs pixel buffers and was out of scope).
- FSRCNNX licence, exact param counts and training-set composition: README/release notes do not state them. ArtCNN DS/DN layer shapes assumed equal to neutral variant; confirm by diffing the GLSL (`//!WIDTH`/`//!DESC` blocks).
- ArtCNN, CuNNy, Anime4K training domain is anime/VN. Whether C4F16 helps or hurts live-action is **untested**; do an A/B on your master (VMAF is misleading for sharpening; igv recommends MAD-pooled SSIM / IW-SSIM / PieAPP for SR evaluation per FSRCNNX 1.1 release notes).
- Live-action-trained tiny nets: none found in OMDB or GitHub. Retraining an ArtCNN-sized model is the main route to fill this gap.
- No public Compact/SPAN/RealPLKSR -> GLSL converter found. Writing one is feasible only for tiny nets (per-pixel cost above); RGB Compact nf64 would need compute-shader tiling and ~30x more throughput than measured GLSL ceiling.
- ANE/Core ML route: PiperSR shows ~9 TFLOP/s-class effective ANE throughput [derived from 453k params x 230k px x 2 / 22.5 ms] (vendor benchmark). At that rate a 1.1 TFLOP Compact-nf64 frame => ~120 ms on M2 Max ANE [derived]; not real time.
- OMDB has no param counts; `size` field is architecture hyper-params (nf/nc) only.
- VT SR: 8-bit 420v only; colour handling of BT.601 content and 10-bit ProRes quantisation to be checked. Model download/availability (LL variant has no status API in the header I read).
- OpenModelDB licences: several best-fit models are NC (2xLiveActionV1_SPAN CC-BY-NC-SA-4.0; SuperScale CC-BY-NC-SA).
- Section B filter is heuristic (tags photo / video-frame, or general/restoration/compression/denoise/deblur/jpeg without anime/cartoon/pixel-art/game-textures/manga/dds; scales 1/2/4; pretrained excluded); 246 rows. Video-frame tag covers game/retro content too (e.g. NES/Genesis, Sonic) -- read the tags column. Full unfiltered TSV (671 records): `scratchpad/omdb_all.tsv`.
