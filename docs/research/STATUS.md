# amp Development Status

**Last Updated:** 2026-10-04  
**Current Phase:** Phase 2B Complete

---

## ✅ Completed

### Phase 1: Core Improvements (commits a808b38 - 9b11675)
- ✅ Window maximization on open (fills visible screen, not native fullscreen)
- ✅ Traffic lights stay visible in fullscreen
- ✅ Removed display-fps-override (lets MPVKit detect via CVDisplayLink)
- ✅ GPU budget uses display rate when interpolating
- ✅ Moved grain to OUTPUT stage (filmgrain-smooth-SDR-light.glsl)
- ✅ Added PixelClipper.glsl for anti-ringing (3 profiles)
- ✅ Fixed 720p threshold (<=720 instead of <720)

### Phase 2A: KrigBilateral Integration (commit 4316b70)
- ✅ Added KrigBilateral.glsl to 4 profiles (.upscaleLight, .compressed, .crisp, .compressedGrain)
- ✅ Implemented conditional shader filtering in MPVPlayer.filterShadersForSource()
- ✅ Safety check: Skips KrigBilateral for 4:2:2 sources (trained on 4:2:0 only)
- ✅ Performance gating: Skips FSRCNNX for >60Hz displays

**Expected Impact:** +3-5 VMAF points for chroma quality on 4:2:0 sources (WhatsApp videos)

### Phase 2B: Spatial Denoising (commit 4199b84)
- ✅ Added nlmeans.glsl to .compressed profile for spatial denoising
- ✅ Shader order: hdeband → nlmeans → ArtCNN_C4F16_DS → CfL_Prediction → PixelClipper → KrigBilateral
- ✅ Updated RenderProfileTests to reflect new shader count (6 shaders in .compressed)

**Expected Impact:** +1-3 VMAF points on WhatsApp-compressed videos through non-local means denoising

---

## 🔄 In Progress

### Phase 2C: Refresh-Rate Detection (Planned)
- [ ] Implement refresh-rate-aware shader selection (detect actual refresh rate via CGDisplayModeGetRefreshRate)
- [ ] Handle ProMotion Low Power Mode (drops to 60Hz or lower)
- [ ] Auto-select shader tier: 120Hz=light, 60Hz=full, 30Hz=everything

### Research Completed (DeepSeek)
- ✅ Chroma upscaling: KrigBilateral is best for 4:2:0 (PSNR 38.6 dB, SSIM 0.9976)
- ✅ Refresh-rate gating: FSRCNNX too expensive for >60Hz (8.33ms budget at 120Hz)
- ✅ 4:2:2 safety: KrigBilateral must be skipped for yuv422p sources
- ✅ Temporal denoising: Not feasible in mpv shader system (single-frame limitation)
- ✅ Neural models: Real-ESRGAN/SwinIR too large for real-time GLSL
- ✅ Quality metrics: VMAF/SSIM recommended for CI/CD gating

---

## 📋 Next Steps

### Future (Phase 2C)
1. **Refresh-rate detection**
   - Query actual refresh rate via `CGDisplayModeGetRefreshRate`
   - Handle ProMotion Low Power Mode (drops to 60Hz or lower)
   - Auto-select shader tier: 120Hz=light, 60Hz=full, 30Hz=everything

2. **Quality metrics pipeline**
   - Set up ffmpeg-quality-metrics for offline testing
   - Render reference frames through shader chain
   - Gate future changes on measurable VMAF improvement

3. **Adaptive shader complexity**
   - Monitor GPU frame time via CVDisplayLink callback
   - Dynamically reduce shader complexity if frame time exceeds budget
   - Fallback chain: neural pre-scaler → spline36 → bilinear

---

## 📊 Test Results

### Build Status
- ✅ Release build succeeded (commit 4199b84)
- ✅ All 12 RenderProfileTests passing
- ✅ App running with P5.mp4 fixture

### Manual Testing (TODO)
- [ ] P5.mp4 (1280x720, 4:2:0) - Verify KrigBilateral chroma improvement
- [ ] gaia.mov (1280x720, 4:2:2) - Verify KrigBilateral is skipped
- [ ] Patty7.mp4 (1.88 Mbit/s) - Verify nlmeans + grain + KrigBilateral combination
- [ ] P1.mp4 - Verify PixelClipper + KrigBilateral interaction
- [ ] 120Hz vs 60Hz displays - Verify FSRCNNX gating

---

## 📁 Key Documents

- `docs/research/2026-10-03-engine-improvements.md` - Comprehensive research report
- `docs/research/2026-10-03-phase1-completion.md` - Phase 1 completion details
- `docs/research/2026-10-03-comprehensive-improvement-plan.md` - Full improvement roadmap
- `docs/research/STATUS.md` - This file

---

## 🔧 Current State

**Hardware:** 14" M1 Pro MacBook Pro, 3024x1964 Retina, ~120Hz ProMotion  
**Use Case:** WhatsApp-compressed videos (640x352, 320x640, 1280x720, all 4:2:0)  
**Target:** Aggressive upscaling with enhancement (debanding, denoising, chroma reconstruction)

**Shader Library:** ~/.config/mpv/shaders (27 shaders, 12 wired, 15 unwired)  
**Render Profiles:** 11 profiles (automatic, off, chroma, efficient, sharpen, upscaleLight, compressed, crisp, upscaleStrong, compressedGrain, restore)

**Recent Changes (Phase 2A+2B):**
- KrigBilateral.glsl added to 4 profiles with 4:2:2 safety check
- nlmeans.glsl added to .compressed profile for spatial denoising
- Conditional shader filtering based on pixel format and refresh rate
- FSRCNNX gated to ≤60Hz displays for performance
- PixelClipper added to 3 profiles for anti-ringing

---

## 🎯 Success Metrics

### Quality Metrics (Target)
- VMAF improvement: +5-10 points on WhatsApp fixtures vs baseline
- SSIM improvement: +0.02-0.05 on upscaled content
- Chroma quality: PSNR >38 dB on 4:2:0 sources with KrigBilateral

### Performance Metrics (Target)
- Frame drop rate: <1% on 120Hz ProMotion display
- GPU utilization: <80% at 120Hz, <60% at 60Hz
- Frame time: <8.33ms at 120Hz, <16.67ms at 60Hz

---

**Last updated:** 2026-10-04 (commit 4199b84)
