# gaia.mov upscaler benchmark — 2026-09-30

Source: /Users/filip/Downloads/Movies/gaia.mov (ProRes 422 HQ 1280x720p30, 10-bit 4:2:2, BT.601).
Segment: 10 s from t=120 s (300 frames). Frames were never viewed; metrics only.

## Quality (2x reconstruction)
ref = 720p segment; input = ref downscaled 2x (bicubic, 640x360); candidate = libplacebo upscale back to 1280x720
with the mpv shader via /Users/filip/ffmpeg-apple-silicon/dist/9.0.1/full/ffmpeg (libplacebo 7.360.1, same as amp);
scored with libvmaf vmaf_v0.6.1 + psnr + float_ssim on yuv420p.

| Upscaler | VMAF | PSNR-Y dB | SSIM |
|---|---|---|---|
| lanczos (Faithful) | 91.323 | 39.407 | 0.99910 |
| ArtCNN_C4F16 | 98.879 | 43.151 | 0.99940 |
| ArtCNN_C4F32 | 98.847 | 43.168 | 0.99939 |
| FSRCNNX_x2_16-0-4-1 | 98.492 | 44.597 | 0.99956 | (re-rendered with ffv1 -slicecrc 1; the first render had a corrupt frame and scored 98.031 / 44.354) |
| ArtCNN_C4F16_DS | 99.995 | 43.156 | 0.99863 | (VMAF rewards its sharpening; SSIM is lower than neutral) |
| ArtCNN_C4F16_DN | 93.081 | 41.420 | 0.99841 |
| SSimSuperRes (+ewa_lanczossharp) | 97.304 | 41.455 | 0.99891 |
| FSRCNNX_x2_8-0-4-1 | 97.184 | 42.807 | 0.99677 |
| ravu-zoom-ar-r3 | — | — | — | ffmpeg libplacebo filter segfaults (exit 139); mpv runs it fine |

## Speed (real playback, fullscreen 3448x2164 = 2.694x, mpv 0.41.0, hwdec=videotoolbox, M1 Pro)
| Stack | ms/frame (vo-passes) | drops |
|---|---|---|
| faithful | 5.8 | start-up only |
| ravu-zoom-ar-r3 | 10.7 | 0 |
| SSimSuperRes | 11.2 | 0 |
| ArtCNN_C4F16 | 13.7 | 0 |
| ArtCNN_C4F32 | 39.1 | ~15/s |
| FSRCNNX_x2_16-0-4-1 | 15.2 + unsampled final pass (~0.9) | 0 |
| FSRCNNX_x2_8-0-4-1 | 10.6 | 0 |
| ArtCNN_C4F16_DS | 13.8 | 0 |

Finding: C4F32 is no better than C4F16 on this content (VMAF 98.85 vs 98.88) at ~3x the cost.

Finding: with FSRCNNX_x2_16 loaded, mpv never samples the final output pass (count 0 while 29 shader passes reach 256). `VOPassTiming` now ignores unsampled passes (commit 2569bc3).

Decision (commit 2569bc3): the heaviest tier is FSRCNNX_x2_16 (best PSNR-Y and SSIM, ~16 ms, fits the 16.7 ms budget at 30 fps); ArtCNN_C4F32 is dropped.

## Apple low-latency super-resolution (probed on this Mac, macOS 27.0.1, M1 Pro)
`VTLowLatencySuperResolutionScalerConfiguration`: supported = true; factors for 1280x720 = [1.5]; for 640x360 = [1.5, 2.0];
max source dimension per factor: 1.5x -> 1280, 2.0x -> 960, 4.0x -> 480. So a 720p source can only go to 1920x1080 here.
