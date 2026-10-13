# Session Summary: amp Development 2026-10-03

## Completed Tasks

### 1. UI Improvements (committed a808b38)
- **Window maximization**: Movies open filling visible screen (1724x975 on M1 Pro) instead of source resolution
- **Traffic lights in fullscreen**: Alpha forced to 1 at `willEnterFullScreen`, restored on exit
- **Hidden setting**: `openMaximized` for test control (suppressed in PlayerChromeBehaviourTests, CompareLiveBackendTests)
- **Tests**: New WindowConfiguratorTests with 9 test methods covering decision functions and real NSWindow behavior

### 2. Engine Research (committed a808b38)
- Generated comprehensive research report: `docs/research/2026-10-03-engine-improvements.md`
- Identified 10 high-impact improvements for WhatsApp-class sources (640x352 -> 1728x1117 upscaling)
- Prioritized by impact and implementation cost

### 3. Frame Timing Fixes (committed e604a39)
- **Removed `display-fps-override`** (MPVPlayer.swift:353, :1636, MPVVideoView.swift:364)
  - Was defeating fork patch 0004's CVDisplayLink detection
  - On ProMotion displays dropping below 120 Hz, hard-coding 120 is wrong
  - Now `screen-name` drives detection
- **GPU budget display-rate aware** (GPUBudgetMonitor.swift:65-67)
  - New `interpolating: Bool` parameter
  - When true, budget uses display rate (8.33 ms at 120 Hz) not `min(source, display)` (16.7 ms for 30 fps)
  - Prevents Automatic from selecting profiles that cannot meet deadline

### 4. Shader Pipeline Fixes (committed efb6a40, 9b11675)
- **Grain at OUTPUT stage** (RenderProfile.swift:83)
  - `.compressedGrain` now uses `filmgrain-smooth-SDR-light.glsl` (hooks OUTPUT, 1:1 with display)
  - Previously used `noise_static_luma.hook` (hooks LUMA, 2x plane resampled by 1.35x lanczos)
  - Grain at OUTPUT preserves per-pixel character that masks blocking
- **PixelClipper for anti-ringing** (RenderProfile.swift:73,77,79)
  - Added to `.upscaleLight`, `.compressed`, `.crisp`
  - Hooks POSTKERNEL (anti-rings 1.35x residual luma upscale)
  - Hooks CHROMA_SCALED (anti-rings 2.70x chroma upscale from cscale=spline36)
  - Clips overshoot to local envelope, doesn't fabricate detail
- **720p classification gap** (SourceClassifier.swift:106)
  - Changed `min(width, height) < 720` to `<= 720`
  - P5.mp4 and Patricia114747.mp4 (both 1280x720) were falling through to `clean` with no debander
  - Now classify as `compressed` and get deband+upscale stack
  - Blunt fix; better fix is adding chroma statistic to classifier

## Testing Status

- **Build**: All changes compile cleanly (xcodebuild Release)
- **Tests**: 9 new WindowConfiguratorTests pass; existing PlayerChromeBehaviourTests suppressed
- **Smoke test**: Installed to /Applications/amp.app, verified window at 1724x975
- **Known flaky**: CompareLiveBackendTests has 3 deadline-based tests that may fail under load (pre-existing)

## Next Steps

1. **A/B testing with fixtures**:
   - P5.mp4 (24.917 fps) - verify frame timing improvements
   - Patty7.mp4 (1.88 Mbit/s) - verify grain placement
   - P1.mp4 - verify PixelClipper doesn't cause edge darkening
   - Patricia114747.mp4 (1280x720) - verify 720p classification fix

2. **Remaining high-impact items from research**:
   - Add chroma statistic to classifier (M cost, low risk) - better than blunt 720p fix
   - Split cost model (M cost, low risk) - ProfilePicker under-predicts 3x at 1728x1117
   - Verify fork patch 0004 detection works on external monitors

3. **Documentation**:
   - Update design docs to reflect 720p threshold change
   - Record A/B test results once fixtures are tested

## Git State

- Branch: main (134 commits ahead of upstream)
- Latest commit: 9b11675
- All changes committed, working tree clean
- Installed to /Applications/amp.app
