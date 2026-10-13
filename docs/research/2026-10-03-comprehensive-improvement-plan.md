# Comprehensive Improvement Plan for amp

Generated: 2026-10-03  
Status: Planning Phase  
Priority: Engine and Backend (user's primary focus)

---

## Table of Contents
1. [Backend/Engine Improvements](#backendengine-improvements)
2. [Architecture Improvements](#architecture-improvements)
3. [Frontend/UI Improvements](#frontendui-improvements)
4. [Testing and Quality Assurance](#testing-and-quality-assurance)
5. [Performance Optimization](#performance-optimization)
6. [Developer Experience](#developer-experience)

---

## Backend/Engine Improvements

### Priority 1: Video Enhancement Pipeline (HIGH IMPACT)

**Current State:**
- 6 render profiles: Faithful, Chroma, Efficient, Sharpen, UpscaleLight, Compressed
- Shader chain in `RenderProfile.swift:62-89`
- Auto-profile picker in `SourceClassifier.swift` + `ProfilePicker.swift`
- GPU budget monitoring in `GPUBudgetMonitor.swift`

**Identified Issues:**
1. **Grain placement bug** (FIXED in efb6a40): `.compressedGrain` was applying grain at wrong stage
2. **Missing anti-ringing** (FIXED in efb6a40): PixelClipper now added to 3 profiles
3. **720p classification gap** (FIXED in 9b11675): Threshold changed to `<= 720`
4. **Display FPS override** (FIXED in e604a39): Now letting MPVKit fork detect via CVDisplayLink

**Remaining Issues:**

#### 1.1 Chroma Upscaling Quality
- **Problem:** `cscale=spline36` at 2.70x upscale may introduce color fringing
- **Solution:** Evaluate `cscale=ewa_lanczossharp` for chroma channels
- **Impact:** Better color fidelity on upscaled WhatsApp videos
- **Effort:** Low (1 line change + testing)
- **Files:** `MPVPlayer.swift:1302`

#### 1.2 Adaptive Shader Selection
- **Problem:** Manual profile selection doesn't adapt to scene complexity
- **Solution:** Implement motion detection and scene-change aware profile switching
- **Impact:** Better performance on high-motion scenes, better quality on static scenes
- **Effort:** Medium-High (new detection system + switching logic)
- **Files:** New `MotionDetector.swift`, modify `PlayerController.swift`
- **Reference:** Research report Section 4, Gap 6

#### 1.3 Neural Model Integration
- **Problem:** ArtCNN models are 2020-era, newer models exist
- **Solution:** Evaluate and integrate modern neural upscalers:
  - Real-ESRGAN (2021, better on faces)
  - SwinIR (2021, state-of-art quality)
  - HAT (2022, hybrid attention transformer)
- **Impact:** 10-30% quality improvement on upscaled content
- **Effort:** High (model conversion to GLSL, performance testing)
- **Files:** New shader files, `RenderProfile.swift`

#### 1.4 Temporal Denoising
- **Problem:** `nlmeans.glsl` is spatial-only, temporal would reduce noise better
- **Solution:** Implement temporal denoising using frame history buffer
- **Impact:** Better noise reduction with less detail loss
- **Effort:** High (requires frame history, motion estimation)
- **Files:** New `TemporalDenoise.glsl`, `MPVPlayer.swift`

### Priority 2: Frame Timing and Synchronization (HIGH IMPACT)

**Current State:**
- `display-resample` with `interpolation=yes` for non-Faithful profiles
- CVDisplayLink via MPVKit fork patch 0004
- GPU budget monitoring at 0.5 fraction

**Identified Issues:**

#### 2.1 ProMotion Display Handling
- **Problem:** Not detecting actual refresh rate (only max 120Hz)
- **Solution:** Query actual refresh rate via `CGDisplayModeGetRefreshRate`
- **Impact:** Better frame timing on ProMotion displays in Low Power Mode
- **Effort:** Medium (API integration + testing)
- **Files:** `MPVVideoView.swift`, `MPVPlayer.swift`
- **Reference:** Research report Section 4, Gap 1

#### 2.2 GPU Budget Calibration
- **Problem:** Budget fraction 0.5 may be too conservative/aggressive
- **Solution:** 
  - Implement automatic calibration based on actual frame drops
  - Separate budgets for different profile tiers
  - Add hysteresis to prevent rapid profile switching
- **Impact:** Fewer frame drops on complex scenes, better quality on simple scenes
- **Effort:** Medium (algorithm refinement + testing)
- **Files:** `GPUBudgetMonitor.swift`, `ProfilePicker.swift`

#### 2.3 Frame Drop Prediction
- **Problem:** Reactive (drops frames then recovers), not predictive
- **Solution:** 
  - Monitor GPU utilization via Metal Performance HUD
  - Predict frame budget based on scene complexity metrics
  - Pre-emptively switch profiles before drops occur
- **Impact:** Smoother playback, no visible stuttering
- **Effort:** High (GPU metrics + prediction model)
- **Files:** New `FrameBudgetPredictor.swift`

### Priority 3: Hardware Acceleration (MEDIUM IMPACT)

**Current State:**
- `hwdec=videotoolbox` zero-copy by default
- `hwdec-extra-frames=4` (no-op on macOS per research)

**Improvements:**

#### 3.1 VideoToolbox Optimization
- **Problem:** Not leveraging all VideoToolbox capabilities
- **Solution:**
  - Enable `hwdec-image-format=nv12` for better compatibility
  - Test `hwdec-codecs` whitelist optimization
  - Investigate Metal texture cache for zero-copy rendering
- **Impact:** 5-15% CPU reduction
- **Effort:** Medium (configuration + testing)
- **Files:** `MPVPlayer.swift:228-234`

#### 3.2 Metal Performance Shaders
- **Problem:** Using GLSL shaders, not leveraging Metal-native performance
- **Solution:** 
  - Evaluate converting critical shaders to Metal Shading Language
  - Use Metal Performance Shaders for common operations
- **Impact:** 20-40% GPU performance improvement
- **Effort:** Very High (shader rewrite, testing)
- **Files:** New `.metal` shader files

### Priority 4: Audio Pipeline (LOW IMPACT)

**Current State:**
- Basic audio passthrough
- Audio waveform visualization

**Improvements:**

#### 4.1 Audio Enhancement
- **Problem:** No audio quality enhancement for compressed sources
- **Solution:**
  - Implement audio upscaling (44.1kHz → 48kHz)
  - Add dynamic range compression option
  - Spatial audio support for headphone listening
- **Impact:** Better audio quality on compressed sources
- **Effort:** Medium (audio DSP algorithms)
- **Files:** New `AudioEnhancer.swift`

---

## Architecture Improvements

### Priority 1: Code Organization (MEDIUM IMPACT)

**Current State:**
- `PlayerController.swift`: 1,715 lines (too large)
- `CompareSessionController.swift`: 2,259 lines (too large)
- `MPVPlayer.swift`: 1,663 lines (too large)

**Refactoring Plan:**

#### 1.1 PlayerController Decomposition
- **Extract:** `PlaybackState.swift`, `MediaLoader.swift`, `TrackManager.swift`
- **Impact:** Better maintainability, easier testing
- **Effort:** Medium (refactoring + test updates)
- **Files:** `PlayerController.swift` → 4 smaller files

#### 1.2 MPVPlayer Abstraction
- **Extract:** `MPVOptions.swift`, `MPVCommands.swift`, `MPVProperties.swift`
- **Impact:** Cleaner separation of concerns
- **Effort:** Low-Medium (extraction refactoring)
- **Files:** `MPVPlayer.swift` → 4 smaller files

#### 1.3 Render Pipeline Abstraction
- **Extract:** `RenderPipeline.swift`, `ShaderLoader.swift`, `ProfileManager.swift`
- **Impact:** Easier to add new render profiles
- **Effort:** Medium (abstraction + testing)
- **Files:** `RenderProfile.swift`, `MPVPlayer.swift`

### Priority 2: Dependency Management (LOW IMPACT)

**Current State:**
- MPVKit via Swift Package Manager
- Fork at `https://github.com/profanitys1/MPVKit`

**Improvements:**

#### 2.1 Dependency Versioning
- **Problem:** Fork may drift from upstream
- **Solution:**
  - Implement automated dependency updates (Dependabot/Renovate)
  - Pin specific commits for stability
  - Document fork differences
- **Impact:** Better dependency tracking
- **Effort:** Low (CI configuration)
- **Files:** `.github/dependabot.yml`

### Priority 3: Plugin Architecture (LOW IMPACT)

**Current State:**
- Monolithic architecture
- No plugin system

**Future Consideration:**

#### 3.1 Shader Plugin System
- **Problem:** Hard to add custom shaders without code changes
- **Solution:**
  - Plugin manifest format (JSON/YAML)
  - Shader discovery mechanism
  - User-installable shader packs
- **Impact:** Community contributions, easier customization
- **Effort:** High (plugin architecture design + implementation)
- **Files:** New `PluginManager.swift`, plugin format spec

---

## Frontend/UI Improvements

### Priority 1: User Experience (MEDIUM IMPACT)

**Current State:**
- Maximized window on open (FIXED in a808b38)
- Traffic lights visible in fullscreen (FIXED in a808b38)
- Floating OSC (on-screen controls)

**Improvements:**

#### 1.1 Gesture Controls
- **Problem:** Limited touch/gesture support
- **Solution:**
  - Trackpad gestures for seek, volume, fullscreen
  - Touch Bar support (if applicable)
  - Magic Remote support (Apple TV remote)
- **Impact:** More intuitive control
- **Effort:** Medium (gesture recognition + UI updates)
- **Files:** `PlayerView.swift`, new `GestureController.swift`

#### 1.2 Picture-in-Picture
- **Problem:** No PiP support
- **Solution:** Implement AVKit Picture-in-Picture
- **Impact:** Better multitasking
- **Effort:** Medium (AVKit integration)
- **Files:** `PlayerView.swift`

#### 1.3 Accessibility
- **Problem:** Limited VoiceOver support
- **Solution:**
  - Full VoiceOver support for all controls
  - Audio descriptions support
  - High contrast mode
- **Impact:** Better accessibility compliance
- **Effort:** Medium (accessibility audit + fixes)
- **Files:** All UI files

### Priority 2: Visual Polish (LOW IMPACT)

**Current State:**
- Clean, minimal UI
- Dark mode support

**Improvements:**

#### 2.1 Animation Refinement
- **Problem:** Some transitions could be smoother
- **Solution:**
  - Use `NSAnimationContext` for all transitions
  - Add spring animations for controls
  - Reduce motion support
- **Impact:** More polished feel
- **Effort:** Low-Medium (animation tuning)
- **Files:** UI files

#### 2.2 Custom Themes
- **Problem:** Limited visual customization
- **Solution:**
  - Theme system (light/dark/custom)
  - Color scheme customization
  - Icon pack support
- **Impact:** User personalization
- **Effort:** Medium (theme system design)
- **Files:** New `ThemeManager.swift`

### Priority 3: Information Display (LOW IMPACT)

**Improvements:**

#### 3.1 Enhanced Metadata Display
- **Problem:** Limited metadata visualization
- **Solution:**
  - Video codec info panel
  - Audio track details
  - Subtitle track info
  - Bitrate graph
- **Impact:** Better technical information access
- **Effort:** Medium (UI design + implementation)
- **Files:** `MetadataInspectorView.swift`

#### 3.2 Performance Overlay
- **Problem:** No real-time performance metrics
- **Solution:**
  - FPS counter
  - GPU utilization
  - Frame drop counter
  - Shader performance stats
- **Impact:** Better debugging and optimization
- **Effort:** Medium (metrics collection + UI)
- **Files:** New `PerformanceOverlay.swift`

---

## Testing and Quality Assurance

### Priority 1: Automated Testing (HIGH IMPACT)

**Current State:**
- 129 Swift files
- Test suite exists but coverage unknown
- No automated quality metrics

**Improvements:**

#### 1.1 Test Coverage
- **Problem:** Unknown test coverage
- **Solution:**
  - Enable code coverage in Xcode
  - Set coverage targets (80%+ for critical paths)
  - Add coverage reporting to CI
- **Impact:** Better code quality, fewer regressions
- **Effort:** Low-Medium (configuration + test writing)
- **Files:** Test files, CI configuration

#### 1.2 Visual Regression Testing
- **Problem:** No automated visual quality testing
- **Solution:**
  - Screenshot comparison tests
  - VMAF/SSIM/PSNR measurement in CI
  - Reference image management
- **Impact:** Catch visual regressions automatically
- **Effort:** High (test framework + reference images)
- **Files:** New `VisualRegressionTests.swift`

#### 1.3 Performance Regression Testing
- **Problem:** No automated performance testing
- **Solution:**
  - Benchmark suite for critical paths
  - Performance regression detection in CI
  - Historical performance tracking
- **Impact:** Catch performance regressions early
- **Effort:** Medium-High (benchmark framework)
- **Files:** New `PerformanceTests.swift`

### Priority 2: Quality Metrics (MEDIUM IMPACT)

**Improvements:**

#### 2.1 Video Quality Metrics
- **Problem:** No automated quality measurement
- **Solution:**
  - VMAF (Video Multi-Method Assessment Fusion)
  - SSIM (Structural Similarity Index)
  - PSNR (Peak Signal-to-Noise Ratio)
  - Custom perceptual metrics
- **Impact:** Quantifiable quality improvements
- **Effort:** High (metric implementation + integration)
- **Files:** New `QualityMetrics.swift`

#### 2.2 A/B Testing Framework
- **Problem:** Manual A/B testing only
- **Solution:**
  - Side-by-side comparison view
  - Automated quality scoring
  - User preference collection
- **Impact:** Data-driven quality decisions
- **Effort:** Medium (UI + scoring system)
- **Files:** `ComparePlayerView.swift` (enhance existing)

---

## Performance Optimization

### Priority 1: Startup Time (MEDIUM IMPACT)

**Current State:**
- Unknown startup time
- Likely loading all shaders at launch

**Improvements:**

#### 1.1 Lazy Loading
- **Problem:** Loading all resources at startup
- **Solution:**
  - Lazy shader loading (on first use)
  - Deferred initialization of non-critical systems
  - Async metadata loading
- **Impact:** Faster app launch
- **Effort:** Low-Medium (refactoring)
- **Files:** `PlayerController.swift`, `RenderProfile.swift`

#### 1.2 Precompilation
- **Problem:** Shader compilation on first use causes stutter
- **Solution:**
  - Precompile shaders in background
  - Cache compiled shaders
  - Warm up GPU on launch
- **Impact:** Smoother first playback
- **Effort:** Medium (caching system)
- **Files:** `MPVPlayer.swift`

### Priority 2: Memory Management (LOW IMPACT)

**Improvements:**

#### 2.1 Memory Profiling
- **Problem:** Unknown memory usage patterns
- **Solution:**
  - Memory profiling with Instruments
  - Identify and fix memory leaks
  - Optimize texture memory usage
- **Impact:** Lower memory footprint
- **Effort:** Medium (profiling + fixes)
- **Files:** Various

#### 2.2 Resource Cleanup
- **Problem:** Resources may not be released promptly
- **Solution:**
  - Implement resource pooling
  - Aggressive cleanup on media close
  - Background resource deallocation
- **Impact:** Better memory efficiency
- **Effort:** Low-Medium (cleanup logic)
- **Files:** `PlayerController.swift`

### Priority 3: GPU Optimization (HIGH IMPACT)

**Improvements:**

#### 3.1 Shader Optimization
- **Problem:** Some shaders may be suboptimal
- **Solution:**
  - Profile shader performance with Metal Debugger
  - Optimize hot shaders (ArtCNN, hdeband)
  - Use shader specialization constants
- **Impact:** 10-30% GPU performance improvement
- **Effort:** High (shader profiling + optimization)
- **Files:** Shader files

#### 3.2 Render Pass Optimization
- **Problem:** Multiple render passes may be inefficient
- **Solution:**
  - Combine render passes where possible
  - Use Metal render pass descriptors
  - Implement tile shading
- **Impact:** 20-50% GPU performance improvement
- **Effort:** Very High (render pipeline redesign)
- **Files:** `MPVPlayer.swift`, shader files

---

## Developer Experience

### Priority 1: Documentation (MEDIUM IMPACT)

**Current State:**
- Code comments exist but inconsistent
- Research reports well-documented
- No API documentation

**Improvements:**

#### 1.1 API Documentation
- **Problem:** No generated API docs
- **Solution:**
  - Add SwiftDoc comments to all public APIs
  - Generate documentation with Swift-DocC
  - Host on GitHub Pages
- **Impact:** Better developer onboarding
- **Effort:** Medium (documentation writing)
- **Files:** All Swift files

#### 1.2 Architecture Documentation
- **Problem:** Architecture decisions not documented
- **Solution:**
  - Architecture Decision Records (ADRs)
  - System design diagrams
  - Component interaction diagrams
- **Impact:** Better understanding of system
- **Effort:** Low-Medium (documentation writing)
- **Files:** `docs/architecture/`

### Priority 2: Build System (LOW IMPACT)

**Current State:**
- Xcode project
- Release build installs to `/Applications/amp.app`

**Improvements:**

#### 2.1 Build Optimization
- **Problem:** Build times unknown
- **Solution:**
  - Enable build time profiling
  - Optimize module boundaries
  - Use Swift build server for faster iteration
- **Impact:** Faster development cycle
- **Effort:** Low (configuration)
- **Files:** Xcode project settings

#### 2.2 CI/CD Pipeline
- **Problem:** No CI/CD
- **Solution:**
  - GitHub Actions for automated builds
  - Automated testing on PR
  - Automated releases
- **Impact:** Better release quality
- **Effort:** Medium (CI configuration)
- **Files:** `.github/workflows/`

### Priority 3: Debugging Tools (LOW IMPACT)

**Improvements:**

#### 3.1 Debug Overlay
- **Problem:** Limited debugging information
- **Solution:**
  - In-app debug overlay
  - Real-time metrics display
  - Shader performance stats
  - Frame timing visualization
- **Impact:** Easier debugging
- **Effort:** Medium (UI + metrics collection)
- **Files:** New `DebugOverlay.swift`

#### 3.2 Logging Improvements
- **Problem:** Limited structured logging
- **Solution:**
  - Structured logging with os_log
  - Log levels and categories
  - Log export functionality
- **Impact:** Better debugging information
- **Effort:** Low-Medium (logging system)
- **Files:** New `Logger.swift`

---

## Implementation Roadmap

### Phase 1: Quick Wins (1-2 weeks)
1. ✅ Frame timing fix (already done)
2. ✅ Grain placement fix (already done)
3. ✅ PixelClipper integration (already done)
4. ✅ 720p classification fix (already done)
5. Chroma upscaling improvement (cscale change)
6. Test coverage audit
7. Lazy shader loading

### Phase 2: Core Improvements (3-4 weeks)
1. ProMotion display handling
2. GPU budget calibration
3. PlayerController decomposition
4. Visual regression testing setup
5. Performance regression testing setup

### Phase 3: Advanced Features (5-8 weeks)
1. Adaptive shader selection
2. Neural model integration (Real-ESRGAN)
3. Temporal denoising
4. Picture-in-Picture support
5. Video quality metrics integration

### Phase 4: Optimization (ongoing)
1. Shader optimization
2. Render pass optimization
3. Memory profiling and optimization
4. Build system optimization

---

## Success Metrics

### Quality Metrics
- VMAF score improvement on test fixtures (target: +5-10 points)
- SSIM/PSNR improvement on upscaled content
- User-reported quality improvements

### Performance Metrics
- Frame drop rate reduction (target: <1% from current unknown)
- GPU utilization reduction (target: -20% at same quality)
- Startup time reduction (target: -30%)
- Memory usage reduction (target: -20%)

### Developer Experience Metrics
- Build time reduction (target: -30%)
- Test coverage increase (target: 80%+ for critical paths)
- Documentation coverage (target: 100% for public APIs)

---

## References

1. Research report: `docs/research/2026-10-03-engine-improvements.md`
2. MPV documentation: https://mpv.io/manual/master/
3. libplacebo documentation: https://code.videolan.org/videolan/libplacebo
4. Apple Metal documentation: https://developer.apple.com/metal/
5. VideoToolbox documentation: https://developer.apple.com/documentation/videotoolbox

---

## Next Steps

1. **Immediate:** Test the 4 fixes already implemented with WhatsApp fixtures
2. **This week:** Implement chroma upscaling improvement (low effort, high impact)
3. **Next week:** Set up visual regression testing
4. **Next month:** Begin Phase 2 core improvements
5. **Ongoing:** Track metrics and adjust priorities based on results

---

**Note:** This plan is a living document. Priorities should be adjusted based on:
- User feedback
- Test results
- Performance measurements
- Resource availability

Last updated: 2026-10-03
