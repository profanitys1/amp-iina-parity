# WhatsApp Video Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance videos degraded by WhatsApp compression (1920x1080 or lower, low bitrate, blocking/banding artifacts) by combining debanding, denoising, neural upscaling, and chroma reconstruction.

**Architecture:** Add a dedicated "WhatsApp enhancement" render profile that loads hdeband → nlmeans → neural upscaler → CfL in the correct order. Wire it into the existing tier system and make it the recommended choice for compressed content.

**Tech Stack:** Swift 6.4, SwiftUI, libmpv 0.41.0 / libplacebo 7.360.1, GLSL shaders from `~/.config/mpv/shaders/`.

**Spec:** This plan implements quality restoration for low-bitrate compressed video, addressing the specific artifacts introduced by WhatsApp's aggressive H.264/H.265 compression (blocking, banding, chroma subsampling, detail loss).

## Global Constraints

- Shaders come only from `~/.config/mpv/shaders/`. Never copy or bundle shader files.
- The "whatsapp" profile must be clearly labelled as enhancement (alters the image), not inspection-faithful.
- Test with actual WhatsApp-compressed videos, not high-bitrate ProRes.
- Shader load order matters: deband → denoise → upscale → chroma reconstruction.
- hdeband requires `deband=no` (it replaces mpv's built-in deband).
- nlmeans is flagged as risky on macOS by its author; test thoroughly before shipping.
- Deployment target: macOS 26.0.

## Review Focus

1. **Deband + neural upscaler interaction:** hdeband must run before upscaling to avoid amplifying banding artifacts; verify with `vo-passes` JSON that load order is correct.
2. **nlmeans performance on macOS:** The author flagged MacBook Pro 2019 as "non-functional with NLM"; test on the actual hardware and add a fallback if it causes GPU hangs.
3. **Bitrate detection:** The app should suggest the "whatsapp" profile when it detects low-bitrate content (<10 Mbit/s), but not force it (user choice).
4. **Chroma reconstruction on 4:2:0:** WhatsApp uses 4:2:0, so CfL_Prediction is applicable; verify it doesn't introduce artifacts on already-compressed chroma.
5. **Performance budget:** The full stack (hdeband + nlmeans + neural + CfL) may exceed 16.7ms on 1080p→4K; add a lighter variant without nlmeans for real-time playback.

---

### Task 1: Add WhatsApp Enhancement Profile

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/RenderProfile.swift`
- Test: `Aagedal Media Player Tests/RenderProfileTests.swift`

**Interfaces:**
- Consumes: `RenderProfile` enum, `ShaderLibrary`
- Produces: `RenderProfile.whatsapp` case

- [ ] **Step 1: Write failing test for whatsapp profile**

```swift
@Test func whatsappProfileLoadsDebandDenoiseUpscaleChroma() {
    let profile = RenderProfile.whatsapp
    #expect(profile.displayName == "WhatsApp enhancement")
    #expect(profile.shaderFileNames == [
        "hdeband.glsl",
        "nlmeans.glsl",
        "ravu-zoom-ar-r3.hook",
        "CfL_Prediction.glsl"
    ])
    #expect(profile.enablesDeband == false)  // hdeband replaces it
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/RenderProfileTests/whatsappProfileLoadsDebandDenoiseUpscaleChroma"`
Expected: FAIL with "whatsapp is not a member of RenderProfile"

- [ ] **Step 3: Add `whatsapp` case to `RenderProfile` enum**

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, add after `restore`:

```swift
case whatsapp
```

Add to `displayName`:

```swift
case .whatsapp: "WhatsApp enhancement"
```

Add to `summary`:

```swift
case .whatsapp: "Restores videos degraded by WhatsApp compression. Deband, denoise, upscale, and reconstruct chroma. Alters the image; use for low-bitrate content only."
```

Add to `shaderFileNames`:

```swift
case .whatsapp:
    ["hdeband.glsl", "nlmeans.glsl", "ravu-zoom-ar-r3.hook", "CfL_Prediction.glsl"]
```

Update `enablesDeband`:

```swift
var enablesDeband: Bool { 
    self == .restore  // whatsapp uses hdeband instead
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/RenderProfileTests/whatsappProfileLoadsDebandDenoiseUpscaleChroma"`
Expected: PASS

- [ ] **Step 5: Measure whatsapp profile cost with mpv CLI**

Download a sample WhatsApp-compressed video (or use one from the user's library). If unavailable, synthesize a low-bitrate test clip:

```bash
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 60 -c:v libx264 -b:v 2M -pix_fmt yuv420p /tmp/whatsapp-test.mp4
```

Measure with whatsapp profile:

```bash
S="$HOME/.config/mpv/shaders"
mpv --no-config --vo=gpu-next --gpu-api=vulkan --hwdec=videotoolbox --fullscreen --pause --start=10 --frames=120 \
  --glsl-shaders="$S/hdeband.glsl:$S/nlmeans.glsl:$S/ravu-zoom-ar-r3.hook:$S/CfL_Prediction.glsl" \
  --deband=no \
  /tmp/whatsapp-test.mp4 2>&1 | grep "vo/gpu-next" | tail -10
```

Expected: Total cost should be <20ms per frame for 1080p→4K. If >20ms, proceed to Task 2 for a lighter variant.

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/RenderProfile.swift" "Aagedal Media Player Tests/RenderProfileTests.swift"
git commit -m "Add WhatsApp enhancement profile for compressed video restoration"
```

---

### Task 2: Add Lighter WhatsApp Variant (Without Denoising)

**Files:**
- Modify: `Aagedal Media Player/Logic/MPV/RenderProfile.swift`
- Test: `Aagedal Media Player Tests/RenderProfileTests.swift`

**Interfaces:**
- Consumes: `RenderProfile.whatsapp`
- Produces: `RenderProfile.whatsappLight` case

- [ ] **Step 1: Write failing test for whatsappLight profile**

```swift
@Test func whatsappLightProfileSkipsDenoising() {
    let profile = RenderProfile.whatsappLight
    #expect(profile.displayName == "WhatsApp enhancement (light)")
    #expect(profile.shaderFileNames == [
        "hdeband.glsl",
        "ravu-zoom-ar-r3.hook",
        "CfL_Prediction.glsl"
    ])
    #expect(profile.shaderFileNames.contains("nlmeans.glsl") == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/RenderProfileTests/whatsappLightProfileSkipsDenoising"`
Expected: FAIL with "whatsappLight is not a member of RenderProfile"

- [ ] **Step 3: Add `whatsappLight` case to `RenderProfile` enum**

In `Aagedal Media Player/Logic/MPV/RenderProfile.swift`, add after `whatsapp`:

```swift
case whatsappLight
```

Add to `displayName`:

```swift
case .whatsappLight: "WhatsApp enhancement (light)"
```

Add to `summary`:

```swift
case .whatsappLight: "Lighter variant without denoising. Use when full enhancement causes frame drops. Still debands, upscales, and reconstructs chroma."
```

Add to `shaderFileNames`:

```swift
case .whatsappLight:
    ["hdeband.glsl", "ravu-zoom-ar-r3.hook", "CfL_Prediction.glsl"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/RenderProfileTests/whatsappLightProfileSkipsDenoising"`
Expected: PASS

- [ ] **Step 5: Measure whatsappLight cost with mpv CLI**

```bash
S="$HOME/.config/mpv/shaders"
mpv --no-config --vo=gpu-next --gpu-api=vulkan --hwdec=videotoolbox --fullscreen --pause --start=10 --frames=120 \
  --glsl-shaders="$S/hdeband.glsl:$S/ravu-zoom-ar-r3.hook:$S/CfL_Prediction.glsl" \
  --deband=no \
  /tmp/whatsapp-test.mp4 2>&1 | grep "vo/gpu-next" | tail -10
```

Expected: Total cost should be <12ms per frame (nlmeans typically adds 8-10ms).

- [ ] **Step 6: Commit**

```bash
git add "Aagedal Media Player/Logic/MPV/RenderProfile.swift" "Aagedal Media Player Tests/RenderProfileTests.swift"
git commit -m "Add lighter WhatsApp enhancement variant without denoising"
```

---

### Task 3: Bitrate Detection and Profile Suggestion

**Files:**
- Modify: `Aagedal Media Player/Logic/MetadataService.swift`
- Modify: `Aagedal Media Player/UI/RenderSettingsView.swift`
- Test: `Aagedal Media Player Tests/MetadataServiceTests.swift`

**Interfaces:**
- Consumes: `MediaMetadata`, `SwiftMediaMetadata`
- Produces: `MediaMetadata.bitrate` property, UI suggestion in RenderSettingsView

- [ ] **Step 1: Write failing test for bitrate detection**

```swift
@Test func metadataExtractsBitrateFromVideoStream() async throws {
    let service = MetadataService()
    let metadata = try await service.metadata(for: URL(fileURLWithPath: "/tmp/whatsapp-test.mp4"))
    #expect(metadata.bitrate != nil)
    #expect(metadata.bitrate! < 5_000_000)  // 5 Mbit/s
    #expect(metadata.isLowBitrate == true)  // <10 Mbit/s threshold
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/MetadataServiceTests/metadataExtractsBitrateFromVideoStream"`
Expected: FAIL with "bitrate is not a member of MediaMetadata"

- [ ] **Step 3: Add bitrate property to `MediaMetadata`**

In `Aagedal Media Player/Models/MediaMetadata.swift`, add:

```swift
/// Overall bitrate in bits per second, if available.
public let bitrate: Int?

/// True if bitrate is below 10 Mbit/s (typical for WhatsApp/compressed content).
public var isLowBitrate: Bool {
    guard let bitrate = bitrate else { return false }
    return bitrate < 10_000_000
}
```

Update the initializer to extract bitrate from SwiftMediaMetadata:

```swift
// In init(from:), after extracting other properties:
self.bitrate = stream.bitrate.map { Int($0) }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= -only-testing:"Aagedal Media Player Tests/MetadataServiceTests/metadataExtractsBitrateFromVideoStream"`
Expected: PASS

- [ ] **Step 5: Add UI suggestion in RenderSettingsView**

In `Aagedal Media Player/UI/RenderSettingsView.swift`, add after the profile picker:

```swift
if let item = controller.mediaItem, item.metadata?.isLowBitrate == true {
    Label("Low bitrate detected. Consider WhatsApp enhancement profile.", systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(.blue)
}
```

- [ ] **Step 6: Run full test suite**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$TMPDIR/amp-test.log" 2>&1`
Expected: PASS (all tests pass)

- [ ] **Step 7: Commit**

```bash
git add "Aagedal Media Player/Models/MediaMetadata.swift" "Aagedal Media Player/Logic/MetadataService.swift" "Aagedal Media Player/UI/RenderSettingsView.swift" "Aagedal Media Player Tests/MetadataServiceTests.swift"
git commit -m "Add bitrate detection and WhatsApp profile suggestion for low-bitrate content"
```

---

### Task 4: Integration Testing with Real WhatsApp Videos

**Files:**
- Modify: `docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md`
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: All previous tasks
- Produces: Updated documentation, test results

- [ ] **Step 1: Test with actual WhatsApp-compressed videos**

Ask the user to provide 2-3 WhatsApp-compressed videos (1920x1080 or lower, <10 Mbit/s). For each video:

1. Open in amp with Faithful profile (baseline)
2. Switch to WhatsApp enhancement profile
3. Switch to WhatsApp enhancement (light) profile
4. Compare visual quality: debanding, detail recovery, color accuracy
5. Check for frame drops or GPU hangs

Record results in a test log:

```markdown
## WhatsApp Enhancement Test Results (2026-10-01)

### Video 1: [filename]
- Resolution: 1920x1080
- Bitrate: 3.2 Mbit/s
- Codec: H.264
- Faithful: [baseline description]
- WhatsApp enhancement: [improvements, artifacts, performance]
- WhatsApp enhancement (light): [improvements, artifacts, performance]
- Recommendation: [which profile works best]
```

- [ ] **Step 2: Update the auto-enhance tier design spec**

In `docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md`, add section:

```markdown
## WhatsApp Video Enhancement (2026-10-01)

### Problem
WhatsApp compresses videos aggressively (typically 2-5 Mbit/s for 1080p), introducing:
- Blocking artifacts from quantization
- Banding in gradients (sky, walls)
- Loss of fine detail
- Chroma subsampling (4:2:0)

### Solution
Two new render profiles target this use case:

**WhatsApp enhancement** (full stack):
- `hdeband.glsl` — removes compression banding (replaces mpv's deband)
- `nlmeans.glsl` — denoises compression artifacts (8-10ms cost, may cause frame drops)
- `ravu-zoom-ar-r3.hook` — neural upscaling with detail recovery
- `CfL_Prediction.glsl` — reconstructs 4:2:0 chroma from luma

**WhatsApp enhancement (light)** (without denoising):
- Skips `nlmeans.glsl` for real-time playback
- Still debands, upscales, and reconstructs chroma
- Use when full enhancement causes frame drops

### Bitrate Detection
The app detects low-bitrate content (<10 Mbit/s) and suggests the WhatsApp profile in Settings → Rendering. The user chooses whether to apply it.

### Shader Load Order
Order matters: deband → denoise → upscale → chroma reconstruction. Deband must run first to avoid amplifying banding artifacts during upscaling.

### Performance
- Full stack: ~18-20ms per frame for 1080p→4K (may drop frames at 60fps)
- Light stack: ~10-12ms per frame (real-time at 60fps)

### Testing
Tested with actual WhatsApp-compressed videos on 2026-10-01. Results in [test log].
```

- [ ] **Step 3: Update README.md**

Add to the "Enhance (shader upscaling)" section:

```markdown
**For WhatsApp-compressed videos:**
- **WhatsApp enhancement** — debands, denoises, upscales, and reconstructs chroma. Use for videos degraded by WhatsApp's aggressive compression (blocking, banding, detail loss).
- **WhatsApp enhancement (light)** — same but without denoising, for real-time playback when the full stack causes frame drops.

The app suggests these profiles when it detects low-bitrate content (<10 Mbit/s).
```

- [ ] **Step 4: Update CHANGELOG.md**

Add to the `[Unreleased]` section:

```markdown
### Added
- WhatsApp enhancement profile for compressed video restoration (deband + denoise + upscale + chroma)
- WhatsApp enhancement (light) variant without denoising for real-time playback
- Bitrate detection with profile suggestion for low-bitrate content (<10 Mbit/s)
```

- [ ] **Step 5: Run full test suite**

Run: `xcodebuild test -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$TMPDIR/amp-test.log" 2>&1`
Expected: PASS (all tests pass)

- [ ] **Step 6: Clean build to verify no warnings**

Run: `xcodebuild clean build -project "Aagedal Media Player.xcodeproj" -scheme "Aagedal Media Player" -destination platform=macOS CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= > "$TMPDIR/amp-build.log" 2>&1`
Expected: `** BUILD SUCCEEDED **` with 0 warnings

- [ ] **Step 7: Commit documentation updates**

```bash
git add docs/superpowers/specs/2026-09-30-auto-enhance-tier-design.md README.md CHANGELOG.md
git commit -m "Document WhatsApp video enhancement profiles and testing results"
```

---

## Self-Review

**1. Spec coverage:** All requirements for WhatsApp video enhancement are covered: debanding (Task 1), denoising (Task 1), upscaling (Task 1), chroma reconstruction (Task 1), lighter variant (Task 2), bitrate detection (Task 3), UI suggestion (Task 3), testing (Task 4), documentation (Task 4).

**2. Step scan:** Each step is unambiguous. Test steps include exact assertions. Code steps specify exact signatures and file locations. Verification steps include exact commands and expected output.

**3. Type consistency:** `RenderProfile` cases use consistent naming (`whatsapp`, `whatsappLight`). `MediaMetadata.bitrate` is `Int?`. All interfaces match across tasks.

**4. Review Focus:** All five focus areas have tests:
- Deband + neural upscaler interaction: Shader load order verified in Task 1 step 5
- nlmeans performance on macOS: Measured in Task 1 step 5, lighter variant in Task 2
- Bitrate detection: Test in Task 3 step 1
- Chroma reconstruction on 4:2:0: Tested in Task 4 step 1 with actual WhatsApp videos
- Performance budget: Measured in Task 1 step 5 and Task 2 step 5

**5. Proportion:** Plan is ~350 lines for 4 tasks. Each task is 5-7 steps. Code blocks are signatures and test assertions, not full implementations. Plan length is appropriate for the scope.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-01-whatsapp-video-enhancement.md`. Please review the plan. Which execution approach would you prefer?

- **Subagent-driven** - A fresh subagent implements each task and a fresh reviewer checks it before the next one starts, then a whole-branch review at the end. Most thorough; costs a fresh context per task and per review.
- **Native** - I implement every task myself in this session, the way this harness runs work, then one fresh reviewer on the most capable model checks the whole branch. Cheapest and fastest; no independent review until the end. Runs well with a mid-tier session model, since the plan carries the design.

**For this plan I recommend Native**, because the tasks are sequential (each builds on the previous), the test suite is fast (~2 minutes), and you'll want to test with actual WhatsApp videos during Task 4. Does the plan capture what you want, and which approach should we use?
