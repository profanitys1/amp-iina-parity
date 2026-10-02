# OpenModelDB full per-model audit, 1x/2x realistic and compression focus

Date: 2026-10-02. Companion CSV: `2026-10-02-openmodeldb-full-audit.csv` (one row per record, 671 rows, same count as records). Redoes `2026-09-30-openmodeldb-model-survey.md`, which filtered in bulk. No model weights were downloaded; GitHub content was read through the API/raw text only. Numbers marked **[derived]** are my calculations, **[stated]** come from a cited source, **[assumed]** are guesses with the assumption named.

## 1. Bottom line

- **Nothing in OpenModelDB is a real-time candidate today.** Of 671 records, 324 are 1x/2x. Only two 1x/2x records have a derived cost within 3x of the amp budget, and neither is a verified live-action restorer: `1x-Debandurh-FS-Ultra-lite` (tiny ESRGAN, debanding, cost depends on an unknown weight layout, 80 GFLOP or about 1.2 TFLOP per 720p frame) and `2x-AnimeJaNai-HD-V3-SuperUltraCompact` (anime-primary).
- The only OpenModelDB model actually trained for live-action H.264/H.265 artefacts, `2xLiveActionV1_SPAN` (+ ONNX, 1.65 MB), costs ~755 GFLOP per 720p frame **[derived]**: about 13x the budget even before 1080p. It is an offline reference, not a playback option.
- The architecture class that fits is **SRVGGNetCompact nf24/nc8 (SuperUltraCompact)**, 79 GFLOP per 720p frame **[derived]**. OpenModelDB has no live-action compression-removal weights in that size. The practical route is training one (neosr / traiNNer) and exporting to Core ML / MLX, not finding one.
- Real-time non-OMDB gains are classical or tiny-network GLSL (section 8): sharpen-with-coring, deband, grain synthesis, bilateral chroma/clipper. No GLSL deblocker was found.

## 2. Method (so nothing can be skipped unnoticed)

1. `git clone --depth 1 https://github.com/OpenModelDB/open-model-database` into `scratchpad/omdb-audit`. Records = every file `data/models/*.json`: **671 files**. Script `scratchpad/build.py` loops over all of them, no filter; it writes one CSV row per file and asserts `records == csv rows` (printed: records 671, csv rows 671, match True).
2. Fields: taken from the JSON (`name, architecture, scale, size, tags, license, author, date, inputChannels, outputChannels, resources`). Input type (image/video) is derived by the site from `architectures.json` (`src/lib/derive-tags.ts`): video archs are CAIN, CAIN-YUV, RIFE, SOFVSR, TSCUNet.
3. **Params**: no record states a parameter count [stated]; the CSV `params_derived` column is a torch count where torch was used, empty for analytic cases.
4. **Cost** (`gflop_720p`, `gflop_1080p` = x2.25, `x_budget_720p`): only for scale 1 and 2 (scale 3/4/8/16 get `skip-scale` and no cost, per instruction). FLOP = 2 x MAC, one 1280x720 input frame, RGB, per-pixel. Method per architecture, all **[derived]**:
   - Compact: closed form 9(3nf + nc nf^2 + nf 3 s^2) MAC/px (reproduces the 2026-09-30 figures 79 / 1103 GFLOP).
   - ESRGAN (RRDBNet, gc=32): closed form assuming the Real-ESRGAN pixel-unshuffle layout for 1x and 2x (the `gflop_720p` lower bound). The `gflop_720p_high` column gives the full-resolution old-layout cost; the true layout cannot be known without reading the weights' `conv_first` shape, and the two differ 15x.
   - SPAN: closed form with Conv3XC fused to a single 3x3 (deployed form). The 2026-09-30 figure (1079) used the unfused module.
   - OmniSR, RealPLKSR, DAT, SwinIR, HAT, DiTN, CUGAN, Swift-SRGAN: instantiated with `spandrel` 0.4.2 classes (no weights) and counted with `torch.utils.flop_counter` at 64x64, scaled to 720p. Configs are guessed from the `size` field where present, else defaults (`cost_method` says which). SRFormer approximated by SwinIR; EDSR-baseline and RCAN analytic.
   - MoSR, SR-ResNet, and the video archs: no cost computed (blank).
   - Budget B = 35 ms x 1.6 TFLOP/s = 56 GFLOP per frame (calibration from the task brief: ArtCNN C4F16 ~22 GFLOP at 720p measured ~14 ms). "Within ~3x" = <=168 GFLOP per 720p frame.
5. **Domain** (`domain`): from tags. photo/video-frame/faces => photo or film; compression-removal/jpeg/debanding => compression; anime/manga/cartoon without any photo, video-frame, faces or compression tag => anime; game/pixel/texture/CGI/text/AI-generated without those => game or other; with both => `anime-mixed` / `other-mixed` (kept per instruction, evaluated by cost, flagged in reason); no subject tag => keyword match on name+description, else `general`. OpenModelDB has no "Realistic" subject tag: the closest are `photo` and the dataset field (`dataset:realistic` exists in tags.json but no record carries it); I treat `photo` or a dataset text containing realistic/photo/real as Realistic.
6. **Verdict** (first rule that matches): scale>2 `skip-scale`; arch CAIN/RIFE (interpolation), SOFVSR/TSCUNet (multi-frame), LUD-VAE, tags colorization/inpainting/dehalftone/dds/texture-generation, names with exposure/deinterlace/book/scan, SkinContrast, pretrain-only tags => `skip-wrong-task`; anime domain => `skip-anime`; game/other => `skip-other-domain`; otherwise cost <=168 => `candidate-if-converted`, cost above => `offline-only`, no cost => `offline-only` (heavy arch). `candidate-realtime` is reserved for records with an existing GLSL/Core ML port that fits; **no record qualifies** (count 0).
7. **tag_priority** = yes if tags include photo / video-frame / faces, or compression-removal / debanding / deblur / denoise / dehalo / jpeg / restoration / general-upscaler, or architecture input is video, or dataset text says realistic. 488 of 671 records. (Because `restoration` and `general-upscaler` are very common, this view is wide; `skip-anime` records inside it are those with anime tags and no photo/compression tag.)
8. Estimate columns `coreml_or_mlx_ms_est`, `port_exists`: section 6.

## 3. Counts per verdict (all 671)

- `candidate-realtime`: 0
- `candidate-if-converted`: 2
- `offline-only`: 165
- `skip-anime`: 97
- `skip-other-domain`: 16
- `skip-wrong-task`: 44
- `skip-scale`: 347
- total 671 = records 671.

Scale mix: 1x 158, 2x 166, 3x 8, 4x 324, 8x 13, 16x 2. 1x/2x = 324; of those 165 offline-only, 97 skip-anime, 44 skip-wrong-task, 16 skip-other-domain, 2 candidate-if-converted.

## 4. Priority view by architecture (tag_priority=yes, scale 1 or 2)

ms columns are section 6 estimates for the cheapest record of the group: ANE-optimistic / GPU. Budget ~35 ms usable.

| arch | records | GFLOP/720p min-max [derived] | GFLOP/1080p min | ms 720p (ANE-opt / GPU) min | ms 1080p min | note |
|---|---|---|---|---|---|---|
| compact | 55 | 79 - 2190 | 177 | 12 / 26 | 27 / 59 | only nf24/nc8 fits; nf64 nc16 is ~1.1 TFLOP |
| esrgan | 126 | 80 - 8594 | 181 | 12 / 27 | 28 / 60 | tiny nf8/nb3 and nf16/nb8 low end only; mainstream nf64/nb23 1x = 2.1 TFLOP (unshuffle) up to ~30 TFLOP (full-res layout) |
| swift-srgan | 1 | 356 - 356 | 801 | 55 / 119 | 123 / 267 | depthwise-separable; 2x general (DIV2K+Flickr2K) |
| span | 14 | 748 - 1337 | 1683 | 115 / 249 | 259 / 561 | fused-3x3 cost; training form is larger |
| ditn | 1 | 829 - 829 | 1866 | 128 / 276 | 287 / 622 | anime SR |
| realplksr | 10 | 1284 - 13558 | 2890 | 198 / 428 | 445 / 963 | default dim64/nb28; Small/Tiny hypothetical config |
| dat | 2 | 1483 - 23061 | 3337 | 228 / 494 | 513 / 1112 | transformer |
| omnisr | 11 | 1540 - 1549 | 3464 | 237 / 513 | 533 / 1155 | research model |
| real-cugan | 2 | 1946 - 1946 | 4379 | 299 / 649 | 674 / 1460 | anime |
| cugan | 3 | 1946 - 1946 | 4379 | 299 / 649 | 674 / 1460 | anime |
| edsr | 1 | 2530 - 2530 | 5692 | 389 / 843 | 876 / 1898 | baseline assumed |
| swinir | 6 | 2555 - 31575 | 5749 | 393 / 852 | 885 / 1916 | transformer |
| rcan | 3 | 27930 - 27930 | 62842 | 4297 / 9310 | 9668 / 20947 | lower bound |
| hat | 1 | 29874 - 29874 | 67218 | 4596 / 9958 | 10341 / 22406 | transformer |
| srformer | 3 | 31293 - 31575 | 70410 | 4814 / 10431 | 10832 / 23470 | approx. by SwinIR |
| ludvae | 1 | n/a | n/a | n/a | n/a | noise VAE |
| mosr | 3 | n/a | n/a | n/a | n/a | cost not computed |
| tscunet | 3 | n/a | n/a | n/a | n/a | multi-frame |
| sofvsr | 2 | n/a | n/a | n/a | n/a | multi-frame |
| sr-res-net | 1 | n/a | n/a | n/a | n/a | cost not computed |
| cain | 4 | n/a | n/a | n/a | n/a | interpolation |
| cain-yuv | 1 | n/a | n/a | n/a | n/a | interpolation |
| rife | 1 | n/a | n/a | n/a | n/a | interpolation |

## 5. Every priority record with its verdict

Format: grouped by verdict, then architecture and scale; ids are the OpenModelDB filenames (URL = https://openmodeldb.info/models/<id>). Priority records total 488; counts per verdict below add up to that. Full per-record reasons are in the CSV.

### candidate-if-converted (2)
- compact 2x (1): 2x-AnimeJaNai-HD-V3-SuperUltraCompact
- esrgan 1x (1): 1x-Debandurh-FS-Ultra-lite

### offline-only (161)
- compact 1x (4): 1x-BroadcastToStudio-Compact, 1x-NES-Composite-2-RGB-Small, 1x-Sega-Genesis-Cleanup-Small, 1x-WhereOnEarthDeintFixS
- compact 2x (16): 2x-90s-Sonic, 2x-Ani4K, 2x-Ani4VK-v2-Compact, 2x-AniScale-2-Compact, 2x-AniScale, 2x-AnimeJaNai-HD-V3-Compact, 2x-AnimeJaNai-HD-V3-UltraCompact, 2x-HDCube-Compact, 2x-HFA2k-compact-multijpg, 2x-HFA2kAVCCompact, 2x-MLP-StarSample-V1-0, 2x-NomosUni-compact-multijpg, 2x-NomosUni-compact-otf-medium, 2x-ParimgCompact, 2x-Where-On-Earth-Upscale-Small, 2x-realesrganv2-animevideo-xsx2
- dat 2x (1): 2x-Manga-Ora
- ditn 2x (1): 2x-AniScale-2-DITN
- edsr 2x (1): 2x-HFA2kAVCEDSR-M
- esrgan 1x (75): 1x-BC1-smooth2, 1x-BCGone-Detailed, 1x-BCGone-DetailedV2-40-60, 1x-BCGone-Smooth, 1x-BSChroma, 1x-BSLuma, 1x-BaldrickVHSFixV0-2, 1x-Bandage-Smooth, 1x-DEDXT, 1x-DEPVR-Artifact, 1x-DEPVR, 1x-DXTDecompressor-Source-V3, 1x-DXTless-SourceEngine, 1x-DeBLR, 1x-DeBink-Lite, 1x-DeBink-v4, 1x-DeBink-v5, 1x-DeBink-v6, 1x-DeEdge, 1x-DeJpeg-Fatality-PlusULTRA, 1x-DeRoqBeta-lite, 1x-DeSharpen, 1x-DitherDeleterV2-Smooth, 1x-DitherDeleterV3-Smooth, 1x-Fatality-DeBlur, 1x-Film-Degrainer-1-000, 1x-Filmify4K-v2, 1x-Focus-Moderate, 1x-Focus, 1x-ISO-denoise-v1, 1x-ISO-denoise-v2, 1x-ITF-SkinDiffDDS-v1, 1x-ITF-SkinDiffDetail-Lite-v1, 1x-JPEGDestroyer, 1x-JPG-00-20-alsa, 1x-JPG-00-20, 1x-JPG-20-40-alsa, 1x-JPG-20-40, 1x-JPG-40-60-alsa, 1x-JPG-40-60, 1x-JPG-60-80-alsa, 1x-JPG-60-80, 1x-JPG-80-100-alsa, 1x-JPG-80-100, 1x-Kim2091-DeJpeg-v0, 1x-Loyaldk-SharpKeroro, 1x-MangaJPEGHQ, 1x-MangaJPEGHQPlus, 1x-MangaJPEGLQ, 1x-MangaJPEGMQ, 1x-Manhwa-Null, 1x-N64clean, 1x-NMKD-Jaywreck3-Lite, 1x-NMKD-Jaywreck3-Soft-Lite, 1x-NMKD-h264Texturize, 1x-NoiseToner-Poisson-Detailed, 1x-NoiseToner-Poisson-Soft, 1x-NoiseToner-Poisson, 1x-NoiseToner-Uniform-Detailed, 1x-NoiseToner-Uniform-Soft, 1x-NoiseToner-Uniform, 1x-Plants, 1x-RedImage, 1x-RoQ-nRoll, 1x-SBDV-DeJPEG-Lite, 1x-SaiyaJin-DeJpeg, 1x-SpongeBC1-Lite, 1x-StarSample-V2-NS, 1x-ToonVHS, 1x-UnResize-V3, 1x-VHS-Sharpen, 1x-artifacts-bc1-free-alsa, 1x-artifacts-dithering-alsa, 1x-cinepak, 1x-mdeblur
- esrgan 2x (21): 2x-AniScale-2-ESRGAN-Lite, 2x-AniScale-2-ESRGAN, 2x-BSRGAN, 2x-CGIMaster-v1, 2x-DeGif, 2x-DigiGradients-Lite, 2x-DigitoonLite, 2x-KemonoScale-v2, 2x-Loyaldk-Giroro, 2x-Loyaldk-Keroro, 2x-Loyaldk-Kororo, 2x-Loyaldk-LitePonyV2-0, 2x-Loyaldk-MediumPonyV2-0, 2x-Loyaldk-SuperPonyV2-0, 2x-NomosUni-esrgan-multijpg, 2x-Pooh-V4, 2x-StarSample-V2, 2x-UniScale-CartoonRestore-lite, 2x-VHS-upscale-and-denoise-Film, 2x-Waifaux-NL3-SuperLite, 2x-realesrgan-x2plus
- hat 2x (1): 2x-StarSample-V2-HQ
- mosr 2x (3): 2x-AnimeSharpV2-MoSR-Sharp, 2x-AnimeSharpV2-MoSR-Soft, 2x-AoMR-mosr
- omnisr 1x (4): 1x-DeJPG-OmniSR, 1x-NES-Composite-2-RGB, 1x-SEGA-Genesis-Cleanup, 1x-WhereOnEarthDeintFixL
- omnisr 2x (5): 2x-AniScale-2-OmniSR, 2x-HFA2kAVCOmniSR, 2x-OmniSR-DF2K, 2x-OmniSR-DIV2K, 2x-Where-On-Earth-Upscale-Large
- rcan 1x (1): 1x-UnResizeOnly-RCAN
- rcan 2x (2): 2x-AnimeSharpV4-Fast-RCAN-PU, 2x-AnimeSharpV4
- realplksr 1x (5): 1x-DeH264-realplksr, 1x-DeJPG-realplksr-otf, 1x-DeNoise-realplksr-otf, 1x-SuperScale-Alt-RPLKSR-S, 1x-SuperScale-RPLKSR-S
- realplksr 2x (5): 2x-90s-Sonic-LG, 2x-AnimeSharpV2-RPLKSR-Sharp, 2x-AnimeSharpV2-RPLKSR-Soft, 2x-Text2HD-v-1, 2x-VHS2HD
- span 1x (2): 1x-StarSample-V2-Lite-NS, 1x-SuperScale
- span 2x (5): 2x-AniSD-Suite, 2x-LiveActionV1-SPAN, 2x-NomosUni-span-multijpg-ldl, 2x-NomosUni-span-multijpg, 2x-StarSample-V2-Lite
- sr-res-net 2x (1): 2x-Waifaux-NL3-SRResNet
- srformer 1x (2): 1x-DeJPG-SRFormer-light, 1x-Frankenfixer-SRFormerLight
- srformer 2x (1): 2x-HFA2kAVCSRFormer-light
- swift-srgan 2x (1): 2x-Swift-SRGAN
- swinir 2x (4): 2x-classicalSR-DF2K-s64w8-SwinIR-M, 2x-classicalSR-DIV2K-s64w8-SwinIR-M, 2x-lightweightSR-DIV2K-s64w8-SwinIR-S, 2x-realSR-BSRGAN-DFO-s64w8-SwinIR-M-x2-GAN

### skip-wrong-task (23)
- cain 2x (4): 2x-cainREALTIME, 2x-cainliteanime, 2x-cvpv6, 2x-rvpV1
- cain-yuv 2x (1): 2x-explodV1
- compact 1x (9): 1x-AnimeUndeint-Compact, 1x-Book-Compact, 1x-ExposureCorrection-compact, 1x-OverExposureCorrection-compact, 1x-SkinContrast-High-SuperUltraCompact, 1x-SkinContrast-HighAlternative-SuperUltraCompact, 1x-SkinContrast-SuperUltraCompact, 1x-UnderExposureCorrection-compact, 1x-wtp-descreentone-compact
- esrgan 1x (1): 1x-KDM003-scans
- ludvae 1x (1): 1x-Ludvae200
- rife 2x (1): 2x-sudo-rife4-testV1
- sofvsr 2x (2): 2x-SBS11-RRDB, 2x-VimeoScale-Unet
- swinir 1x (1): 1x-Bendel-Halftone
- tscunet 2x (3): 2x-GameUp-TSCUNet, 2x-GameUpV2-TSCUNet-Small, 2x-GameUpV2-TSCUNet

### skip-anime (66)
- compact 1x (8): 1x-BW-Denoise, 1x-BleedOut-Compact, 1x-Dehalo-v1-Compact, 1x-Dotzilla-Compact, 1x-Epsilon-one-compact, 1x-HurrDeblur-SuperUltraCompact, 1x-RGB-max-Denoise, 1x-SwatKats-Compact
- compact 2x (17): 2x-AnimeJaNai-Standard-v1-Compact, 2x-AnimeJaNai-Standard-v1-SuperUltraCompact, 2x-AnimeJaNai-Standard-v1-UltraCompact, 2x-AnimeJaNai-Strong-v1-Compact, 2x-AnimeJaNai-Strong-v1-UltraCompact, 2x-AnimeJaNai-v2-Compact, 2x-AnimeJaNai-v2-SuperUltraCompact, 2x-AnimeJaNai-v2-UltraCompact, 2x-DigitalFlim-SuperUltraCompact, 2x-DigitalPokemon-s, 2x-HFA2kCompact, 2x-Higurashi-v1-compact, 2x-LD-Anime-Compact, 2x-ken-v1-eva-01, 2x-smbss-m, 2x-smbss, 2x-sudo-UltraCompact
- cugan 2x (3): 2x-Fallin-Soft, 2x-Fallin-Strong, 2x-sudo-shuffle-cugan-9-584-969
- dat 2x (1): 2x-Evangelion-dat2
- esrgan 1x (10): 1x-Archiver-AntiLines, 1x-Archiver-Medium, 1x-Archiver-RGB, 1x-Archiver-Rough, 1x-Archiver-Soft, 1x-DoubleDetoon, 1x-ReFocus-Cleanly, 1x-ReFocus-V3, 1x-Spongebob-De-Quantize, 1x-ThePi7on-Solidd-Deborutify-UltraLite
- esrgan 2x (15): 2x-AnimeClassics-UltraLite, 2x-AstroManLite, 2x-AstroManPlus-262k, 2x-BIGOLDIES, 2x-DBZScanLite, 2x-DigitalFilmV5-Lite, 2x-Eva16Lite-201k, 2x-Eva16Lite-64k, 2x-Garfield1-308k, 2x-HFA2kShallowESRGAN, 2x-LD-Anime-Skr-v1-0, 2x-Loyaldk-LitePonyV1-0, 2x-Loyaldk-SuperPonyV1-0, 2x-SwatKats, 2x-smbss-l
- omnisr 2x (2): 2x-DigitalPokemon-l, 2x-HFA2OmniSR
- real-cugan 2x (2): 2x-Adore, 2x-HFA2Real-CUGAN
- span 1x (4): 1x-BroadcastToStudio-SPAN, 1x-SPANGELION-INTERPOLATED, 1x-SPANGELION-SHARP, 1x-SPANGELION
- span 2x (3): 2x-GarfieldJr-span, 2x-HFA2kSPAN, 2x-ModernSpanimationV1
- swinir 2x (1): 2x-HFA2SwinIR-S

### skip-other-domain (3)
- esrgan 1x (2): 1x-ArtClarity, 1x-PixelSharpen
- esrgan 2x (1): 2x-BS-Wolly

### skip-scale (233)
- atd 4x (4): 4x-Nomos2-hq-atd, 4x-Nomos8k-atd-jpg, 4x-NomosWebPhoto-atd, 4x-RealWebPhoto-v3-atd
- compact 4x (14): 4x-FatePlusCompact, 4x-LSDIRCompact-v2, 4x-LSDIRCompact, 4x-LSDIRCompactC, 4x-LSDIRCompactC3, 4x-LSDIRCompactN, 4x-LSDIRCompactR, 4x-LSDIRCompactR3, 4x-Rybu, 4x-animerd-v1, 4x-realesr-animevideo-v3, 4x-realesr-general-wdn-x4v3, 4x-realesr-general-x4v3, 4x-realesrganv2-animevideo-xsx4
- dat 4x (23): 4x-DWTP-DS-dat2-v3-2, 4x-DWTP-DS-dat2-v3, 4x-FFHQDAT, 4x-FFHQLDAT, 4x-FaceUpDAT, 4x-FaceUpLDAT, 4x-FaceUpSharpDAT, 4x-FaceUpSharpLDAT, 4x-IllustrationJaNai-V1-DAT2, 4x-LSDIRDAT, 4x-Nomos2-hq-dat2, 4x-Nomos8kDAT, 4x-NomosUniDAT-bokeh-jpg, 4x-NomosUniDAT-otf, 4x-NomosUniDAT2-box, 4x-NomosUniDAT2-multijpg-ldl-sharp, 4x-NomosUniDAT2-multijpg-ldl, 4x-PBRify-UpscalerDAT2-V1, 4x-PBRify-UpscalerV4, 4x-Real-SSDIR-DAT-GAN, 4x-RealWebPhoto-v4-dat2, 4x-SSDIRDAT, 4x-UltraSharpV2
- drct 4x (5): 4x-Nomos2-hq-drct-l, 4x-RealWebPhoto-v4-drct-l, 4x-mssim-drct-l-pretrain, 4x-mssim-drct-pretrain, 4x-mssim-drct-s-pretrain
- esrgan 4x (117): 4x-1ch-Alpha-Lite, 4x-ArtStation1337-Dedither-v2, 4x-ArtStation1337-Dedither, 4x-BS-SbeveHarvey, 4x-BSRGAN, 4x-BigFace-V3-Blend, 4x-BigFace-V3-Clear, 4x-BigFace-v3, 4x-BigFace, 4x-Box, 4x-Cat-Patch, 4x-CountryRoads, 4x-DWTP-descreenton-H-esrgan, 4x-DeIndeo, 4x-Deoldify, 4x-DigiPaint, 4x-DigitalFake-2-1, 4x-FArtFace, 4x-FSDedither-Manga, 4x-FSDedither-Riven, 4x-FSDedither, 4x-FSMangaV2, 4x-Fabric-Alt, 4x-Fabric, 4x-Face-Ality-V1, 4x-Face-Focus, 4x-Faces-04-N, 4x-Fatality-Comix-MK3, 4x-Fatality-Comix, 4x-Fatality-MK2, 4x-Fatality, 4x-FatePlus-lite, 4x-FireAlpha, 4x-FuzzyBox, 4x-GameAI-1-0, 4x-GameAI-2-0, 4x-Ground, 4x-HDCube, 4x-HDCube2, 4x-HDCube3, 4x-HFA2k, 4x-HellinaCel, 4x-IllustrationJaNai-V1-ESRGAN, 4x-Jaypeg90, 4x-LADDIER1, 4x-LSDIR, 4x-LSDIRplus, 4x-LSDIRplusC, 4x-LSDIRplusN, 4x-LSDIRplusR, 4x-Link, 4x-Lollypop, 4x-Loyaldk-Giroro, 4x-Loyaldk-Keroro, 4x-Loyaldk-Kororo, 4x-Loyaldk-LitePonyV2-0, 4x-Loyaldk-MediumPonyV2-0, 4x-Loyaldk-SuperPonyV2-0, 4x-MinecraftAlphaUpscaler-with-Good-data, 4x-Minepack, 4x-Misc, 4x-NMKD-PatchySharp, 4x-NMKD-Siax-CX, 4x-NMKD-Superscale, 4x-NMKD-UltraYandere, 4x-Nickelback, 4x-NickelbackFS, 4x-Nickelfront, 4x-Nomos2-otf-esrgan, 4x-Nomos8kSC, 4x-NomosWebPhoto-esrgan, 4x-Normal-RG0-BC1, 4x-Normal-RG0-BC7, 4x-OLDIESFINAL, 4x-PackCraft-v4, 4x-RRDB-G-ResNet-D, 4x-RealisticRescaler, 4x-Rek-s-Effeks-Photoanime-v2, 4x-Remacri, 4x-SGI, 4x-ScreenBooster-V2, 4x-SmolFace-Clean, 4x-SmolFace, 4x-SmoothRealism, 4x-SpongeBob-Reloaded-SWAG, 4x-SpongeBob-Reloaded, 4x-Spongebob-v6-Deblur, 4x-Trixie, 4x-UltraSharp, 4x-UniScale-Balanced, 4x-UniScale-Restore, 4x-UniScale-Strong, 4x-UniScaleNR-Balanced, 4x-UniScaleNR-Strong, 4x-UniScaleV2-Moderate, 4x-UniScaleV2-Sharp, 4x-UniScaleV2-Soft, 4x-UniversalUpscalerV2-Neutral, 4x-UniversalUpscalerV2-Sharp, 4x-UniversalUpscalerV2-Sharper, 4x-VolArt, 4x-VolArtNR, 4x-WTP-ColorDS, 4x-WTP-UDS-Esrgan, 4x-Wood-BC1, 4x-detoon-alt, 4x-detoon, 4x-eula-digimanga-MiA-65k, 4x-eula-digimanga-bw-v1, 4x-eula-digimanga-bw-v2-nc1, 4x-realesrgan-x4minus, 4x-realesrgan-x4plus-anime-6b, 4x-realesrgan-x4plus, 4x-realsr-df2k-jpeg, 4x-realsr-df2k, 4x-realsr-dped, 4x-xbrz-dd
- esrgan 8x (2): 8x-MS-Unpainter-De-Dither, 8x-TGHQFace
- esrgan+ 4x (1): 4x-Valar
- grl 4x (2): 4x-HFA2k-VCISR-GRLGAN-ep200, 4x-HFA2kLUDVAEGRL-small
- hat 4x (5): 4x-HAT-L-SRx4-ImageNet-pretrain, 4x-HAT-S-SRx4, 4x-Nomos8kHAT-L-otf, 4x-Nomos8kSCHAT-L, 4x-Nomos8kSCHAT-S
- hma 4x (1): 4x-mssim-hma-pretrains
- mosr 4x (2): 4x-Nomos2-hq-mosr, 4x-mssim-mosr-pretrain
- omnisr 3x (2): 3x-OmniSR-DF2K, 3x-OmniSR-DIV2K
- omnisr 4x (6): 4x-DWTP-descreenton-VH4, 4x-DWTP-descreenton-VL4, 4x-OmniSR-DF2K, 4x-OmniSR-DIV2K, 4x-ardo, 4x-wtp-descreentone
- realplksr 4x (6): 4x-Nomos2-realplksr-dysample, 4x-NomosWebPhoto-RealPLKSR, 4x-PurePhoto-RealPLSKR, 4x-mssim-realplksr-dysample-pretrain, 4x-realplksr-gan-pretrain, 4x-realplksr-mssim-pretrain
- realplksr-dysample 4x (3): 4x-ArtFaces-realplksr-dysample, 4x-HFA2k-ludvae-realplksr-dysample, 4x-PBRify-RPLKSRd-V3
- rgt 4x (4): 4x-NomosUni-rgt-multijpg, 4x-NomosUni-rgt-s-multijpg, 4x-RealWebPhoto-v2-rgt-s, 4x-Textures-GTAV-rgt-s-dither
- sofvsr 3x (2): 3x-Video-TSSM-RRDB, 3x-Video-TSSM
- sofvsr 4x (5): 4x-REDSVAL-7f-RRDB-Lite, 4x-SOFVSR-REDS-F3-V1, 4x-VESRGAN-G, 4x-VimeoScale, 4x-video-G
- span 4x (10): 4x-ClearRealityV1, 4x-Nomos8k-span-otf-medium, 4x-Nomos8k-span-otf-strong, 4x-Nomos8k-span-otf-weak, 4x-NomosUni-span-multijpg, 4x-PBRify-UpscalerSPANV4, 4x-PurePhoto-span, 4x-SPANkendata, 4x-mssim-span-pretrain, 4x-pix-span-pretrain
- spsr 4x (2): 4x-BS-ScreenBooster-SPSR, 4x-SPSR
- srformer 4x (4): 4x-Frankendata-FullDegradation-SRFormer, 4x-FrankendataPretainer-SRFormer, 4x-HFA2kLUDVAESRFormer-light, 4x-Nomos8kSCSRFormer
- swift-srgan 4x (1): 4x-Swift-SRGAN
- swinir 3x (3): 3x-classicalSR-DF2K-s64w8-SwinIR-M, 3x-classicalSR-DIV2K-s64w8-SwinIR-M, 3x-lightweightSR-DIV2K-s64w8-SwinIR-S
- swinir 4x (7): 4x-HFA2kLUDVAESwinIR-light, 4x-PBRify-UpscalerSIR-M-V2, 4x-classicalSR-DF2K-s64w8-SwinIR-M, 4x-classicalSR-DIV2K-s64w8-SwinIR-M, 4x-lightweightSR-DIV2K-s64w8-SwinIR-S, 4x-realSR-BSRGAN-DFO-s64w8-SwinIR-M-x4-GAN, 4x-realSR-BSRGAN-DFOWMFC-s64w8-SwinIR-L-x4-GAN
- swinir 8x (2): 8x-classicalSR-DF2K-s64w8-SwinIR-M, 8x-classicalSR-DIV2K-s64w8-SwinIR-M

## 6. Apple-native execution estimates (Core ML / MLX / MPSGraph)

Method **[derived]**: ms = GFLOP / effective throughput. Two throughputs:
- **GPU path (MLX, Core ML on GPU, MPSGraph): 3.0 TFLOP/s effective [derived].** Calibration: hanxiao/real-esrgan-coreml benchmarked an M3 Ultra, fp16, `general` (SRVGGNetCompact nf64 nc32, x4) at 0.03 s for a 512x512 input and `animevideo` (nc16) at 0.02 s [stated, README], which is about 21 and 16 TFLOP/s by my FLOP count; scaled by M1 Pro / M3 Ultra GPU peak (5.2 / ~28 TFLOPS) gives ~3-4 TFLOP/s. This is the same order as the 1.6 TFLOP/s measured for ArtCNN GLSL.
- **ANE path, optimistic: 6.5 TFLOP/s [derived].** Calibration: PiperSR 22.5 ms for 640x360 on M2 Max ANE [stated, README, vendor figure, unverified], 453k params = about 9.3 TFLOP/s effective; scaled by 11/15.8 TOPS (M1 Pro / M2 Max). Caveats: fixed shapes only; hanxiao's README states Core ML does not place RRDBNet or SRVGGNetCompact on the ANE (concat/residual patterns) and runs them on the GPU, so for Compact/ESRGAN use the GPU figure; memory bandwidth and the ~1080p tile limits are ignored; fp16 only.
- Both ignore decode, colour conversion and hand-off cost: use ~35 of the 41.7 ms.

Per-record figures are in CSV `coreml_or_mlx_ms_est` (720p and 1080p, ANE-opt / GPU). Highlights:

| model | GFLOP 720p | 720p ms ANE-opt / GPU | 1080p ms ANE-opt / GPU | fits 35 ms? |
|---|---|---|---|---|
| SuperUltraCompact nf24/nc8 1x (pretrain or SkinContrast weights) | 79 | 12 / 26 | 27 / 59 | 1080p only if ANE really takes it; GPU no |
| Debandurh Ultra-lite 1x (unshuffle layout, **[assumed]**) | 80 | 12 / 27 | 28 / 60 | same as above; 15x worse if full-res layout |
| Kim2091 DeJpeg v0 1x (nf16 nb8) | 273 | 42 / 91 | 94 / 205 | no |
| Swift-SRGAN 2x | 356 | 55 / 119 | 123 / 267 | no |
| 2xLiveActionV1-SPAN | 755 | 116 / 252 | 261 / 566 | no |
| 2xNomosUni-compact-otf-medium / 2xParimgCompact | 1103 | 170 / 368 | 382 / 827 | no |
| 2xOmniSR DF2K | 1549 | 238 / 516 | 536 / 1161 | no |

**Existing ports (searched on GitHub 2026-10-02):**
- Real-ESRGAN family (Compact nf64 nc16/nc32 x4, RRDBNet x2/x4): Core ML `hanxiao/real-esrgan-coreml` (*11, no license stated), MLX `hanxiao/real-esrgan-mlx`, `xocialize/realesrgan-mlx` and `xocialize/realesrgan-mlx-swift` (MIT, tile-based). These implement the Compact/RRDBNet architectures, so an OMDB Compact `.pth` of the same shape could be loaded after weight conversion, but none of the OMDB 1x/2x records has been converted.
- `blka/ane-superres` (MIT): Core ML on the ANE, Real-ESRGAN animevideov3 x4, **103 ms/frame at 720x576 on an M4 Air [stated]**, i.e. not real-time.
- `thomas-sky2024/video-scale-mlx`: ~0.4 s/frame 720p video on M1 Pro [stated, approximate].
- `ModelPiper/PiperSR`: Core ML .mlpackage 928 KB, 2x locked 360p to 720p, 22.5 ms on M2 Max [stated]; AGPL code, CC BY 4.0 weights. Wrong input size for amp.
- `xocialize/efrlfn-mlx` (EfRLFN, ICLR 2026, "real-time" x2/x4): ~0.46M MAC/px **[derived from README: feature 52, 6 ERLFB]**, about 850 GFLOP per 720p frame; README claims 270x480 to 1080x1920 in ~0.06 s. Not real-time at 720p/1080p input here.
- `xocialize/mlx-nerve-swift` (NERVE x2/x4, Apache-2.0): ~21 ms per output megapixel on an M5 Max [stated]; x2 HD to 4K 0.59 s. No.
- No Core ML/MLX/Metal port exists for SPAN, OmniSR, DAT, or any OMDB 1x record (searched: "span coreml", "mpsgraph super resolution", "metal super resolution video": zero hits).
- Metal: Anime4KMetal (`imxieyi`, Apache-2.0) is anime-only and cannot load other weights.

**Apple-native ranking (best real-time chances first), all [derived]:**
1. A custom-trained SRVGGNetCompact nf24/nc8 (or smaller) 1x restorer on live-action H.264/HEVC pairs, exported to Core ML (ANE-first, GPU fallback). 79 GFLOP/720p; ~27 ms at 1080p only under the optimistic ANE estimate; a nf16/nc6 variant (~27 GFLOP/720p by the same formula) would sit at ~9 ms (ANE-opt) to ~20 ms (GPU) at 1080p.
2. `1x-Debandurh-FS-Ultra-lite` through Core ML, **only after checking the weight layout** (see 7).
3. Everything else misses by 4x or more (Kim2091 DeJpeg 273, Swift-SRGAN 356, LiveActionV1-SPAN 755 GFLOP per 720p frame).
A model that runs at a lower internal resolution (restore at 720p then scale) is the standard trick: LiveActionV1-SPAN on a 540p luma crop is still ~420 GFLOP. Not enough.

## 7. Closer look: 1x/2x realistic/compression records within ~3x of budget (or close)

| record | arch / cost | source facts | what it takes in mpv / Apple-native |
|---|---|---|---|
| 1x-Debandurh-FS-Ultra-lite | ESRGAN nf8 nb3, 2.7 MB pth, CC-BY-NC-SA-4.0, twittman 2020, debanding+restoration, dataset "Anime, real life, manga", empty description (OMDB) | 80 GFLOP/720p if unshuffle layout, ~1.2 TFLOP if not **[derived]** | Read `conv_first.weight` shape from the .pth: 48 input channels = unshuffle layout (fits), 3 = full-res (does not). No GLSL exporter; RRDB has dense concat, so GLSL is awkward; Core ML via coremltools is the path. Mixed anime/real training, deband only. |
| 1x-Kim2091-DeJpeg-v0 | ESRGAN nf16 nb8, 9.2 MB, CC-BY-NC-SA-4.0, 2022 | 273 GFLOP (4.9x budget), up to ~4.2 TFLOP if full-res layout | author calls it incomplete, JPEG-only. Too slow and wrong codec; skip. |
| 1x-SuperUltraCompact-Pretrain / 2x | Compact nf24 nc8, 0.36 / 0.38 MB, WTFPL, zarxrax 2022 | 79 / 82 GFLOP | Not a restorer: pretrain init. Use as the **starting weights for a custom fine-tune** (it exists to be interpolated with Compact models). |
| 1x-SkinContrast-*-SuperUltraCompact (3) | Compact nf24 nc8, 0.18 MB, CC0, brigadeiro 2024 | 79 GFLOP | contrast enhancer; tags over-broad; marked wrong-task. |
| 2xLiveActionV1_SPAN | SPAN nf48, pth 8.9 MB + ONNX 1.65 MB, CC-BY-NC-SA-4.0, jcj83429 2025 | 755 GFLOP (13.5x budget) | Trained on JPEG/MPEG-4/H.264/VP9/H.265, chroma subsampling, halos, deinterlace jaggies, no denoise, consistency loss (OMDB description [stated]). Quality reference for offline comparison (VMAF against amp's shader stack), license is non-commercial. A GLSL port would have 6 SPAB blocks of 3x3 convs at 48 ch; at 755 GFLOP no GLSL implementation could run it. |
| 2xNomosUni-compact-otf-medium | Compact nf64 nc16, 2.4 MB, CC-BY-4.0, helaman | 1103 GFLOP | Real-ESRGAN-style OTF degradations (jpg, noise, blur); 20x budget. |

Existing ONNX-to-GLSL exporter for any of these: **none found** (ArtCNN repo, CuNNy `mpv.py` and igv scripts are model-specific). The generic route with an existing tool is ONNX to Core ML (`coremltools`) or MLX (hand-written; Compact and RRDBNet exist as MLX modules).

## 8. GitHub findings: non-anime real-time shaders for compressed video

Already installed (not rediscovered): ArtCNN C4F16/C4F32 (+DN/DS), FSRCNNX x2 8/16, ravu-zoom-ar-r3, CfL, KrigBilateral, SSimSuperRes/Downscaler, CAS, adaptive-sharpen, hdeband, nlmeans, noise_static. Newer versions: ArtCNN latest release is still v1.6.2 (2026-03-14); FSRCNNX latest still 1.1 (checked via API 2026-10-02).

| find | repo / license / size | what it does | domain | cost data |
|---|---|---|---|---|
| Debandit v3.4 | https://github.com/sup3rflyer/Wicket-shaders, GPL-3.0, Debandit.glsl 94 KB | detect-and-reconstruct deband (weighted plane fit, trust mask, chroma path) | any | none published; check it works on MoltenVK compute |
| TextureClarity | same repo, GPL-3.0, 8 KB | sharpening with coring and texture-variance floor (avoids sharpening noise) | any | none; params tc_strength/coring/texture_thresh |
| filmgrain-smooth (SDR light/medium/heavy) | same repo, GPL-3.0, 5.4 KB each (+19.8 KB `filmgrain-smooth.glsl`, 200 KB `filmgrain-match.glsl`) | film-grain synthesis in an OUTPUT-stage compute hook, uses `//@shampv` header (plain comments to libplacebo) | live-action | none |
| JointBilateral / FastBilateral | https://github.com/Artoriuz/glsl-joint-bilateral, MIT, 9.5 KB / 3.3 KB | chroma upscaler (joint bilateral) | any | none (KrigBilateral already installed) |
| PixelClipper | https://github.com/Artoriuz/glsl-pixel-clipper, MIT, 6.5 KB | clips ringing/overshoot of a prescaler | any | none |
| Anime4K Denoise_Bilateral Mean/Median/Mode | https://github.com/bloc97/Anime4K, MIT, 2.8-4.3 KB each | small bilateral/median denoisers | tuned for anime but generic filters | Anime4K reports no ms here |
| bShaders | https://github.com/butterw/bShaders (no license, mpv `.hook` colour tools) | grading only | any | irrelevant to compression |
| webgpu-video-shaders | https://github.com/kbrandwijk/webgpu-video-shaders | WGSL ports of libplacebo shaders | n/a | WGSL, not GLSL |
| MagpieExtras / MagpieToys | https://github.com/Blinue/MagpieExtras (GPL-3.0) | Windows Magpie HLSL effects | n/a | not usable in mpv |

Searched with no hits (treat as "not found", not "does not exist"): `mpv deblock shader`, `mpv shader debanding`, `mpv denoise shader glsl`, `film grain synthesis glsl mpv` (the grain shaders above came from a different query), and Magpie/AviSynth/VapourSynth community lists were not exhaustively walked for lack of budget. Licensing note: the Wicket shaders are GPL-3.0; check that fits amp's licence before bundling.

## 9. What is NOT possible in real time, and why

- **Any trained model that handles real H.264 artefacts well at 720p-1080p source**: the cheapest verified one is LiveActionV1-SPAN at ~755 / 1700 GFLOP per frame (720p / 1080p) [derived]. M1 Pro GPU peak is 5.2 TFLOPS, so even at 100% utilisation it needs 145 / 330 ms per frame; at the measured 1.6-3 TFLOP/s it is 250-1000 ms. A 24 fps budget is 41.7 ms.
- **Transformers (DAT, SwinIR, HAT, SRFormer, ATD, DRCT)**: 20-30 TFLOP per 720p frame [derived]; windowed attention also does not map to GLSL.
- **Mainstream ESRGAN RRDB (nf64 nb23)**: 2-30 TFLOP per frame depending on layout.
- **Multi-frame / temporal models (TSCUNet, SOFVSR, RIFE, CAIN)**: need frame stacks or are interpolators; wrong task.
- **GLSL conversion of any of the above**: no tool exists; the shader would also exceed the budget by 10x or more.
- Apple's own VT low-latency SR (previous survey) is 1.5x at 720p only; not re-checked here.
- ANE paths carry fixed-shape and per-chip uncertainty; my ANE figures are an optimistic ceiling.

## 10. Where this differs from the 2026-09-30 survey

1. That survey said every real-life OMDB model is 30x-600x over budget. True for realistic mainstream models, but it **missed the 1x tiny ESRGAN class** (Debandurh nf8 nb3 = 80 GFLOP, Kim2091 DeJpeg nf16 nb8 = 273 GFLOP), because it filtered on tags/architecture names.
2. It listed `1xSkinContrast-SuperUltraCompact` as a candidate-sized photo model; it is a contrast enhancer with over-broad tags, so I mark it wrong-task (size-class example only).
3. SPAN cost: 1079 there (unfused module) vs 755 here (Conv3XC fused).
4. It reported no Apple-native ports for the Real-ESRGAN family beyond one MLX Swift repo; there are also Core ML (`hanxiao`, `blka`, `thomas-sky2024`), MLX Python (`hanxiao`, `xocialize`), EfRLFN-MLX, NERVE-MLX, RealPLKSR-MLX (4x). Two give timings usable for calibration (hanxiao M3 Ultra, blka M4).
5. It said "no GLSL/mpv exporter found"; still true. New finds are the Wicket-shaders (Debandit, TextureClarity, grain) and Artoriuz bilateral/clipper shaders.
6. Counts agree: 671 records both times.

## 11. Ranked shortlist to benchmark in amp

1. **Custom Compact nf24/nc8 (or smaller) live-action restorer, fine-tuned from the SuperUltraCompact pretrain** (https://objectstorage.us-phoenix-1.oraclecloud.com/n/ax6ygfvpvzka/b/open-modeldb-files/o/1x-SuperUltraCompact-Pretrain.pth, 362 KB, WTFPL). First benchmark the cost shape only: build random-weight Core ML / MLX nf24/nc8 net and time 720p/1080p frames to confirm 27 / 59 ms (ANE / GPU).
2. **1x-Debandurh-FS-Ultra-lite** (https://objectstorage.us-phoenix-1.oraclecloud.com/n/ax6ygfvpvzka/b/open-modeldb-files/o/1x-Debandurh-FS-Ultra-lite.pth, 2.7 MB, CC-BY-NC-SA-4.0): check the layout, then time through Core ML.
3. **Debandit.glsl** (94 KB, GPL-3.0) https://github.com/sup3rflyer/Wicket-shaders: real-time banding fix, compare against installed hdeband.
4. **TextureClarity.glsl** (8 KB, GPL-3.0): coring sharpener, compare against CAS/adaptive-sharpen on compressed sources.
5. **filmgrain-smooth-SDR-light.glsl** (5.3 KB, GPL-3.0): hides banding/plastic look after restoration.
6. **PixelClipper.glsl** (6.5 KB, MIT) https://github.com/Artoriuz/glsl-pixel-clipper: ringing clamp after FSRCNNX/ArtCNN.
7. **2xLiveActionV1_SPAN ONNX** (https://github.com/jcj83429/upscaling/raw/f73a3a02874360ec6ced18f8bdd8e43b5d7bba57/2xLiveActionV1_SPAN/2xLiveActionV1_SPAN_490000.onnx, 1.65 MB, CC-BY-NC-SA-4.0): offline ceiling for VMAF only, not playback.

Sources: OMDB repo `data/models/*.json`, `data/architectures.json`, `src/lib/derive-tags.ts`; READMEs of hanxiao/real-esrgan-coreml, blka/ane-superres, xocialize/efrlfn-mlx, xocialize/mlx-nerve-swift, thomas-sky2024/video-scale-mlx, ModelPiper/PiperSR; GitHub API listings and raw file headers for Wicket-shaders, glsl-joint-bilateral, glsl-pixel-clipper, Anime4K, ArtCNN, FSRCNN-TensorFlow.
