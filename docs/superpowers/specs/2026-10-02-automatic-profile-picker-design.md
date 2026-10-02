# Automatic render-profile picker — design

Date: 2026-10-02. Status: approved by the user 2026-10-02.
Supersedes the ratio-only Enhance tier ladder (`docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md`).

## Goal

When a file opens, amp chooses a shader profile that fits the file's actual quality and the GPU budget. This matters because sources of the same resolution differ: a Topaz-enhanced 1080p ProRes, a 2 Mbit/s web 1080p and a blown-up 480p need different processing.

## Behaviour

- A new `RenderProfile.automatic` ("Automatic") appears in Settings → Rendering → Profile. Picking any concrete profile there overrides it.
- Automatic applies its choice without asking. The existing badge (`RenderTierBadge`) shows `Auto · <profile> · <reason>`, e.g. `Auto · Compressed movie · 2.1 Mbit/s`.
- The Enhance toggle and its ratio-based tier ladder are removed, because Automatic replaces them. `RenderTier`, `TierSelector` and `RenderTierTests` are deleted. `GPUBudgetMonitor` is kept. Settings migration: a stored `enhance = true` with profile Faithful becomes profile Automatic, and the `enhance` key is then removed. Automatic is the new app-wide default (`AppSettings.renderProfile` default becomes `automatic`), replacing the earlier faithful-by-default decision at the user's request; Faithful stays one click away in the Profile list.

## Source classes and mapping

| Class | Detection | ≤ 30 fps | > 30 fps (16.7 ms frame) |
|---|---|---|---|
| hdr | PQ/HLG transfer (existing gate) | Faithful | Faithful |
| topaz | container or stream tag `videoai` or `videoai_provider` | Neural upscale — light | Sharpened upscale |
| compressed | low bits per pixel, or high blockiness | Compressed movie | Efficient upscale |
| soft | low detail ratio (an upscale of a lower-resolution source) | Crisp | Sharpened upscale |
| clean | everything else | Neural upscale — light | Sharpened upscale |

Precedence: hdr > topaz > frame-stat classes. Topaz output is already denoised and sharpened, so it never gets DS/DN or adaptive-sharpen.

## Components

1. **`SourceFacts`** (value type): codec, width, height, fps, video bitrate, bit depth, isHDR, Topaz tag text. It is built from metadata amp already loads (SwiftMediaMetadata `MediaMetadata` plus mpv `video-bitrate`). bits per pixel = bitrate / (width × height × fps).
2. **`FrameStats`** (value type): `detailRatio`, `blockiness`, `noise`, each a 0–1 or ratio value averaged over the sampled frames.
3. **`FrameAnalyzer`** (actor): it runs the bundled ffmpeg (`FFmpegService.ffmpegPath`) to decode 8 luma frames spread evenly through the file (skipping the first and last 5 %), as raw `gray` at source resolution, and computes with Accelerate:
   - detail ratio: mean absolute difference between a frame and the same frame downscaled 2× and upscaled back (bilinear), normalised by the frame's mean gradient. Low means little real high-frequency detail.
   - blockiness: mean absolute luma step across 8-pixel column/row boundaries divided by the mean step at non-boundary positions. Values well above 1 mean visible blocking.
   - noise: median local standard deviation over the flattest 10 % of 8×8 blocks.
   It caches results in memory keyed by path, size and modification date. It is cancellable and never runs on the main actor.
4. **`SourceClassifier`** (pure): `(SourceFacts, FrameStats?) -> (SourceClass, reason: String)`. When `FrameStats` is nil, only metadata rules apply (hdr, topaz, compressed by bits per pixel, else clean).
5. **`ProfilePicker`** (pure): `(SourceClass, fps, sourcePixels, drawablePixels) -> RenderProfile`. Each class has a fallback chain, for example compressed: Compressed movie → Efficient upscale → Sharpened upscale → Chroma reconstruction → Faithful. It takes the first profile whose estimated cost ≤ 0.8 × frame period. Cost estimate = measured ms (fullscreen 3448×1940, 1080p source; table from `docs/research` / memory `amp-run-and-bench`) × (sourcePixels / 1080p pixels) × (drawablePixels / 3448×1940 pixels).
6. **MPVPlayer wiring**: on file load with profile `.automatic`, it applies the metadata-only pick immediately, starts `FrameAnalyzer`, re-picks when the stats arrive, and re-applies only if the pick changed. When the drawable size changes (fullscreen, resize), it re-picks with the same stats. When `GPUBudgetMonitor` reports over budget, it moves one step down the chain for the rest of the file.

## Thresholds and calibration

The bits-per-pixel, detail-ratio, blockiness and noise thresholds start from defaults and are then set from a calibration run. The run is a script that prints facts, stats and the resulting class for every video in the user's folders (`~/Downloads/Movies`, `~/Downloads/whatsapp`, `~/Downloads/Archives/Movies`). It records numbers only and views no frames. The user approves the thresholds before they are fixed in code.

## Error handling

- No ffmpeg, a decode failure, a file shorter than 2 s, or analysis taking more than 5 s: keep the metadata-only pick and log why.
- A missing shader file: existing `ShaderLibrary` behaviour, which drops the missing file and keeps the rest.
- If the file changes during analysis, the analysis is cancelled and its result discarded.

## Testing

- Unit: `SourceClassifier` covers each class and the precedence rules. `ProfilePicker` covers fallback at 24, 30 and 60 fps, 720p and 1080p sources, and windowed versus fullscreen drawables. `FrameAnalyzer` maths is tested on synthetic frames (an 8×8 block pattern gives high blockiness, a blurred upscale gives low detail ratio, Gaussian noise gives high noise).
- Integration: the analyzer runs on a generated ffmpeg fixture and stays within stated bounds.
- On device, in amp.app only (never a standalone mpv): one file per class shows the expected badge and profile; a fullscreen GPU-log run shows no sustained drops; a 60 fps Topaz file lands on a light profile.

## Out of scope

The 25 fps display-resample fix (needs an MPVKit vsync patch), trained classifiers or models, enhancement on HDR, and disk-persisted analysis cache.
