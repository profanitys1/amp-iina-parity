# MPVKit fork rebuild: vsync + libplacebo/mpv master — design

Date: 2026-10-03. Status: approved by the user 2026-10-03 (approach B).
Builds on `docs/research/2026-10-02-backend-quality-review.md` (sections 0, 2, 5, 6, 8 items 6–7).

## Goal

Every video plays with no sustained dropped or repeated frames on the 120 Hz ProMotion panel, including 25 fps, and HDR footage gets libplacebo's 2026 tone-mapping rewrite. This applies to all sources, compressed or not.

## Why now

- `video-sync=display-resample` + `interpolation=yes` dropped about 20 frames per 40 s in amp.app on 2026-10-02, even at 7 ms GPU load. Cause: MPVKit's `moltenvk` gpu-context (patch `0001-player-add-moltenvk-context.patch`) has no `get_vsync` / presentation-feedback hook, so mpv times against the nominal `display-fps-override`.
- No upstream release has landed since the research (checked 2026-10-03): MoltenVK v1.4.2, libplacebo v7.360.1, MPVKit 1.0.0, no mpv tag after 0.41.0.
- libplacebo master (API 7.374) is additive over 7.360.1: new fields and two deprecations, no removals.

## Pins

| Component | Now | New |
|---|---|---|
| libplacebo | v7.360.1 | master `92b5ac6db79f4d680eb656692f7bf51e9606f42a` (2026-10-01) |
| mpv | v0.41.0 | master `3186d369f9` (2026-09-29) |
| MoltenVK | 1.4.2 | unchanged |
| FFmpeg | n8.1.2 | unchanged |
| Other MPVKit targets | Truls's `aagedal-1.0.0-*` release URLs | unchanged |

What the new pins bring: HDR spline/hyperbolic tone mapping, per-cone tone mapping, mastering-peak soft clip, gamut folding, HDR10+ scene max, Dolby Vision FEL composition (libplacebo); linear-light frame blending for interpolation; dither no longer lifts black; AV1/H.274 grain fixes; Vulkan sync and threading fixes; mpv's 2026-09-01 "keep hwdec frames mapped while the queue holds them" and 2026-09-29 "defer the queue reset until a new frame arrives".

## Components

1. **Fork.** Fork `aagedal/MPVKit` to `profanitys1/MPVKit`. Build Libplacebo and Libmpv-GPL with the `mpvkit/*-build` scripts (same toolchain as `~/src/moltenvk-build`), macOS platform only, GPL variant. Build logs go to the scratch directory, not the repo.
2. **Patch rebase.** Re-apply MPVKit's `libmpv` patches (`0001` moltenvk context, `0002` revert static build, `0003` avfoundation ao tvos) onto mpv master. If `0003` does not apply and is tvOS-only, drop it and record why.
3. **Vsync hook.** Extend the `moltenvk` context in patch `0001` with a `get_vsync` callback. Source: a `CVDisplayLink` bound to the display that currently shows the layer, ported from upstream mpv's `macvk` timing (`video/out/mac/common.swift`, commit "add support for frame timing via presentation feedback", 2024-04-06). It reports vsync interval, last vsync time and skipped vsyncs. On display change (window moves screens) the link is re-bound. If no link can be created, the callback reports nothing and mpv behaves as today.
4. **Release.** Zip the two xcframeworks, compute SwiftPM checksums, publish them as a release on `profanitys1/MPVKit` (the user confirms before publishing), and point the fork's `Package.swift` at them for those two targets only.
5. **amp pin.** Change amp's MPVKit dependency to the fork revision, update `Package.resolved`, and update the version-floor paragraph in `CLAUDE.md`.
6. **amp playback options.** Viewing profiles (every profile except Faithful/`off`) set `video-sync=display-resample`, `interpolation=yes`, `tscale=oversample`. `hwdec-extra-frames=4` is set before `mpv_initialize`, because the hwdec pool is sized at decoder init. Faithful stays on `video-sync=audio` with interpolation off, so inspection shows untouched frames. Switching profiles at runtime updates `video-sync` and `interpolation` together.

## Verification (amp.app only, never a standalone mpv)

- Build Release, install to `/Applications/amp.app`, bench with the GPU log as in memory `amp-run-and-bench`.
- Smoothness: 24, 25, 30 and 60 fps clips, fullscreen, 40 s each, on Chroma and Compressed movie profiles. Pass: drop counter does not rise after warm-up (today: about 20 per 40 s).
- GPU cost: per-profile ms/frame does not regress more than 10 % against the 2026-10-02 table.
- HDR: one iPhone HDR clip (HLG or DV 8.4) shows no hue shift or clipping against the current build, judged on a fixed frame in fullscreen.
- Regression: full unit suite passes (634 passed, 0 failed, 5 skipped baseline).

## Error handling and fallbacks

- mpv master fails to build or the patches do not rebase in reasonable effort: fall back to approach A (mpv v0.41.0 + libplacebo master + vsync patch).
- Vsync hook builds but drops persist: ship the libplacebo/mpv gains with `video-sync=audio`, record measurements in `docs/research`, and stop.
- HDR regression from libplacebo master: try the previous master commit range; if unresolved, keep libplacebo v7.360.1 and ship only the vsync work.

## Out of scope

Native Metal backend (libplacebo #380), MoltenVK 1.4.3 (unreleased), `vf_fruc_vulkan`, Apple `VTFrameProcessor` interpolation or super resolution, SDR colour-path verification and deband on light profiles (separate cheap sub-project), iOS/tvOS builds.
