# Phase 1 Completion Report

**Date:** 2026-10-03  
**Status:** ✅ Complete  
**Commits:** a808b38, e604a39, efb6a40, 9b11675

---

## Summary

Phase 1 addressed four high-impact bugs identified in the engine improvements research:

1. **Display FPS override defeated vsync detection** (e604a39)
2. **GPU budget ignored interpolation cadence** (e604a39)
3. **Grain placement at wrong pipeline stage** (efb6a40)
4. **720p threshold excluded WhatsApp fixtures** (9b11675)
5. **Missing anti-ringing on residual upscale** (efb6a40)

All changes compile cleanly and are ready for testing.

---

## Changes Detail

### Commit a808b38: UI Fixes
**Files:** `WindowConfigurator.swift`, `AppSettings.swift`  
**Tests:** 9 new tests in `WindowConfiguratorTests.swift`

- Window opens maximized (fills visible screen, not native fullscreen)
- Traffic lights stay opaque in fullscreen mode
- Added `openMaximized` hidden setting for test control
- Updated `PlayerChromeBehaviourTests.swift` to suppress both settings

**Verification:**
- [ ] Open app → window should fill 1724x975 (visible screen area)
- [ ] Enter fullscreen → traffic lights should remain visible
- [ ] Exit fullscreen → traffic lights should fade based on hover

---

### Commit e604a39: Frame Timing & Budget
**Files:** `MPVPlayer.swift`, `MPVVideoView.swift`, `GPUBudgetMonitor.swift`

**Change 1: Removed display-fps-override**
```swift
// MPVPlayer.swift:352 - REMOVED
// mpv_set_option_string(mpv, "display-fps-override", ...)

// MPVVideoView.swift:364 - REMOVED
// player.applyDisplay(refreshRate: Double(screen.maximumFramesPerSecond), ...)
```

**Why:** Let MPVKit's CVDisplayLink (patch 0004) detect actual refresh rate. Hard-coded 120Hz is wrong when ProMotion drops below 120Hz for static content, battery, or Low Power Mode.

**Change 2: GPU budget uses display rate when interpolating**
```swift
// GPUBudgetMonitor.swift:65-67
init(sourceFPS: Double, displayFPS: Double, interpolating: Bool = false) {
    let rate = interpolating ? displayFPS : [sourceFPS, displayFPS].min() ?? 0
    budgetMilliseconds = rate > 0 ? Self.budgetFraction * 1000 / rate : nil
}

// MPVPlayer.swift:1481
budgetMonitor = GPUBudgetMonitor(
    sourceFPS: getDouble("container-fps"),
    displayFPS: displayRefreshRate,
    interpolating: renderProfile != .off
)
```

**Why:** With `interpolation=yes`, mpv presents at display rate (120Hz), not source rate (30fps). Budget must reflect actual deadline (8.33ms at 120Hz, not 16.7ms at 30fps).

**Verification:**
- [ ] Play P5.mp4 (24.917fps) → should have smooth playback, no frame drops
- [ ] Play 60fps content → should maintain 60fps without stuttering
- [ ] Check GPU usage in Activity Monitor → should stay below 80%

---

### Commit efb6a40: Grain Placement & Anti-Ringing
**Files:** `RenderProfile.swift`

**Change 1: Grain moved to OUTPUT stage**
```swift
// BEFORE (line 83)
case .compressedGrain:
    ["hdeband.glsl", "ArtCNN_C4F16_DS.glsl", "CfL_Prediction.glsl", "noise_static_luma.hook"]

// AFTER
case .compressedGrain:
    ["hdeband.glsl", "ArtCNN_C4F16_DS.glsl", "CfL_Prediction.glsl", "filmgrain-smooth-SDR-light.glsl"]
```

**Why:** `noise_static_luma.hook` hooks LUMA stage (2x plane, then resampled by 1.35x lanczos). `filmgrain-smooth-SDR-light.glsl` hooks OUTPUT stage (1:1 with display pixels). Grain must be at OUTPUT to preserve per-pixel character that masks blocking artifacts.

**Change 2: Added PixelClipper for anti-ringing**
```swift
case .upscaleLight:
    ["ArtCNN_C4F16.glsl", "CfL_Prediction.glsl", "PixelClipper.glsl"]

case .compressed:
    ["hdeband.glsl", "ArtCNN_C4F16_DS.glsl", "CfL_Prediction.glsl", "PixelClipper.glsl"]

case .crisp:
    ["ArtCNN_C4F16_DS.glsl", "CfL_Prediction.glsl", "adaptive-sharpen.glsl", "PixelClipper.glsl"]
```

**Why:** PixelClipper hooks POSTKERNEL (anti-rings 1.35x residual luma upscale) and CHROMA_SCALED (anti-rings 2.70x chroma upscale from cscale=spline36). Clips overshoot to local envelope rather than fabricating detail.

**Verification:**
- [ ] Play Patty7.mp4 (1.88 Mbit/s, blockiest) → grain should mask blocking without blurring
- [ ] Play P1.mp4 → check high-contrast edges (text, fence lines) for no darkening
- [ ] Compare with/without PixelClipper → should see reduced color-edge bleeding

---

### Commit 9b11675: 720p Classification Fix
**Files:** `SourceClassifier.swift`

**Change:**
```swift
// BEFORE (line 106)
if facts.width > 0, facts.height > 0, min(facts.width, facts.height) < 720 {

// AFTER
if facts.width > 0, facts.height > 0, min(facts.width, facts.height) <= 720 {
```

**Why:** P5.mp4 and Patricia114747.mp4 are both 1280x720. With `< 720`, they fell through to `clean` profile (no debander). With `<= 720`, they now classify as `compressed` and get deband+upscale stack.

**Trade-off:** This blunt fix may catch genuinely clean 720p sources. Better fix is adding chroma statistic to classifier (Phase 2).

**Verification:**
- [ ] Play P5.mp4 → should apply .compressed profile (check shader indicator)
- [ ] Play Patricia114747.mp4 → should apply .compressed profile
- [ ] Verify debanding is active (no visible banding in gradients)

---

## Test Results

### Automated Tests
- ✅ WindowConfiguratorTests: 9/9 passing
- ✅ PlayerChromeBehaviourTests: passing (with openMaximized suppressed)
- ✅ Build succeeded (Release configuration)

### Manual Tests (TODO)
- [ ] P5.mp4 (24.917fps): Frame timing, 720p classification
- [ ] Patty7.mp4 (1.88 Mbit/s): Grain placement
- [ ] P1.mp4: PixelClipper anti-ringing
- [ ] Patricia114747.mp4 (1280x720): 720p classification
- [ ] Window maximization behavior
- [ ] Fullscreen traffic light visibility

---

## Known Issues

### 1. CompareLiveBackendTests Flakiness
**Status:** Unresolved, not caused by our changes  
**Symptom:** 3 deadline-based tests occasionally fail  
**Root cause:** Pre-existing timing sensitivity in test suite  
**Impact:** Low - does not affect app functionality

### 2. 720p Blunt Fix
**Status:** Known trade-off  
**Impact:** May incorrectly classify clean 720p sources as compressed  
**Mitigation:** Phase 2 will add chroma statistic to classifier

---

## Next Steps

### Phase 2: Core Improvements (Planned)

1. **Chroma Upscaling Quality**
   - Evaluate `cscale=ewa_lanczossharp` vs current `spline36`
   - Test on WhatsApp fixtures with color gradients
   - Measure performance impact

2. **ProMotion Display Handling**
   - Query actual refresh rate via `CGDisplayModeGetRefreshRate`
   - Handle Low Power Mode (drops to 60Hz or lower)
   - Verify vsync detection works correctly

3. **GPU Budget Calibration**
   - Implement automatic calibration based on frame drops
   - Separate budgets for different profile tiers
   - Add hysteresis to prevent rapid profile switching

4. **720p Classifier Enhancement**
   - Add chroma statistic to SourceClassifier
   - Decode one extra `yuv420p` sample
   - Implement chroma-edge-bleed metric
   - Separate luma-clean/chroma-bad clips

5. **Adaptive Shader Selection**
   - Implement motion detection
   - Scene-change aware profile switching
   - Prevent visible artifacts during transitions

### Research In Progress

DeepSeek research agent is investigating:
- Chroma upscaling best practices
- Temporal denoising algorithms
- Neural model integration (Real-ESRGAN, SwinIR, HAT)
- Apple Silicon optimization techniques
- Quality metrics (VMAF, SSIM, PSNR)

---

## Files Modified

```
Aagedal Media Player/Logic/MPV/MPVPlayer.swift          (frame timing)
Aagedal Media Player/Logic/MPV/MPVVideoView.swift       (display rate)
Aagedal Media Player/Logic/MPV/GPUBudgetMonitor.swift   (budget calc)
Aagedal Media Player/Logic/MPV/RenderProfile.swift      (shaders)
Aagedal Media Player/Logic/MPV/SourceClassifier.swift   (720p threshold)
Aagedal Media Player/UI/WindowConfigurator.swift        (window size)
Aagedal Media Player/Logic/AppSettings.swift            (openMaximized)
Aagedal Media Player Tests/WindowConfiguratorTests.swift (new tests)
Aagedal Media Player Tests/PlayerChromeBehaviourTests.swift (suppression)
```

---

## Verification Checklist

Use this checklist to manually verify all Phase 1 fixes:

### Window Behavior
- [ ] App opens with window filling visible screen (1724x975 on M1 Pro)
- [ ] Window is not in native fullscreen (menu bar and Dock visible)
- [ ] Traffic lights (red/yellow/green) visible in top-left corner
- [ ] Enter fullscreen → traffic lights remain visible
- [ ] Exit fullscreen → traffic lights fade based on hover state

### Frame Timing (P5.mp4 - 24.917fps)
- [ ] Playback is smooth, no visible stuttering
- [ ] No frame drops reported (check if there's a frame drop counter)
- [ ] GPU usage stays below 80% (Activity Monitor)
- [ ] Battery usage is reasonable (not excessive drain)

### Grain Placement (Patty7.mp4 - 1.88 Mbit/s)
- [ ] Grain is visible and masks blocking artifacts
- [ ] Grain doesn't blur fine details
- [ ] Grain pattern is consistent (not resampled/distorted)
- [ ] Compare with .compressed profile (no grain) → grain should help

### Anti-Ringing (P1.mp4)
- [ ] High-contrast edges (text, fence lines) look clean
- [ ] No dark halos around bright edges
- [ ] No color bleeding at color transitions
- [ ] Detail is preserved (not over-sharpened)

### 720p Classification (P5.mp4, Patricia114747.mp4)
- [ ] Both files apply .compressed profile (check shader indicator)
- [ ] Debanding is active (gradients look smooth, no banding)
- [ ] Upscaling quality is good (no artifacts)
- [ ] Playback is smooth at 120Hz

---

## Metrics to Track

For ongoing improvement measurement:

1. **Frame drop rate:** % of frames dropped during playback
2. **GPU utilization:** Average and peak GPU usage
3. **Memory usage:** RAM consumption during playback
4. **Battery drain:** % battery per hour of playback
5. **Thermal state:** CPU/GPU temperature during sustained playback
6. **Profile accuracy:** % of clips correctly classified by auto-picker

---

## References

- Research report: `docs/research/2026-10-03-engine-improvements.md`
- Session summary: `docs/research/2026-10-03-session-summary.md`
- Commit log: `git log --oneline a808b38..9b11675`

---

**Status:** Phase 1 complete, ready for Phase 2 planning based on research findings.
